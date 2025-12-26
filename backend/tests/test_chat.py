def test_chat_unknown_session_404(client):
    resp = client.post(
        "/chat",
        json={"session_id": "does-not-exist", "user_message": "RAVI"},
    )
    assert resp.status_code == 404


def test_chat_returns_action_for_current_field(client, sample_image_bytes, mock_ocr):
    # First upload (creates a session with mocked OCR fields)
    up = client.post(
        "/upload-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    assert up.status_code == 200
    session_id = up.json()["session_id"]

    # Then chat
    resp = client.post(
        "/chat",
        json={"session_id": session_id, "user_message": "RAVI KUMAR"},
    )
    assert resp.status_code == 200
    body = resp.json()

    assert "reply_text" in body
    assert isinstance(body["reply_text"], str)
    assert body["reply_text"]

    action = body.get("action")
    assert action is not None
    assert action["type"] == "DRAW_GUIDE"
    assert action["text"] == "RAVI KUMAR"
    assert isinstance(action["bbox"], list)
    assert len(action["bbox"]) == 4
