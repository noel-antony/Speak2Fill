---
title: Speak2Fill Backend
sdk: docker
app_port: 7860
---

# Speak2Fill Backend (FastAPI)

FastAPI backend that:
- Accepts a scanned form image
- Calls a remote PaddleOCR-VL service for OCR (configurable via `OCR_SERVICE_URL`)
- Sends OCR results to Gemini to identify fillable fields
- Creates a session per upload (stored in SQLite)
- Provides a chat endpoint to guide form filling

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

### POST /analyze-form
Multipart form-data:
- `file`: image

Returns:
```json
{
  "session_id": "...",
  "ocr_items": [{ "text": "Name", "bbox": [0,0,0,0], "score": 0.99 }],
  "fields": [{ "label": "Name", "text": "", "bbox": [0,0,0,0] }]
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

## Test with curl

Set your base URL (adjust the port if needed):

```bash
export BASE_URL="http://127.0.0.1:8000"
```

Health:

```bash
curl -sS "$BASE_URL/health" | cat
```

Upload an image (this repo has sample images in `random/`):

```bash
# If you're running this from the repo root (Speak2Fill/):
curl -sS -X POST "$BASE_URL/analyze-form" \
  -F "file=@./random/form1.jpg" | cat

# If you're running this from backend/:
# curl -sS -X POST "$BASE_URL/analyze-form" \
#   -F "file=@../random/form1.jpg" | cat
```

Grab the `session_id` from the upload response and chat:

```bash
SESSION_ID="<paste session_id here>"

curl -sS -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{"session_id":"'"$SESSION_ID"'","user_message":"RAVI KUMAR"}' | cat
```

## Notes
- Sessions are stored in SQLite (single file). Restarting the server keeps sessions as long as the DB file remains.
- PaddleOCR-VL may download model weights on first run.
- Field detection is a heuristic (hackathon MVP) and will improve later.

## Database

This backend uses a small SQLite database to store:

- `session_id` created by `POST /analyze-form`
- OCR output (`ocr_items`) and inferred `fields`
- Chat messages and the current field index

How `/chat` retrieves OCR:

- `/analyze-form` saves OCR + fields into SQLite under a new `session_id`.
- `/chat` receives `session_id`, loads the stored fields from SQLite, and decides which field to guide next.

Configuration:

- `SPEAK2FILL_DB_PATH` (default: `data/speak2fill.db`)

Hugging Face Spaces note: the filesystem may be ephemeral unless you enable persistent storage. If you need sessions to survive restarts, store the DB on a persistent volume.

## OCR Configuration

This backend calls a remote PaddleOCR-VL service.

Environment variables:

- `OCR_SERVICE_URL` (or `PADDLE_OCR_SERVICE_URL`): base URL of the OCR service. Required.

The backend never exposes this URL in responses or logs; configure it through environment variables.

## Deploy to Hugging Face Spaces (Docker)

You can host the **entire `backend/` folder** as a Space.

1) Create a new Space
- On Hugging Face: **New Space** → choose **SDK: Docker**.

2) Put backend files at the Space repo root
- Copy the contents of this `backend/` folder into your Space repository root.
- Make sure these are present at the root of the Space repo:
  - `app/`
  - `requirements.txt`
  - `Dockerfile`
  - `README.md` (this file)

3) Push to the Space repo

4) The Space will build and start Uvicorn automatically
- The API will be served on port **7860** (required by Spaces).

Local Docker sanity-check (optional):

```bash
docker build -t speak2fill-backend .
docker run --rm -p 7860:7860 speak2fill-backend
```

Then open:
- `http://localhost:7860/health`
