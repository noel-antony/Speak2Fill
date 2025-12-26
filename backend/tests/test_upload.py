import os
from pathlib import Path

import pytest


def test_upload_form_rejects_non_image(client):
    resp = client.post(
        "/upload-form",
        files={"file": ("x.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 400


def test_upload_form_creates_session_and_fields(client, sample_image_bytes, mock_ocr):
    resp = client.post(
        "/upload-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body.get("session_id"), str)
    assert body["session_id"]

    ocr_items = body.get("ocr_items")
    assert isinstance(ocr_items, list)
    assert len(ocr_items) >= 1
    assert "text" in ocr_items[0]
    assert "bbox" in ocr_items[0]
    assert "score" in ocr_items[0]

    fields = body.get("fields")
    assert isinstance(fields, list)
    assert len(fields) >= 1

    f0 = fields[0]
    assert f0["label"] == "Name"
    assert f0["text"] == ""
    assert isinstance(f0["bbox"], list)
    assert len(f0["bbox"]) == 4


@pytest.mark.integration
def test_upload_form_live_server_real_image():
    """Integration test against a running server.

    Opt-in only:
    - Set RUN_LIVE_TESTS=1
    - Optionally set SPEAK2FILL_BASE_URL (default http://127.0.0.1:8000)
    """

    if os.getenv("RUN_LIVE_TESTS") != "1":
        pytest.skip("Set RUN_LIVE_TESTS=1 to run live server tests")

    base_url = (os.getenv("SPEAK2FILL_BASE_URL") or "http://127.0.0.1:8000").rstrip("/")

    repo_root = Path(__file__).resolve().parents[2]
    image_path = repo_root / "random" / "form1.jpg"
    assert image_path.exists(), f"Missing test image: {image_path}"

    import requests

    with image_path.open("rb") as f:
        resp = requests.post(
            f"{base_url}/upload-form",
            files={"file": (image_path.name, f, "image/jpeg")},
            timeout=120,
        )

    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert isinstance(body.get("session_id"), str)
    assert body["session_id"]

    ocr_items = body.get("ocr_items")
    assert isinstance(ocr_items, list)
    assert len(ocr_items) > 0

    first = ocr_items[0]
    assert isinstance(first.get("text"), str)
    assert first["text"].strip()
    assert isinstance(first.get("bbox"), list)
    assert len(first["bbox"]) == 4
    assert isinstance(first.get("score"), (int, float))
    assert float(first["score"]) >= 0.0

    fields = body.get("fields")
    assert isinstance(fields, list)

