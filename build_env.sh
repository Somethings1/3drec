#!/usr/bin/env bash

# ==============================================================================
# VSFCore - Docker Build Automation Script
# Description: Automatically detects NVIDIA GPU architecture and builds the
#              3D reconstruction environment.
# ==============================================================================

# Thiết lập an toàn cho Bash:
# -e: Dừng ngay lập tức nếu có lệnh lỗi.
# -u: Báo lỗi nếu dùng biến chưa khai báo.
# -o pipefail: Bắt lỗi trong chuỗi lệnh pipe (ví dụ: lệnh1 | lệnh2).
set -euo pipefail

# Mã màu để in ra terminal cho "chuyên nghiệp"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Không màu

IMAGE_NAME="vsfcore-3d-pipeline"
DEFAULT_ARCH="86" # Mặc định là RTX 30-series nếu không dò được

echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE} [VSFCore] Initiating Docker Environment Build Process...     ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# Bước 1: Dò tìm kiến trúc GPU
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[1/2] Analyzing hardware configuration...${NC}"

if command -v nvidia-smi &> /dev/null; then
    # Bóc tách tên và Compute Capability từ nvidia-smi
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 | tr -d '.')

    echo -e "${GREEN}  -> Detected GPU: ${GPU_NAME}${NC}"
    echo -e "${GREEN}  -> Target Compute Capability: ${ARCH}${NC}"
else
    echo -e "${RED}  -> Warning: 'nvidia-smi' not found or NVIDIA driver missing.${NC}"
    echo -e "${YELLOW}  -> Falling back to default architecture: ${DEFAULT_ARCH}${NC}"
    ARCH=$DEFAULT_ARCH
fi

echo ""

# ------------------------------------------------------------------------------
# Bước 2: Kích hoạt tiến trình Build
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/2] Building Docker image '${IMAGE_NAME}'...${NC}"
echo -e "      (This may take a while depending on network and cache)"
echo ""

# Ném cái biến ARCH vào Dockerfile
docker build --build-arg CUDA_ARCH="${ARCH}" -t "${IMAGE_NAME}" .

echo ""
echo -e "${GREEN}==============================================================${NC}"
echo -e "${GREEN} [SUCCESS] Build completed successfully!                      ${NC}"
echo -e "${GREEN} Run the pipeline using:                                      ${NC}"
echo -e "${GREEN} docker run -it --ipc=host --gpus all -v \$(pwd)/data:/workspace/3dgrut/data ${IMAGE_NAME} ${NC}"
echo -e "${GREEN}==============================================================${NC}"
