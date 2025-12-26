from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from uuid import uuid4

from app.schemas.models import FormField


@dataclass
class _MemoryService:
    """Hackathon-friendly in-memory session store.

    - Stateless HTTP APIs, but sessions are stored in process memory.
    - If the process restarts (HF Spaces redeploy), sessions are lost.
    """

    sessions: Dict[str, Dict[str, Any]]

    def create_session(self, filename: str, ocr_items: List[Dict[str, Any]], fields: List[FormField]) -> str:
        session_id = str(uuid4())
        self.sessions[session_id] = {
            "session_id": session_id,
            "created_at": time.time(),
            "filename": filename,
            "ocr_items": ocr_items,
            "fields": [f.model_dump() for f in fields],
            "current_field_index": 0,
            "messages": [],
        }
        return session_id

    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        return self.sessions.get(session_id)

    def append_message(self, session_id: str, role: str, content: str) -> None:
        session = self.sessions.get(session_id)
        if session is None:
            return
        session["messages"].append({"role": role, "content": content, "ts": time.time()})

    def get_next_field(self, session_id: str) -> Optional[Dict[str, Any]]:
        session = self.sessions.get(session_id)
        if session is None:
            return None
        fields = session.get("fields", [])
        if not fields:
            return None

        idx = int(session.get("current_field_index", 0))
        if idx >= len(fields):
            return None
        return fields[idx]

    def advance_field(self, session_id: str) -> None:
        session = self.sessions.get(session_id)
        if session is None:
            return
        session["current_field_index"] = int(session.get("current_field_index", 0)) + 1


memory = _MemoryService(sessions={})
