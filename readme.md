# VSFCore: Automated 3D Reconstruction Pipeline

Dự án cung cấp quy trình (pipeline) tự động hóa việc tái tạo môi trường 3D từ hình ảnh hoặc video. Hệ thống tích hợp sức mạnh tính toán camera pose của **COLMAP** và khả năng nội suy không gian của **3DGRUT**, xuất ra định dạng đám mây điểm (Point Cloud) chất lượng cao và Lưới tam giác (Mesh) tương tác được.

## 🛠 Yêu cầu hệ thống
- **Hệ điều hành:** Linux (Khuyến nghị Ubuntu 22.04).
- **Phần cứng:** NVIDIA GPU hỗ trợ CUDA 12.8 (RTX 30-series, 40-series hoặc tương đương).
- **Phần mềm:** Cài đặt sẵn `Docker` và `NVIDIA Container Toolkit`.

---

## 🚀 Hướng dẫn cài đặt

### Bước 0: Tải mã nguồn
Clone dự án về máy của bạn:
```bash
git clone https://github.com/Somethings1/3drec
cd 3drec
```

### Bước 1: Khởi tạo môi trường (Build Image)
Dự án cung cấp sẵn script tự động nhận diện phần cứng GPU và build Docker image tối ưu nhất. Bạn chỉ cần chạy:
```bash
chmod +x build_env.sh
./build_env.sh
```

### Bước 2: Khởi động Container
**Lưu ý quan trọng:** Bắt buộc phải ánh xạ (mount) thư mục `data` từ máy thật vào container để lưu trữ kết quả và không bị mất dữ liệu sau khi tắt.
```bash
docker run -it --gpus all -v $(pwd)/data:/workspace/3dgrut/data vsfcore-3d-pipeline
```

---

## ⚡ Chạy thử nghiệm (Quickstart Demo)

Sau khi đã vào bên trong container (Terminal hiện chữ `(3dgrut)`), bạn có thể tải một bộ dữ liệu mẫu về và chạy thử ngay lập tức bằng cụm lệnh sau:

```bash
# 1. Tải và giải nén dữ liệu mẫu
gdown "1lSpqDyTZeBzsUzCNJypO4GcaUKod14u6" -O data/pot_images.zip && \
mkdir -p data/pot && \
unzip -q data/pot_images.zip -d data/pot/

# 2. Chạy pipeline tái tạo
./run_all.sh --exp_name pot_demo --data_path data/pot/images --data_type images --data_compression 2
```

---

## 📈 Tùy chỉnh tham số Pipeline

Để chạy với dữ liệu cá nhân của bạn, sử dụng cú pháp lệnh sau:

```bash
./run_all.sh \
  --data_path ./data/thu_muc_cua_ban \
  --exp_name ten_du_an \
  --data_type [images|video] \
  --data_compression 2 \
  --fps 5
```

**Bảng giải thích tham số:**
* `--data_path` *(Bắt buộc)*: Đường dẫn tới thư mục chứa ảnh gốc hoặc file video trực tiếp.
* `--exp_name` *(Bắt buộc)*: Tên duy nhất định danh cho lần chạy này (Dùng để quản lý file output và cache).
* `--data_type`: Chọn `images` (mặc định) hoặc `video`.
* `--data_compression`: Hệ số nén ảnh để giảm tải GPU. Càng to ảnh càng mờ, chạy càng nhanh. (Giá trị: `1`, `2`, `4`, `8` - Khuyến nghị `2`).
* `--fps`: Chỉ dùng khi `--data_type` là `video`. Số khung hình (frames) muốn cắt ra trên mỗi giây.

---

## 📁 Cấu trúc đầu ra
Toàn bộ kết quả sau khi hoàn tất sẽ được tự động gom gọn vào thư mục `auto_data/[exp_name]/output/` nằm trong hệ thống file của bạn (trong thư mục `data` đã mount). Thành quả bao gồm:

1.  `[exp_name]_pointcloud.usdz`: File Point Cloud đã được train và làm nét qua 3DGRUT.
2.  `[exp_name]_mesh.obj`: File Mesh đã được trích xuất bề mặt (dùng để tương tác vật lý/collision).
3.  `run_[timestamp].log`: Nhật ký ghi lại toàn bộ quá trình chạy để tiện tra cứu lỗi.

---

## 🙏 Lời cảm ơn & Nguồn tham khảo
Dự án này được xây dựng dựa trên vai khổng lồ của các công nghệ mã nguồn mở:
- Trích xuất đặc trưng và Camera Pose: [COLMAP](https://colmap.github.io/)
- Kết xuất không gian 3D: [3DGRUT (NVIDIA Research)](https://github.com/nv-tlabs/3dgrut)
