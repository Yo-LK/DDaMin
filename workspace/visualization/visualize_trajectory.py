import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
import sys
import os
import matplotlib
matplotlib.rcParams['font.family'] = 'Malgun Gothic'  # Windows 한글 폰트
matplotlib.rcParams['axes.unicode_minus'] = False

TRAJECTORY_FILE = "KeyFrameTrajectory.txt"

if len(sys.argv) > 1:
    TRAJECTORY_FILE = sys.argv[1]

if not os.path.exists(TRAJECTORY_FILE):
    print(f"파일 없음: {TRAJECTORY_FILE}")
    sys.exit(1)

# 파일 로드
data = []
with open(TRAJECTORY_FILE, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        vals = list(map(float, line.split()))
        data.append(vals)

data = np.array(data)
print(f"키프레임 수: {len(data)}")

timestamps = data[:, 0]
tx = data[:, 1]
ty = data[:, 2]
tz = data[:, 3]

# 시작 시간 기준 상대 시간
t_rel = timestamps - timestamps[0]

# ── 3D 궤적 ──────────────────────────────────────────
fig = plt.figure(figsize=(14, 6))

ax1 = fig.add_subplot(121, projection='3d')
sc = ax1.scatter(tx, tz, ty, c=t_rel, cmap='plasma', s=20)
ax1.plot(tx, tz, ty, 'gray', alpha=0.3, linewidth=0.8)
ax1.scatter(tx[0],  tz[0],  ty[0],  c='green', s=100, zorder=5, label='시작')
ax1.scatter(tx[-1], tz[-1], ty[-1], c='red',   s=100, zorder=5, label='종료')
ax1.set_xlabel('X (m)')
ax1.set_ylabel('Z (m)')
ax1.set_zlabel('Y (m)')
ax1.set_title('3D 궤적')
ax1.legend()
plt.colorbar(sc, ax=ax1, label='경과 시간 (s)', shrink=0.5)

# ── XZ 평면 (탑뷰) ────────────────────────────────────
ax2 = fig.add_subplot(122)
sc2 = ax2.scatter(tx, tz, c=t_rel, cmap='plasma', s=20)
ax2.plot(tx, tz, 'gray', alpha=0.3, linewidth=0.8)
ax2.scatter(tx[0],  tz[0],  c='green', s=100, zorder=5, label='시작')
ax2.scatter(tx[-1], tz[-1], c='red',   s=100, zorder=5, label='종료')
ax2.set_xlabel('X (m)')
ax2.set_ylabel('Z (m)')
ax2.set_title('탑뷰 (XZ 평면)')
ax2.legend()
ax2.axis('equal')
ax2.grid(True, alpha=0.3)
plt.colorbar(sc2, ax=ax2, label='경과 시간 (s)')

plt.tight_layout()
plt.savefig('trajectory.png', dpi=150, bbox_inches='tight')
print("trajectory.png 저장됨")
plt.show()

# ── 통계 ─────────────────────────────────────────────
total_time = t_rel[-1]
dist = np.sum(np.sqrt(np.diff(tx)**2 + np.diff(ty)**2 + np.diff(tz)**2))
print(f"총 시간: {total_time:.1f}s")
print(f"이동 거리 (추정): {dist:.3f}m")
print(f"X 범위: {tx.min():.3f} ~ {tx.max():.3f}m")
print(f"Y 범위: {ty.min():.3f} ~ {ty.max():.3f}m")
print(f"Z 범위: {tz.min():.3f} ~ {tz.max():.3f}m")
