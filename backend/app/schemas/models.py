from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class FormField(BaseModel):
    field_id: str = Field(..., description="Stable snake_case identifier for this field")
    label: str = Field(..., description="Human-readable field label, e.g., Name, DOB")
    bbox: List[int] = Field(..., min_length=4, max_length=4, description="[x1,y1,x2,y2]")
    input_mode: str = Field("voice", description="voice or placeholder")
    write_language: str = Field("en", description="en, ml, or numeric")


class OcrItem(BaseModel):
    text: str = Field(..., description="Detected text content")
    bbox: List[int] = Field(..., min_length=4, max_length=4, description="[x1,y1,x2,y2]")
    score: float = Field(..., description="OCR confidence score (0.0-1.0)")


class UploadFormResponse(BaseModel):
    session_id: str = Field(..., description="Unique session identifier")
    image_width: int = Field(..., description="Original image width in pixels")
    image_height: int = Field(..., description="Original image height in pixels")
    ocr_items: List[OcrItem] = Field(..., description="Deduplicated OCR text boxes")
    fields: List[FormField] = Field(..., description="Detected fillable form fields (ordered, immutable)")


class ChatRequest(BaseModel):
    session_id: str = Field(..., description="Session identifier")
    user_message: str = Field(..., description="User's transcribed voice input or text message")


class DrawGuideAction(BaseModel):
    type: Literal["DRAW_GUIDE"] = Field("DRAW_GUIDE", description="Action type")
    field_label: str = Field(..., description="Human-readable field label")
    text_to_write: str = Field(..., description="Text user should write (empty for placeholder fields)")
    bbox: List[int] = Field(..., min_length=4, max_length=4, description="[x1,y1,x2,y2] where to write")
    image_width: int = Field(..., description="Image width for coordinate scaling")
    image_height: int = Field(..., description="Image height for coordinate scaling")


class ChatResponse(BaseModel):
    assistant_text: str = Field(..., description="Spoken/displayed assistant instruction")
    action: Optional[DrawGuideAction] = Field(None, description="Visual guidance action for frontend")
