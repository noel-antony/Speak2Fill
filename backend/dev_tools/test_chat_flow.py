#!/usr/bin/env python3
"""
Temporary developer tool to test the /chat endpoint interactively.

Usage:
  python backend/dev_tools/test_chat_flow.py --session-id <uuid>

Notes:
- Assumes a session already exists (created via /analyze-form).
- No FastAPI routes; this is a pure client.
- Prints assistant_text and action payloads per response.
- Recognizes confirmation words like "done" and "next".
"""

import argparse
import sys
import requests
import json
from typing import Any, Dict

BASE_URL = "http://localhost:8000"
CHAT_URL = f"{BASE_URL}/chat"

BANNER = """
============================================================
Speak2Fill Chat Flow Tester (Gemini Live)
============================================================
Type your messages and press Enter.
Special commands: done, next, quit/exit
------------------------------------------------------------
"""


def print_response(resp_json: Dict[str, Any]) -> None:
    print("\n[ASSISTANT]")
    assistant_text = resp_json.get("assistant_text", "(no assistant_text)")
    print(assistant_text)

    action = resp_json.get("action")
    if action:
        print("\n[ACTION]")
        print(json.dumps(action, indent=2))


def send_chat(session_id: str, user_message: str) -> Dict[str, Any]:
    payload = {
        "session_id": session_id,
        "user_message": user_message,
    }
    try:
        r = requests.post(CHAT_URL, json=payload, timeout=60)
        r.raise_for_status()
        return r.json()
    except requests.HTTPError as e:
        print(f"[HTTP ERROR] {e} -> {getattr(e, 'response', None)}")
        try:
            return r.json()
        except Exception:
            return {"error": str(e), "status_code": r.status_code, "text": r.text}
    except Exception as e:
        return {"error": str(e)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Interactive tester for /chat endpoint")
    parser.add_argument("--session-id", required=True, help="Existing session_id from /analyze-form")
    parser.add_argument("--no-init", action="store_true", help="Skip initial empty message ping")
    args = parser.parse_args()

    print(BANNER)
    print(f"Backend: {BASE_URL}")
    print(f"Session ID: {args.session_id}")

    # Initial ping as per app flow (empty user_message)
    if not args.no_init:
        print("\n[INIT] Sending initial empty message...")
        init_resp = send_chat(args.session_id, "")
        print_response(init_resp)

    # Interactive loop
    while True:
        try:
            user_input = input("\n[YOU] > ").strip()
        except EOFError:
            print("\n[INFO] EOF received. Exiting.")
            break
        except KeyboardInterrupt:
            print("\n[INFO] Interrupted. Exiting.")
            break

        if not user_input:
            # Allow empty messages to nudge assistant/state
            pass
        else:
            low = user_input.lower()
            if low in {"quit", "exit"}:
                print("[INFO] Goodbye.")
                break
            # Map confirmation shortcuts
            if low in {"done", "next"}:
                user_input = low

        resp = send_chat(args.session_id, user_input)
        print_response(resp)

    return 0


if __name__ == "__main__":
    sys.exit(main())
