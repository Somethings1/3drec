# Sử dụng nền tảng CUDA 12.8 chính thức từ NVIDIA [cite: 6]
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# Cài đặt các gói phụ trợ hệ thống và dependencies cho Colmap/3DGRUT [cite: 19-37, 45-61, 82-83, 251]
RUN apt-get update && apt-get install -y \
    gcc-11 g++-11 git cmake ninja-build build-essential \
    libboost-program-options-dev libboost-graph-dev libboost-system-dev \
    libeigen3-dev libopenimageio-dev openimageio-tools libmetis-dev \
    libgoogle-glog-dev libgtest-dev libgmock-dev libsqlite3-dev libglew-dev \
    qt6-base-dev libqt6opengl6-dev libqt6openglwidgets6 \
    libcgal-dev libceres-dev libsuitesparse-dev libcurl4-openssl-dev \
    libssl-dev libmkl-full-dev xvfb imagemagick-6.q16 ffmpeg wget curl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/include/opencv4

# Biên dịch COLMAP từ mã nguồn để tối ưu hóa hiệu suất GPU [cite: 63-72]
WORKDIR /opt
RUN git clone https://github.com/colmap/colmap.git && \
    cd colmap && mkdir build && cd build && \
    cmake .. -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc \
             -DCUDAToolkit_ROOT=/usr/local/cuda-12.8 \
             -DCMAKE_CUDA_ARCHITECTURES=native && \
    make -j$(nproc) && make install

# Thiết lập Miniconda cho môi trường Python của 3DGRUT [cite: 16]
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh
ENV PATH="/opt/conda/bin:${PATH}"

# Cấu trúc thư mục làm việc và cài đặt 3DGRUT [cite: 10-12, 16]
WORKDIR /workspace
RUN git clone --recursive https://github.com/nv-tlabs/3dgrut.git
WORKDIR /workspace/3dgrut

RUN chmod +x install_env.sh && \
    ./install_env.sh 3dgrut WITH_GCC11

# Cài đặt các thư viện Python bổ sung [cite: 78]
RUN conda run -n 3dgrut pip install open3d numpy pymeshlab usd-core viser

# SAO CHÉP CÁC TỆP TIN TỪ MÁY HOST VÀO CONTAINER [cite: 84-85, 99]
COPY extract_mesh.py .
COPY run_all.sh .
RUN chmod +x run_all.sh

# Cấu hình môi trường mặc định
ENV QT_QPA_PLATFORM=offscreen
RUN echo "source /opt/conda/etc/profile.d/conda.sh && conda activate 3dgrut" >> ~/.bashrc

CMD ["/bin/bash"]
