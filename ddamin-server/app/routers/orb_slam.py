import csv
import struct
import uuid
from pathlib import Path
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

_IMU_ENTRY_FMT  = '<d3f3f'
_IMU_ENTRY_SIZE = struct.calcsize(_IMU_ENTRY_FMT)  # 32 bytes


@router.websocket("/ws/orb-slam")
async def orb_slam_ws(websocket: WebSocket):
    await websocket.accept()

    session_id  = str(uuid.uuid4())
    imu_csv_path = UPLOAD_DIR / f"imu_{session_id}.csv"

    with open(imu_csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            "frame_number",
            "timestamp_ms",
            "ax", "ay", "az",
            "gx", "gy", "gz",
        ])

    try:
        while True:
            data = await websocket.receive_bytes()

            if len(data) < 6:
                continue

            frame_number = struct.unpack_from('<I', data, 0)[0]
            imu_count    = struct.unpack_from('<H', data, 2)[0]
            imu_end      = 6 + imu_count * _IMU_ENTRY_SIZE

            if len(data) < imu_end:
                continue

            imu_points = []
            rows = []
            for i in range(imu_count):
                offset = 6 + i * _IMU_ENTRY_SIZE
                ts, ax, ay, az, gx, gy, gz = struct.unpack_from(
                    _IMU_ENTRY_FMT, data, offset
                )
                imu_points.append({
                    "timestamp_ms": ts,
                    "accel": (ax, ay, az),
                    "gyro":  (gx, gy, gz),
                })
                rows.append([frame_number, ts, ax, ay, az, gx, gy, gz])

            with open(imu_csv_path, 'a', newline='') as f:
                writer = csv.writer(f)
                writer.writerows(rows)

            frame = data[imu_end:]
            result = process_orb_slam(frame, imu_points)
            await websocket.send_bytes(result)

    except WebSocketDisconnect:
        pass


def process_orb_slam(frame: bytes, imu_points: list[dict]) -> bytes:
    # TODO: ORB-SLAM3 연동
    return frame