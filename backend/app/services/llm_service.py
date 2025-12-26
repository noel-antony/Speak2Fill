from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

from app.schemas.models import ChatResponse, WhiteboardAction


@dataclass
class _LLMService:
    """Mocked LLM logic.

    This is intentionally simple for the hackathon MVP.
    Later you can replace `generate_reply` with Gemini calls.
    """

    def generate_reply(self, current_field: Optional[Dict[str, Any]], user_message: str) -> ChatResponse:
        if not current_field:
            reply_text = "I couldn't find any fields on this form. Please upload a clearer image or zoom in."
            return ChatResponse(reply_text=reply_text, action=None)

        label = str(current_field.get("label", "this field"))
        bbox = current_field.get("bbox", [0, 0, 0, 0])

        suggested_text = (user_message or "").strip() or "SAMPLE TEXT"

        reply_text = f"Please fill {label} in the highlighted box."
        action = WhiteboardAction(type="DRAW_GUIDE", text=suggested_text, bbox=bbox)
        return ChatResponse(reply_text=reply_text, action=action)


llm_service = _LLMService()
