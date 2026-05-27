import numpy as np
import matplotlib
matplotlib.rcParams['font.family'] = 'Malgun Gothic'
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
import sys
import os

MAP_FILE = "MapPoints.txt"
TRAJ_FILE = "KeyFrameTrajectory.txt"

if len(sys.argv) > 1:
    MAP_FILE = sys.argv[1]

if not os.path.exists(MAP_FILE):
    print(f"파일 없음: {MAP_FILE}")
    sys.exit(1)

# 맵 포인트 로드
pts = np.loadtxt(MAP_FILE)
if pts.ndim == 1:
    pts = pts.reshape(1, 3)
print(f"맵 포인트 수: {len(pts)}")

x, y, z = pts[:, 0], pts[:, 1], pts[:, 2]

# 이상치 제거 (3σ 기준)
def remove_outliers(arr):
    m, s = arr.mean(), arr.std()
    return (arr > m - 3*s) & (arr < m + 3*s)

mask = remove_outliers(x) & remove_outliers(y) & remove_outliers(z)
x, y, z = x[mask], y[mask], z[mask]
print(f"이상치 제거 후: {mask.sum()}개")

# 색상: 높이(Y) 기준
colors = y - y.min()
colors = colors / colors.max() if colors.max() > 0 else colors

fig = plt.figure(figsize=(16, 7))

# ── 3D 포인트 클라우드 ────────────────────────────────
ax1 = fig.add_subplot(121, projection='3d')
ax1.scatter(-x, z, y, c=colors, cmap='viridis', s=1, alpha=0.6)

# 카메라 궤적 오버레이
if os.path.exists(TRAJ_FILE):
    traj = np.loadtxt(TRAJ_FILE)
    if traj.ndim == 1:
        traj = traj.reshape(1, -1)
    tx, ty, tz = traj[:, 1], traj[:, 2], traj[:, 3]
    ax1.plot(tx, tz, ty, 'r-', linewidth=1.5, alpha=0.8, label='카메라 궤적')
    ax1.scatter(tx[0], tz[0], ty[0], c='green', s=80, zorder=5)
    ax1.scatter(tx[-1], tz[-1], ty[-1], c='red', s=80, zorder=5)
    ax1.legend(fontsize=9)

ax1.set_xlabel('X (m)')
ax1.set_ylabel('Z (m)')
ax1.set_zlabel('Y (m)')
ax1.set_title(f'3D 포인트 클라우드 ({len(x)}개)')

# ── 탑뷰 (XZ) ────────────────────────────────────────
ax2 = fig.add_subplot(122)
ax2.scatter(-x, z, c=colors, cmap='viridis', s=1, alpha=0.5)

if os.path.exists(TRAJ_FILE):
    ax2.plot(tx, tz, 'r-', linewidth=1.5, alpha=0.8, label='카메라 궤적')
    ax2.scatter(tx[0], tz[0], c='green', s=80, zorder=5, label='시작')
    ax2.scatter(tx[-1], tz[-1], c='red', s=80, zorder=5, label='종료')
    ax2.legend(fontsize=9)

ax2.set_xlabel('X (m)')
ax2.set_ylabel('Z (m)')
ax2.set_title('탑뷰 (XZ 평면)')
ax2.axis('equal')
ax2.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig('pointcloud.png', dpi=200, bbox_inches='tight')
print("pointcloud.png 저장됨")
plt.show()
