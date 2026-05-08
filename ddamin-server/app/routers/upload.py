import uuid
import os
from fastapi import APIRouter, UploadFile, File
from dotenv import load_dotenv

load_dotenv()

router = APIRouter()

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

@router.post("/upload/video")
async def upload_video(file: UploadFile = File(...)):
    session_id = str(uuid.uuid4())
    save_path = os.path.join(UPLOAD_DIR, f"{session_id}.mp4")

    with open(save_path, "wb") as f:
        content = await file.read()
        f.write(content)

    return {"message": "success", "session_id": session_id}
