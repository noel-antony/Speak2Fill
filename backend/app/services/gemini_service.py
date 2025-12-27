from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import requests


@dataclass
class GeminiService:
    """Service for interacting with Google Gemini API."""

    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY", "")
        if not self.api_key:
            raise ValueError("GEMINI_API_KEY not set in environment")
        # Use gemini-1.5-flash for faster responses, or gemini-1.5-pro for better quality
        self.model_name = "gemini-2.5-flash-lite"
        self.base_url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model_name}:generateContent"

    def analyze_form_fields(
        self, ocr_items: List[Dict[str, Any]], image_width: int, image_height: int
    ) -> List[Dict[str, Any]]:
        """
        Call Gemini API to identify form fields from OCR data.
        Returns list of field dicts with: label, bbox, input_mode, write_language
        """
        # Build prompt with OCR data
        ocr_text_items = []
        for idx, item in enumerate(ocr_items):
            text = item.get("text", "")
            bbox = item.get("bbox", [0, 0, 0, 0])
            score = item.get("score", 0.0)
            ocr_text_items.append(f"{idx}. '{text}' (confidence: {score:.2f}, bbox: {bbox})")

        ocr_summary = "\n".join(ocr_text_items)

        prompt = f"""You are analyzing a scanned form. Based on the OCR text below, identify ALL fillable fields that need user input.

OCR Data (image dimensions: {image_width}x{image_height}):
{ocr_summary}

Rules:
1. EXCLUDE office-only fields (e.g., "For office use only", "Approval stamp")
2. EXCLUDE pre-filled system fields (e.g., form numbers, dates already filled)
3. For each user-fillable field, determine:
   - label: clear field name (e.g., "Name", "Date of Birth", "Address")
   - bbox: bounding box coordinates [x1, y1, x2, y2] where user should write
   - input_mode: "voice" for text fields, "placeholder" for dates/signatures
   - write_language: "en" for English, "ml" for Malayalam/native, "numeric" for numbers

Return ONLY valid JSON array (no markdown, no explanation):
[
  {{
    "label": "Name",
    "bbox": [x1, y1, x2, y2],
    "input_mode": "voice",
    "write_language": "en"
  }},
  ...
]

JSON output:"""

        try:
            response = requests.post(
                f"{self.base_url}?key={self.api_key}",
                headers={"Content-Type": "application/json"},
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {
                        "temperature": 0.1,
                        "maxOutputTokens": 2048,
                    },
                },
                timeout=30,
            )
            response.raise_for_status()

            result = response.json()
            generated_text = result["candidates"][0]["content"]["parts"][0]["text"]

            # Extract JSON from response (handle markdown code blocks)
            json_match = re.search(r"```json\s*(\[.*?\])\s*```", generated_text, re.DOTALL)
            if json_match:
                json_text = json_match.group(1)
            else:
                # Try to find raw JSON array
                json_match = re.search(r"(\[.*\])", generated_text, re.DOTALL)
                if json_match:
                    json_text = json_match.group(1)
                else:
                    json_text = generated_text

            fields = json.loads(json_text)

            # Validate structure
            validated_fields = []
            for field in fields:
                if not isinstance(field, dict):
                    continue
                if "label" not in field or "bbox" not in field:
                    continue
                bbox = field.get("bbox", [])
                if not isinstance(bbox, list) or len(bbox) != 4:
                    continue

                # Set defaults
                field.setdefault("input_mode", "voice")
                field.setdefault("write_language", "en")
                field.setdefault("text", "")

                validated_fields.append(field)

            return validated_fields

        except Exception as e:
            print(f"Gemini API error: {e}")
            return []

    def generate_assistant_message(
        self, field_label: str, language: str = "en", is_confirmation: bool = False
    ) -> str:
        """
        Generate assistant instruction for current field.
        Simple deterministic generation - can use Gemini for multilingual support.
        """
        if is_confirmation:
            prompts = {
                "en": f"Great! Now moving to the next field.",
                "ml": f"നല്ലത്! അടുത്ത ഫീൽഡിലേക്ക് പോകുന്നു.",
            }
        else:
            prompts = {
                "en": f"Please fill in the '{field_label}' field. Say 'done' when you finish writing.",
                "ml": f"'{field_label}' ഫീൽഡ് പൂരിപ്പിക്കുക. എഴുതി കഴിഞ്ഞാൽ 'ചെയ്തു' എന്ന് പറയുക.",
            }

        return prompts.get(language, prompts["en"])


# Singleton instance
gemini_service: Optional[GeminiService] = None


def get_gemini_service() -> GeminiService:
    """Get or create Gemini service instance."""
    global gemini_service
    if gemini_service is None:
        gemini_service = GeminiService()
    return gemini_service
