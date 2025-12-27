#!/bin/bash
# Quick test script - runs server and tests in one go

set -e

echo "🚀 Speak2Fill Backend - Quick Test"
echo "=================================="
echo ""

# Check if .env exists
if [ ! -f "../.env" ]; then
    echo "⚠️  Creating .env from .env.example..."
    cp ../.env.example ../.env
fi

# Load environment
echo "📦 Loading environment variables..."
export $(cat ../.env | grep -v '^#' | xargs)

# Check if server is running
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "✅ Server is already running"
else
    echo "❌ Server not running. Please start it first:"
    echo ""
    echo "   In a separate terminal, run:"
    echo "   cd backend"
    echo "   uvicorn app.main:app --reload"
    echo ""
    exit 1
fi

echo ""
echo "🧪 Running tests..."
echo ""

python test_endpoints.py

echo ""
echo "✅ Tests complete!"
echo ""
echo "📖 For more details, see:"
echo "   - QUICKSTART.md"
echo "   - TESTING.md"
