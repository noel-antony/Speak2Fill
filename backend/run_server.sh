#!/bin/bash
# Speak2Fill Backend Server Startup Script
#
# Usage:
#   ./run_server.sh              # Auto-detect GPU and use optimal settings
#   ./run_server.sh --vllm       # Use vLLM acceleration (recommended for production)
#   ./run_server.sh --cpu        # Force CPU mode
#   ./run_server.sh --gpu        # Force direct GPU mode (no vLLM)

cd "$(dirname "$0")"

MODE="${1:---auto}"

# Check GPU VRAM
if command -v nvidia-smi &> /dev/null; then
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    echo "Detected GPU with ${GPU_MEM}MB VRAM"
    HAS_GPU=true
else
    echo "No GPU detected."
    HAS_GPU=false
    MODE="--cpu"
fi

case "$MODE" in
    --vllm)
        if [ "$HAS_GPU" = false ]; then
            echo "❌ Error: vLLM requires GPU"
            exit 1
        fi
        
        echo "🚀 Starting in vLLM acceleration mode (optimal performance)"
        echo ""
        echo "📋 Prerequisites:"
        echo "   1. Install vLLM dependencies in a separate venv:"
        echo "      python -m venv .venv_vllm"
        echo "      source .venv_vllm/bin/activate"
        echo "      pip install 'paddleocr[doc-parser]'"
        echo "      paddleocr install_genai_server_deps vllm"
        echo ""
        echo "   2. Start vLLM server (in the .venv_vllm environment):"
        echo "      paddleocr genai_server --model_name PaddleOCR-VL-0.9B --backend vllm --port 8118"
        echo ""
        echo "   3. Then run this script again"
        echo ""
        read -p "Is vLLM server running on port 8118? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Please start vLLM server first."
            exit 1
        fi
        
        export USE_VLLM_SERVER=true
        export VLLM_SERVER_URL=http://127.0.0.1:8118/v1
        export OCR_DEVICE=gpu
        ;;
        
    --cpu)
        echo "🐌 Starting in CPU mode (slower but works on any hardware)"
        export OCR_DEVICE=cpu
        export USE_VLLM_SERVER=false
        ;;
        
    --gpu)
        if [ "$HAS_GPU" = false ]; then
            echo "❌ Error: No GPU detected"
            exit 1
        fi
        
        if [ "$GPU_MEM" -lt 6000 ]; then
            echo "⚠️  WARNING: Direct GPU mode requires ~6GB VRAM minimum."
            echo "    Your GPU has only ${GPU_MEM}MB. This will likely fail with OOM errors."
            echo "    Recommended: Use --vllm for better memory efficiency or --cpu for stability."
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        
        echo "⚡ Starting in direct GPU mode"
        export FLAGS_fraction_of_gpu_memory_to_use=0.8
        export OCR_DEVICE=gpu
        export USE_VLLM_SERVER=false
        ;;
        
    --auto|*)
        if [ "$HAS_GPU" = false ]; then
            echo "🐌 Auto-selected: CPU mode"
            export OCR_DEVICE=cpu
            export USE_VLLM_SERVER=false
        elif [ "$GPU_MEM" -lt 6000 ]; then
            echo "🐌 Auto-selected: CPU mode (GPU has insufficient VRAM)"
            echo "    For optimal performance, use: ./run_server.sh --vllm"
            export OCR_DEVICE=cpu
            export USE_VLLM_SERVER=false
        else
            echo "⚡ Auto-selected: Direct GPU mode"
            echo "    For optimal performance, use: ./run_server.sh --vllm"
            export FLAGS_fraction_of_gpu_memory_to_use=0.8
            export OCR_DEVICE=gpu
            export USE_VLLM_SERVER=false
        fi
        ;;
esac

# Disable model source check for faster startup
export DISABLE_MODEL_SOURCE_CHECK=True

# Start server
echo ""
echo "Starting server on http://0.0.0.0:8000"
echo "OCR Device: $OCR_DEVICE"
echo "vLLM Acceleration: $USE_VLLM_SERVER"
echo ""
.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
