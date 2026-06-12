from __future__ import annotations

import argparse
import os
from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image
from transformers import SegformerForSemanticSegmentation, SegformerImageProcessor

REMOVE_CLASSES: dict[int, str] = {
    2:  "sky",
    4:  "tree",
    9:  "grass",
    17: "plant",
    21: "water",
    26: "sea",
    29: "field",
}

OPTIONAL_REMOVE: dict[int, str] = {
    16: "mountain",
}

SUPPORTED_EXT = {".jpg", ".jpeg", ".png", ".bmp"}


def load_model(device: str) -> tuple[SegformerImageProcessor, SegformerForSemanticSegmentation]:
    print("[INFO] Loading SegFormer-b2 (ADE20K) model...")
    processor = SegformerImageProcessor.from_pretrained(
        "nvidia/segformer-b2-finetuned-ade-512-512"
    )
    model = SegformerForSemanticSegmentation.from_pretrained(
        "nvidia/segformer-b2-finetuned-ade-512-512"
    ).to(device)
    model.eval()
    print(f"[INFO] Model loaded | device: {device}\n")
    return processor, model


def process_image(
    img_bgr: np.ndarray,
    processor: SegformerImageProcessor,
    model: SegformerForSemanticSegmentation,
    device: str,
    remove_mountain: bool,
) -> tuple[np.ndarray, np.ndarray]:
    h, w = img_bgr.shape[:2]

    pil_img = Image.fromarray(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))

    inputs = processor(images=pil_img, return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = model(**inputs)

    seg_map = (
        torch.nn.functional.interpolate(
            outputs.logits, size=(h, w), mode="bilinear", align_corners=False
        )
        .argmax(dim=1)
        .squeeze()
        .cpu()
        .numpy()
    )

    target = dict(REMOVE_CLASSES)
    if remove_mountain:
        target.update(OPTIONAL_REMOVE)

    mask = np.zeros((h, w), dtype=np.uint8)
    for class_idx in target:
        mask[seg_map == class_idx] = 255

    masked_img = _apply_mask_with_blur(img_bgr, mask)
    return masked_img, mask


def _apply_mask_with_blur(
    img_bgr: np.ndarray,
    mask: np.ndarray,
    blur_kernel: int = 11,
) -> np.ndarray:
    result = img_bgr.copy()
    result[mask == 255] = 0

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (blur_kernel, blur_kernel))
    dilated = cv2.dilate(mask, kernel, iterations=1)
    edge_mask = (dilated == 255) & (mask == 0)

    if edge_mask.any():
        mask_blur = cv2.GaussianBlur(mask, (blur_kernel, blur_kernel), 0)
        alpha = mask_blur[edge_mask].astype(np.float32) / 255.0
        for c in range(3):
            result[edge_mask, c] = (
                img_bgr[edge_mask, c].astype(np.float32) * (1.0 - alpha)
            ).astype(np.uint8)

    return result


def process_folder(
    input_dir: str,
    output_dir: str,
    processor: SegformerImageProcessor,
    model: SegformerForSemanticSegmentation,
    device: str,
    remove_mountain: bool,
    save_mask: bool,
) -> None:
    rgb_dir = os.path.join(output_dir, "rgb")
    mask_dir = os.path.join(output_dir, "masks")
    os.makedirs(rgb_dir, exist_ok=True)
    if save_mask:
        os.makedirs(mask_dir, exist_ok=True)

    files = sorted(
        f for f in Path(input_dir).iterdir() if f.suffix.lower() in SUPPORTED_EXT
    )

    if not files:
        print(f"[ERROR] No images found in '{input_dir}'.")
        return

    total = len(files)
    removed_ratios: list[float] = []

    print(f"{'='*55}")
    print(f"  Processing {total} images")
    print(f"{'='*55}\n")

    for idx, file in enumerate(files, 1):
        img = cv2.imread(str(file))
        if img is None:
            print(f"  [SKIP] Failed to read: {file.name}")
            continue

        masked_img, mask = process_image(img, processor, model, device, remove_mountain)

        if not cv2.imwrite(os.path.join(rgb_dir, file.name), masked_img):
            print(f"  [ERROR] Failed to save: {file.name}")
        if save_mask:
            cv2.imwrite(os.path.join(mask_dir, file.name), mask)

        ratio = (mask == 255).sum() / mask.size * 100
        removed_ratios.append(ratio)
        print(f"  [{idx:4d}/{total}] {file.name:30s}  removed: {ratio:5.1f}%")

    avg_ratio = np.mean(removed_ratios) if removed_ratios else 0.0
    print(f"\n{'='*55}")
    print(f"  Done")
    print(f"  Total images      : {total}")
    print(f"  Avg removed ratio : {avg_ratio:.1f}%")
    if avg_ratio > 60:
        print(f"  WARNING: High removal ratio. Consider adjusting REMOVE_CLASSES.")
    print(f"  Output            : {output_dir}")
    print(f"{'='*55}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SegFormer-b2 ADE20K semantic masking for mountain terrain images"
    )
    parser.add_argument("--input", type=str, required=True, help="Input image folder")
    parser.add_argument("--output", type=str, required=True, help="Output folder")
    parser.add_argument("--remove_mountain", action="store_true", help="Also mask distant mountains")
    parser.add_argument("--save_mask", action="store_true", help="Save binary masks separately")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    device = "cuda" if torch.cuda.is_available() else "cpu"

    print(f"\n{'='*55}")
    print(f"  SegFormer-b2 (ADE20K) Mountain Terrain Masking")
    print(f"{'='*55}")
    print(f"  Device         : {device}")
    print(f"  Remove classes :")
    for idx, name in REMOVE_CLASSES.items():
        print(f"    [{idx:3d}] {name}")
    if args.remove_mountain:
        print(f"    [ 16] mountain  (optional ON)")
    print(f"  Save masks     : {'ON' if args.save_mask else 'OFF'}")
    print(f"{'='*55}\n")

    processor, model = load_model(device)
    process_folder(
        args.input, args.output,
        processor, model, device,
        args.remove_mountain, args.save_mask,
    )
