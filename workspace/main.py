import os
import subprocess
import time
import csv
import struct
import uuid
import fcntl
import asyncio
import errno
import concurrent.futures
from fastapi import FastAPI, UploadFile, Form, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

_fifo_executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
_fifo_write_future = None


def _write_all_sync(fd, data):
    total = 0
    while total < len(data):
        n = os.write(fd, data[total:])
        total += n


app = FastAPI()

_fifo_fd = -1

@app.on_event("startup")
async def open_fifo():
    global _fifo_fd
    try:
        _fifo_fd = os.open(FIFO_PATH, os.O_WRONLY | os.O_NONBLOCK)
        flags = fcntl.fcntl(_fifo_fd, fcntl.F_GETFL)
        is_nonblocking = bool(flags & os.O_NONBLOCK)
        print(f"[FIFO] blocking={not is_nonblocking}")
        fcntl.fcntl(_fifo_fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
        print("[SLAM] FIFO 연결됨 (startup)")
    except OSError:
        _fifo_fd = -1
        print("[SLAM] FIFO 연결 실패")


FIFO_PATH = '/tmp/slam_pipe'
if not os.path.exists(FIFO_PATH):
    os.mkfifo(FIFO_PATH)

# --- [INSERT 1] CORS 미들웨어 설정 ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ngrok 도메인 등 모든 외부 출처 허용
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# ------------------------------------

UPLOAD_DIR = "/app/video_upload" # 도커 컨테이너 내부의 저장 경로로 맞추세요.



# 폴더가 없으면 생성
os.makedirs(UPLOAD_DIR, exist_ok=True)
def merge_video(filename: str, total_chunks: int):
    print(f"[{filename}] 병합 작업을 시작합니다...")

    chunk_files = [f for f in os.listdir(UPLOAD_DIR) if f.endswith(f"_{filename}")]
    chunk_files.sort(key=lambda x: int(x.split('_')[0]))

    if len(chunk_files) != total_chunks:
        print(f"오류: 청크 수 불일치 (기대: {total_chunks}, 실제: {len(chunk_files)})")
        return

    output_path = os.path.join(UPLOAD_DIR, f"final_{filename}")

    with open(output_path, "wb") as outfile:
        for chunk in chunk_files:
            chunk_path = os.path.join(UPLOAD_DIR, chunk)
            with open(chunk_path, "rb") as f:
                outfile.write(f.read())
          

    print(f"[{filename}] 병합 완료! 최종 파일: {output_path}")

@app.post("/upload")
async def upload_chunk(
    background_tasks: BackgroundTasks,
    file: UploadFile,
    filename: str = Form(...),
    chunk_index: int = Form(...),
    total_chunks: int = Form(...),
    file_name: str = Form(None),
    is_list: str = Form(None),
):
    """청크를 수신하고, 모두 모이면 백그라운드로 병합을 지시하는 엔드포인트"""
    
    # 청크 저장 (예: 0_video.mp4, 1_video.mp4)
    save_path = os.path.join(UPLOAD_DIR, f"{chunk_index}_{filename}")
    
    with open(save_path, "wb") as f:
        f.write(await file.read())

    # 현재까지 저장된 해당 파일의 청크 개수 확인
    saved_chunks = [f for f in os.listdir(UPLOAD_DIR) if f.endswith(f"_{filename}")]
    
    # 모든 청크가 다 들어왔다면 병합 트리거!
    if len(saved_chunks) == total_chunks:
        # 응답 지연을 막기 위해 BackgroundTasks로 넘김
        background_tasks.add_task(merge_video, filename, total_chunks)
        return JSONResponse(content={"message": "모든 청크 수신 완료. 병합을 시작합니다."})

    return JSONResponse(content={"message": f"청크 {chunk_index}/{total_chunks} 수신 완료"})

# --- [INSERT 2] ORB-SLAM WebSocket 엔드포인트 ---
# SLAM 이미지 저장 경로 설정
SLAM_SAVE_DIR = "/app/slam_images"
os.makedirs(SLAM_SAVE_DIR, exist_ok=True)

_IMU_ENTRY_FMT  = '<d3f3f'
_IMU_ENTRY_SIZE = struct.calcsize(_IMU_ENTRY_FMT)  # 32 bytes

@app.websocket("/ws/orb-slam")
async def websocket_orb_slam(websocket: WebSocket):
    await websocket.accept()
    print("[System] WebSocket 연결 수락: /ws/orb-slam")

    global _fifo_fd
    fifo_fd = _fifo_fd

    session_id   = str(uuid.uuid4())
    imu_csv_path = os.path.join(SLAM_SAVE_DIR, f"imu_{session_id}.csv")

    with open(imu_csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["frame_number", "timestamp_ms", "ax", "ay", "az", "gx", "gy", "gz"])

    try:
        while True:
            message = await websocket.receive()

            if message.get("type") == "websocket.disconnect":
                break

            data = message.get("bytes") or (message.get("text", "").encode() if "text" in message else None)
            if not data or len(data) < 6:
                print(f"[WS] 데이터 없음 또는 너무 짧음: {len(data) if data else 0}")
                continue

            # 패킷 파싱: [4B frame_number][2B imu_count][N×32B IMU][JPEG]
            frame_number = struct.unpack_from('<I', data, 0)[0]
            imu_count    = struct.unpack_from('<H', data, 4)[0]
            imu_end      = 6 + imu_count * _IMU_ENTRY_SIZE

            print(f"[WS] frame={frame_number}, imu_count={imu_count}, imu_end={imu_end}, total={len(data)}")

            if len(data) < imu_end:
                continue

            # IMU 파싱 및 CSV 저장
            rows = []
            for i in range(imu_count):
                offset = 6 + i * _IMU_ENTRY_SIZE
                ts, ax, ay, az, gx, gy, gz = struct.unpack_from(_IMU_ENTRY_FMT, data, offset)
                rows.append([frame_number, ts, ax, ay, az, gx, gy, gz])

            with open(imu_csv_path, 'a', newline='') as f:
                csv.writer(f).writerows(rows)

            # JPEG 저장
            jpeg = data[imu_end:]
            file_name = f"frame_{int(time.time())}_{frame_number}.jpg"
            save_path = os.path.join(SLAM_SAVE_DIR, file_name)
            with open(save_path, "wb") as f:
                f.write(jpeg)

            global _fifo_write_future
          
            if _fifo_fd >= 0:
                fifo_payload = struct.pack('<IH', len(jpeg), imu_count) + data[6:imu_end] + jpeg
                print(f"[FIFO DEBUG] 전송: jpeg={len(jpeg)}B, payload={len(fifo_payload)}B")
                if _fifo_write_future is None or _fifo_write_future.done():
                    _fifo_write_future = asyncio.get_event_loop().run_in_executor(
                        _fifo_executor, _write_all_sync, _fifo_fd, fifo_payload
                    )
                else:
                    print("[FIFO] 이전 쓰기 중, 프레임 스킵")

            await websocket.send_text(f"Saved: {file_name}")

    except WebSocketDisconnect:
        print("[System] WebSocket 연결 해제됨")
    finally:
        pass
