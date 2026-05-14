#!/bin/bash
set -e

# ==============================================================================
# 1. PARAMETER PARSING
# ==============================================================================
DATA_TYPE="images"
DATA_COMP=2
FPS=2

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --exp_name) EXP_NAME="$2"; shift ;;
        --data_path) DATA_PATH="$2"; shift ;;
        --data_type) DATA_TYPE="$2"; shift ;;
        --fps) FPS="$2"; shift ;;
        --data_compression) DATA_COMP="$2"; shift ;;
        *) echo "[ERROR] Invalid parameter: '$1'"; exit 1 ;;
    esac
    shift
done

if [ -z "$EXP_NAME" ] || [ -z "$DATA_PATH" ]; then
    echo "[ERROR] Missing required parameters."
    echo "Usage: ./run_all.sh --exp_name <name> --data_path <path> [--data_type images/video] [--fps 2] [--data_compression 1/2/4/8]"
    exit 1
fi

if [ ! -e "$DATA_PATH" ]; then
    echo "[ERROR] The specified data path does not exist: '$DATA_PATH'"
    exit 1
fi

# ==============================================================================
# 2. WORKSPACE SETUP & OVERWRITE PROTECTION
# ==============================================================================
BASE_DIR="auto_data/$EXP_NAME"

if [ -d "$BASE_DIR" ]; then
    echo "[WARNING] The directory '$BASE_DIR' already exists."
    read -p "Choose action: Overwrite (o) / Keep and resume (k) / Quit (q)? [o/k/q]: " choice
    case "$choice" in
        o|O )
            echo "[INFO] Cleaning up previous workspace..."
            rm -rf "$BASE_DIR"
            ;;
        k|K )
            echo "[INFO] Retaining existing data. Will resume from available checkpoints..."
            ;;
        * )
            echo "[INFO] Operation aborted by user."
            exit 1
            ;;
    esac
fi

mkdir -p "$BASE_DIR"

# ==============================================================================
# 3. LOGGING CONFIGURATION
# ==============================================================================
LOG_FILE="$BASE_DIR/run_$(date +%Y%m%d_%H%M%S).log"
echo "[INFO] Execution log will be saved to: $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ==============================================================================
# 4. DIRECTORY VARIABLES INITIALIZATION
# ==============================================================================
CACHE_DIR="$BASE_DIR/.cache"
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

IMG_ORIG_DIR="$BASE_DIR/images"
if [ "$DATA_COMP" -eq 1 ]; then
    IMG_WORK_DIR="$IMG_ORIG_DIR"
else
    IMG_WORK_DIR="$BASE_DIR/images_$DATA_COMP"
fi

DB_PATH="$BASE_DIR/database.db"
SPARSE_DIR="$BASE_DIR/sparse"
DENSE_DIR="$BASE_DIR/dense"

export QT_QPA_PLATFORM=offscreen

# ==============================================================================
# STAGE 0: DATA INGESTION
# ==============================================================================
if [ ! -f "$CACHE_DIR/stage0.done" ]; then
    echo "========================================"
    echo " STAGE 0: DATA PREPARATION"
    echo "========================================"
    mkdir -p "$IMG_ORIG_DIR"

    if [ "$DATA_TYPE" == "video" ]; then
        echo "[INFO] Extracting frames from video '$DATA_PATH' at $FPS FPS..."
        if ! command -v ffmpeg &> /dev/null; then
            echo "[ERROR] ffmpeg is not installed. Please install it in the Docker environment."
            exit 1
        fi
        ffmpeg -i "$DATA_PATH" -vf "fps=$FPS" -q:v 2 "$IMG_ORIG_DIR/%04d.jpg"
    else
        echo "[INFO] Copying images from '$DATA_PATH' to workspace..."
        cp "$DATA_PATH"/* "$IMG_ORIG_DIR/"
    fi

    if [ "$DATA_COMP" -ne 1 ]; then
        echo "[INFO] Compressing images (downsample factor: $DATA_COMP)..."
        mkdir -p "$IMG_WORK_DIR"
        SCALE_PCT=$(awk "BEGIN {print 100 / $DATA_COMP}")
        cp "$IMG_ORIG_DIR"/* "$IMG_WORK_DIR/"
        mogrify -resize "${SCALE_PCT}%" "$IMG_WORK_DIR"/*
    fi

    touch "$CACHE_DIR/stage0.done"
else
    echo "[SKIP] Stage 0 completed previously. Skipping."
fi

# ==============================================================================
# STAGE 1: COLMAP SPARSE RECONSTRUCTION
# ==============================================================================
if [ ! -f "$CACHE_DIR/stage1.done" ]; then
    echo "========================================"
    echo " STAGE 1: COLMAP SPARSE RECONSTRUCTION"
    echo "========================================"

    if [ -f "$DB_PATH" ] || [ -d "$SPARSE_DIR" ]; then
        echo "[INFO] Detected incomplete COLMAP artifacts. Cleaning up for a fresh run..."
        rm -rf "$DB_PATH" "$SPARSE_DIR"
    fi

    xvfb-run -a colmap feature_extractor \
        --database_path "$DB_PATH" \
        --image_path "$IMG_WORK_DIR" \
        --SiftExtraction.max_num_features 8192 \
        --ImageReader.camera_model OPENCV_FISHEYE

    xvfb-run -a colmap sequential_matcher \
        --database_path "$DB_PATH" \
        --SequentialMatching.overlap 15

    mkdir -p "$SPARSE_DIR"
    colmap mapper \
        --database_path "$DB_PATH" \
        --output_path "$SPARSE_DIR" \
        --image_path "$IMG_WORK_DIR"

    if [ ! -d "$SPARSE_DIR/0" ]; then
        echo "[ERROR] COLMAP Mapper failed (sparse/0 directory not created). Please check image quality."
        exit 1
    fi

    touch "$CACHE_DIR/stage1.done"
else
    echo "[SKIP] Stage 1 (COLMAP Sparse) completed previously. Skipping."
fi

# ==============================================================================
# SPATIAL RECONSTRUCTION CLUSTER EVALUATION & SUBSTITUTION
# ==============================================================================
if [ -d "$SPARSE_DIR/1" ] && [ ! -f "$CACHE_DIR/stage1_fix.done" ]; then
    echo "[INFO] Multiple spatial reconstruction clusters detected. Evaluating optimal cluster based on registration payload..."

    # Function to extract payload size (in bytes) of the images file
    get_payload_size() {
        local target_dir=$1
        local size=0
        if [ -f "$target_dir/images.bin" ]; then
            size=$(stat -c%s "$target_dir/images.bin")
        elif [ -f "$target_dir/images.txt" ]; then
            size=$(stat -c%s "$target_dir/images.txt")
        fi
        echo "$size"
    }

    # Retrieve comparative metrics
    SIZE_0=$(get_payload_size "$SPARSE_DIR/0")
    SIZE_1=$(get_payload_size "$SPARSE_DIR/1")

    echo "[INFO] Cluster 0 payload size: $SIZE_0 bytes | Cluster 1 payload size: $SIZE_1 bytes"

    # Evaluate and execute substitution if Cluster 1 is statistically dominant
    if [ "$SIZE_1" -gt "$SIZE_0" ]; then
        echo "[INFO] Cluster 1 exhibits a significantly larger reconstruction volume. Executing cluster substitution..."
        mv "$SPARSE_DIR/0" "$SPARSE_DIR/0_trash"
        mv "$SPARSE_DIR/1" "$SPARSE_DIR/0"
    else
        echo "[INFO] Cluster 0 retains primary validity or equivalence. No topological substitution required."
    fi

    touch "$CACHE_DIR/stage1_fix.done"
fi

# ==============================================================================
# STAGE 2: 3DGRUT TRAINING
# ==============================================================================
if [ ! -f "$CACHE_DIR/stage2.done" ]; then
    echo "========================================"
    echo " STAGE 2: 3DGRUT MODEL TRAINING"
    echo "========================================"
    conda run -n 3dgrut python train.py --config-name apps/colmap_3dgut.yaml \
       path="$BASE_DIR" out_dir=runs \
       experiment_name="$EXP_NAME" \
       export_ply.enabled=true \
       dataset.downsample_factor="$DATA_COMP"

    touch "$CACHE_DIR/stage2.done"
else
    echo "[SKIP] Stage 2 (3DGRUT) completed previously. Skipping."
fi

# ==============================================================================
# STAGE 3: COLMAP DENSE RECONSTRUCTION & MESH EXTRACTION
# ==============================================================================
if [ ! -f "$CACHE_DIR/stage3.done" ]; then
    echo "========================================"
    echo " STAGE 3: DENSE RECONSTRUCTION & MESH EXTRACTION"
    echo "========================================"

    rm -rf "$DENSE_DIR"
    mkdir -p "$DENSE_DIR"

    xvfb-run -a colmap image_undistorter \
        --image_path "$IMG_WORK_DIR" \
        --input_path "$SPARSE_DIR/0" \
        --output_path "$DENSE_DIR" \
        --output_type COLMAP

    xvfb-run -a colmap patch_match_stereo \
        --workspace_path "$DENSE_DIR" \
        --workspace_format COLMAP

    xvfb-run -a colmap stereo_fusion \
        --workspace_path "$DENSE_DIR" \
        --workspace_format COLMAP \
        --output_path "$DENSE_DIR/fused.ply"

    echo "[INFO] Cleaning up intermediate stereo data (depth_maps/normal_maps)..."
    rm -rf "$DENSE_DIR/stereo"
    echo "[INFO] Storage optimization complete."

    conda run -n 3dgrut python extract_mesh.py "$DENSE_DIR/fused.ply" "$BASE_DIR/mesh.usd"

    touch "$CACHE_DIR/stage3.done"
else
    echo "[SKIP] Stage 3 (Mesh Extraction) completed previously. Skipping."
fi

# ==============================================================================
# STAGE 4: POST-PROCESSING & ARTIFACT COLLECTION
# ==============================================================================
echo "========================================"
echo " STAGE 4: ARTIFACT COLLECTION"
echo "========================================"

# Locate the generated PLY file using a wildcard (retrieves the first match)
PLY_FILE=$(find "runs/$EXP_NAME" -name "*.ply" -type f | head -n 1)

if [ -n "$PLY_FILE" ]; then
    cp "$PLY_FILE" "$OUTPUT_DIR/${EXP_NAME}_pointcloud.ply"
    echo "[SUCCESS] PLY spatial representation successfully extracted to: $OUTPUT_DIR/${EXP_NAME}_pointcloud.ply"
else
    echo "[ERROR] Target PLY artifact not located within runs/$EXP_NAME. The export sequence may have encountered an exception."
fi

# Retrieve OBJ mesh (if applicable)
if [ -f "temp_room.obj" ]; then
    mv "temp_room.obj" "$OUTPUT_DIR/${EXP_NAME}_mesh.obj"
    echo "[SUCCESS] Topographical mesh retrieved from temp_room.obj to: $OUTPUT_DIR/${EXP_NAME}_mesh.obj"
else
    echo "[WARNING] temp_room.obj was not detected. The mesh extraction script might have failed or executed in an alternate directory."
fi

# Grant permissions to mitigate host-container access restrictions
chmod -R 777 "$BASE_DIR"

echo "========================================"
echo " [COMPLETE] Pipeline execution concluded."
echo " Output directory : $OUTPUT_DIR"
echo " Execution log    : $LOG_FILE"
echo "========================================"

