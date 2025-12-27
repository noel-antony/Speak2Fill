from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class FormField(BaseModel):
    label: str = Field(..., description="Best-effort field label, e.g., Name, DOB")
    text: str = Field("", description="(Optional) extracted or user-filled value")
    bbox: List[int] = Field(..., min_length=4, max_length=4, description="[x1,y1,x2,y2]")
    input_mode: str = Field("voice", description="voice or placeholder")
    write_language: str = Field("en", description="en, ml, or numeric")


class OcrItem(BaseModel):
    text: str
    score: float
    bbox: List[int] = Field(..., min_length=4, max_length=4, description="[x1,y1,x2,y2]")
    points: Optional[List[List[float]]] = Field(
        default=None, description="Quadrilateral points: [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]"
    )


class UploadFormResponse(BaseModel):
    session_id: str
    ocr_items: List[OcrItem]
    fields: List[FormField]
