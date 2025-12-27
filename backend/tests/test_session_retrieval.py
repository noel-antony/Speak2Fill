def test_get_session_returns_full_response(client, sample_image_bytes, mock_remote_ocr):
    """Test that we can retrieve the full analyze-form response by session_id."""
    # Create a session first
    resp = client.post(
        "/analyze-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    assert resp.status_code == 200
    session_id = resp.json()["session_id"]

    # Retrieve the session
    get_resp = client.get(f"/session/{session_id}")
    assert get_resp.status_code == 200

    body = get_resp.json()
    assert body["session_id"] == session_id
    assert "image_width" in body
    assert "image_height" in body
    assert "ocr_items" in body
    assert "fields" in body
    assert len(body["fields"]) >= 1


def test_get_session_image_returns_image(client, sample_image_bytes, mock_remote_ocr):
    """Test that we can retrieve the original uploaded image by session_id."""
    # Create a session first
    resp = client.post(
        "/analyze-form",
        files={"file": ("form.png", sample_image_bytes, "image/png")},
    )
    assert resp.status_code == 200
    session_id = resp.json()["session_id"]

    # Retrieve the image
    img_resp = client.get(f"/session/{session_id}/image")
    assert img_resp.status_code == 200
    assert img_resp.headers["content-type"] == "image/jpeg"
    assert len(img_resp.content) > 0


def test_get_session_not_found(client):
    """Test that retrieving a non-existent session returns 404."""
    resp = client.get("/session/does-not-exist")
    assert resp.status_code == 404


def test_get_session_image_not_found(client):
    """Test that retrieving image for non-existent session returns 404."""
    resp = client.get("/session/does-not-exist/image")
    assert resp.status_code == 404
