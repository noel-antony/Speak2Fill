# Testing the New Endpoints

## Overview

Two new endpoints have been added:
1. **`/analyze-form`** - Analyzes OCR data using Gemini API to identify fillable fields
2. **`/chat`** - Updated with deterministic flow control for form filling

## Setup

### 1. Install Dependencies
```bash
cd backend
pip install requests  # Already in requirements.txt
```

### 2. Set Environment Variables
The `.env` file should contain your Gemini API key:
```bash
GEMINI_API_KEY=AIzaSyAEud9xjZYVTg-f8W5JULQzASIx3GpVMHo
```

### 3. Start the Server
**Recommended** - Use the provided script that loads environment variables:
```bash
cd backend
./start_server.sh
```

Alternative (manual):
```bash
cd backend
export $(cat ../.env | grep -v '^#' | xargs)  # Load environment
uvicorn app.main:app --reload
```

## Testing with Mock Data

### Quick Test
Run the comprehensive test script that creates mock data and tests both endpoints:

```bash
cd backend
python test_endpoints.py
```

This script will:
1. Create a mock session with sample OCR data in SQLite
2. Test `/analyze-form` to identify fields using Gemini
3. Test `/chat` with a conversation flow:
   - Get first field instruction
   - Provide voice input
   - Confirm completion
   - Move to next field

### Manual Testing with curl

#### 1. Create Mock Session First
Run the test script once to create mock data, or manually insert into SQLite:

```bash
sqlite3 data/speak2fill.db
```

```sql
-- Check existing sessions
SELECT session_id FROM sessions LIMIT 1;
```

Copy a session_id from the output.

#### 2. Test /analyze-form

```bash
SESSION_ID="<your-session-id>"

curl -X POST http://localhost:8000/analyze-form \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION_ID\"}"
```

Expected response:
```json
{
  "session_id": "abc-123...",
  "fields_count": 4,
  "message": "Successfully identified 4 fillable fields"
}
```

#### 3. Test /chat Flow

**Turn 1: Start conversation (get first field)**
```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION_ID\", \"user_message\": \"start\"}"
```

Response example:
```json
{
  "reply_text": "Please fill in the 'Name' field. Say 'done' when you finish writing.",
  "action": {
    "type": "DRAW_GUIDE",
    "text": "Name",
    "bbox": [160, 150, 400, 180]
  }
}
```

**Turn 2: Provide voice input**
```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION_ID\", \"user_message\": \"John Doe\"}"
```

Response:
```json
{
  "reply_text": "Got it: 'John Doe'. Please write it in the 'Name' box and say 'done' when finished.",
  "action": {
    "type": "DRAW_GUIDE",
    "text": "John Doe",
    "bbox": [160, 150, 400, 180]
  }
}
```

**Turn 3: Confirm completion**
```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION_ID\", \"user_message\": \"done\"}"
```

Response (moves to next field):
```json
{
  "reply_text": "Please fill in the 'Date of Birth' field. Say 'done' when you finish writing.",
  "action": {
    "type": "DRAW_GUIDE",
    "text": "Date of Birth",
    "bbox": [210, 200, 350, 230]
  }
}
```

## Testing with Real Form Upload

### 1. Upload a Form Image

```bash
curl -X POST http://localhost:8000/upload-form \
  -F "file=@path/to/your/form.jpg"
```

Save the `session_id` from the response.

### 2. Analyze the Form

```bash
curl -X POST http://localhost:8000/analyze-form \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"<session_id>\"}"
```

### 3. Start Chat Flow

Use the `/chat` endpoint as shown above.

## Database Inspection

Check session state:

```bash
sqlite3 data/speak2fill.db

-- View all sessions
SELECT session_id, filename, current_field_index, language FROM sessions;

-- View fields for a session
SELECT fields_json FROM sessions WHERE session_id = '<session_id>';

-- View filled fields
SELECT filled_fields_json FROM sessions WHERE session_id = '<session_id>';

-- View chat history
SELECT role, content FROM messages WHERE session_id = '<session_id>' ORDER BY ts;
```

## Expected Behavior

### /analyze-form
- **Input**: `session_id` with OCR data
- **Process**: 
  - Filters low confidence OCR items (< 0.5)
  - Calls Gemini API with OCR text
  - Validates returned fields
  - Stores fields in DB with `current_field_index = 0`
- **Output**: Number of fields identified

### /chat
- **Input**: `session_id` + `user_message`
- **Logic**:
  - If message contains confirmation words ("done", "ok", etc.) → advance to next field
  - Otherwise → treat as voice input, store but wait for confirmation
- **Output**: 
  - `reply_text`: Instruction for user
  - `action`: DRAW_GUIDE with bbox and text (or null if form complete)

## Confirmation Words

The following words trigger field advancement:
- English: `done`, `ok`, `next`, `complete`, `finished`, `yes`
- Malayalam: `കഴിഞ്ഞു`, `ചെയ്തു`

## Troubleshooting

### "GEMINI_API_KEY not set" Error
- Make sure `.env` file exists in the parent directory (not in `backend/`)
- Start server using `./start_server.sh` which loads environment variables
- Or manually export: `export GEMINI_API_KEY=your-key-here`

### "404 Not Found" from Gemini API
- The Gemini API model name has changed
- Current code uses `gemini-1.5-flash` (fast) or `gemini-1.5-pro` (better quality)
- Check [app/services/gemini_service.py](app/services/gemini_service.py) line 20 for model name
- Verify your API key has access to these models

### Gemini API Other Errors
- Verify API key is valid and active
- Check network connectivity
- Look at server logs for detailed error messages
- Test API key manually: `curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_KEY"`

### Session Not Found
- Ensure session exists in database
- Check if session_id is correct
- Run test script to create mock data: `python test_endpoints.py`

### No Fields Identified
- Check OCR quality (confidence scores must be >= 0.5)
- Verify image has fillable fields (not just text)
- Look at Gemini API response in server logs
- Try with a clearer image or adjust confidence threshold

### Database Errors (AttributeError, KeyError)
- Delete old database: `rm -f data/speak2fill.db*`
- Restart server to create new schema
- The database will be automatically recreated on first request

## Architecture Notes

### Key Design Decisions:
1. **Backend controls flow** - No LLM decides order or logic
2. **Explicit confirmation** - User must say "done" to advance fields
3. **Deterministic** - Same input always produces same output
4. **Fail-safe** - Validates Gemini output before storing
5. **Simple state** - All state in SQLite, easy to debug

### Files Modified:
- `/app/services/gemini_service.py` - NEW: Gemini API integration
- `/app/services/storage_service.py` - Updated: DB schema + new methods
- `/app/schemas/models.py` - Updated: New models for endpoints
- `/app/routes/analyze.py` - NEW: /analyze-form endpoint
- `/app/routes/chat.py` - REWRITTEN: Deterministic flow logic
- `/app/main.py` - Updated: Include analyze router
- `/.env` - Updated: Added GEMINI_API_KEY

### Files Removed:
- `/app/services/llm_service.py` - Replaced by gemini_service.py
