from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from app.services.sarvam_service import SarvamService
import logging

logger = logging.getLogger(__name__)
router = APIRouter(tags=["stt"])


def _lang_to_code(language: str) -> str:
    """Map short language code to Sarvam locale code."""
    lang = (language or "ml").lower()
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
    language: str = Form("ml")
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
    
    language_code = _lang_to_code(language)
    logger.info(f"STT: Using language_code={language_code}")
    
    try:
        transcript = await sarvam.speech_to_text(content, language_code=language_code)
        logger.info(f"STT: Transcript received: '{transcript}'")
    except Exception as e:
        logger.error(f"STT: Sarvam API failed: {e}")
        raise HTTPException(status_code=502, detail=f"STT failed: {e}")
    
    return {
        "transcript": transcript,
        "language": (language or "ml").lower()
    }