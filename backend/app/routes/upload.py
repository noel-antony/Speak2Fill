from fastapi import APIRouter, File, HTTPException, UploadFile

from app.schemas.models import OcrItem, UploadFormResponse
from app.services.storage_service import store
from app.services.ocr_service import ocr_service

router = APIRouter(tags=["forms"])


@router.post("/upload-form", response_model=UploadFormResponse)
async def upload_form(file: UploadFile = File(...)) -> UploadFormResponse:
    """Process an uploaded form image with GPU-accelerated OCR."""
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Please upload an image file.")

    if not ocr_service.is_ready():
        ocr_service.warmup_async()
        err = ocr_service.get_warmup_error()
        detail = "OCR model is warming up. Retry in 30–120 seconds."
        if err:
            detail = f"OCR warmup failed: {err}"
        raise HTTPException(status_code=503, detail=detail)

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty upload.")

    try:
        ocr_result = ocr_service.run_ocr(image_bytes=image_bytes)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    session_id = store.create_session(
        filename=file.filename or "uploaded_image",
        ocr_items=ocr_result.items,
        fields=ocr_result.fields,
    )

    return UploadFormResponse(
        session_id=session_id,
        ocr_items=[OcrItem(**item) for item in ocr_result.items],
        fields=ocr_result.fields,
    )
