# vLLM Acceleration Setup Guide

For optimal performance with Flash Attention 2 and memory efficiency, use vLLM acceleration.

## Prerequisites

- NVIDIA GPU with Compute Capability ≥ 8.0 (RTX 30/40/50 series, A10/A100, etc.)
- CUDA 12.6 or higher
- At least 6GB VRAM (8GB+ recommended)

**Note:** RTX 3050 (4GB VRAM) does not meet minimum requirements. Use CPU mode instead.

## Setup Instructions

### 1. Create Separate Virtual Environment for vLLM

vLLM has different dependencies than PaddleOCR, so use a separate environment:

```bash
cd backend
python3.12 -m venv .venv_vllm
source .venv_vllm/bin/activate
```

### 2. Install PaddleOCR and vLLM Dependencies

```bash
# Install PaddleOCR
pip install "paddleocr[doc-parser]"

# Install vLLM dependencies
paddleocr install_genai_server_deps vllm
```

**Note:** This requires CUDA compilation tools (nvcc). If you don't have them, install pre-built Flash Attention:

```bash
# For CUDA 12.8 and Python 3.10
pip install https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.3.14/flash_attn-2.8.2+cu128torch2.8-cp310-cp310-linux_x86_64.whl

# Adjust the wheel URL for your Python version (cp310 = Python 3.10, cp312 = Python 3.12)
```

### 3. Start vLLM Server

In the `.venv_vllm` environment:

```bash
paddleocr genai_server --model_name PaddleOCR-VL-0.9B --backend vllm --port 8118
```

**Memory Optimization:** For GPUs with limited VRAM, create a config file:

```bash
# Create vllm_config.yaml
cat > vllm_config.yaml << EOF
gpu-memory-utilization: 0.8
max-num-seqs: 64
EOF

# Start with config
paddleocr genai_server \
  --model_name PaddleOCR-VL-0.9B \
  --backend vllm \
  --port 8118 \
  --backend_config vllm_config.yaml
```

### 4. Start PaddleOCR-VL Service

In a **separate terminal**, using the main `.venv`:

```bash
cd backend
./run_server.sh --vllm
```

Or manually:

```bash
source .venv/bin/activate
USE_VLLM_SERVER=true VLLM_SERVER_URL=http://127.0.0.1:8118/v1 OCR_DEVICE=gpu \
  python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Performance Benefits

- **2-5x faster inference** compared to direct mode
- **Better memory efficiency** with Flash Attention 2
- **Batching and caching** for concurrent requests
- **Stable memory usage** prevents OOM errors

## Architecture

```
┌─────────────────────────────────────────┐
│  Client Request (upload-form)           │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  PaddleOCR-VL Service (:8000)           │
│  - Layout detection                     │
│  - Document preprocessing               │
│  - Coordinates VLM calls                │
└────────────────┬────────────────────────┘
                 │ VLM inference requests
                 ▼
┌─────────────────────────────────────────┐
│  vLLM Server (:8118)                    │
│  - Vision-Language Model inference      │
│  - Flash Attention 2                    │
│  - Optimized GPU utilization            │
└─────────────────────────────────────────┘
```

## Troubleshooting

### vLLM Server Won't Start

**Problem:** `ModuleNotFoundError: No module named 'vllm'`

**Solution:** Make sure you're in the `.venv_vllm` environment and installed vLLM dependencies:
```bash
source .venv_vllm/bin/activate
paddleocr install_genai_server_deps vllm
```

### Out of Memory Errors

**Problem:** vLLM server crashes with CUDA OOM

**Solutions:**
1. Reduce `gpu-memory-utilization` in config (try 0.6-0.7)
2. Reduce `max-num-seqs` (try 32)
3. Use CPU mode if GPU has <6GB VRAM

### Connection Refused

**Problem:** `ConnectionRefused` when calling vLLM server

**Solution:** Ensure vLLM server is running:
```bash
curl http://127.0.0.1:8118/health
```

## Alternative: CPU Mode

For systems without sufficient GPU:

```bash
./run_server.sh --cpu
```

This uses CPU for all inference. Slower but guaranteed to work.
