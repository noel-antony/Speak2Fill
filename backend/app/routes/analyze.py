from fastapi import APIRouter, HTTPException

from app.schemas.models import AnalyzeFormRequest, AnalyzeFormResponse
from app.services.gemini_service import get_gemini_service
from app.services.storage_service import store

router = APIRouter(tags=["forms"])


@router.post("/analyze-form", response_model=AnalyzeFormResponse)
def analyze_form(req: AnalyzeFormRequest) -> AnalyzeFormResponse:
    """
    Analyze OCR data with Gemini to identify fillable fields.
    Runs ONCE per session after initial upload.
    """
    # Load session
    session = store.get_session(req.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")

    ocr_items = session.get("ocr_items", [])
    if not ocr_items:
        raise HTTPException(status_code=400, detail="No OCR data found for this session")

    image_width = session.get("image_width", 0)
    image_height = session.get("image_height", 0)

    # Filter low confidence items
    MIN_CONFIDENCE = 0.5
    filtered_items = [item for item in ocr_items if item.get("score", 0) >= MIN_CONFIDENCE]

    if not filtered_items:
        raise HTTPException(status_code=400, detail="No high-confidence OCR text found")

    # Call Gemini API
    try:
        gemini = get_gemini_service()
        fields = gemini.analyze_form_fields(filtered_items, image_width, image_height)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gemini API error: {str(e)}")

    if not fields:
        raise HTTPException(
            status_code=400, detail="Gemini could not identify any fillable fields. Try a clearer image."
        )

    # Validate and store fields
    validated_fields = []
    for field in fields:
        if not isinstance(field.get("bbox"), list) or len(field["bbox"]) != 4:
            continue
        validated_fields.append(
            {
                "label": field.get("label", "Unknown"),
                "bbox": field["bbox"],
                "text": field.get("text", ""),
                "input_mode": field.get("input_mode", "voice"),
                "write_language": field.get("write_language", "en"),
            }
        )

    if not validated_fields:
        raise HTTPException(status_code=400, detail="No valid fields after validation")

    # Update session with analyzed fields
    store.update_fields(req.session_id, validated_fields)

    return AnalyzeFormResponse(
        session_id=req.session_id,
        fields_count=len(validated_fields),
        message=f"Successfully identified {len(validated_fields)} fillable fields",
    )
