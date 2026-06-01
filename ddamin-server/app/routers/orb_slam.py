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

    try:
        while True:
            data = await websocket.receive_bytes()

            if len(data) < 6:
                continue

            # ⭕ 플러터와 완벽하게 일치하는 6바이트 헤더 파싱
            frame_number = struct.unpack_from('<I', data, 0)[0]
            imu_count    = struct.unpack_from('<H', data, 4)[0]

            _IMU_ENTRY_SIZE = 32
            imu_end = 6 + imu_count * _IMU_ENTRY_SIZE 

            if len(data) < imu_end:
                continue

            imu_points = []
            rows = []
            for i in range(imu_count):
                offset = 6 + i * _IMU_ENTRY_SIZE
                ts, ax, ay, az, gx, gy, gz = struct.unpack_from(_IMU_ENTRY_FMT, data, offset)
                rows.append([frame_number, ts, ax, ay, az, gx, gy, gz])

            with open(imu_csv_path, 'a', newline='') as f:
                writer = csv.writer(f)
                writer.writerows(rows)

            frame = data[imu_end:] 

            # C++ FIFO 파이프 연결 및 전송 로직
            global _fifo_fd
            if _fifo_fd is None:
                try:
                    _fifo_fd = os.open(FIFO_PATH, os.O_WRONLY)
                    print("[SLAM] C++ ORB-SLAM3 FIFO 파이프 연결 성공!")
                except Exception:
                    pass # C++이 켜질 때까지 패스

            if _fifo_fd is not None:
                fifo_header = struct.pack('<IH', len(frame), imu_count)
                raw_imu_bytes = data[6:imu_end]
                
                payload = fifo_header + raw_imu_bytes + frame
                
                bytes_written = 0
                while bytes_written < len(payload):
                    w = os.write(_fifo_fd, payload[bytes_written:])
                    if w == 0:
                        break
                    bytes_written += w

            await websocket.send_bytes(frame)

    except WebSocketDisconnect:
        pass


