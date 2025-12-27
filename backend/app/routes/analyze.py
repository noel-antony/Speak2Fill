from __future__ import annotations

import os
from io import BytesIO
from typing import Any, Dict, List, Optional, Tuple

import requests
from fastapi import APIRouter, File, HTTPException, UploadFile
from PIL import Image

from app.schemas.models import FormField, OcrItem, UploadFormResponse
from app.services.gemini_service import get_gemini_service
from app.services.storage_service import store

router = APIRouter(tags=["forms"])


def _get_ocr_service_url() -> str:
    url = os.getenv("OCR_SERVICE_URL") or os.getenv("PADDLE_OCR_SERVICE_URL")
    if not url:
        raise HTTPException(status_code=500, detail="OCR service URL is not configured")
    return url.rstrip("/")


def _bbox_from_points(points: List[List[float]]) -> Optional[List[int]]:
    try:
        xs = [float(p[0]) for p in points]
        ys = [float(p[1]) for p in points]
        x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)
        return [int(x1), int(y1), int(x2), int(y2)]
    except Exception:
        return None


def _coerce_item(raw: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    # Accept multiple text keys
    text_val = raw.get("text") or raw.get("block_content")
    if not isinstance(text_val, str):
        return None
    text = text_val.strip()
    if not text:
        return None

    # Accept multiple bbox shapes
    bbox = raw.get("bbox") or raw.get("block_bbox") or raw.get("coordinate")
    points = raw.get("points") or raw.get("poly")
    if bbox is None and points:
        bbox = _bbox_from_points(points)

    if isinstance(bbox, (list, tuple)) and len(bbox) == 4:
        try:
            bbox = [int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])]
        except Exception:
            return None
    else:
        return None

    try:
        score = float(raw.get("score", raw.get("rec_score", 1.0)))
    except Exception:
        score = 1.0

    return {
        "text": text,
        "score": score,
        "bbox": bbox,
        "points": points if isinstance(points, list) else None,
    }


def _extract_ocr_items(payload: Any) -> List[Dict[str, Any]]:
    """Walk any JSON structure to extract text boxes.

    Handles nested formats from PaddleOCR-VL including arrays wrapping a `res` dict
    and `parsing_res_list` entries with `block_content` and `block_bbox`.
    """
    items: List[Dict[str, Any]] = []

    def _walk(node: Any) -> None:
        if node is None:
            return
        if isinstance(node, dict):
            # Direct coercion if this node looks like a text box
            boxed = _coerce_item(node)
            if boxed:
                items.append(boxed)

            # Known nested containers
            for key in ("res", "result", "response"):
                if isinstance(node.get(key), (dict, list)):
                    _walk(node[key])
            for key in (
                "items",
                "data",
                "results",
                "ocr",
                "output",
                "parsing_res_list",
                "layout_det_res",
                "boxes",
            ):
                val = node.get(key)
                if isinstance(val, (dict, list)):
                    _walk(val)
            # Also walk all dict values generically
            for v in node.values():
                if isinstance(v, (dict, list)):
                    _walk(v)
            return

        if isinstance(node, list):
            for v in node:
                _walk(v)
            return

    _walk(payload)
    return items


def _find_image_dims(payload: Any) -> Tuple[int, int]:
    width = 0
    height = 0

    def _walk(node: Any) -> None:
        nonlocal width, height
        if isinstance(node, dict):
            try:
                w = int(node.get("width", 0))
                h = int(node.get("height", 0))
                if w > 0 and h > 0:
                    width, height = w, h
            except Exception:
                pass
            for v in node.values():
                if isinstance(v, (dict, list)):
                    _walk(v)
        elif isinstance(node, list):
            for v in node:
                _walk(v)

    _walk(payload)
    return width, height


def _call_remote_ocr(image_bytes: bytes, filename: Optional[str], content_type: Optional[str]):
    url = _get_ocr_service_url()

    try:
        # Send raw binary with application/octet-stream, no multipart fields.
        resp = requests.post(
            url,
            data=image_bytes,
            headers={
                "Content-Type": "application/octet-stream",
                "Accept": "application/json",
            },
            timeout=120,
        )
        resp.raise_for_status()
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="OCR service unavailable") from exc

    try:
        payload = resp.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="OCR service returned invalid JSON") from exc

    items = _extract_ocr_items(payload)
    if not items:
        raise HTTPException(status_code=502, detail="OCR service returned no text boxes")

    image_width, image_height = _find_image_dims(payload)

    return items, image_width, image_height


@router.post("/analyze-form", response_model=UploadFormResponse)
async def analyze_form(file: UploadFile = File(...)) -> UploadFormResponse:
    """Accept an image, run remote OCR, validate with Gemini, and create a session."""
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Please upload an image file.")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty upload.")

    try:
        pil = Image.open(BytesIO(image_bytes)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid image data.") from exc

    local_width, local_height = pil.size

    ocr_items, reported_width, reported_height = _call_remote_ocr(
        image_bytes=image_bytes, filename=file.filename, content_type=file.content_type
    )

    image_width = reported_width or local_width
    image_height = reported_height or local_height

    MIN_CONFIDENCE = 0.5
    filtered_items = [item for item in ocr_items if item.get("score", 0) >= MIN_CONFIDENCE]
    if not filtered_items:
        raise HTTPException(status_code=400, detail="No high-confidence OCR text found")

    try:
        gemini = get_gemini_service()
        fields = gemini.analyze_form_fields(filtered_items, image_width, image_height)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Gemini API error: {str(exc)}") from exc

    if not fields:
        raise HTTPException(status_code=400, detail="Gemini could not identify any fillable fields")

    try:
        validated_fields = [FormField(**field) for field in fields]
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Invalid field structure returned from Gemini") from exc

    session_id = store.create_session(
        filename=file.filename or "uploaded_image",
        ocr_items=ocr_items,
        fields=validated_fields,
        image_width=image_width,
        image_height=image_height,
    )

    return UploadFormResponse(
        session_id=session_id,
        ocr_items=[OcrItem(**item) for item in ocr_items],
        fields=validated_fields,
    )
