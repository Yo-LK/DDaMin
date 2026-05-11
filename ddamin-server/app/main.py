from fastapi import FastAPI
from app.routers import upload, orb_slam

app = FastAPI()

app.include_router(upload.router)
app.include_router(orb_slam.router)