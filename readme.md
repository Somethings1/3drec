# Automated 3D Reconstruction Pipeline

## 🛠 Yêu cầu hệ thống
- **Hệ điều hành:** Linux (Ubuntu 22.04 khuyến nghị).
- **Phần cứng:** NVIDIA GPU hỗ trợ CUDA 12.8.
- **Phần mềm:** Docker và NVIDIA Container Toolkit.

## 🚀 Hướng dẫn cài đặt

### 0. Clone

```bash
git clone https://github.com/Somethings1/3drec
```

### 1. Build Docker Image

```bash
docker build -t vsfcore-3d-pipeline .
```

### 2. Chạy Container

```bash
docker run -it --gpus all \
  vsfcore-3d-pipeline
```

## 📈 Cách sử dụng Pipeline
Sau khi vào bên trong container, bạn chỉ cần thực hiện lệnh sau để chạy toàn bộ quy trình:

```bash
./run_all.sh \
  --data_path ./data/my_project \
  --exp_name run_v1 \
  --data_type images \
  --data_compression 2 \
  --fps 5
```

**Các tham số chính:**
- `--data_path`: Đường dẫn tới thư mục chứa ảnh hoặc tệp video.
- `--exp_name`: Tên duy nhất cho lần chạy này.
- `--data_type`: `images` hoặc `video`.
- `--data_compression`: Hệ số nén ảnh (1, 2, 4, 8).
- `--fps`: Số frame/s được cắt từ video

Ví dụ với bộ dữ liệu test

```bash
gdown "1lSpqDyTZeBzsUzCNJypO4GcaUKod14u6" -O data/pot_images.zip && \
mkdir -p data/pot && \
unzip -q data/pot_images.zip -d data/pot/ && \
./run_all.sh --exp_name pot_demo --data_path data/pot/images --data_type images --data_compression 2
```

## 📁 Kết quả đầu ra
Kết quả sau khi hoàn tất sẽ nằm trong thư mục `auto_data/[exp_name]/output`, bao gồm:
- File Point Cloud dạng `.usdz`.
- File Mesh dạng `.obj`.
- Nhật ký hoạt động (Log file).

## 🙏 Lời cảm ơn
Dự án sử dụng các công nghệ mã nguồn mở từ:
- [COLMAP](https://colmap.github.io/)
- [3DGRUT (NVIDIA Research)](https://github.com/nv-tlabs/3dgrut)

