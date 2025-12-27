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
