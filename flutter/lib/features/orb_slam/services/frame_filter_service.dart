import 'dart:math' as math;
import 'dart:typed_data';

const double kBlurThreshold = 1.0;
const double kSimilarityThreshold = 0.9999;
const int kDownWidth = 320;
const int kDownHeight = 240;

class FrameFilterService {
  FrameFilterService._();

  /// BGRA8888 raw bytes → 320×240 grayscale bytes
  static Uint8List? extractGrayBytes({
    required Uint8List bgraBytes,
    required int srcWidth,
    required int srcHeight,
  }) {
    try {
      final out = Uint8List(kDownWidth * kDownHeight);
      final scaleX = srcWidth / kDownWidth;
      final scaleY = srcHeight / kDownHeight;

      for (int dy = 0; dy < kDownHeight; dy++) {
        final sy = (dy * scaleY).toInt().clamp(0, srcHeight - 1);
        for (int dx = 0; dx < kDownWidth; dx++) {
          final sx = (dx * scaleX).toInt().clamp(0, srcWidth - 1);
          final idx = (sy * srcWidth + sx) * 4;
          final b = bgraBytes[idx];
          final g = bgraBytes[idx + 1];
          final r = bgraBytes[idx + 2];
          out[dy * kDownWidth + dx] =
              (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Laplacian variance — 높을수록 선명
  static double laplacianVariance(
    Uint8List gray, {
    int width = kDownWidth,
    int height = kDownHeight,
  }) {
    double sum = 0.0, sumSq = 0.0;
    int count = 0;

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final c = gray[y * width + x].toDouble();
        final lap = gray[(y - 1) * width + x].toDouble() +
            gray[(y + 1) * width + x].toDouble() +
            gray[y * width + (x - 1)].toDouble() +
            gray[y * width + (x + 1)].toDouble() -
            4.0 * c;
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    return sumSq / count - mean * mean;
  }

  /// 정규화 히스토그램 상관계수 유사도 [0.0, 1.0]
  /// Python SSIM 대체 — 1.0에 가까울수록 유사
  static double histogramSimilarity(Uint8List gray1, Uint8List gray2) {
    final h1 = Float64List(256);
    final h2 = Float64List(256);

    for (final v in gray1) h1[v]++;
    for (final v in gray2) h2[v]++;

    final n1 = gray1.length.toDouble();
    final n2 = gray2.length.toDouble();
    for (int i = 0; i < 256; i++) {
      h1[i] /= n1;
      h2[i] /= n2;
    }

    double m1 = 0, m2 = 0;
    for (int i = 0; i < 256; i++) {
      m1 += h1[i];
      m2 += h2[i];
    }
    m1 /= 256;
    m2 /= 256;

    double dot = 0, n1sq = 0, n2sq = 0;
    for (int i = 0; i < 256; i++) {
      final d1 = h1[i] - m1;
      final d2 = h2[i] - m2;
      dot += d1 * d2;
      n1sq += d1 * d1;
      n2sq += d2 * d2;
    }

    if (n1sq == 0 || n2sq == 0) return 1.0;
    final corr = dot / math.sqrt(n1sq * n2sq);
    return ((corr + 1.0) / 2.0).clamp(0.0, 1.0);
  }
}