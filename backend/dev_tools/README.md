# Speak2Fill Backend Dev Tools

Interactive testing tools for the Speak2Fill backend.

## test_chat_flow.py

Interactive CLI tester for the `/chat` endpoint with Gemini Live.

### Prerequisites

- Backend running: `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- A session already created via `/analyze-form` (you need a `session_id`)

### Usage

```bash
cd backend
python dev_tools/test_chat_flow.py --session-id <your-session-id>
```

### Example Workflow

1. **Upload a form image via frontend** (or curl) to get a session_id:
   ```bash
   curl -X POST "http://localhost:8000/analyze-form" \
     -F file="@/path/to/form.jpg"
   ```
   Copy the `session_id` from response.

2. **Run the tester:**
   ```bash
   python dev_tools/test_chat_flow.py --session-id 550e8400-e29b-41d4-a716-446655440000
   ```

3. **Interact:**
   - Type your message and press Enter
   - Type `done` or `next` for confirmation
   - Type `quit` or `exit` to stop
   - Leave blank and press Enter to nudge the assistant
   - Type `--no-init` flag to skip initial empty message

### Output

Each response shows:
- `[ASSISTANT]` — The assistant's text response
- `[ACTION]` (if present) — JSON payload with action details (e.g., `DRAW_GUIDE`)

### Example

```
[INIT] Sending initial empty message...
[ASSISTANT]
Please enter your name in the field labeled "Name".

[ACTION]
{
  "type": "DRAW_GUIDE",
  "field_label": "Name",
  "text_to_write": "",
  "bbox": [90, 8, 300, 34],
  "image_width": 2752,
  "image_height": 1536
}

[YOU] > John Doe
[ASSISTANT]
Great! Moving to the next field...
```

### Debugging

- If you get `Unsupported MIME type`, ensure `OCR_SERVICE_URL` and `GEMINI_API_KEY` are set
- If responses are slow, the backend is waiting on external services (OCR, Gemini)
- Use `--no-init` if you want to manually control the first message

