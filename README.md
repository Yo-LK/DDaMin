## 경로
수정 파일 (기존 파일 교체)
flutter/lib/features/orb_slam/services/orb_slam_service.dart

신규 파일 (새로 생성)
flutter/lib/features/orb_slam/services/frame_filter_service.dart

# 클라이언트 프레임 필터링 파이프라인 (Flutter 구현)

Python 레퍼런스(`client_pipeline.py`) 기반으로 Flutter에 포팅한 구현체.  
카메라 30fps 스트림에서 블러 프레임과 중복 프레임을 제거하여 서버로 고품질 프레임만 전송한다.

---

## 파일 구성

```
flutter/lib/features/orb_slam/services/
├── frame_filter_service.dart   # 신규 — 블러 감지 / 중복 감지 유틸
└── orb_slam_service.dart       # 수정 — 버퍼 기반 파이프라인으로 교체
```

---

## frame_filter_service.dart (신규)

프레임 품질 판별에 필요한 순수 정적 유틸 클래스.

### 상수

| 상수 | 값 | 설명 |
|---|---|---|
| `kBlurThreshold` | `300.0` | 라플라시안 분산 임계값. 미달 시 블러 프레임으로 판단 |
| `kSimilarityThreshold` | `0.98` | 히스토그램 유사도 임계값. 이상 시 중복으로 판단 |
| `kDownWidth` | `320` | 블러 계산용 다운샘플 가로 크기 |
| `kDownHeight` | `240` | 블러 계산용 다운샘플 세로 크기 |

### 메서드

#### `extractGrayBytes()`

```dart
static Uint8List? extractGrayBytes({
  required Uint8List bgraBytes,
  required int srcWidth,
  required int srcHeight,
})
```

- BGRA8888 raw bytes를 320×240 그레이스케일 bytes로 변환
- 변환식: `Gray = 0.299R + 0.587G + 0.114B`
- 블러 계산 전 다운샘플링으로 연산 비용 절감
- 640×480 입력 기준 scaleX=2.0, scaleY=2.0 (정확히 2:1 비율)

#### `laplacianVariance()`

```dart
static double laplacianVariance(Uint8List gray, {int width, int height})
```

- 라플라시안 커널(`[0,1,0; 1,-4,1; 0,1,0]`) 적용 후 분산값 반환
- 값이 높을수록 선명한 프레임
- Python `cv2.Laplacian(gray, cv2.CV_64F).var()` 와 동일한 결과

#### `histogramSimilarity()`

```dart
static double histogramSimilarity(Uint8List gray1, Uint8List gray2)
```

- 정규화 히스토그램 상관계수로 두 그레이스케일 이미지의 유사도 반환 (`0.0 ~ 1.0`)
- Python `skimage.metrics.structural_similarity` (SSIM) 대체
- SSIM보다 연산이 빠르고 Dart 구현이 단순함

---

## orb_slam_service.dart (수정)

### 변경 전 vs 변경 후

| 항목 | 변경 전 | 변경 후 |
|---|---|---|
| 프레임 선택 | 100ms마다 도착하는 첫 프레임 그대로 전송 | 100ms 버퍼에서 가장 선명한 1장 선택 |
| 블러 감지 | 없음 | 라플라시안 분산 ≥ 300 통과 |
| 중복 제거 | 없음 | 히스토그램 유사도 < 0.98 이어야 전송 |
| 프레임 복사 | 콜백 내 즉시 JPEG 변환 | 콜백에서 bytes 즉시 복사 후 큐 적재 |

### 추가된 내부 구조

#### `_FrameEntry`

```dart
class _FrameEntry {
  final DateTime timestamp;
  final Uint8List grayBytes; // 320×240 그레이스케일 — 블러 점수 계산용
  final Uint8List bgraBytes; // 원본 BGRA — JPEG 변환용
  final int width;
  final int height;
}
```

큐에 적재되는 프레임 단위. `CameraImage`는 콜백 반환 후 재사용될 수 있으므로 bytes를 즉시 복사하여 보관한다.

#### `_frameQueue`

- 최대 15장을 유지하는 링버퍼
- `_onFrame()`에서 프레임 적재, `_processBuffer()`에서 소비

#### `_sendTimer`

- `Timer.periodic(100ms)`로 `_processBuffer()`를 주기적으로 호출

#### `_lastSentGray`

- 마지막으로 전송한 프레임의 그레이스케일 bytes
- 다음 전송 후보와 히스토그램 유사도 비교에 사용

### 파이프라인 흐름

```
카메라 30fps → _onFrame()
  └── BGRA bytes 복사 (640×480)
  └── 320×240 그레이스케일 추출
  └── _frameQueue 적재 (최대 15장)

100ms Timer → _processBuffer()
  └── Step 1. 큐 스냅샷 & 비우기 (약 3장 @ 30fps)
  └── Step 2. 라플라시안 분산 계산 → score < 300 제거
  └── Step 3. score 최고 프레임 1장 선택
  └── Step 4. 히스토그램 유사도 ≥ 0.98 → 중복 제거
  └── JPEG 인코딩 (640×480, quality 70) → 패킷 조립 → WebSocket 전송
```

### 패킷 구조 (기존과 동일)

```
[4B: frame_number (uint32 LE)]
[2B: IMU count N (uint16 LE)]
[N × 32B: IMU entries]
  └── [8B: timestamp ms (float64)]
  └── [4B: ax (float32)] [4B: ay] [4B: az]
  └── [4B: gx (float32)] [4B: gy] [4B: gz]
[나머지: JPEG bytes]
```

---

## 파라미터 조정

`frame_filter_service.dart` 상단 상수를 수정하여 조정한다.

```dart
const double kBlurThreshold = 300.0;      // 높일수록 더 엄격하게 블러 제거
const double kSimilarityThreshold = 0.98; // 낮출수록 더 자주 전송
```

`orb_slam_service.dart` 상단 상수로 버퍼 크기와 전송 주기를 조정한다.

```dart
static const int _maxQueueSize = 15;    // 링버퍼 최대 크기
static const int _sendIntervalMs = 100; // 전송 타이밍 간격 (ms)
```
