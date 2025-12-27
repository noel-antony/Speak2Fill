"""
Chat endpoint - Deterministic state machine for form filling.

This endpoint handles ONE conversational turn per request.
The backend controls ALL logic - Gemini is only used for polite text generation.

Flow:
1. Load session state
2. Check completion
3. Get current field
4. PHASE A (Data Collection): Collect value if needed
5. PHASE B (Writing Guidance): Guide user to write
6. Wait for confirmation, then advance
"""

from fastapi import APIRouter, HTTPException

from app.schemas.models import ChatRequest, ChatResponse, DrawGuideAction
from app.services.gemini_service import get_gemini_service
from app.services.storage_service import store

router = APIRouter(tags=["chat"])

# Confirmation keywords (language-agnostic)
CONFIRMATION_WORDS = {"done", "finished", "ok", "completed", "yes", "next"}


def _normalize_value(value: str, write_language: str) -> str:
    """Normalize user input based on field language."""
    value = value.strip()
    
    if write_language == "numeric":
        # Extract only digits
        return "".join(c for c in value if c.isdigit())
    
    # For en/ml, just clean whitespace
    return " ".join(value.split())


def _is_confirmation(user_message: str) -> bool:
    """Check if user message is a confirmation keyword."""
    normalized = user_message.strip().lower()
    return normalized in CONFIRMATION_WORDS


@router.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    """
    Handle one chat turn in the form-filling state machine.
    
    The backend decides ALL logic:
    - Which field is current
    - Whether to collect data or guide writing
    - When to advance to the next field
    
    Gemini is ONLY used to generate polite assistant text.
    """
    
    # ===== STEP 1: Load session state =====
    session = store.get_session(req.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    
    fields = session.get("fields", [])
    image_width = session.get("image_width", 0)
    image_height = session.get("image_height", 0)
    
    # Get current field index from DB
    current_index = store.get_current_field_index(req.session_id)
    if current_index is None:
        current_index = 0
    
    # ===== STEP 2: Check if all fields completed =====
    if current_index >= len(fields):
        gemini = get_gemini_service()
        assistant_text = gemini.generate_assistant_text(
            phase="completion",
            field_label="",
            input_mode="",
            write_language="",
        )
        return ChatResponse(assistant_text=assistant_text, action=None)
    
    # ===== STEP 3: Get current field =====
    current_field = fields[current_index]
    field_id = current_field.get("field_id")
    field_label = current_field.get("label")
    bbox = current_field.get("bbox")
    input_mode = current_field.get("input_mode", "voice")
    write_language = current_field.get("write_language", "en")
    
    # Get current stored value
    current_value = store.get_field_value(req.session_id, field_id) or ""
    
    gemini = get_gemini_service()
    
    # ===== STEP 4: Check if user is confirming completion =====
    if _is_confirmation(req.user_message):
        # User confirmed they finished writing
        # Advance to next field
        store.advance_field_index(req.session_id)
        
        # Check if there's a next field
        next_index = current_index + 1
        if next_index >= len(fields):
            # All fields complete
            assistant_text = gemini.generate_assistant_text(
                phase="completion",
                field_label="",
                input_mode="",
                write_language="",
            )
            return ChatResponse(assistant_text=assistant_text, action=None)
        
        # Move to next field - start PHASE A (data collection)
        next_field = fields[next_index]
        next_field_id = next_field.get("field_id")
        next_label = next_field.get("label")
        next_bbox = next_field.get("bbox")
        next_input_mode = next_field.get("input_mode", "voice")
        next_write_language = next_field.get("write_language", "en")
        
        # If next field is placeholder, skip data collection
        if next_input_mode == "placeholder":
            assistant_text = gemini.generate_assistant_text(
                phase="writing_guide",
                field_label=next_label,
                input_mode=next_input_mode,
                write_language=next_write_language,
                value="",
            )
            return ChatResponse(
                assistant_text=assistant_text,
                action=DrawGuideAction(
                    field_label=next_label,
                    text_to_write="",
                    bbox=next_bbox,
                    image_width=image_width,
                    image_height=image_height,
                ),
            )
        
        # Voice field - ask for value
        assistant_text = gemini.generate_assistant_text(
            phase="collect_value",
            field_label=next_label,
            input_mode=next_input_mode,
            write_language=next_write_language,
        )
        return ChatResponse(assistant_text=assistant_text, action=None)
    
    # ===== PHASE A: DATA COLLECTION =====
    if not current_value:
        # No value stored yet
        
        if input_mode == "placeholder":
            # Placeholder fields don't collect data - go straight to writing guide
            assistant_text = gemini.generate_assistant_text(
                phase="writing_guide",
                field_label=field_label,
                input_mode=input_mode,
                write_language=write_language,
                value="",
            )
            return ChatResponse(
                assistant_text=assistant_text,
                action=DrawGuideAction(
                    field_label=field_label,
                    text_to_write="",
                    bbox=bbox,
                    image_width=image_width,
                    image_height=image_height,
                ),
            )
        
        # Voice mode - collect value from user_message
        normalized_value = _normalize_value(req.user_message, write_language)
        
        if not normalized_value:
            # Empty value - ask again
            assistant_text = gemini.generate_assistant_text(
                phase="collect_value",
                field_label=field_label,
                input_mode=input_mode,
                write_language=write_language,
            )
            return ChatResponse(assistant_text=assistant_text, action=None)
        
        # Store the value
        store.set_field_value(req.session_id, field_id, normalized_value)
        
        # Move to PHASE B (writing guidance)
        assistant_text = gemini.generate_assistant_text(
            phase="writing_guide",
            field_label=field_label,
            input_mode=input_mode,
            write_language=write_language,
            value=normalized_value,
        )
        return ChatResponse(
            assistant_text=assistant_text,
            action=DrawGuideAction(
                field_label=field_label,
                text_to_write=normalized_value,
                bbox=bbox,
                image_width=image_width,
                image_height=image_height,
            ),
        )
    
    # ===== PHASE B: WRITING GUIDANCE (value already exists) =====
    # User hasn't confirmed yet, repeat writing instruction
    assistant_text = gemini.generate_assistant_text(
        phase="writing_guide",
        field_label=field_label,
        input_mode=input_mode,
        write_language=write_language,
        value=current_value,
    )
    return ChatResponse(
        assistant_text=assistant_text,
        action=DrawGuideAction(
            field_label=field_label,
            text_to_write=current_value,
            bbox=bbox,
            image_width=image_width,
            image_height=image_height,
        ),
    )
