import os
import subprocess
import time
from fastapi import FastAPI, UploadFile, Form, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

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

@app.websocket("/ws/orb-slam")
async def websocket_orb_slam(websocket: WebSocket):
    await websocket.accept()
    print("[System] WebSocket 연결 수락: /ws/orb-slam")

    try:
        frame_count = 0
        while True:
            message = await websocket.receive()
            data = None

            if "bytes" in message:
                data = message["bytes"]
            elif "text" in message:
                data = message["text"].encode()
            elif message.get("type") == "websocket.disconnect":
                break
            else:
                continue

            if data:
                # --- [저장 로직 추가] ---
                frame_count += 1
                # 파일명 예시: frame_1715400000_1.jpg
                file_name = f"frame_{int(time.time())}_{frame_count}.jpg"
                save_path = os.path.join(SLAM_SAVE_DIR, file_name)
               
                with open(save_path, "wb") as f:
                    f.write(data)
                # -----------------------

                await websocket.send_text(f"Saved: {file_name}")

    except WebSocketDisconnect:
        print("[System] WebSocket 연결 해제됨")
