# Frontend-Backend Integration Summary

## Backend Response Structures

### POST /analyze-form

**Response Model:** `UploadFormResponse`

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "image_width": 2752,
  "image_height": 1536,
  "ocr_items": [
    {
      "text": "Name",
      "bbox": [10, 10, 80, 30],
      "score": 0.99
    }
  ],
  "fields": [
    {
      "field_id": "name_0",
      "label": "Name",
      "bbox": [90, 8, 300, 34],
      "input_mode": "voice",
      "write_language": "en"
    }
  ]
}
```

**Key Fields:**
- `session_id` — UUID for session management
- `image_width`, `image_height` — Original image dimensions
- `fields[].label` — Human-readable field name
- `fields[].bbox` — [x1, y1, x2, y2] in image coordinates

---

### POST /chat

**Response Model:** `ChatResponse`

```json
{
  "assistant_text": "Please write your name in the Name field.",
  "action": {
    "type": "DRAW_GUIDE",
    "field_label": "Name",
    "text_to_write": "",
    "bbox": [90, 8, 300, 34],
    "image_width": 2752,
    "image_height": 1536
  }
}
```

**OR (no action):**
```json
{
  "assistant_text": "Next field coming up...",
  "action": null
}
```

**Key Fields (when action is present):**
- `action.type` — Always `"DRAW_GUIDE"` (for now)
- `action.field_label` — Name of the field
- `action.text_to_write` — Expected text (empty if placeholder)
- `action.bbox` — [x1, y1, x2, y2] where to write
- `action.image_width`, `action.image_height` — For coordinate scaling

---

### GET /session/{session_id}/image

Returns the original uploaded image as `image/jpeg`.

**Usage in Flutter:**
```dart
Image.network(
  'http://localhost:8000/session/$sessionId/image',
  fit: BoxFit.fill,
)
```

---

## How to Run Dev Tools

### 1. Start Backend
```bash
cd backend
export OCR_SERVICE_URL=https://your-ocr-service/
export GEMINI_API_KEY=your-api-key
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2. Upload a Form (Get Session ID)
```bash
curl -X POST "http://localhost:8000/analyze-form" \
  -F file="@/path/to/form.jpg"
```

Copy the `session_id` from response.

### 3. Run Interactive Chat Tester
```bash
cd backend
python dev_tools/test_chat_flow.py --session-id <copied-session-id>
```

Type messages and interact:
- `done` / `next` — Confirmation words
- `quit` / `exit` — Stop testing
- Leave blank → nudge assistant

---

## Frontend Fixes Applied

### 1. **Image Loading in WhiteboardScreen**
- Fetches from `GET /session/{session_id}/image`
- Added error builder with detailed error messages
- Added loading builder with spinner

### 2. **Text Display in Writing Guide**
- If `text_to_write` is empty, shows `(any value)`
- Properly handles both filled and placeholder fields

### 3. **Bbox Extraction**
- Directly from `action.bbox` (NOT `action.payload.bbox`)
- Validates `bbox.length >= 4` before using

### 4. **Debug Logging**
- All responses logged to browser console
- Logs include full action object and extracted bbox

---

## Frontend Console Debug Output

When a user uploads an image and proceeds to chat:

```
[UPLOAD] Uploading image to http://localhost:8000/analyze-form
[Chat Response] {"assistant_text": "...", "action": {...}}
[DRAW_GUIDE action extracted]
  text_to_write: John
  field_label: Name
  bbox: [90, 8, 300, 34]
[converted bbox to doubles: [90.0, 8.0, 300.0, 34.0]]
[Image.network] Loading http://localhost:8000/session/550e8400-.../image
```

**If bbox is empty:** `[bboxList is null or empty!]`  
**If image fails:** `[Image.network error: ...]`

---

## Testing Checklist

- [ ] Backend running with correct env vars
- [ ] Form uploads successfully (check `/analyze-form` response)
- [ ] Chat endpoint returns valid responses
- [ ] Image displays in whiteboard (check network tab for 404s)
- [ ] Bbox is parsed correctly (check console logs)
- [ ] Writing guide shows correct field label and text

