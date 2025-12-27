#!/bin/bash
# Start the Speak2Fill backend server with environment variables loaded

cd "$(dirname "$0")"

# Load environment variables from .env file
if [ -f "../.env" ]; then
    echo "📦 Loading environment variables from .env..."
    export $(cat ../.env | grep -v '^#' | xargs)
    echo "✅ Environment loaded"
else
    echo "⚠️  Warning: .env file not found"
fi

# Verify Gemini API key is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "❌ Error: GEMINI_API_KEY not set"
    echo "Please set it in ../.env file"
    exit 1
fi

echo "🚀 Starting Speak2Fill backend server..."
echo "   API Key: ${GEMINI_API_KEY:0:20}..."
echo ""

uvicorn app.main:app --reload
