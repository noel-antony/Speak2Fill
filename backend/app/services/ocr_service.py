from __future__ import annotations

import re
import threading
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from io import BytesIO
import os
import tempfile

from PIL import Image

from paddleocr import PaddleOCRVL

import paddle

from app.schemas.models import FormField


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
        """Lazy-init PaddleOCRVL pipeline.

        Note: PaddleOCRVL requires extra dependencies (see backend/README.md).
        """
        if self._vl is not None:
            return self._vl

        device = self._select_device()

        with self._lock:
            if self._vl is None:
                try:
                    self._vl = PaddleOCRVL(device=device)  # type: ignore[misc]
                except TypeError:
                    self._vl = PaddleOCRVL()  # type: ignore[misc]
        return self._vl

    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        try:
            pil = Image.open(BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            head = image_bytes[:16].hex()
            raise ValueError(f"Invalid image data (len={len(image_bytes)} head={head})") from e
        pipeline = self._get_vl()
        with tempfile.NamedTemporaryFile(suffix=".png", delete=True) as tmp:
            pil.save(tmp, format="PNG")
            tmp.flush()
            output = pipeline.predict(tmp.name)

        items: List[Dict[str, Any]] = []
        for res in output or []:
            if not isinstance(res, dict):
                continue

            # Prefer line-level OCR output if present.
            ocr_result = res.get("ocr_result")
            if isinstance(ocr_result, list) and ocr_result:
                for r in ocr_result:
                    if not isinstance(r, dict):
                        continue
                    text = str(r.get("text", "") or "").strip()
                    if not text:
                        continue

                    bbox_raw = r.get("bbox")
                    if not bbox_raw:
                        continue

                    bbox: Optional[List[int]] = None
                    points: Optional[List[List[float]]] = None

                    if isinstance(bbox_raw, (list, tuple)) and len(bbox_raw) == 4 and not isinstance(bbox_raw[0], (list, tuple)):
                        bbox = [int(bbox_raw[0]), int(bbox_raw[1]), int(bbox_raw[2]), int(bbox_raw[3])]
                    elif isinstance(bbox_raw, (list, tuple)) and len(bbox_raw) == 4 and isinstance(bbox_raw[0], (list, tuple)):
                        points = [[float(p[0]), float(p[1])] for p in bbox_raw]  # type: ignore[index]
                        bbox = _bbox_points_to_xyxy(points)

                    if not bbox:
                        continue

                    score_raw = r.get("score", r.get("rec_score", 1.0))
                    try:
                        score = float(score_raw)
                    except Exception:
                        score = 1.0

                    items.append({"text": text, "score": score, "bbox": bbox, "points": points})
                continue

            # Fallback: document parsing layout regions (coarser regions).
            layout = res.get("layout_parsing_result")
            if isinstance(layout, dict):
                regions = layout.get("layout_regions", [])
                if isinstance(regions, list):
                    for region in regions:
                        if not isinstance(region, dict):
                            continue
                        text = str(region.get("text", "") or "").strip()
                        if not text:
                            continue
                        bbox_raw = region.get("bbox")
                        if not (isinstance(bbox_raw, (list, tuple)) and len(bbox_raw) == 4):
                            continue
                        try:
                            bbox = [int(bbox_raw[0]), int(bbox_raw[1]), int(bbox_raw[2]), int(bbox_raw[3])]
                        except Exception:
                            continue
                        items.append({"text": text, "score": 1.0, "bbox": bbox, "points": None})

        if not items:
            raise RuntimeError(
                "PaddleOCRVL returned no OCR items. "
                "If you're seeing a dependency error, install `paddleocr[doc-parser]` and `paddlex[ocr]`."
            )

        fields = _infer_fields_from_ocr_items(items)
        return OcrResult(items=items, fields=fields)


ocr_service = OCRService()
