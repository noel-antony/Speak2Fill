import pytest


def test_analyze_form_rejects_non_image(client):
    resp = client.post(
        "/analyze-form",
        files={"file": ("x.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 400


def test_analyze_form_creates_session_and_fields(client, sample_image_bytes, mock_remote_ocr):
    resp = client.post(
        "/analyze-form",
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

    first_field = fields[0]
    assert first_field["label"] == "Name"
    assert first_field["text"] == ""
    assert isinstance(first_field["bbox"], list)
    assert len(first_field["bbox"]) == 4
