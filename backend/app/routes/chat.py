"""
Chat endpoint - Deterministic state machine for form filling.
NO Gemini. NO WebSockets.
Uses Sarvam APIs: Saarika (STT), Sarvam-M (LLM), Bulbul (TTS)

State Machine:
- ASK_INPUT: Ask user for field value via voice
- AWAIT_CONFIRMATION: Wait for user to confirm they wrote it

Events:
- USER_SPOKE: User provided voice input (after STT)
- CONFIRM_DONE: User confirmed writing is complete
"""
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from typing import Optional
from app.schemas.models import ChatRequest, ChatResponse, DrawGuideAction
from app.services.sarvam_service import SarvamService
from app.services.session_service import session_service, Phase
import logging

logger = logging.getLogger(__name__)
router = APIRouter(tags=["chat"])


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    """
    Deterministic state machine for form filling.
    
    Request Events:
    - USER_SPOKE: User provided voice input (after STT)
    - CONFIRM_DONE: User confirmed writing is complete
    
    Two Phases:
    - ASK_INPUT: Extract value from user speech
    - AWAIT_CONFIRMATION: Wait for user to write and confirm
    """
    
    # ===== STEP 1: Load session state =====
    state = session_service.get_session(req.session_id)
    if not state:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # ===== STEP 2: Check if form is complete =====
    if not session_service.has_more_fields(req.session_id):
        return ChatResponse(
            assistant_text="നിങ്ങൾ ഫോം പൂർത്തിയാക്കി. നന്ദി!",
            action=None
        )
    
    # ===== STEP 3: Get current field =====
    current_field = session_service.get_current_field(req.session_id)
    if not current_field:
        raise HTTPException(status_code=500, detail="No current field")
    
    sarvam = SarvamService()
    
    # ===== STATE MACHINE LOGIC =====
    
    if state.phase == Phase.ASK_INPUT:
        # ===== PHASE: ASK_INPUT =====
        if req.event != "USER_SPOKE":
            # Invalid event for this phase
            return ChatResponse(
                assistant_text=f"ദയവായി {current_field.label} നു വേണ്ട മൂല്യം സംസാരിക്കുക.",
                action=None
            )
        
        if not req.user_text:
            raise HTTPException(status_code=400, detail="user_text required for USER_SPOKE event")
        
        # Extract value using Sarvam-M
        extracted_value = await sarvam.extract_field_value(
            field_label=current_field.label,
            user_text=req.user_text,
            write_language=current_field.write_language
        )
        
        # Store the value
        session_service.store_value(req.session_id, current_field.field_id, extracted_value)
        
        # Switch to AWAIT_CONFIRMATION phase
        session_service.set_phase(req.session_id, Phase.AWAIT_CONFIRMATION)
        
        # Generate instruction text
        instruction_text = f"ദയവായി ഹൈലൈറ്റ് ചെയ്ത ബോക്സിൽ {extracted_value} എഴുതുക."
        
        # Return with draw guide action
        return ChatResponse(
            assistant_text=instruction_text,
            action=DrawGuideAction(
                type="DRAW_GUIDE",
                field_id=current_field.field_id,
                text_to_write=extracted_value,
                bbox=current_field.bbox,
                image_width=state.image_width,
                image_height=state.image_height
            )
        )
    
    elif state.phase == Phase.AWAIT_CONFIRMATION:
        # ===== PHASE: AWAIT_CONFIRMATION =====
        if req.event != "CONFIRM_DONE":
            # User is speaking when they should be confirming
            return ChatResponse(
                assistant_text="ദയവായി ആദ്യം എഴുതുക, പിന്നെ 'ഞാൻ എഴുതിച്ചു' ബട്ടൺ അമർത്തുക.",
                action=DrawGuideAction(
                    type="DRAW_GUIDE",
                    field_id=current_field.field_id,
                    text_to_write=state.collected_values.get(current_field.field_id, ""),
                    bbox=current_field.bbox,
                    image_width=state.image_width,
                    image_height=state.image_height
                )
            )
        
        # User confirmed - advance to next field
        session_service.advance_to_next_field(req.session_id)
        
        # Check if more fields remain
        if not session_service.has_more_fields(req.session_id):
            return ChatResponse(
                assistant_text="ശബാശ്! ഫോം പൂർത്തിയായി.",
                action=None
            )
        
        # Get next field
        next_field = session_service.get_current_field(req.session_id)
        if not next_field:
            return ChatResponse(
                assistant_text="ഫോം പൂർത്തിയായി.",
                action=None
            )
        
        # Ask for next field value
        next_instruction = f"ഇപ്പോൾ ദയവായി {next_field.label} നു വേണ്ട മൂല്യം സംസാരിക്കുക."
        
        return ChatResponse(
            assistant_text=next_instruction,
            action=None
        )
    
    # Should not reach here
    raise HTTPException(status_code=500, detail="Invalid state")