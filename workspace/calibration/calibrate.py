import cv2
import numpy as np
import glob
import os

# ── 설정 ──────────────────────────────────────────────
IMAGE_DIR    = "/Users/lim/Downloads/orb/*.jpg"
OUTPUT_YAML  = "/Users/lim/Downloads/orb/iphone13mini_480x640.yaml" 
BOARD_COLS   = 5   # 내부 코너 수 (가로)
BOARD_ROWS   = 8   # 내부 코너 수 (세로)
SQUARE_SIZE  = 25.0  # mm

# 첨부해주신 이미지 속성에 맞춰 가로 480, 세로 640으로 설정
IMG_W, IMG_H = 480, 640 
# ──────────────────────────────────────────────────────

objp = np.zeros((BOARD_ROWS * BOARD_COLS, 3), np.float32)
objp[:, :2] = np.mgrid[0:BOARD_COLS, 0:BOARD_ROWS].T.reshape(-1, 2) * SQUARE_SIZE

obj_points = []
img_points = []

images = sorted(glob.glob(IMAGE_DIR))
print(f"이미지 {len(images)}장 로드")

for path in images:
    img = cv2.imread(path)
    if img is None:
        print(f"  ✗ {os.path.basename(path)} — 로드 실패 (스킵)")
        continue
    
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    ret, corners = cv2.findChessboardCorners(gray, (BOARD_COLS, BOARD_ROWS), None)
    if ret:
        corners_refined = cv2.cornerSubPix(
            gray, corners, (11, 11), (-1, -1),
            (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
        )
        obj_points.append(objp)
        img_points.append(corners_refined)
        print(f"  ✓ {os.path.basename(path)}")
    else:
        print(f"  ✗ {os.path.basename(path)} — 코너 검출 실패")

print(f"\n유효 이미지: {len(obj_points)}/{len(images)}")

if len(obj_points) < 10:
    print("유효 이미지가 너무 적음. 사진을 다시 찍어야 해.")
    exit(1)

ret, K, dist, rvecs, tvecs = cv2.calibrateCamera(
    obj_points, img_points, (IMG_W, IMG_H), None, None
)

fx, fy = K[0, 0], K[1, 1]
cx, cy = K[0, 2], K[1, 2]
k1, k2, p1, p2, k3 = dist[0]

# 재투영 오차 계산
total_err = 0
for i in range(len(obj_points)):
    projected, _ = cv2.projectPoints(obj_points[i], rvecs[i], tvecs[i], K, dist)
    total_err += cv2.norm(img_points[i], projected, cv2.NORM_L2) / len(projected)
rpe = total_err / len(obj_points)
print(f"재투영 오차(RPE): {rpe:.4f} px")

# ORB-SLAM3 YAML 생성
data = f"""%YAML:1.0

# Camera Calibration Parameters
Camera.type: "PinHole"

Camera.fx: {fx:.6f}
Camera.fy: {fy:.6f}
Camera.cx: {cx:.6f}
Camera.cy: {cy:.6f}

# Distortion Parameters
Camera.k1: {k1:.6f}
Camera.k2: {k2:.6f}
Camera.p1: {p1:.6f}
Camera.p2: {p2:.6f}

# Image Dimension & Settings
Camera.width: {IMG_W}
Camera.height: {IMG_H}
Camera.fps: 30
Camera.RGB: 1

# ORB Extractor Parameters
ORBextractor.nFeatures: 1000
ORBextractor.scaleFactor: 1.2
ORBextractor.nLevels: 8
ORBextractor.iniThFAST: 20
ORBextractor.minThFAST: 7

# IMU (iPhone 13 mini 근사값)
IMU.NoiseGyro: 1.7e-4
IMU.NoiseAcc: 2.0e-3
IMU.GyroWalk: 1.9393e-5
IMU.AccWalk: 3.0e-3
IMU.Frequency: 100

# Tbc: 카메라-IMU 외부 파라미터
Tbc: !!opencv-matrix
   rows: 4
   cols: 4
   dt: f
   data: [1,0,0,0,
          0,1,0,0,
          0,0,1,0,
          0,0,0,1]

# 궤적 및 포인트 클라우드 시각화 파라미터
Viewer.KeyFrameSize: 0.05
Viewer.KeyFrameLineWidth: 1.0
Viewer.GraphLineWidth: 0.9
Viewer.PointSize: 2.0
Viewer.CameraSize: 0.08
Viewer.CameraLineWidth: 3.0
Viewer.ViewpointX: 0.0
Viewer.ViewpointY: -0.7
Viewer.ViewpointZ: -1.8
Viewer.ViewpointF: 500.0
"""

with open(OUTPUT_YAML, "w") as f:
    f.write(data)

print(f"\nyaml 저장 완료: {OUTPUT_YAML}")
print(f"fx={fx:.2f}, fy={fy:.2f}, cx={cx:.2f}, cy={cy:.2f}")
print(f"k1={k1:.6f}, k2={k2:.6f}, p1={p1:.6f}, p2={p2:.6f}")