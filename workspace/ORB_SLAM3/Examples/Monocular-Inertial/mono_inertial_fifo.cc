#include <iostream>
#include <chrono>
#include <vector>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <csignal>

#include <opencv2/core/core.hpp>
#include <opencv2/imgcodecs.hpp>

#include <System.h>

#define FIFO_PATH "/tmp/slam_pipe"

static ORB_SLAM3::System* g_SLAM = nullptr;
static bool read_exact(int fd, uint8_t* buf, size_t n) {
    size_t total = 0;
    while (total < n) {
        ssize_t r = read(fd, buf + total, n - total);
        if (r <= 0) return false;
        total += r;
    }
    return true;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: ./mono_inertial_fifo <vocabulary> <settings_yaml>" << std::endl;
        return 1;
    }

    system("mkdir -p /app/slam_output");

    // 테스트: 순수 Monocular
    ORB_SLAM3::System SLAM(argv[1], argv[2], ORB_SLAM3::System::MONOCULAR, true);
    // IMU 사용 시 아래로 교체:
    // ORB_SLAM3::System SLAM(argv[1], argv[2], ORB_SLAM3::System::IMU_MONOCULAR, true);
    
    g_SLAM = &SLAM;
    signal(SIGINT, [](int) {
        if (g_SLAM) {
            g_SLAM->SaveKeyFrameTrajectoryTUM("/app/slam_output/KeyFrameTrajectory.txt");
            g_SLAM->SaveMapPoints("/app/slam_output/MapPoints.txt"); 
            g_SLAM->Shutdown();
        }
        exit(0);
    });

    while (true) {
        std::cout << "[SLAM] FIFO 대기 중..." << std::endl;
        int fd = open(FIFO_PATH, O_RDONLY);
        if (fd < 0) {
            std::cerr << "[SLAM] FIFO open 실패" << std::endl;
            sleep(1);
            continue;
        }
      
        { 
            int flags = fcntl(fd, F_GETFL); 
            fcntl(fd, F_SETFL, flags | O_NONBLOCK); uint8_t drain_buf[4096]; 
            while (read(fd,drain_buf, sizeof(drain_buf)) > 0); 
            fcntl(fd, F_SETFL, flags); // blocking 복원 
            std::cout << "[SLAM] 잔류 버퍼 제거 완료" << std::endl; 
        } 
  
        std::cout << "[SLAM] FIFO 연결됨, 프레임 수신 대기 중..." << std::endl;

        while (true) {
            uint32_t jpeg_size = 0;
            uint16_t imu_count = 0;

            if (!read_exact(fd, (uint8_t*)&jpeg_size, 4)) break;
            if (!read_exact(fd, (uint8_t*)&imu_count,  2)) break;
            std::cout << "[SLAM DEBUG] 수신: jpeg_size=" << jpeg_size 
                      << " imu_count=" << imu_count << std::endl;

            if (jpeg_size > 5*1024*1024 || imu_count > 500) {
                std::cerr << "[SLAM] 패킷 손상 감지 (jpeg=" << jpeg_size 
                          << "), 재연결" << std::endl;
                break;
            }
            // IMU 파싱 (MONOCULAR 테스트 중에도 데이터는 읽어서 버퍼 소진)
            std::vector<ORB_SLAM3::IMU::Point> imu_points;
            static double last_imu_t = 0.0;
          
            for (int i = 0; i < imu_count; i++) {
                uint8_t entry[32];
                if (!read_exact(fd, entry, 32)) goto next_session;

                double ts_ms;
                float ax, ay, az, gx, gy, gz;
                memcpy(&ts_ms, entry,      8);
                memcpy(&ax,    entry +  8, 4);
                memcpy(&ay,    entry + 12, 4);
                memcpy(&az,    entry + 16, 4);
                memcpy(&gx,    entry + 20, 4);
                memcpy(&gy,    entry + 24, 4);
                memcpy(&gz,    entry + 28, 4);

                double t_sec = ts_ms / 1000.0;

                if (t_sec <= last_imu_t) {
                    t_sec = last_imu_t + 0.001;
                }
                last_imu_t = t_sec;
              
                imu_points.emplace_back(ax, ay, az, gx, gy, gz, t_sec);
            }

            {
                // JPEG 수신
                std::vector<uint8_t> jpeg_buf(jpeg_size);
                if (!read_exact(fd, jpeg_buf.data(), jpeg_size)) break;

                // JPEG 디코딩
                cv::Mat img = cv::imdecode(jpeg_buf, cv::IMREAD_GRAYSCALE);
                if (img.empty()) {
                    std::cerr << "[SLAM] JPEG 디코딩 실패, FIFO 재연결" << std::endl;
                    break;
                }
              
                static double last_valid_timestamp = 0.0;
                double timestamp = 0.0;

                if (!imu_points.empty()) {
                    timestamp = imu_points.back().t;
                    last_valid_timestamp = timestamp;
                } else {
                    // 플러터가 IMU를 안 보냈을 때 2026년 현재 시간으로 튀는 것을 방지
                    timestamp = last_valid_timestamp + 0.033;
                    last_valid_timestamp = timestamp;
                }

                // 순수 Monocular
                SLAM.TrackMonocular(img, timestamp);
                // IMU 사용 시 아래로 교체:
                // SLAM.TrackMonocular(img, timestamp, imu_points);
            }
            continue;

next_session:
            break;
        }

        std::cout << "[SLAM] FIFO 연결 해제, 재연결 대기..." << std::endl;
        close(fd);
        SLAM.SaveKeyFrameTrajectoryTUM("/app/slam_output/KeyFrameTrajectory.txt");
    }

    SLAM.Shutdown();
    return 0;
}