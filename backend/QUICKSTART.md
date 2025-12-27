# Speak2Fill Backend - Quick Start

## What's Been Built

### 1. `/analyze-form` Endpoint
- **Purpose**: Analyze OCR data once per session to identify fillable fields
- **Flow**: OCR data → Filter → Gemini API → Validate → Store in DB
- **Location**: [app/routes/analyze.py](app/routes/analyze.py)

### 2. `/chat` Endpoint (Rewritten)
- **Purpose**: Deterministic form-filling conversation flow
- **Flow**: Load state → Interpret message → Update state → Return next action
- **Logic**: 
  - User input → Store value
  - User says "done" → Advance to next field
  - Backend controls everything
- **Location**: [app/routes/chat.py](app/routes/chat.py)

### 3. Gemini Service
- **Purpose**: Call Gemini API for field analysis
- **Features**: 
  - JSON-only responses
  - Error handling
  - Field validation
- **Location**: [app/services/gemini_service.py](app/services/gemini_service.py)

## How to Test

### Option 1: Automated Test (Recommended)
```bash
cd backend

# Start server in terminal 1
uvicorn app.main:app --reload

# Run tests in terminal 2
python test_endpoints.py
```

### Option 2: Manual with curl
See [TESTING.md](TESTING.md) for detailed curl examples.

## API Flow

```
1. Upload form image
   POST /upload-form
   ↓
   Returns: session_id

2. Analyze form fields
   POST /analyze-form
   Body: {"session_id": "..."}
   ↓
   Gemini identifies fields
   Returns: fields_count

3. Start chat flow
   POST /chat
   Body: {"session_id": "...", "user_message": "start"}
   ↓
   Returns: First field instruction + DRAW_GUIDE

4. Provide input
   POST /chat
   Body: {"session_id": "...", "user_message": "John Doe"}
   ↓
   Returns: Confirmation + DRAW_GUIDE with user text

5. Confirm completion
   POST /chat
   Body: {"session_id": "...", "user_message": "done"}
   ↓
   Advances to next field
   Returns: Next field instruction + DRAW_GUIDE

6. Repeat steps 4-5 until all fields complete
   ↓
   Returns: "All fields completed" + action=null
```

## Environment Setup

The `.env` file contains:
```bash
GEMINI_API_KEY=AIzaSyAEud9xjZYVTg-f8W5JULQzASIx3GpVMHo
```

Make sure to load it:
```bash
export $(cat ../.env | xargs)  # Linux/Mac
# or
set -a; source ../.env; set +a  # Alternative
```

## Database Schema

```sql
sessions:
  - session_id (PK)
  - ocr_items_json (raw OCR data)
  - fields_json (analyzed fields with bbox, label, etc.)
  - current_field_index (which field user is on)
  - filled_fields_json (map of label -> user input)
  - language (en, ml)
  - image_width, image_height
```

## Key Features

✅ **Deterministic**: Same input = same output  
✅ **Debuggable**: All state in SQLite  
✅ **Simple**: Backend controls flow, not LLM  
✅ **Safe**: Validates Gemini responses  
✅ **Efficient**: Runs Gemini once per session  

## Files Changed

- ✨ NEW: `app/services/gemini_service.py`
- ✨ NEW: `app/routes/analyze.py`
- ✨ NEW: `test_endpoints.py`
- ✨ NEW: `TESTING.md`
- 🔄 UPDATED: `app/routes/chat.py` (complete rewrite)
- 🔄 UPDATED: `app/services/storage_service.py` (new DB schema)
- 🔄 UPDATED: `app/schemas/models.py` (new models)
- 🔄 UPDATED: `app/main.py` (added analyze router)
- 🔄 UPDATED: `.env.example` (Gemini key)
- ❌ REMOVED: `app/services/llm_service.py` (obsolete)

## Next Steps

1. **Test locally**: Run `python test_endpoints.py`
2. **Test with real forms**: Upload actual form images
3. **Adjust prompts**: Fine-tune Gemini prompts in `gemini_service.py`
4. **Add logging**: Add debug logs to track Gemini responses
5. **Error handling**: Test edge cases (empty forms, bad OCR, etc.)

## Troubleshooting

**"Gemini API error"**: Check API key in `.env`  
**"Session not found"**: Run test script to create mock data  
**"No fields identified"**: Check OCR confidence scores in database  

See [TESTING.md](TESTING.md) for detailed troubleshooting guide.
