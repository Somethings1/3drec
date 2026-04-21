#!/bin/bash
set -e

# ==========================================
# 1. PARSE THAM SỐ
# ==========================================
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
        *) echo "Lỗi: Tham số quái thai gì đây '$1'?"; exit 1 ;;
    esac
    shift
done

if [ -z "$EXP_NAME" ] || [ -z "$DATA_PATH" ]; then
    echo "Ê thiếu tham số! Đọc lại HDSD:"
    echo "Cách dùng: ./run_all.sh --exp_name <tên> --data_path <đường_dẫn> [--data_type images/video] [--fps 2] [--data_compression 1/2/4/8]"
    exit 1
fi

if [ ! -e "$DATA_PATH" ]; then
    echo "Lỗi: Cái đường dẫn data '$DATA_PATH' không tồn tại. Mắt để đi đâu đấy?"
    exit 1
fi

# ==========================================
# 2. SETUP WORKSPACE & CẢNH BÁO GHI ĐÈ
# ==========================================
BASE_DIR="auto_data/$EXP_NAME"

if [ -d "$BASE_DIR" ]; then
    echo "CẢNH BÁO: Thư mục '$BASE_DIR' đã tồn tại."
    read -p "Ông muốn Ghi đè xóa sạch (o) / Giữ nguyên chạy tiếp (k) / Hủy lệnh (q)? [o/k/q]: " choice
    case "$choice" in
        o|O )
            echo "Đang dọn dẹp bãi chiến trường cũ..."
            rm -rf "$BASE_DIR"
            ;;
        k|K )
            echo "Ok, giữ nguyên data cũ, chạy tiếp từ checkpoint (nếu có)..."
            ;;
        * )
            echo "Hủy. Nhát gan thế."
            exit 1
            ;;
    esac
fi

mkdir -p "$BASE_DIR"

# ==========================================
# 3. BẬT CHẾ ĐỘ GHI LOG
# ==========================================
LOG_FILE="$BASE_DIR/run_$(date +%Y%m%d_%H%M%S).log"
echo ">> Toàn bộ quá trình sẽ được ghi âm ghi hình tại: $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ==========================================
# 4. KHAI BÁO BIẾN THƯ MỤC LÀM VIỆC
# ==========================================
CACHE_DIR="$BASE_DIR/.cache"
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

# Thư mục chứa ảnh gốc luôn là "images"
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

# ==========================================
# GIAI ĐOẠN 0: INGEST DATA
# ==========================================
if [ ! -f "$CACHE_DIR/stage0.done" ]; then
    echo "========================================"
    echo " GIAI ĐOẠN 0: CHUẨN BỊ DATA"
    echo "========================================"
    mkdir -p "$IMG_ORIG_DIR"

    if [ "$DATA_TYPE" == "video" ]; then
        echo "Đang rã video '$DATA_PATH' thành từng frame với FPS=$FPS..."
        if ! command -v ffmpeg &> /dev/null; then
            echo "Lỗi: Không tìm thấy ffmpeg. Cài vào Docker đi bố!"
            exit 1
        fi
        ffmpeg -i "$DATA_PATH" -vf "fps=$FPS" -q:v 2 "$IMG_ORIG_DIR/%04d.jpg"
    else
        echo "Đang copy ảnh từ '$DATA_PATH' sang workspace..."
        cp "$DATA_PATH"/* "$IMG_ORIG_DIR/"
    fi

    if [ "$DATA_COMP" -ne 1 ]; then
        echo "Đang nén ảnh (downsample factor: $DATA_COMP)..."
        mkdir -p "$IMG_WORK_DIR"
        SCALE_PCT=$(awk "BEGIN {print 100 / $DATA_COMP}")
        cp "$IMG_ORIG_DIR"/* "$IMG_WORK_DIR/"
        mogrify -resize "${SCALE_PCT}%" "$IMG_WORK_DIR"/*
    fi

    touch "$CACHE_DIR/stage0.done"
else
    echo ">> Đã xong Giai đoạn 0. Bỏ qua."
fi

# ==========================================
# GIAI ĐOẠN 1: COLMAP SPARSE
# ==========================================
if [ ! -f "$CACHE_DIR/stage1.done" ]; then
    echo "========================================"
    echo " GIAI ĐOẠN 1: COLMAP SPARSE"
    echo "========================================"

    if [ -f "$DB_PATH" ] || [ -d "$SPARSE_DIR" ]; then
        echo "Phát hiện vết tích COLMAP dở dang. Đang dọn dẹp để cày lại..."
        rm -rf "$DB_PATH" "$SPARSE_DIR"
    fi

    xvfb-run -a colmap feature_extractor \
        --database_path "$DB_PATH" \
        --image_path "$IMG_WORK_DIR" \
        --SiftExtraction.max_num_features 8192 \
        --ImageReader.camera_model PINHOLE

    xvfb-run -a colmap sequential_matcher \
        --database_path "$DB_PATH" \
        --SequentialMatching.overlap 15

    mkdir -p "$SPARSE_DIR"
    colmap mapper \
        --database_path "$DB_PATH" \
        --output_path "$SPARSE_DIR" \
        --image_path "$IMG_WORK_DIR"

    if [ ! -d "$SPARSE_DIR/0" ]; then
        echo "LỖI: COLMAP Mapper tạch (không tạo được sparse/0). Xem lại chất lượng ảnh!"
        exit 1
    fi

    touch "$CACHE_DIR/stage1.done"
else
    echo ">> Đã xong Giai đoạn 1 (COLMAP). Bỏ qua."
fi

# ==========================================
# GIAI ĐOẠN 2: 3DGRUT
# ==========================================
if [ ! -f "$CACHE_DIR/stage2.done" ]; then
    echo "========================================"
    echo " GIAI ĐOẠN 2: TRAIN 3DGRUT"
    echo "========================================"
    python train.py --config-name apps/colmap_3dgut.yaml \
       path="$BASE_DIR" out_dir=runs \
       experiment_name="$EXP_NAME" \
       +export_usdz.enabled=true \
       dataset.downsample_factor="$DATA_COMP"

    touch "$CACHE_DIR/stage2.done"
else
    echo ">> Đã xong Giai đoạn 2 (3DGRUT). Bỏ qua."
fi

# ==========================================
# GIAI ĐOẠN 3: COLMAP DENSE & EXTRACT MESH
# ==========================================
if [ ! -f "$CACHE_DIR/stage3.done" ]; then
    echo "========================================"
    echo " GIAI ĐOẠN 3: DENSE & EXTRACT MESH"
    echo "========================================"

    rm -rf "$DENSE_DIR"
    mkdir -p "$DENSE_DIR"

    colmap image_undistorter \
        --image_path "$IMG_WORK_DIR" \
        --input_path "$SPARSE_DIR/0" \
        --output_path "$DENSE_DIR" \
        --output_type COLMAP

    colmap patch_match_stereo \
        --workspace_path "$DENSE_DIR" \
        --workspace_format COLMAP

    colmap stereo_fusion \
        --workspace_path "$DENSE_DIR" \
        --workspace_format COLMAP \
        --output_path "$DENSE_DIR/fused.ply"

    python extract_mesh.py "$DENSE_DIR/fused.ply" "$BASE_DIR/mesh.usd"

    touch "$CACHE_DIR/stage3.done"
else
    echo ">> Đã xong Giai đoạn 3 (Mesh). Bỏ qua."
fi

# ==========================================
# GIAI ĐOẠN 4: (POST-PROCESSING)
# ==========================================
echo "========================================"
echo " GIAI ĐOẠN 4: GOM CHIẾN LỢI PHẨM"
echo "========================================"

USDZ_FILE=$(find "runs/$EXP_NAME" -name "export_last.usdz" -type f | head -n 1)
if [ -n "$USDZ_FILE" ]; then
    cp "$USDZ_FILE" "$OUTPUT_DIR/${EXP_NAME}_pointcloud.usdz"
    echo "[OK] Đã bế file USDZ về: $OUTPUT_DIR/${EXP_NAME}_pointcloud.usdz"
else
    echo "[LỖI] Tìm mờ mắt không thấy cái export_last.usdz nào trong runs/$EXP_NAME. 3DGRUT chạy xịt à?"
fi

if [ -f "temp_room.obj" ]; then
    mv "temp_room.obj" "$OUTPUT_DIR/${EXP_NAME}_mesh.obj"
    echo "[OK] Đã hốt file OBJ về: $OUTPUT_DIR/${EXP_NAME}_mesh.obj"
else
    echo "[CẢNH BÁO] Không thấy file temp_room.obj. Script extract_mesh tạch hay ông lại chạy sai thư mục đấy?"
fi

echo "========================================"
echo " XONG! TẤT CẢ ĐÃ AN BÀI TRONG: $OUTPUT_DIR"
echo " FILE LOG CỦA ÔNG NẰM Ở: $LOG_FILE"
echo "========================================"
