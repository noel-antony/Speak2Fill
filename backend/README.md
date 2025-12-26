# Speak2Fill Backend (FastAPI + PaddleOCR)

FastAPI backend that:
- Accepts a scanned form image
- Runs PaddleOCR (CPU)
- Extracts text + bounding boxes
- Infers likely form fields via simple heuristics
- Creates an in-memory session per upload
- Provides a mocked chat endpoint to guide form filling

## Requirements
- Python 3.10+

## Install

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## API

### GET /health
Returns:
```json
{ "status": "ok" }
```

### POST /upload-form
Multipart form-data:
- `file`: image

Returns:
```json
{
  "session_id": "...",
  "fields": [
    { "label": "Name", "text": "", "bbox": [0,0,0,0] }
  ]
}
```

### POST /chat
Body:
```json
{ "session_id": "...", "user_message": "RAVI KUMAR" }
```

Returns:
```json
{
  "reply_text": "Please fill Name in the highlighted box.",
  "action": { "type": "DRAW_GUIDE", "text": "RAVI KUMAR", "bbox": [0,0,0,0] }
}
```

## Notes
- Sessions are stored in RAM (dictionary). Restarting the server clears sessions.
- PaddleOCR may download model weights on first run.
- Field detection is a heuristic (hackathon MVP) and will improve later.
