import io
from typing import List

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app


@pytest.fixture()
def app():
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


class _FakeOcrResult:
    def __init__(self, items: List[dict], fields: list):
        self.items = items
        self.fields = fields


@pytest.fixture()
def mock_ocr(monkeypatch):
    """Mock PaddleOCR execution so tests are fast and deterministic."""

    from app.schemas.models import FormField

    def _fake_run_ocr(*, image_bytes: bytes):
        # Minimal fake OCR output that still matches our schema expectations.
        items = [
            {
                "text": "Name",
                "score": 0.99,
                "bbox": [10, 10, 80, 30],
                "points": [[10, 10], [80, 10], [80, 30], [10, 30]],
            }
        ]
        fields = [FormField(label="Name", text="", bbox=[90, 8, 300, 34])]
        return _FakeOcrResult(items=items, fields=fields)

    from app.services.ocr_service import ocr_service

    monkeypatch.setattr(ocr_service, "run_ocr", _fake_run_ocr)
    return True
