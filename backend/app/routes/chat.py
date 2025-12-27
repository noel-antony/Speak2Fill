from fastapi import APIRouter, HTTPException

from app.schemas.models import ChatRequest, ChatResponse, WhiteboardAction
from app.services.gemini_service import get_gemini_service
from app.services.storage_service import store

router = APIRouter(tags=["chat"])


CONFIRMATION_WORDS = {"done", "ok", "next", "complete", "finished", "yes", "കഴിഞ്ഞു", "ചെയ്തു"}


@router.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    """
    Form filling chat endpoint with deterministic flow control.
    Backend decides field order and progression logic.
    """
    # Load session
    session = store.get_session(req.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")

    fields = session.get("fields", [])
    current_idx = session.get("current_field_index", 0)
    filled_fields = session.get("filled_fields", {})
    language = session.get("language", "en")

    # Check if form is complete
    if current_idx >= len(fields):
        store.append_message(req.session_id, role="user", content=req.user_message)
        return ChatResponse(
            reply_text="All fields completed! Your form is ready." if language == "en" else "എല്ലാ ഫീൽഡുകളും പൂർത്തിയായി!",
            action=None,
        )

    current_field = fields[current_idx]
    field_label = current_field.get("label", "this field")
    field_bbox = current_field.get("bbox", [0, 0, 0, 0])

    user_msg_lower = req.user_message.strip().lower()

    # Check if user is confirming completion
    is_confirmation = any(word in user_msg_lower for word in CONFIRMATION_WORDS)

    if is_confirmation:
        # User confirmed they've written the field - advance to next
        store.append_message(req.session_id, role="user", content=req.user_message)
        store.advance_field(req.session_id)

        # Check if there's a next field
        next_idx = current_idx + 1
        if next_idx >= len(fields):
            # Form complete
            reply_text = (
                "Perfect! All fields are now complete."
                if language == "en"
                else "എല്ലാ ഫീൽഡുകളും പൂർത്തിയായി!"
            )
            store.append_message(req.session_id, role="assistant", content=reply_text)
            return ChatResponse(reply_text=reply_text, action=None)

        # Move to next field
        next_field = fields[next_idx]
        next_label = next_field.get("label", "next field")
        next_bbox = next_field.get("bbox", [0, 0, 0, 0])

        gemini = get_gemini_service()
        reply_text = gemini.generate_assistant_message(next_label, language, is_confirmation=False)

        store.append_message(req.session_id, role="assistant", content=reply_text)

        return ChatResponse(
            reply_text=reply_text,
            action=WhiteboardAction(type="DRAW_GUIDE", text=next_label, bbox=next_bbox),
        )

    else:
        # User is providing input (voice transcription)
        # Store it but don't advance yet - wait for explicit confirmation
        store.update_filled_field(req.session_id, field_label, req.user_message)
        store.append_message(req.session_id, role="user", content=req.user_message)

        # Ask user to confirm by saying "done"
        if language == "en":
            reply_text = f"Got it: '{req.user_message}'. Please write it in the '{field_label}' box and say 'done' when finished."
        else:
            reply_text = f"മനസ്സിലായി: '{req.user_message}'. '{field_label}' ബോക്സിൽ എഴുതി 'ചെയ്തു' എന്ന് പറയുക."

        store.append_message(req.session_id, role="assistant", content=reply_text)

        return ChatResponse(
            reply_text=reply_text,
            action=WhiteboardAction(type="DRAW_GUIDE", text=req.user_message, bbox=field_bbox),
        )
