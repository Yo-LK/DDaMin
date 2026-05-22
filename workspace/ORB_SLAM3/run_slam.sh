#!/bin/bash
set -e

SLAM_DIR="/workspace/ORB_SLAM3"
VOCAB="$SLAM_DIR/Vocabulary/ORBvoc.txt"
CONFIG="/app/config/iphone13mini_480x640.yaml"
BINARY="$SLAM_DIR/Examples/Monocular-Inertial/mono_inertial_fifo"

# FIFO 생성 (없으면)
if [ ! -p /tmp/slam_pipe ]; then
    mkfifo /tmp/slam_pipe
    echo "[run_slam] FIFO 재생성됨"
fi

echo "[run_slam] ORB-SLAM3 시작"
echo "  Vocabulary : $VOCAB"
echo "  Config     : $CONFIG"

exec "$BINARY" "$VOCAB" "$CONFIG"
