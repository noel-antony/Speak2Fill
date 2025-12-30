from fastapi import APIRouter, HTTPException
from fastapi import Body
from fastapi.responses import Response
from app.services.sarvam_service import SarvamService
from app.services.storage_service import store
from app.services.session_service import session_service
import logging

logger = logging.getLogger(__name__)
router = APIRouter(tags=["tts"])


def _lang_to_code(language: str) -> str:
    lang = (language or "en").lower().replace("_", "-")
    if "-" in lang:
        lang = lang.split("-")[0]
    return {
        "ml": "ml-IN",
        "en": "en-IN",
        "hi": "hi-IN",
        "ta": "ta-IN",
        "te": "te-IN",
    }.get(lang, "en-IN")


def _voice_to_speaker(voice: str) -> str:
    # Map app-level voice to Sarvam speaker. 'default' → a neutral female voice.
    v = (voice or "default").lower()
    return {
        "default": "anushka",
        "female": "anushka",
        "male": "karun",
    }.get(v, "anushka")


@router.post("/tts")
async def tts(
    payload: dict = Body(...)
):
    """
    Convert assistant text → speech using Sarvam Bulbul.
    Input JSON:
    - text: text to synthesize
    - language: short code (default ml)
    - voice: 'default' or a specific mapping
    Output: binary audio stream (audio/mpeg)
    """
    text = payload.get("text")
    language = payload.get("language", "en")
    voice = payload.get("voice", "default")
    session_id = payload.get("session_id")
    
    logger.info(f"TTS request received: text='{text}', language={language}, voice={voice}, session_id={session_id}")
    
    if not text:
        logger.error("TTS: No text provided")
        raise HTTPException(status_code=400, detail="text is required")
    
    try:
        sarvam = SarvamService()
        logger.info("TTS: SarvamService initialized")
    except Exception as e:
        logger.error(f"TTS: Sarvam init failed: {e}")
        raise HTTPException(status_code=500, detail=f"Sarvam init failed: {e}")
    
    resolved_language = language
    if session_id:
        # Prefer session-level detected language if available
        session_lang = session_service.get_session(session_id).detected_language if session_service.get_session(session_id) else None
        db_lang = store.get_language(session_id)
        resolved_language = session_lang or db_lang or language

    language_code = _lang_to_code(resolved_language)
    speaker = _voice_to_speaker(voice)
    logger.info(f"TTS: Using language_code={language_code}, speaker={speaker}")
    
    try:
        audio_bytes = await sarvam.text_to_speech(
            text=text, 
            language_code=language_code, 
            speaker=speaker
        )
        logger.info(f"TTS: Audio generated, size={len(audio_bytes)} bytes")
    except Exception as e:
        logger.error(f"TTS: Sarvam API failed: {e}")
        raise HTTPException(status_code=502, detail=f"TTS failed: {e}")
    
    return Response(content=audio_bytes, media_type="audio/mpeg")