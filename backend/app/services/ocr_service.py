from __future__ import annotations

import re
import threading
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from io import BytesIO

import numpy as np
from PIL import Image

# PaddleOCR docs (Python API):
# result = ocr.ocr(img_path_or_array, cls=True)
# each line: [ [[x1,y1], [x2,y2], [x3,y3], [x4,y4]], (text, score) ]
from paddleocr import PaddleOCR

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
        self._ocr: Optional[PaddleOCR] = None

    def _get_ocr(self) -> PaddleOCR:
        # Lazy init so importing the app doesn't immediately download models.
        # On first call, PaddleOCR may download weights.
        if self._ocr is not None:
            return self._ocr

        with self._lock:
            if self._ocr is None:
                # CPU only. PaddleOCR supports `use_gpu` in many versions.
                self._ocr = PaddleOCR(use_angle_cls=True, lang="en", use_gpu=False)
        return self._ocr

    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        try:
            pil = Image.open(BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise ValueError("Invalid image data") from e
        img = np.array(pil)

        ocr = self._get_ocr()
        raw = ocr.ocr(img, cls=True)

        # raw is typically a list of pages; for a single image it is [page0]
        page0 = raw[0] if isinstance(raw, list) and raw else []

        items: List[Dict[str, Any]] = []
        for line in page0 or []:
            try:
                points = line[0]
                text = line[1][0]
                score = float(line[1][1])
                bbox = _bbox_points_to_xyxy(points)
                items.append(
                    {
                        "text": text,
                        "score": score,
                        "bbox": bbox,
                        "points": points,
                    }
                )
            except Exception:
                # Best-effort: skip malformed lines.
                continue

        fields = _infer_fields_from_ocr_items(items)
        return OcrResult(items=items, fields=fields)


ocr_service = OCRService()
