import csv
import struct
import uuid
import os
from pathlib import Path
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

FIFO_PATH = "/tmp/slam_pipe"
_fifo_fd = None

_IMU_ENTRY_FMT  = '<d3f3f'
_IMU_ENTRY_SIZE = struct.calcsize(_IMU_ENTRY_FMT)  # 32 bytes


@router.websocket("/ws/orb-slam")
async def orb_slam_ws(websocket: WebSocket):
    await websocket.accept()

    session_id  = str(uuid.uuid4())
    imu_csv_path = UPLOAD_DIR / f"imu_{session_id}.csv"

    with open(imu_csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["frame_number", "timestamp_ms", "ax", "ay", "az", "gx", "gy", "gz"])

    global _fifo_fd
    
    try:
        while True:
            data = await websocket.receive_bytes()

            if len(data) < 6:
                continue

            frame_number = struct.unpack_from('<I', data, 0)[0]
            imu_count    = struct.unpack_from('<H', data, 4)[0]

            _IMU_ENTRY_SIZE = 32
            imu_end = 6 + imu_count * _IMU_ENTRY_SIZE 

            if len(data) < imu_end:
                continue

            rows = []
            for i in range(imu_count):
                offset = 6 + i * _IMU_ENTRY_SIZE
                ts, ax, ay, az, gx, gy, gz = struct.unpack_from(_IMU_ENTRY_FMT, data, offset)
                rows.append([frame_number, ts, ax, ay, az, gx, gy, gz])

            with open(imu_csv_path, 'a', newline='') as f:
                writer = csv.writer(f)
                writer.writerows(rows)

            frame = data[imu_end:] 

            # C++ FIFO 파이프 연결 및 전송
            if _fifo_fd is None:
                try:
                    _fifo_fd = os.open(FIFO_PATH, os.O_WRONLY | os.O_NONBLOCK)
                    print("[SLAM] C++ ORB-SLAM3 FIFO 파이프 연결 성공!")
                except Exception:
                    pass

            if _fifo_fd is not None:
                try:
                    fifo_header = struct.pack('<IH', len(frame), imu_count)
                    raw_imu_bytes = data[6:imu_end]
                    payload = fifo_header + raw_imu_bytes + frame
                    
                    bytes_written = 0
                    while bytes_written < len(payload):
                        try:
                            w = os.write(_fifo_fd, payload[bytes_written:])
                            if w <= 0:
                                _fifo_fd = None
                                break
                            bytes_written += w
                        except OSError:
                            _fifo_fd = None
                            break
                except BrokenPipeError:
                    print("[SLAM] C++ 프로그램이 종료되어 파이프가 끊겼습니다.")
                    os.close(_fifo_fd)
                    _fifo_fd = None

            await websocket.send_bytes(frame)

    except WebSocketDisconnect:
        print("[SLAM] 플러터 앱과의 웹소켓 연결이 종료되었습니다.")
    except Exception as e:
        print(f"[SLAM] 서버 에러 발생: {e}")
    finally:
        # 🔥 핵심: 앱이 끊어지거나 에러가 나면 무조건 파이프를 닫아줍니다!
        # 이렇게 해야 C++이 무한 대기에 빠지지 않고 안전하게 리셋됩니다.
        if _fifo_fd is not None:
            try:
                os.close(_fifo_fd)
            except:
                pass
            _fifo_fd = None
            print("[SLAM] FIFO 파이프를 안전하게 닫았습니다.")

