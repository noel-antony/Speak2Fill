# Speak2Fill — Voice‑First AI Assistant for Filling Paper Forms

Speak2Fill helps people who struggle with reading/writing (illiteracy, low literacy, or language barriers) correctly fill essential paper forms—bank challans, government applications, hospital forms, college documents—independently and with dignity.

Users take a photo of a paper form, then the system guides them step‑by‑step (voice-first, in their native language) on what to write and *where to write it*.

## Why this matters

Millions of people rely on third parties to fill forms, face frequent mistakes, or are denied services because they can’t confidently read/understand the form. Speak2Fill focuses on accessibility, inclusivity, and reducing dependence—without changing the physical workflow (people still write by hand on paper).

## System overview

**Frontend (Flutter: Android / iOS / Web)**
- Captures or uploads a form image
- Talks to the backend via JSON APIs
- Renders “whiteboard guidance” on top of the form image (canvas overlay)
- Speaks/plays back assistant guidance in the user’s language

**Backend (Python FastAPI)**
- Receives the form image
- Runs PaddleOCR (CPU) to extract text + bounding boxes
- Infers likely “field labels” (best‑effort heuristic in MVP)
- Stores extracted structure in an in‑memory session (dictionary)
- Produces “whiteboard actions” that the frontend can render

**AI reasoning layer (Gemini — planned, mocked for now)**
- Maintains conversation context
- Decides what information to ask next
- Decides which form field should be filled next

> Hackathon note: LLM logic is intentionally mocked/simplified in the current backend to keep the system fast, cheap, and deployable on CPU.

## Repository layout

- `backend/` — FastAPI + PaddleOCR backend
- `frontend/` — Flutter app (not scaffolded yet in this repo)

## Backend APIs (current)

### `GET /health`
Returns:
```json
{ "status": "ok" }
```

### `POST /upload-form`
**Input:** multipart form upload
- `file`: image (`image/png`, `image/jpeg`, ...)

**Behavior:**
- Runs PaddleOCR
- Extracts text + bounding boxes
- Infers field-like labels (heuristic)
- Creates a new in-memory session

**Output:**
```json
{
  "session_id": "string",
  "fields": [
    { "label": "Name", "text": "", "bbox": [10, 20, 200, 60] }
  ]
}
```

### `POST /chat`
**Input:**
```json
{ "session_id": "string", "user_message": "string" }
```

**Behavior (MVP):**
- Loads session
- Picks the “current field”
- Returns a mocked assistant message
- Returns an optional “whiteboard action” to guide handwriting

**Output:**
```json
{
  "reply_text": "Please fill Name in the highlighted box.",
  "action": {
    "type": "DRAW_GUIDE",
    "text": "RAVI KUMAR",
    "bbox": [10, 20, 200, 60]
  }
}
```

## Running the backend

### 1) Install dependencies

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2) Start the server

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 3) Quick smoke test

```bash
curl http://127.0.0.1:8000/health
```

## Running backend tests

The backend includes pytest tests that verify the endpoints behave correctly. OCR is mocked in tests so they run fast and deterministically.

```bash
cd backend
python -m pytest
```

## Configuration

The backend is designed to be minimal and stateless over HTTP. Sessions are stored in RAM (dictionary), so restarting the process clears sessions.

Optional environment variables:
- `DISABLE_MODEL_SOURCE_CHECK=True` — skips Paddle model source connectivity checks if they slow down startup.

See `.env.example` for a small template.

## Deployment notes (CPU-friendly)

- PaddleOCR runs in CPU mode.
- First OCR call may download model weights.
- For Hugging Face Spaces (CPU), prefer keeping the container/process warm and caching model downloads between restarts when possible.

## Roadmap (next)

- Integrate Gemini for multilingual conversational flow
- Improve field detection heuristics (key-value association, layout grouping)
- Add support for multiple languages (OCR language models + speech)
- Improve UI guidance actions (multiple guide steps, confirmations)

