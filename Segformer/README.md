# SegFormer 산악 지형 시멘틱 마스킹

**SegFormer-b2 (ADE20K)** 세그멘테이션 모델을 활용하여 산악 환경 이미지에서 특징점 추출에 방해가 되는 영역(하늘, 식생, 수면 등)을 자동으로 제거하는 전처리 도구입니다.  
ORB-SLAM3 파이프라인의 전처리 단계로 설계되었습니다.

---

## 동작 방식

1. 입력 이미지에 SegFormer-b2 추론을 수행하여 픽셀 단위 클래스 맵 생성
2. 제거 대상 클래스(하늘, 나무, 풀 등)에 해당하는 바이너리 마스크 생성
3. 마스크 경계에 가우시안 블러를 적용하여 경계선에서 발생하는 FAST 코너 오검출 억제
4. 결과 이미지를 `<output>/rgb/`에 저장, 옵션에 따라 마스크를 `<output>/masks/`에 별도 저장

---

## 요구 사항

- Python 3.9 이상
- CUDA GPU 권장 (없을 경우 CPU로 자동 전환)

```bash
pip install transformers torch torchvision pillow opencv-python
```

> 최초 실행 시 모델 가중치(약 200MB)가 Hugging Face에서 자동 다운로드되어 `~/.cache/huggingface/`에 캐시됩니다.

---

## 사용법

```bash
python make_masked_segformer.py --input <입력_폴더> --output <출력_폴더> [옵션]
```

### 인자

| 인자 | 필수 여부 | 설명 |
|---|---|---|
| `--input` | ✅ | 입력 이미지 폴더 경로 |
| `--output` | ✅ | 출력 폴더 경로 |
| `--remove_mountain` | ❌ | 원거리 산 능선 추가 제거 (ADE20K 클래스 16) |
| `--save_mask` | ❌ | 바이너리 마스크를 `<output>/masks/`에 별도 저장 |

### 예시

```bash
# 기본 실행
python make_masked_segformer.py --input ./snapshots --output ./masked_output

# 산 능선 제거 + 마스크 저장
python make_masked_segformer.py --input ./snapshots --output ./masked_output --remove_mountain --save_mask
```

---

## 출력 구조

```
masked_output/
├── rgb/          # 마스킹이 적용된 이미지 (제거 영역 검정 처리)
│   ├── frame_001.jpg
│   └── ...
└── masks/        # 바이너리 마스크 (--save_mask 옵션 사용 시 생성)
    ├── frame_001.jpg
    └── ...
```

마스크 픽셀값: `255` = 제거된 영역, `0` = 유지된 영역

---

## 제거 클래스 (ADE20K)

| 클래스 ID | 레이블 | 제거 이유 |
|---|---|---|
| 2 | sky (하늘) | 깊이 정보 없음 |
| 4 | tree (나무) | 반복 텍스처, 흔들림에 의한 노이즈 |
| 9 | grass (잔디) | 균일한 패턴 |
| 17 | plant (식생) | 밀집된 초목 |
| 21 | water (물) | 반사면 |
| 26 | sea (수면) | 반사면 |
| 29 | field (들판) | 균일한 패턴 |
| 16 | mountain (산) | 원거리 능선 — `--remove_mountain` 옵션으로 선택 제거 |

제거 클래스를 수정하려면 `make_masked_segformer.py` 내의 `REMOVE_CLASSES` 또는 `OPTIONAL_REMOVE`를 직접 편집하세요.

---

## 지원 포맷

`.jpg` `.jpeg` `.png` `.bmp`

---

## 사용 모델

[nvidia/segformer-b2-finetuned-ade-512-512](https://huggingface.co/nvidia/segformer-b2-finetuned-ade-512-512)
