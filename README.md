# Speak2Fill — AI-Powered Voice Form Filling

Speak2Fill is an innovative application that enables users to fill paper forms using voice commands. It leverages AI to analyze form images, extract fields, and guide users through filling them via speech-to-text and text-to-speech in multiple languages.

## Features

- **Form Analysis**: Upload a form image and automatically detect fillable fields using OCR and AI.
- **Voice Guidance**: Step-by-step voice instructions in native languages (Malayalam, English, Hindi, etc.).
- **Speech-to-Text**: Convert user speech to text for form filling.
- **Text-to-Speech**: Provide audio feedback and instructions.
- **Multi-Language Support**: Supports Malayalam, English, Hindi, Tamil, Telugu.
- **Cross-Platform**: Works on web, Android, and iOS via Flutter.

## Architecture

### Frontend (Flutter)
- **Platform**: Web, Android, iOS
- **Key Components**:
  - `SttService`: Handles speech-to-text recording and API calls.
  - `TtsService`: Manages text-to-speech playback.
  - Screens: Form upload, analysis, guided filling.
- **Libraries**: `record` for audio recording, `audioplayers` for playback, `http` for API communication.

### Backend (FastAPI)
- **Platform**: Python with FastAPI
- **Key Routes**:
  - `/health`: Health check.
  - `/analyze-form`: Analyze uploaded form image, extract fields.
  - `/chat`: Handle conversational form filling logic.
  - `/stt`: Speech-to-text conversion.
  - `/tts`: Text-to-speech synthesis.
- **Services**:
  - `SarvamService`: Integrates Sarvam AI for STT, TTS, and LLM.
  - `GeminiService`: Uses Google Gemini for form field analysis.
  - `SessionService`: Manages user sessions and form state.
  - `StorageService`: In-memory storage for sessions and logs.

### AI Services
- **Sarvam AI**: Provides STT (Saarika), TTS (Bulbul), and LLM (Sarvam-M) capabilities.
- **Google Gemini**: Analyzes OCR data to identify form fields.

## Prerequisites

- Python 3.10+
- Flutter 3.10+
- API Keys: `SARVAM_API_KEY`, `GEMINI_API_KEY`

## Setup

### Backend

1. Navigate to the backend directory:
   ```
   cd backend
   ```

2. Create a virtual environment:
   ```
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

4. Set environment variables:
   Create a `.env` file with:
   ```
   SARVAM_API_KEY=your_sarvam_api_key
   GEMINI_API_KEY=your_gemini_api_key
   ```

5. Run the server:
   ```
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

### Frontend

1. Navigate to the frontend directory:
   ```
   cd frontend
   ```

2. Install dependencies:
   ```
   flutter pub get
   ```

3. Run the app:
   - For web: `flutter run -d chrome --web-port 5000`
   - For Android/iOS: `flutter run`

## Usage

1. **Upload Form**: Take a photo or upload an image of the paper form.
2. **Analyze**: The backend processes the image, extracts text via OCR, and identifies fields using Gemini.
3. **Guided Filling**: The app guides the user voice-by-voice:
   - Asks for field values via TTS.
   - Records user speech via STT.
   - Extracts values using Sarvam LLM.
   - Provides writing instructions.
4. **Completion**: User fills the form manually based on guidance.

## API Endpoints

### Health
- `GET /health`
- Response: `{"status": "ok"}`

### Analyze Form
- `POST /analyze-form`
- Input: Multipart form with `file` (image).
- Response: Form fields with labels, bboxes, etc.

### Chat
- `POST /chat`
- Input: JSON with session_id, event, user_text.
- Response: Assistant text and actions.

### Speech-to-Text
- `POST /stt`
- Input: Multipart with `audio` (wav) and `language`.
- Response: `{"transcript": "...", "language": "..."}`

### Text-to-Speech
- `POST /tts`
- Input: JSON with `text`, `language`, `voice`.
- Response: Audio binary (MPEG).

## Development

- **Testing**: Run `pytest` in backend.
- **Linting**: Use `flutter analyze` for frontend.
- **Build**: `flutter build web` for production.

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Commit changes.
4. Push and create a PR.

## License

MIT License.

## Acknowledgments

- Sarvam AI for multilingual AI services.
- Google Gemini for advanced analysis.
- Flutter and FastAPI communities.

