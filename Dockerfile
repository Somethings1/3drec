# ==============================================================================
# VSFCore - 3D Reconstruction Pipeline Environment
# ==============================================================================
# Base image: NVIDIA CUDA 12.8.1 Development (Ubuntu 22.04)
# ==============================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# Thiết lập môi trường không tương tác để tránh các prompt hỏi đáp khi cài đặt
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# 1. Cài đặt Dependencies Hệ Thống
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    gcc-11 g++-11 git ninja-build build-essential \
    libboost-program-options-dev libboost-graph-dev libboost-system-dev \
    libeigen3-dev libopenimageio-dev openimageio-tools libmetis-dev \
    libgoogle-glog-dev libgtest-dev libgmock-dev libsqlite3-dev libglew-dev \
    qt6-base-dev libqt6opengl6-dev libqt6openglwidgets6 libqt6svg6-dev \
    libcgal-dev libceres-dev libsuitesparse-dev libcurl4-openssl-dev \
    libssl-dev libmkl-full-dev xvfb imagemagick-6.q16 ffmpeg wget curl \
    libopenexr-dev zip unzip && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/include/opencv4

# ------------------------------------------------------------------------------
# 2. Cập nhật CMake (Yêu cầu cho COLMAP/faiss)
# ------------------------------------------------------------------------------
RUN wget --no-check-certificate https://github.com/Kitware/CMake/releases/download/v3.30.2/cmake-3.30.2-linux-x86_64.sh -O /tmp/cmake-install.sh && \
    chmod u+x /tmp/cmake-install.sh && \
    /tmp/cmake-install.sh --skip-license --prefix=/usr/local && \
    rm /tmp/cmake-install.sh

# ------------------------------------------------------------------------------
# 3. Biên dịch COLMAP từ mã nguồn
# ------------------------------------------------------------------------------
# Sử dụng biến môi trường CUDA_ARCH để linh hoạt biên dịch cho các kiến trúc GPU khác nhau.
# Mặc định: 89 (RTX 40-series). Khi build có thể truyền biến: --build-arg CUDA_ARCH=86
ARG CUDA_ARCH=89

WORKDIR /opt
RUN git clone https://github.com/colmap/colmap.git && \
    cd colmap && mkdir build && cd build && \
    cmake .. -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc \
             -DCUDAToolkit_ROOT=/usr/local/cuda-12.8 \
             -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} && \
    make -j$(nproc) && make install

# ------------------------------------------------------------------------------
# 4. Cài đặt Môi Trường Conda
# ------------------------------------------------------------------------------
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh
ENV PATH="/opt/conda/bin:${PATH}"
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# ------------------------------------------------------------------------------
# 5. Cài đặt 3DGRUT và Môi trường Python (Khu vực thay đổi thường xuyên)
# ------------------------------------------------------------------------------
WORKDIR /workspace
RUN git clone --recursive https://github.com/nv-tlabs/3dgrut.git
WORKDIR /workspace/3dgrut

# Thiết lập biến môi trường để Conda tự động đồng ý điều khoản (Bypass TOS prompt)
ENV CONDA_AUTO_UPDATE_CONDA=false
ENV CONDA_YES=true

# Thực thi script cài đặt môi trường của 3DGRUT
RUN chmod +x install_env.sh && \
    ./install_env.sh 3dgrut WITH_GCC11

# Cài đặt các thư viện Python bổ trợ cho quá trình trích xuất mesh và xử lý dữ liệu
RUN conda run -n 3dgrut pip install open3d numpy pymeshlab usd-core viser gdown

# ------------------------------------------------------------------------------
# 6. Sao chép Mã Nguồn Tùy Chỉnh & Cấu Hình Cuối
# ------------------------------------------------------------------------------
COPY extract_mesh.py .
COPY run_all.sh .
RUN chmod +x run_all.sh

# Cấu hình môi trường đồ họa ẩn (offscreen) cho các ứng dụng yêu cầu Qt
ENV QT_QPA_PLATFORM=offscreen

# Tự động kích hoạt môi trường conda khi vào container
RUN echo "source /opt/conda/etc/profile.d/conda.sh && conda activate 3dgrut" >> ~/.bashrc

CMD ["/bin/bash"]
