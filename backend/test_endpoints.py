"""
Test script for /analyze-form and /chat endpoints.
Creates mock data in SQLite if needed.
"""

import json
import os
import sqlite3
import time
from pathlib import Path
from uuid import uuid4

import requests

# Load environment variables from .env file
env_file = Path(__file__).parent.parent / ".env"
if env_file.exists():
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ[key] = value
    print(f"✅ Loaded environment from {env_file}")

# Configuration
BASE_URL = "http://localhost:8000"
DB_PATH = "data/speak2fill.db"


def create_mock_session():
    """Create a mock session with OCR data in SQLite."""
    session_id = str(uuid4())
    created_at = time.time()

    # Mock OCR items for a simple form
    ocr_items = [
        {
            "text": "APPLICATION FORM",
            "score": 0.98,
            "bbox": [100, 50, 400, 100],
        },
        {
            "text": "Name:",
            "score": 0.95,
            "bbox": [50, 150, 150, 180],
        },
        {
            "text": "_________________",
            "score": 0.92,
            "bbox": [160, 150, 400, 180],
        },
        {
            "text": "Date of Birth:",
            "score": 0.94,
            "bbox": [50, 200, 200, 230],
        },
        {
            "text": "__/__/____",
            "score": 0.90,
            "bbox": [210, 200, 350, 230],
        },
        {
            "text": "Address:",
            "score": 0.96,
            "bbox": [50, 250, 150, 280],
        },
        {
            "text": "_________________",
            "score": 0.91,
            "bbox": [160, 250, 400, 280],
        },
        {
            "text": "_________________",
            "score": 0.91,
            "bbox": [160, 290, 400, 320],
        },
        {
            "text": "Phone Number:",
            "score": 0.95,
            "bbox": [50, 350, 200, 380],
        },
        {
            "text": "_________________",
            "score": 0.93,
            "bbox": [210, 350, 400, 380],
        },
        {
            "text": "For Office Use Only",
            "score": 0.89,
            "bbox": [50, 450, 250, 480],
        },
    ]

    # Empty fields initially (will be filled by /analyze-form)
    fields = []

    # Connect to DB
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # Create tables if needed
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            filename TEXT NOT NULL,
            ocr_items_json TEXT NOT NULL,
            fields_json TEXT NOT NULL,
            current_field_index INTEGER NOT NULL DEFAULT 0,
            filled_fields_json TEXT NOT NULL DEFAULT '{}',
            language TEXT NOT NULL DEFAULT 'en',
            image_width INTEGER NOT NULL DEFAULT 0,
            image_height INTEGER NOT NULL DEFAULT 0
        );
        """
    )

    # Insert mock session
    conn.execute(
        """
        INSERT INTO sessions 
        (session_id, created_at, filename, ocr_items_json, fields_json, current_field_index, filled_fields_json, language, image_width, image_height)
        VALUES (?, ?, ?, ?, ?, 0, '{}', 'en', 800, 1000)
        """,
        (
            session_id,
            created_at,
            "mock_form.jpg",
            json.dumps(ocr_items),
            json.dumps(fields),
        ),
    )

    conn.commit()
    conn.close()

    print(f"✅ Created mock session: {session_id}")
    return session_id


def test_analyze_form(session_id):
    """Test the /analyze-form endpoint."""
    print(f"\n🔍 Testing /analyze-form with session_id: {session_id}")

    response = requests.post(
        f"{BASE_URL}/analyze-form",
        json={"session_id": session_id},
        headers={"Content-Type": "application/json"},
    )

    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    if response.status_code == 200:
        print("✅ /analyze-form succeeded")
        return True
    else:
        print("❌ /analyze-form failed")
        return False


def test_chat_flow(session_id):
    """Test the /chat endpoint with a conversation flow."""
    print(f"\n💬 Testing /chat flow with session_id: {session_id}")

    # Test 1: Get first field instruction
    print("\n--- Turn 1: Initial request ---")
    response = requests.post(
        f"{BASE_URL}/chat",
        json={"session_id": session_id, "user_message": "start"},
        headers={"Content-Type": "application/json"},
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    # Test 2: Provide voice input for field
    print("\n--- Turn 2: Provide voice input ---")
    response = requests.post(
        f"{BASE_URL}/chat",
        json={"session_id": session_id, "user_message": "John Doe"},
        headers={"Content-Type": "application/json"},
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    # Test 3: Confirm completion
    print("\n--- Turn 3: Confirm field completion ---")
    response = requests.post(
        f"{BASE_URL}/chat",
        json={"session_id": session_id, "user_message": "done"},
        headers={"Content-Type": "application/json"},
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    # Test 4: Next field input
    print("\n--- Turn 4: Next field input ---")
    response = requests.post(
        f"{BASE_URL}/chat",
        json={"session_id": session_id, "user_message": "01/15/1990"},
        headers={"Content-Type": "application/json"},
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    print("\n✅ Chat flow test complete")


def check_server():
    """Check if the server is running."""
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=2)
        if response.status_code == 200:
            print("✅ Server is running")
            return True
    except Exception as e:
        print(f"❌ Server not reachable: {e}")
        print("\nPlease start the server first:")
        print("  cd backend")
        print("  uvicorn app.main:app --reload")
        return False


def main():
    print("=" * 60)
    print("🧪 Speak2Fill Backend Test Suite")
    print("=" * 60)

    # Check if server is running
    if not check_server():
        return

    # Create mock session
    session_id = create_mock_session()

    # Test analyze-form
    if test_analyze_form(session_id):
        # Test chat flow
        test_chat_flow(session_id)

    print("\n" + "=" * 60)
    print("✅ All tests completed")
    print("=" * 60)


if __name__ == "__main__":
    main()
