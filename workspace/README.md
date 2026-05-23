# ORB-SLAM3 Mobile-Server Real-Time Visual SLAM Pipeline

스마트폰(iPhone)에서 촬영한 영상과 IMU 데이터를 서버로 실시간 스트리밍하여 ORB-SLAM3로 3D 맵을 생성하는 하이브리드 Visual SLAM 시스템의 서버 구현입니다.

---

## 프로젝트 구조

```
workspace/
├── main.py                              # FastAPI 서버 (WebSocket 수신 + FIFO 전달)
├── calibration/
│   └── calibrate.py                     # iPhone 카메라 캘리브레이션 스크립트
├── ORB_SLAM3/
│   ├── Examples/Monocular-Inertial/
│   │   └── mono_inertial_fifo.cc        # FIFO 기반 실시간 ORB-SLAM3 실행
│   └── run_slam.sh                      # ORB-SLAM3 실행 스크립트
└── visualization/
    ├── visualize_pointcloud.py          # 맵 포인트 클라우드 시각화
    └── visualize_trajectory.py          # 카메라 궤적 시각화
```

---

## 시스템 아키텍처

```
[Flutter iOS 앱]
      │
      │  WebSocket (/ws/orb-slam)
      │  패킷: [4B frame_number][2B imu_count][N×32B IMU][JPEG]
      ▼
[FastAPI 서버 - main.py]
      │
      │  FIFO (/tmp/slam_pipe)
      ▼
[ORB-SLAM3 - mono_inertial_fifo.cc]
      │
      ▼
[결과물: KeyFrameTrajectory.txt / MapPoints.txt]
```

---

## 환경

- **서버**: Docker 컨테이너 (Ubuntu + CUDA)
- **카메라**: iPhone 13 mini (`ResolutionPreset.medium`, 640×480)
- **ORB-SLAM3**: [UZ-SLAMLab/ORB_SLAM3](https://github.com/UZ-SLAMLab/ORB_SLAM3)
- **의존성**: FastAPI, OpenCV, Pangolin

---

## 설치 및 빌드

### 1. ORB-SLAM3 클론 및 빌드
```bash
git clone https://github.com/UZ-SLAMLab/ORB_SLAM3.git /workspace/ORB_SLAM3
cd /workspace/ORB_SLAM3
chmod +x build.sh && ./build.sh
```

### 2. mono_inertial_fifo 빌드
`CMakeLists.txt`에 아래 내용 추가 후 빌드:
```cmake
add_executable(mono_inertial_fifo
    Examples/Monocular-Inertial/mono_inertial_fifo.cc)
target_link_libraries(mono_inertial_fifo ${PROJECT_NAME})
set_target_properties(mono_inertial_fifo PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/Examples/Monocular-Inertial")
```
```bash
cd /workspace/ORB_SLAM3/build && make -j4
```

### 3. FastAPI 의존성 설치
```bash
pip install fastapi uvicorn python-multipart
```

---

## 카메라 캘리브레이션

iPhone과 동일한 해상도로 체커보드(9×6, 25mm) 사진 20장 이상 촬영 후 실행:

```bash
pip install opencv-python numpy
python calibration/calibrate.py
```

결과 yaml 파일을 `/app/config/` 에 배치.

---

## 실행 방법

### 실시간 모드

```bash
# 터미널 1: ORB-SLAM3 먼저 실행
bash /workspace/ORB_SLAM3/run_slam.sh

# 터미널 2: FastAPI 서버
cd /workspace
uvicorn main:app --host 0.0.0.0 --port 8000
```

Flutter 앱에서 스트리밍 시작 후 `Ctrl+C`로 종료하면 결과 파일 자동 저장.

### 오프라인 모드 (저장 데이터 재처리)

서버에 쌓인 프레임 데이터로 ORB-SLAM3 재실행:
```bash
cd /workspace/ORB_SLAM3
./Examples/Monocular-Inertial/mono_offline \
    Vocabulary/ORBvoc.txt \
    /app/config/iphone13mini_480x640.yaml
```

---

## 출력 파일

| 파일 | 위치 | 형식 |
|------|------|------|
| 카메라 궤적 | `/app/slam_output/KeyFrameTrajectory.txt` | TUM: `timestamp tx ty tz qx qy qz qw` |
| 맵 포인트 | `/app/slam_output/MapPoints.txt` | `x y z` |
| 수신 프레임 | `/app/slam_images/frame_{ts}_{fn}.jpg` | JPEG |
| IMU 데이터 | `/app/slam_images/imu_{uuid}.csv` | CSV |

---

## 결과 시각화

Windows/Mac에서 결과 파일을 꺼낸 후 실행:

```bash
pip install matplotlib numpy

# 포인트 클라우드 (3D 맵)
python visualization/visualize_pointcloud.py MapPoints.txt

# 카메라 궤적
python visualization/visualize_trajectory.py KeyFrameTrajectory.txt
```

---

## .gitignore 권장

```
__pycache__/
*.pyc
slam_images/
slam_output/
video_upload/
*.csv
ORB_SLAM3/build/
ORB_SLAM3/lib/
ORB_SLAM3/Thirdparty/
.env
```