import uuid
import os
from fastapi import APIRouter, UploadFile, File, Form
from dotenv import load_dotenv

load_dotenv()

router = APIRouter()

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# 진행 중인 세션 관리 (chunk_index 0일 때 session_id 생성)
_sessions = {}

@router.post("/api/video/upload")
async def upload_video(
    file: UploadFile = File(...),
    chunk_index: int = Form(...),
    total_chunks: int = Form(...),
    file_name: str = Form(...),
    is_last: str = Form(...),
):
    # 첫 청크일 때 session_id 생성
    if chunk_index == 0:
        session_id = str(uuid.uuid4())
        _sessions[file_name] = session_id
    else:
        session_id = _sessions.get(file_name, str(uuid.uuid4()))

    save_path = os.path.join(UPLOAD_DIR, f"{session_id}.mp4")

    with open(save_path, "ab") as f:
        while data := await file.read(1024 * 1024):
            f.write(data)

    if is_last == "true":
        _sessions.pop(file_name, None)
        return {"message": "success", "session_id": session_id}

    return {"message": "chunk received", "chunk_index": chunk_index}