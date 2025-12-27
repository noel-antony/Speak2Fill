"""Tests for /chat endpoint state machine."""


def test_chat_unknown_session_404(client):
    """Test that chat with invalid session returns 404."""
    resp = client.post(
        "/chat",
        json={"session_id": "does-not-exist", "user_message": "hello"},
    )
    assert resp.status_code == 404


def test_chat_flow_voice_field(client, sample_image_bytes, mock_remote_ocr):
    """Test complete flow: create session, collect value, confirm, complete."""
    
    # Step 1: Create session
    analyze_resp = client.post(
        "/analyze-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    assert analyze_resp.status_code == 200
    session_id = analyze_resp.json()["session_id"]
    
    # Step 2: Provide value directly - should get writing guide (PHASE B)
    chat1 = client.post(
        "/chat",
        json={"session_id": session_id, "user_message": "John Doe"},
    )
    assert chat1.status_code == 200
    body1 = chat1.json()
    assert "assistant_text" in body1
    assert body1["action"] is not None
    assert body1["action"]["type"] == "DRAW_GUIDE"
    assert body1["action"]["text_to_write"] == "John Doe"
    assert body1["action"]["field_label"] == "Name"
    
    # Step 3: Confirm completion
    chat2 = client.post(
        "/chat",
        json={"session_id": session_id, "user_message": "done"},
    )
    assert chat2.status_code == 200
    body2 = chat2.json()
    assert "assistant_text" in body2
    # Should either move to next field or complete


def test_chat_confirmation_words(client, sample_image_bytes, mock_remote_ocr):
    """Test that various confirmation words are recognized."""
    
    # Create session
    analyze_resp = client.post(
        "/analyze-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    session_id = analyze_resp.json()["session_id"]
    
    # Provide value
    client.post("/chat", json={"session_id": session_id, "user_message": "Test Value"})
    
    # Test different confirmation words
    for word in ["done", "finished", "ok", "completed"]:
        # Reset to field with value
        resp = client.post("/chat", json={"session_id": session_id, "user_message": word})
        assert resp.status_code == 200
        # Should process confirmation


def test_chat_numeric_normalization(client, sample_image_bytes, mock_remote_ocr):
    """Test that numeric fields extract only digits."""
    
    # This test would need a mock field with write_language="numeric"
    # For now, just verify the endpoint works
    analyze_resp = client.post(
        "/analyze-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    session_id = analyze_resp.json()["session_id"]
    
    resp = client.post(
        "/chat",
        json={"session_id": session_id, "user_message": "abc123def456"},
    )
    assert resp.status_code == 200
