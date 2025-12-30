from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from typing import Optional
from app.services.sarvam_service import SarvamService
from app.services.storage_service import store
from app.services.session_service import session_service
import logging

logger = logging.getLogger(__name__)
router = APIRouter(tags=["stt"])


def _lang_to_code(language: str) -> str:
    """Map short language code to Sarvam locale code."""
    lang = (language or "en").lower()
    return {
        "ml": "ml-IN",
        "en": "en-IN",
        "hi": "hi-IN",
        "ta": "ta-IN",
        "te": "te-IN",
    }.get(lang, "ml-IN")


@router.post("/stt")
async def stt(
    audio: UploadFile = File(...),
    language: str = Form("en"),
    session_id: Optional[str] = Form(None)
):
    """
    Convert user speech → text using Sarvam Saarika (STT).
    Input: multipart/form-data with fields:
    - audio: raw audio file (wav/mp3)
    - language: short code (default: ml)
    """
    logger.info(f"STT request received: language={language}, filename={audio.filename}, content_type={audio.content_type}")
    
    if audio is None:
        logger.error("STT: No audio file provided")
        raise HTTPException(status_code=400, detail="audio file is required")
    
    content = await audio.read()
    logger.info(f"STT: Audio file read, size={len(content)} bytes")
    
    if not content:
        logger.error("STT: Audio file is empty")
        raise HTTPException(status_code=400, detail="audio file is empty")
    
    try:
        sarvam = SarvamService()
        logger.info("STT: SarvamService initialized")
    except Exception as e:
        logger.error(f"STT: Sarvam init failed: {e}")
        raise HTTPException(status_code=500, detail=f"Sarvam init failed: {e}")
    
    # Use Sarvam auto language detection by default (language_code="unknown" per docs)
    language_code = "unknown"
    logger.info(f"STT: Using language_code={language_code} (auto-detect)")
    
    try:
        transcript, detected_language = await sarvam.speech_to_text(content, language_code=language_code)
        logger.info(f"STT: Transcript received: '{transcript}', detected_language={detected_language}")
    except Exception as e:
        logger.error(f"STT: Sarvam API failed: {e}")
        raise HTTPException(status_code=502, detail=f"STT failed: {e}")

    existing_session_lang = None
    existing_db_lang = None

    if session_id:
        try:
            session = session_service.get_session(session_id)
            if session:
                existing_session_lang = session.detected_language

            existing_db_lang = store.get_language(session_id)
            should_set = not (existing_session_lang or existing_db_lang)

            if should_set and detected_language and detected_language != "unknown":
                session_service.set_language(session_id, detected_language)
                store.set_language(session_id, detected_language)
        except Exception as e:
            logger.warning(f"STT: Failed to persist language for session {session_id}: {e}")

    resolved_language = detected_language or existing_session_lang or existing_db_lang or language

    return {
        "transcript": transcript,
        "language": resolved_language
    }