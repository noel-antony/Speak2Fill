from fastapi import APIRouter, HTTPException
from fastapi import Body
from fastapi.responses import Response
from app.services.sarvam_service import SarvamService
import logging

logger = logging.getLogger(__name__)
router = APIRouter(tags=["tts"])


def _lang_to_code(language: str) -> str:
    lang = (language or "ml").lower()
    return {
        "ml": "ml-IN",
        "en": "en-IN",
        "hi": "hi-IN",
        "ta": "ta-IN",
        "te": "te-IN",
    }.get(lang, "ml-IN")


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
    language = payload.get("language", "ml")
    voice = payload.get("voice", "default")
    
    logger.info(f"TTS request received: text='{text}', language={language}, voice={voice}")
    
    if not text:
        logger.error("TTS: No text provided")
        raise HTTPException(status_code=400, detail="text is required")
    
    try:
        sarvam = SarvamService()
        logger.info("TTS: SarvamService initialized")
    except Exception as e:
        logger.error(f"TTS: Sarvam init failed: {e}")
        raise HTTPException(status_code=500, detail=f"Sarvam init failed: {e}")
    
    language_code = _lang_to_code(language)
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