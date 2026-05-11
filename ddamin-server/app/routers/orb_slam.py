from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()


@router.websocket("/ws/orb-slam")
async def orb_slam_ws(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_bytes()

            # ORB-SLAM 처리 (서버 측 구현 예정)
            result = process_orb_slam(data)

            await websocket.send_bytes(result)
    except WebSocketDisconnect:
        pass


def process_orb_slam(data: bytes) -> bytes:
    # TODO: ORB-SLAM 처리 로직
    return data