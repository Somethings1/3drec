#!/usr/bin/env bash

# ==============================================================================
# VSFCore - Docker Build Automation Script
# Description: Automatically detects NVIDIA GPU architecture and builds the
#              3D reconstruction environment. Features an infinite retry
#              mechanism to handle unstable network environments gracefully.
# ==============================================================================

# Strict execution environment:
# -e: Exit immediately on command failure.
# -u: Treat unset variables as errors.
# -o pipefail: Ensure pipeline errors are not masked.
set -euo pipefail

# ANSI Color Codes for standard terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration Parameters
IMAGE_NAME="vsfcore-3d-pipeline"
DEFAULT_ARCH="86"
LOG_FILE="docker_build_error.log"
RETRY_DELAY=300 # 5 minutes wait time between retries

echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE} [VSFCore] Initiating Docker Environment Build Process...     ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# Step 1: Hardware Analysis and GPU Architecture Detection
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[1/2] Analyzing hardware configuration...${NC}"

if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 | tr -d '.')

    echo -e "${GREEN}  -> Detected GPU: ${GPU_NAME}${NC}"
    echo -e "${GREEN}  -> Target Compute Capability: ${ARCH}${NC}"
else
    echo -e "${RED}  -> Warning: 'nvidia-smi' utility is missing or inaccessible.${NC}"
    echo -e "${YELLOW}  -> Falling back to default architecture: ${DEFAULT_ARCH}${NC}"
    ARCH=$DEFAULT_ARCH
fi

echo ""

# ------------------------------------------------------------------------------
# Step 2: Continuous Build Execution (Infinite Retry Mechanism)
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/2] Building Docker image '${IMAGE_NAME}'...${NC}"
echo -e "      (Note: Automated retry mechanism is active. See ${LOG_FILE} for details)"
echo ""

ATTEMPT=1

while true; do
    echo -e "${YELLOW}>>> Build Attempt ${ATTEMPT} initiated...${NC}"

    # Execute docker build. Redirect output and errors to terminal and LOG_FILE.
    if docker build --build-arg CUDA_ARCH="${ARCH}" -t "${IMAGE_NAME}" . 2>&1 | tee "${LOG_FILE}"; then
        echo -e "${GREEN}>>> Build process completed successfully on attempt ${ATTEMPT}.${NC}"
        break
    else
        echo -e "${RED}>>> Error: Build attempt ${ATTEMPT} failed due to network or dependency issues.${NC}"
        echo -e "${YELLOW}>>> Process will be paused for ${RETRY_DELAY} seconds before the next attempt...${NC}"

        sleep $RETRY_DELAY
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

echo ""
echo -e "${GREEN}==============================================================${NC}"
echo -e "${GREEN} [SUCCESS] Build procedure finalized without critical errors. ${NC}"
echo -e "${GREEN} To initialize the pipeline, execute the following command:   ${NC}"
echo -e "${GREEN} docker run -it --ipc=host --gpus all -v \$(pwd)/data:/workspace/3dgrut/data ${IMAGE_NAME} ${NC}"
echo -e "${GREEN}==============================================================${NC}"
