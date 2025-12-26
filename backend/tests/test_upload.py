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

    fields = body.get("fields")
    assert isinstance(fields, list)
    assert len(fields) >= 1

    f0 = fields[0]
    assert f0["label"] == "Name"
    assert f0["text"] == ""
    assert isinstance(f0["bbox"], list)
    assert len(f0["bbox"]) == 4
