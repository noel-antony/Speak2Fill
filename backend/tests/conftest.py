import io
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))


@pytest.fixture()
def app(tmp_path, monkeypatch):
    # Ensure each test run uses an isolated DB file.
    monkeypatch.setenv("SPEAK2FILL_DB_PATH", str(tmp_path / "test.db"))

    from app.main import create_app

    return create_app()


@pytest.fixture()
def client(app):
    return TestClient(app)


@pytest.fixture()
def sample_image_bytes() -> bytes:
    """Generate a tiny in-memory PNG to use for multipart upload tests."""
    img = Image.new("RGB", (300, 120), color=(255, 255, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture(autouse=True)
def ocr_service_url(monkeypatch):
    """Provide a placeholder OCR endpoint for tests."""

    monkeypatch.setenv("OCR_SERVICE_URL", "http://ocr.test.local")
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    return True


@pytest.fixture(autouse=True)
def mock_gemini(monkeypatch):
    """Stub Gemini field analysis to avoid network calls during tests."""

    from app.services import gemini_service

    def _fake_analyze(self, ocr_items, image_width, image_height):
        _ = image_width, image_height
        if not ocr_items:
            return []
        first_bbox = ocr_items[0].get("bbox", [0, 0, 0, 0])
        return [
            {
                "label": "Name",
                "bbox": first_bbox,
                "input_mode": "voice",
                "write_language": "en",
                "text": "",
            }
        ]

    monkeypatch.setattr(gemini_service.GeminiService, "analyze_form_fields", _fake_analyze)
    return True


@pytest.fixture()
def mock_remote_ocr(monkeypatch):
    """Mock remote OCR HTTP call so tests stay fast and offline."""

    from app.routes import analyze as analyze_module

    class _FakeResponse:
        def __init__(self, payload: dict):
            self._payload = payload

        def raise_for_status(self):
            return None

        def json(self):
            return self._payload

    def _fake_post(url, **kwargs):
        _ = url, kwargs
        # Simulate nested PaddleOCR-VL style payload
        payload = [
            {
                "res": {
                    "width": 300,
                    "height": 120,
                    "parsing_res_list": [
                        {
                            "block_label": "text",
                            "block_content": "Name",
                            "block_bbox": [10, 10, 80, 30],
                            "score": 0.99,
                        }
                    ],
                }
            }
        ]
        return _FakeResponse(payload)

    monkeypatch.setattr(analyze_module.requests, "post", _fake_post)
    return True
