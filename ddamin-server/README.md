# DDaMin Server

ORB-SLAM3 기반 실시간 시각 SLAM 시스템의 FastAPI 백엔드 서버.

## Stack

- Python 3.10+
- FastAPI
- Uvicorn
- WebSocket

## Project Structure

```
ddamin-server/
├── app/
│   ├── __init__.py
│   ├── main.py
│   └── routers/
│       ├── __init__.py
│       ├── upload.py
│       └── orb_slam.py
├── uploads/
├── .env
├── .gitignore
├── requirements.txt
└── README.md
```

## Setup

```bash
pip install -r requirements.txt
```

## Environment Variables

`.env` 파일 생성 후 아래 값 설정:

```
UPLOAD_DIR=uploads
BASE_URL=https://your-ngrok-url
ORB_SLAM_WS_URL=wss://your-ngrok-url/ws/orb-slam
```

## Run

```bash
uvicorn app.main:app --reload
```

## API

### POST /upload/video

mp4 파일 업로드.

- Request: `multipart/form-data`, field: `file`
- Response: `{ "message": "success", "session_id": "uuid" }`

### WebSocket /ws/orb-slam

실시간 카메라 프레임 수신 및 처리.

- 수신: JPEG binary (10fps)
- 송신: 처리 결과 binary 또는 JSON