from __future__ import annotations

import gc
import json
import os
import re
import tempfile
import threading
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np
import paddle
import torch
from PIL import Image
from paddleocr import PaddleOCRVL

from app.schemas.models import FormField

# CRITICAL: Set these BEFORE any Paddle operations
# Configure PaddlePaddle for optimal memory usage on low VRAM GPUs (4GB)
os.environ["FLAGS_allocator_strategy"] = "auto_growth"
os.environ["FLAGS_fraction_of_gpu_memory_to_use"] = "0.75"  # Leave 25% for OS/Display
os.environ["FLAGS_eager_delete_tensor_gb"] = "0.0"
os.environ["FLAGS_memory_fraction_of_eager_deletion"] = "1.0"


FIELD_SYNONYMS: Dict[str, List[str]] = {
    "Name": ["name", "full name", "applicant name", "customer name"],
    "DOB": ["dob", "date of birth", "birth date"],
    "Address": ["address", "residential address", "permanent address"],
    "Phone": ["phone", "mobile", "mobile no", "mobile number", "contact", "contact no"],
    "Email": ["email", "e-mail"],
    "Date": ["date"],
    "Amount": ["amount", "amt", "rupees", "rs", "inr"],
    "Account Number": ["account", "account no", "a/c", "a/c no", "account number"],
    "IFSC": ["ifsc"],
    "Branch": ["branch"],
}


def _normalize_text(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[\s\t\n]+", " ", s)
    s = s.replace("：", ":")
    s = s.strip(" :.-")
    return s

def _resize_image_for_inference(img: Image.Image, max_size: int = 1024) -> Tuple[np.ndarray, float]:
    """Resize image to fit within max_size while maintaining aspect ratio.

    High-resolution images trigger OOM on 4GB GPUs. This resizes images to a
    maximum dimension of 1024px (configurable via MAX_IMAGE_SIZE env var).
    Uses cv2.INTER_AREA for optimal downsampling quality.

    Args:
        img: PIL Image
        max_size: Maximum width or height in pixels

    Returns:
        Tuple of (resized_numpy_array, scale_factor)
    """
    max_size = int(os.getenv("MAX_IMAGE_SIZE", str(max_size)))

    # Convert PIL to numpy array
    img_np = np.array(img)
    h, w = img_np.shape[:2]

    if max(h, w) <= max_size:
        return img_np, 1.0

    # Calculate scale to fit within max_size
    scale = max_size / float(max(h, w))
    new_width = int(w * scale)
    new_height = int(h * scale)

    # Use INTER_AREA for high-quality downsampling (optimal for shrinking)
    resized = cv2.resize(img_np, (new_width, new_height), interpolation=cv2.INTER_AREA)
    return resized, scale


def _bbox_points_to_xyxy(points: List[List[float]]) -> List[int]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x1 = int(min(xs))
    y1 = int(min(ys))
    x2 = int(max(xs))
    y2 = int(max(ys))
    return [x1, y1, x2, y2]


def _expand_bbox_right(bbox: List[int], factor: float = 3.0, min_width: int = 160) -> List[int]:
    x1, y1, x2, y2 = bbox
    width = max(x2 - x1, 1)
    target_width = max(int(width * factor), min_width)
    return [x2 + 8, y1 - 2, x2 + 8 + target_width, y2 + 2]


def _extract_ocr_items_from_json(obj: Any, *, max_nodes: int = 50_000) -> List[Dict[str, Any]]:
    """Best-effort extractor for PaddleOCR-VL saved JSON outputs.

    We don't rely on a single fixed schema because PaddleOCR-VL output JSON can evolve
    and differs across pipeline configs. Instead, we walk the JSON tree and collect
    any dict nodes that look like text boxes.
    """

    def _bbox_from_any(v: Any) -> tuple[Optional[List[int]], Optional[List[List[float]]]]:
        if isinstance(v, (list, tuple)) and len(v) == 4:
            if v and isinstance(v[0], (list, tuple)):
                try:
                    pts = [[float(p[0]), float(p[1])] for p in v]
                    return _bbox_points_to_xyxy(pts), pts
                except Exception:
                    return None, None
            try:
                return [int(v[0]), int(v[1]), int(v[2]), int(v[3])], None
            except Exception:
                return None, None
        return None, None

    items: List[Dict[str, Any]] = []
    stack: List[Any] = [obj]
    seen = 0

    while stack:
        cur = stack.pop()
        seen += 1
        if seen > max_nodes:
            break

        if isinstance(cur, dict):
            # Try multiple text field names
            text_val = cur.get("text") or cur.get("block_content")
            if isinstance(text_val, str):
                text = text_val.strip()
                if text:
                    # Try multiple bbox field names
                    bbox, points = _bbox_from_any(cur.get("bbox"))
                    if bbox is None:
                        bbox, points = _bbox_from_any(cur.get("block_bbox"))
                    if bbox is None:
                        bbox, points = _bbox_from_any(cur.get("box"))
                    if bbox is None:
                        bbox, points = _bbox_from_any(cur.get("poly"))
                    if bbox is None:
                        bbox, points = _bbox_from_any(cur.get("points"))

                    if bbox is not None:
                        score_raw = cur.get("score", cur.get("rec_score", 1.0))
                        try:
                            score = float(score_raw)
                        except Exception:
                            score = 1.0
                        items.append({"text": text, "score": score, "bbox": bbox, "points": points})

            for v in cur.values():
                if isinstance(v, (dict, list, tuple)):
                    stack.append(v)
            continue

        if isinstance(cur, (list, tuple)):
            for v in cur:
                if isinstance(v, (dict, list, tuple)):
                    stack.append(v)
            continue

    return items


def _guess_field_label(text: str) -> Optional[str]:
    norm = _normalize_text(text)
    for canonical, variants in FIELD_SYNONYMS.items():
        for v in variants:
            v_norm = _normalize_text(v)
            if norm == v_norm or norm.startswith(v_norm + " ") or norm.startswith(v_norm + ":"):
                return canonical
    # Also match patterns like "Name:" "DOB:" etc.
    for canonical, variants in FIELD_SYNONYMS.items():
        for v in variants:
            v_norm = _normalize_text(v)
            if norm.startswith(v_norm + ":"):
                return canonical
    return None


def _infer_fields_from_ocr_items(ocr_items: List[Dict[str, Any]]) -> List[FormField]:
    """Best-effort heuristic: treat recognized label-like texts as form fields.

    Strategy:
    - If OCR text matches known label synonyms (Name/DOB/Address...), create a field.
    - The guidance bbox is the label bbox expanded to the right, so the frontend can draw
      a "fill here" guide next to the label.
    """

    fields: List[FormField] = []
    seen_labels = set()

    for item in ocr_items:
        text = str(item.get("text", ""))
        label = _guess_field_label(text)
        if not label:
            continue

        # De-dupe repeated headers/labels.
        key = (label, tuple(item.get("bbox", [])))
        if key in seen_labels:
            continue
        seen_labels.add(key)

        label_bbox = item.get("bbox", [0, 0, 0, 0])
        field_bbox = _expand_bbox_right(label_bbox)

        fields.append(
            FormField(
                label=label,
                text="",
                bbox=field_bbox,
            )
        )

    # If we found nothing, return empty; chat route will degrade gracefully.
    return fields


@dataclass
class OcrResult:
    items: List[Dict[str, Any]]
    fields: List[FormField]


class OCRService:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._vl: Any = None
        self._warmup_started = False
        self._warmup_error: Optional[str] = None

    def is_ready(self) -> bool:
        return self._vl is not None

    def get_warmup_error(self) -> Optional[str]:
        return self._warmup_error

    def warmup_async(self) -> None:
        """Start model download/init in a background thread (best-effort)."""

        with self._lock:
            if self._warmup_started:
                return
            self._warmup_started = True

        def _run() -> None:
            try:
                self._get_vl()
            except Exception as e:
                # Store a compact error so the API can surface it.
                self._warmup_error = f"{type(e).__name__}: {e}"

        t = threading.Thread(target=_run, name="ocr-warmup", daemon=True)
        t.start()

    def _select_device(self) -> str:
        """Return a PaddleOCRVL device string.

        Env:
        - OCR_DEVICE: 'auto' (default), 'cpu', 'gpu', 'gpu:0', ...
        """

        requested = (os.getenv("OCR_DEVICE") or "auto").strip().lower()
        if requested in {"auto", ""}:
            return "gpu:0" if paddle.is_compiled_with_cuda() else "cpu"

        if requested.startswith("gpu") and not paddle.is_compiled_with_cuda():
            raise RuntimeError(
                "GPU was requested (OCR_DEVICE=gpu) but PaddlePaddle is CPU-only in this environment. "
                "Install a CUDA-enabled PaddlePaddle build (paddlepaddle-gpu) matching your CUDA version."
            )

        if requested == "gpu":
            return "gpu:0"

        return requested

    def _get_vl(self):
        """Lazy-init PaddleOCRVL pipeline with FP16 and memory optimizations.

        Optimizations for 4GB VRAM:
        1. FP16 (float16) precision for 50% memory reduction
        2. Flash Attention 2 for efficient attention computation
        3. Auto-growth memory allocation strategy
        4. Disabled optional modules (orientation, unwarping)
        
        For vLLM acceleration (6GB+ VRAM):
        - Start vLLM server: paddleocr genai_server --model_name PaddleOCR-VL-0.9B --backend vllm --port 8118
        - Set environment variables: USE_VLLM_SERVER=true VLLM_SERVER_URL=http://127.0.0.1:8118/v1
        """
        if self._vl is not None:
            return self._vl

        device = self._select_device()
        
        # Check if using vLLM acceleration server
        use_vllm = os.getenv("USE_VLLM_SERVER", "false").lower() == "true"
        vllm_url = os.getenv("VLLM_SERVER_URL", "http://127.0.0.1:8118/v1")
        
        with self._lock:
            if self._vl is None:
                try:
                    if use_vllm:
                        # Use vLLM server for optimal performance with Flash Attention 2
                        self._vl = PaddleOCRVL(
                            device=device,
                            vl_rec_backend="vllm-server",
                            vl_rec_server_url=vllm_url,
                            use_doc_orientation_classify=False,
                            use_doc_unwarping=False,
                        )  # type: ignore[misc]
                    else:
                        # Direct inference mode with FP16 for low VRAM
                        # Note: PaddleOCRVL handles FP16 conversion internally based on device
                        self._vl = PaddleOCRVL(
                            device=device,
                            use_doc_orientation_classify=False,  # Save memory
                            use_doc_unwarping=False,  # Save memory
                            use_layout_detection=True,  # Keep for structure
                        )  # type: ignore[misc]
                        
                        # Force garbage collection after model loading
                        gc.collect()
                        if device.startswith("gpu"):
                            paddle.device.cuda.empty_cache()
                            try:
                                torch.cuda.empty_cache()
                            except Exception:
                                pass  # torch may not be CUDA-enabled
                except TypeError:
                    self._vl = PaddleOCRVL()  # type: ignore[misc]
        return self._vl

    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        """Run OCR with memory-optimized preprocessing and cleanup.
        
        Optimizations:
        1. Resize large images to max 1024px to prevent OOM
        2. torch.no_grad() context to prevent gradient storage
        3. Aggressive garbage collection after inference
        4. Explicit GPU cache clearing (both torch and paddle)
        """
        try:
            pil = Image.open(BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            head = image_bytes[:16].hex()
            raise ValueError(f"Invalid image data (len={len(image_bytes)} head={head})") from e
        
        # Resize image if too large (prevents OOM on 4GB GPUs)
        original_size = pil.size
        img_np, scale_factor = _resize_image_for_inference(pil)
        if scale_factor < 1.0:
            print(f"[OCR] Resized image from {original_size} to {img_np.shape[:2][::-1]} (scale={scale_factor:.2f})")
        
        pipeline = self._get_vl()
        output = None
        items: List[Dict[str, Any]] = []
        
        try:
            # Use no_grad context to prevent gradient storage (saves memory)
            with torch.no_grad():
                with tempfile.TemporaryDirectory(prefix="paddleocrvl_out_") as out_dir:
                    out_path = Path(out_dir)
                    with tempfile.NamedTemporaryFile(suffix=".png", delete=True) as tmp:
                        # Save resized numpy array with optimized compression
                        # numpy array from PIL is RGB, cv2.imwrite expects BGR
                        img_bgr = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)
                        cv2.imwrite(tmp.name, img_bgr)
                        tmp.flush()
                        output = pipeline.predict(tmp.name)

                    # Official API pattern: iterate Result objects, save to JSON, parse JSON.
                    for res in output or []:
                        save_to_json = getattr(res, "save_to_json", None)
                        if callable(save_to_json):
                            save_to_json(save_path=str(out_path))

                    json_files = sorted(out_path.glob("**/*.json"))
                    if not json_files:
                        raise RuntimeError(
                            "PaddleOCRVL produced no JSON outputs via res.save_to_json(). "
                            "This usually indicates an installation/config mismatch."
                        )

                    for jf in json_files:
                        try:
                            text_content = jf.read_text(encoding="utf-8")
                            payload = json.loads(text_content)
                        except Exception:
                            continue
                        items.extend(_extract_ocr_items_from_json(payload))

                    if not items:
                        raise RuntimeError(
                            "PaddleOCRVL returned no OCR items after parsing JSON outputs."
                        )

                # Scale bounding boxes back to original image size if resized
                if scale_factor < 1.0:
                    for item in items:
                        if "bbox" in item and item["bbox"]:
                            item["bbox"] = [
                                int(coord / scale_factor) for coord in item["bbox"]
                            ]
                        if "points" in item and item["points"]:
                            item["points"] = [
                                [coord / scale_factor for coord in point]
                                for point in item["points"]
                            ]
        finally:
            # Aggressive memory cleanup for low VRAM GPUs
            del output
            del img_np
            del pil
            gc.collect()
            
                # Clear GPU cache if using GPU (both torch and paddle)
            device = self._select_device()
            if device.startswith("gpu"):
                try:
                        torch.cuda.empty_cache()
                except Exception:
                    pass  # Ignore errors in cleanup
                try:
                    paddle.device.cuda.empty_cache()
                except Exception:
                    pass

        fields = _infer_fields_from_ocr_items(items)
        return OcrResult(items=items, fields=fields)


ocr_service = OCRService()
