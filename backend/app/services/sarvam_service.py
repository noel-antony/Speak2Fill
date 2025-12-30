"""
Sarvam AI API Service
Handles STT (Saarika), LLM (Sarvam-M), and TTS (Bulbul)
"""
import io
import os
import base64
from sarvamai import SarvamAI


class SarvamService:
    def __init__(self):
        self.api_key = os.getenv("SARVAM_API_KEY")
        if not self.api_key:
            raise ValueError("SARVAM_API_KEY not found in environment")
        
        self.client = SarvamAI(api_subscription_key=self.api_key)
    
    async def speech_to_text(self, audio_data: bytes, language_code: str = "ml-IN") -> str:
        """
        Convert speech to text using Sarvam Saarika (NO translation)
        
        Args:
            audio_data: Audio file bytes (wav, mp3, etc.)
            language_code: Language code (hi-IN, ta-IN, te-IN, etc.)
        
        Returns:
            Transcribed text in original language
        """
        import asyncio
        
        audio_file = io.BytesIO(audio_data)
        audio_file.name = "audio.wav"  # Add a filename attribute
        
        try:
            response = await asyncio.to_thread(
                self.client.speech_to_text.transcribe,
                file=audio_file,
                model="saarika:v2.5",
                language_code=language_code
            )
            return response.transcript
        except Exception as e:
            raise RuntimeError(f"Sarvam STT failed: {e}") from e
    
    async def extract_field_value(
        self, 
        field_label: str, 
        user_text: str, 
        write_language: str
    ) -> str:
        """
        Use Sarvam-M LLM to extract field value from user speech
        
        Args:
            field_label: The form field label
            user_text: What the user said
            write_language: Expected language for the field value
        
        Returns:
            Extracted value only
        """
        import asyncio
        
        prompt = f"""Extract the value for this form field.
Field label: {field_label}
Expected language: {write_language}
User text: {user_text}

Output ONLY the extracted value. Nothing else."""

        messages = [
            {
                "role": "system",
                "content": "You are a precise form field extractor. Output only the extracted value."
            },
            {
                "role": "user",
                "content": prompt
            }
        ]
        
        try:
            response = await asyncio.to_thread(
                self.client.chat.completions,
                messages=messages,
                temperature=0.1
            )
            extracted = response.choices[0].message.content.strip()
            return extracted
        except Exception as e:
            raise RuntimeError(f"Sarvam extract failed: {e}") from e
    
    async def generate_instruction_text(
        self, 
        field_label: str, 
        extracted_value: str,
        target_language: str = "ml"
    ) -> str:
        """
        Generate instruction text in user's language
        
        Args:
            field_label: Field label
            extracted_value: The value to write
            target_language: Language code for instruction
        
        Returns:
            Instruction text
        """
        import asyncio
        
        prompt = f"""Generate a short instruction in {target_language} telling the user to write the value in the form field.

Field: {field_label}
Value to write: {extracted_value}

Output format: "Please write [value] in the [field] box."
Keep it brief and natural in {target_language}."""

        messages = [
            {
                "role": "system",
                "content": "You are a helpful assistant. Generate brief, natural instructions."
            },
            {
                "role": "user",
                "content": prompt
            }
        ]
        
        try:
            response = await asyncio.to_thread(
                self.client.chat.completions,
                messages=messages,
                temperature=0.3
            )
            instruction = response.choices[0].message.content.strip()
            return instruction
        except Exception as e:
            raise RuntimeError(f"Sarvam instruction failed: {e}") from e
    
    async def text_to_speech(
        self, 
        text: str, 
        language_code: str = "ml-IN",
        speaker: str = "anushka"
    ) -> bytes:
        """
        Convert text to speech using Sarvam Bulbul
        
        Args:
            text: Text to synthesize
            language_code: Language code
            speaker: Voice speaker name
        
        Returns:
            Audio bytes (base64 decoded)
        """
        import asyncio
        
        try:
            response = await asyncio.to_thread(
                self.client.text_to_speech.convert,
                text=text,
                target_language_code=language_code,
                speaker=speaker,
                enable_preprocessing=True
            )
            # Assuming response.audios is a list of base64 strings
            audio_base64 = response.audios[0]
            audio_bytes = base64.b64decode(audio_base64)
            return audio_bytes
        except Exception as e:
            raise RuntimeError(f"Sarvam TTS failed: {e}") from e