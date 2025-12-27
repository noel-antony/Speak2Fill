from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
from uuid import uuid4

from app.schemas.models import FormField


def _db_path() -> str:
    # Works well on HF Spaces free CPU: a single SQLite file on local disk.
    # Default is a relative path so it works locally and in Docker.
    return os.getenv("SPEAK2FILL_DB_PATH") or "data/speak2fill.db"


def _connect() -> sqlite3.Connection:
    path = _db_path()
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    # Better concurrency characteristics for a small API.
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn


def _init_db(conn: sqlite3.Connection) -> None:
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
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            ts REAL NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(session_id)
        );
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);")
    conn.commit()


@dataclass
class SQLiteSessionStore:
    """Small, hackathon-friendly SQLite session store.

    Stores OCR + inferred fields from /upload-form and retrieves them by session_id in /chat.
    """

    _lock: threading.Lock

    def _with_db(self, fn):
        # Single lock avoids interleaving writes across threads.
        with self._lock:
            conn = _connect()
            try:
                _init_db(conn)
                return fn(conn)
            finally:
                conn.close()

    def create_session(
        self,
        filename: str,
        ocr_items: List[Dict[str, Any]],
        fields: List[FormField],
        image_width: int = 0,
        image_height: int = 0,
    ) -> str:
        session_id = str(uuid4())
        created_at = time.time()

        def _op(conn: sqlite3.Connection) -> str:
            conn.execute(
                "INSERT INTO sessions(session_id, created_at, filename, ocr_items_json, fields_json, current_field_index, filled_fields_json, language, image_width, image_height) VALUES (?, ?, ?, ?, ?, 0, '{}', 'en', ?, ?)",
                (
                    session_id,
                    created_at,
                    filename,
                    json.dumps(ocr_items, ensure_ascii=False),
                    json.dumps([f.model_dump() for f in fields], ensure_ascii=False),
                    image_width,
                    image_height,
                ),
            )
            conn.commit()
            return session_id

        return self._with_db(_op)

    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        def _op(conn: sqlite3.Connection) -> Optional[Dict[str, Any]]:
            row = conn.execute(
                "SELECT session_id, created_at, filename, ocr_items_json, fields_json, current_field_index, filled_fields_json, language, image_width, image_height FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                return None
            
            # Handle potential missing columns for backward compatibility
            try:
                filled_fields_json = row["filled_fields_json"]
            except (KeyError, IndexError):
                filled_fields_json = "{}"
            
            try:
                language = row["language"]
            except (KeyError, IndexError):
                language = "en"
            
            try:
                image_width = int(row["image_width"])
            except (KeyError, IndexError):
                image_width = 0
            
            try:
                image_height = int(row["image_height"])
            except (KeyError, IndexError):
                image_height = 0
            
            return {
                "session_id": row["session_id"],
                "created_at": row["created_at"],
                "filename": row["filename"],
                "ocr_items": json.loads(row["ocr_items_json"]),
                "fields": json.loads(row["fields_json"]),
                "current_field_index": int(row["current_field_index"]),
                "filled_fields": json.loads(filled_fields_json),
                "language": language,
                "image_width": image_width,
                "image_height": image_height,
            }

        return self._with_db(_op)

    def append_message(self, session_id: str, role: str, content: str) -> None:
        def _op(conn: sqlite3.Connection) -> None:
            conn.execute(
                "INSERT INTO messages(session_id, ts, role, content) VALUES (?, ?, ?, ?)",
                (session_id, time.time(), role, content),
            )
            conn.commit()

        self._with_db(_op)

    def get_next_field(self, session_id: str) -> Optional[Dict[str, Any]]:
        def _op(conn: sqlite3.Connection) -> Optional[Dict[str, Any]]:
            row = conn.execute(
                "SELECT fields_json, current_field_index FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                return None
            fields = json.loads(row["fields_json"])
            if not fields:
                return None
            idx = int(row["current_field_index"])
            if idx >= len(fields):
                return None
            return fields[idx]

        return self._with_db(_op)

    def advance_field(self, session_id: str) -> None:
        def _op(conn: sqlite3.Connection) -> None:
            conn.execute(
                "UPDATE sessions SET current_field_index = current_field_index + 1 WHERE session_id = ?",
                (session_id,),
            )
            conn.commit()

        self._with_db(_op)

    def update_filled_field(self, session_id: str, field_label: str, value: str) -> None:
        """Update a specific field value in the filled_fields map."""

        def _op(conn: sqlite3.Connection) -> None:
            row = conn.execute(
                "SELECT filled_fields_json FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                return
            filled_fields = json.loads(row["filled_fields_json"])
            filled_fields[field_label] = value
            conn.execute(
                "UPDATE sessions SET filled_fields_json = ? WHERE session_id = ?",
                (json.dumps(filled_fields, ensure_ascii=False), session_id),
            )
            conn.commit()

        self._with_db(_op)

    def update_fields(self, session_id: str, fields: List[Dict[str, Any]]) -> None:
        """Replace the entire fields list for a session (used by /analyze-form)."""

        def _op(conn: sqlite3.Connection) -> None:
            conn.execute(
                "UPDATE sessions SET fields_json = ?, current_field_index = 0 WHERE session_id = ?",
                (json.dumps(fields, ensure_ascii=False), session_id),
            )
            conn.commit()

        self._with_db(_op)


store = SQLiteSessionStore(_lock=threading.Lock())
