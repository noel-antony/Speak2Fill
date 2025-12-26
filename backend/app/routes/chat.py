from fastapi import APIRouter, HTTPException

from app.schemas.models import ChatRequest, ChatResponse
from app.services.llm_service import llm_service
from app.services.memory_service import memory

router = APIRouter(tags=["chat"])


@router.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    session = memory.get_session(req.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Unknown session_id")

    current_field = memory.get_next_field(req.session_id)
    reply = llm_service.generate_reply(current_field=current_field, user_message=req.user_message)
    memory.append_message(req.session_id, role="user", content=req.user_message)
    memory.append_message(req.session_id, role="assistant", content=reply.reply_text)

    # MVP behavior: move to the next field on each user turn.
    memory.advance_field(req.session_id)

    return reply
