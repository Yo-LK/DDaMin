# DDaMin Flutter App

스마트폰 카메라 기반 SLAM 플랫폼의 Flutter 클라이언트 앱 (iOS)

---

## 개요

두 가지 모드를 제공하는 이원화 SLAM 플랫폼의 모바일 클라이언트

| 모드 | 설명 |
|------|------|
| **COLMAP** | 갤러리 영상을 서버로 전송하여 고정밀 3D 재구성 |
| **ORB-SLAM** | 실시간 카메라 피드를 서버로 스트리밍하여 실시간 매핑 |

---

## 프로젝트 구조

```
lib/
├── core/
│   ├── constants/
│   ├── error/
│   └── utils/
├── data/
│   ├── local/
│   ├── models/
│   └── remote/
├── features/
│   ├── auth/                  # 로그인/회원가입
│   ├── contributor/           # COLMAP 영상 업로드
│   ├── history/               # 업로드 히스토리
│   ├── home/                  # 모드 선택 홈화면
│   ├── navigator_mode/        # 지도 다운로드 / AR 네비게이션
│   ├── orb_slam/              # ORB-SLAM 실시간 촬영
│   │   ├── screens/
│   │   ├── providers/
│   │   └── services/
│   └── relocalization/        # 재지역화
├── ffi/                       # Native 연동
├── network/                   # Dio 클라이언트, WebSocket
├── shared/
│   ├── providers/
│   └── widgets/
├── app.dart                   # 라우팅
└── main.dart
```

---

## 환경 설정

### 요구사항

- Flutter SDK
- Xcode (iOS 빌드)
- iOS 기기 (카메라 기능 사용)

### 설치

```bash
flutter pub get
```

### 환경변수

프로젝트 루트(`flutter/`)에 `.env` 파일 생성:

```
ORB_SLAM_WS_URL=ws://서버IP:포트/ws/orb-slam
```

`.env.example` 참고

---

## 주요 패키지

| 패키지 | 용도 |
|--------|------|
| `flutter_riverpod` | 상태 관리 |
| `go_router` | 라우팅 |
| `camera` | 실시간 카메라 스트림 |
| `web_socket_channel` | WebSocket 통신 |
| `image` | JPEG 인코딩 |
| `dio` | HTTP 통신 |
| `image_picker` | 갤러리 영상 선택 |
| `sensors_plus` | IMU 센서 데이터 |
| `geolocator` | 위치 정보 |
| `flutter_dotenv` | 환경변수 관리 |

---

## ORB-SLAM 스트리밍 스펙

- 전송 방식: WebSocket (binary)
- 프레임 포맷: JPEG (quality 70)
- 전송 fps: 10fps
- 카메라 해상도: 640x480 (ResolutionPreset.medium)
- iOS raw 프레임: BGRA8888 → JPEG 변환 후 전송

---

## iOS 권한

`ios/Runner/Info.plist`에 아래 항목 필요:

```xml
<key>NSCameraUsageDescription</key>
<string>실시간 SLAM 촬영을 위해 카메라 접근이 필요합니다.</string>
```

---

## 서버 연동

| 기능 | 방식 | 엔드포인트 |
|------|------|------------|
| COLMAP 영상 업로드 | HTTP Multipart / Chunked | `/upload` |
| ORB-SLAM 프레임 스트리밍 | WebSocket | `/ws/orb-slam` |

서버: [ddamin-server](../ddamin-server) 참고