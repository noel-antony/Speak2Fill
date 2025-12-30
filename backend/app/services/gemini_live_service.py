from __future__ import annotations

import os
import uuid
import asyncio
from dataclasses import dataclass
from typing import Optional, Tuple

from app.services.storage_service import store


@dataclass
class GeminiLiveService:
    """Gemini Live API service using Google GenAI SDK.

    - Maintains one Live session handle per Speak2Fill `session_id`.
    - Uses TEXT responses (no audio) for deterministic JSON orchestration.
    - Falls back to a local stub in tests or when disabled.
    """

    model_name: str = os.getenv("GEMINI_LIVE_MODEL", "gemini-2.0-flash-exp")

    def __post_init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY", "")
        self.use_stub = (self.api_key in ("", "test-key")) or (os.getenv("GEMINI_LIVE_STUB") == "1")
        self._client = None
        if not self.use_stub:
            try:
                from google import genai  # type: ignore
                self._genai = genai
                # Instantiate client with API key
                self._client = genai.Client(api_key=self.api_key)
            except Exception as e:
                # If SDK is unavailable, use stub to avoid breaking tests
                self.use_stub = True

    def _normalize(self, text: str, write_language: str) -> str:
        t = (text or "").strip()
        if write_language == "numeric":
            return "".join(ch for ch in t if ch.isdigit())
        return " ".join(t.split())

    async def send_turn(
        self,
        speak_session_id: str,
        system_instruction: str,
        user_message: str,
        field_label: Optional[str] = None,
        write_language: str = "en",
    ) -> Tuple[str, Optional[str], Optional[bytes]]:
        """Send one conversational turn to Gemini Live.

        Returns (assistant_text, final_value or None, audio_bytes or None).
        final_value is derived from user_message normalization, keeping backend control.
        audio_bytes is raw PCM audio data (24kHz, 16-bit) from Live API.
        """
        # Log system + user
        live_handle = store.get_gemini_live_session_id(speak_session_id)
        store.log_message(speak_session_id, "system", f"[live:{live_handle or 'new'}] {system_instruction}")
        store.log_message(speak_session_id, "user", user_message)

        # Local stub path (used in tests/offline)
        if self.use_stub:
            normalized = self._normalize(user_message, write_language)
            if normalized:
                assistant_text = (
                    f"Got it. The value for '{field_label}' is '{normalized}'."
                    if field_label
                    else "Got it."
                )
                store.log_message(speak_session_id, "assistant", assistant_text)
                return assistant_text, normalized, None
            assistant_text = (
                f"Please provide the value for '{field_label}'."
                if field_label
                else "Please provide the required value."
            )
            store.log_message(speak_session_id, "assistant", assistant_text)
            return assistant_text, None, None

        # Real Live API path via google-genai
        assert self._client is not None
        from google.genai import types  # type: ignore

        assistant_text_parts: list[str] = []
        audio_chunks: list[bytes] = []
        new_handle: Optional[str] = None

        config = {
            "response_modalities": ["AUDIO"],
            "system_instruction": system_instruction,
            "output_audio_transcription": {},  # Also get text transcription of audio
        }

        # Include session resumption handle if present
        if live_handle:
            config["session_resumption"] = types.SessionResumptionConfig(handle=live_handle)

        # Try the configured model, then fall back to a known Live-capable model list
        models_to_try = [self.model_name, "gemini-2.5-flash", "gemini-1.5-flash", "gemini-2.0-flash-exp"]
        last_error = None
        for model in models_to_try:
            try:
                async with self._client.aio.live.connect(model=model, config=config) as session:
                    # Send user text as a complete turn
                    await session.send_client_content(
                        turns={"role": "user", "parts": [{"text": user_message}]},
                        turn_complete=True,
                    )

                    async for message in session.receive():
                        # Capture session resumption updates
                        if getattr(message, "session_resumption_update", None):
                            update = message.session_resumption_update
                            if getattr(update, "resumable", False) and getattr(update, "new_handle", None):
                                new_handle = update.new_handle

                        # Collect audio data from model_turn parts
                        if getattr(message, "server_content", None) and message.server_content.model_turn:
                            mt = message.server_content.model_turn
                            for part in getattr(mt, "parts", []):
                                # Try multiple ways to get audio data
                                audio_data = None
                                
                                # Method 1: inline_data.data
                                inline_data = getattr(part, "inline_data", None)
                                if inline_data:
                                    audio_data = getattr(inline_data, "data", None)
                                
                                # Method 2: direct data attribute (for some API versions)
                                if not audio_data:
                                    audio_data = getattr(part, "data", None)
                                
                                if audio_data and isinstance(audio_data, bytes):
                                    audio_chunks.append(audio_data)

                        # Collect text transcription of audio output
                        if getattr(message, "server_content", None) and message.server_content.output_transcription:
                            txt = getattr(message.server_content.output_transcription, "text", None)
                            if isinstance(txt, str) and txt:
                                assistant_text_parts.append(txt)

                        # Stop after generation complete for a single turn
                        if getattr(message, "server_content", None) and getattr(message.server_content, "turn_complete", False):
                            break

                # If we got here, the model worked; set as active and stop trying others
                self.model_name = model
                break
            except Exception as e:
                last_error = e
                continue
        else:
            # No model worked; re-raise last error
            raise last_error

        assistant_text = " ".join(p.strip() for p in assistant_text_parts if p.strip()) or ""
        audio_bytes = b"".join(audio_chunks) if audio_chunks else None
        
        if new_handle:
            store.set_gemini_live_session_id(speak_session_id, new_handle)

        store.log_message(speak_session_id, "assistant", assistant_text or "[audio response]")

        normalized = self._normalize(user_message, write_language)
        final_value = normalized if normalized else None
        return assistant_text or "", final_value, audio_bytes


_gemini_live_service: Optional[GeminiLiveService] = None


def get_gemini_live_service() -> GeminiLiveService:
    global _gemini_live_service
    if _gemini_live_service is None:
        _gemini_live_service = GeminiLiveService()
    return _gemini_live_service
