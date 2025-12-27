#!/bin/bash
# Speak2Fill Backend Server Startup Script

cd "$(dirname "$0")"

# Check GPU VRAM
if command -v nvidia-smi &> /dev/null; then
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    echo "Detected GPU with ${GPU_MEM}MB VRAM"
    
    if [ "$GPU_MEM" -lt 6000 ]; then
        echo "⚠️  WARNING: PaddleOCR-VL requires ~6GB VRAM minimum."
        echo "    Your GPU has only ${GPU_MEM}MB. GPU mode will likely fail with OOM errors."
        echo ""
        echo "Recommended solutions:"
        echo "  1. Use CPU mode (slower but works): OCR_DEVICE=cpu"
        echo "  2. Upgrade to GPU with ≥6GB VRAM (RTX 3060+, RTX 4060+, etc.)"
        echo ""
        echo "Starting in CPU mode..."
        export OCR_DEVICE=cpu
    else
        echo "✓ GPU has sufficient VRAM for PaddleOCR-VL"
        # Set memory fraction for larger GPUs
        export FLAGS_fraction_of_gpu_memory_to_use=0.8
        export OCR_DEVICE=${OCR_DEVICE:-gpu}
    fi
else
    echo "No GPU detected. Using CPU mode."
    export OCR_DEVICE=cpu
fi

# Disable model source check for faster startup
export DISABLE_MODEL_SOURCE_CHECK=True

# Start server
echo "Starting server on http://0.0.0.0:8000"
.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
