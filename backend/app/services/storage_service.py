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
            image_data BLOB,
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
    
    # Migration: Add image_data column if it doesn't exist (for existing databases)
    try:
        conn.execute("SELECT image_data FROM sessions LIMIT 1")
    except sqlite3.OperationalError:
        # Column doesn't exist, add it
        conn.execute("ALTER TABLE sessions ADD COLUMN image_data BLOB")
        conn.commit()
    
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

    Stores OCR + inferred fields from /analyze-form.
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
        image_data: Optional[bytes] = None,
    ) -> str:
        session_id = str(uuid4())
        created_at = time.time()

        def _op(conn: sqlite3.Connection) -> str:
            conn.execute(
                "INSERT INTO sessions(session_id, created_at, filename, image_data, ocr_items_json, fields_json, current_field_index, filled_fields_json, language, image_width, image_height) VALUES (?, ?, ?, ?, ?, ?, 0, '{}', 'en', ?, ?)",
                (
                    session_id,
                    created_at,
                    filename,
                    image_data,
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
                "SELECT session_id, created_at, filename, ocr_items_json, fields_json, image_width, image_height FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                return None
            
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
                "image_width": image_width,
                "image_height": image_height,
            }

        return self._with_db(_op)

    def get_image(self, session_id: str) -> Optional[bytes]:
        """Retrieve the original uploaded image by session_id."""

        def _op(conn: sqlite3.Connection) -> Optional[bytes]:
            row = conn.execute(
                "SELECT image_data FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None or row["image_data"] is None:
                return None
            return bytes(row["image_data"])

        return self._with_db(_op)

    def get_full_response(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve the complete analyze-form response by session_id.
        
        Returns the same structure as UploadFormResponse:
        - session_id
        - image_width, image_height
        - ocr_items (deduplicated)
        - fields (with field_id, label, bbox, etc.)
        """

        def _op(conn: sqlite3.Connection) -> Optional[Dict[str, Any]]:
            row = conn.execute(
                "SELECT session_id, ocr_items_json, fields_json, image_width, image_height FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                return None

            return {
                "session_id": row["session_id"],
                "image_width": int(row["image_width"]),
                "image_height": int(row["image_height"]),
                "ocr_items": json.loads(row["ocr_items_json"]),
                "fields": json.loads(row["fields_json"]),
            }

        return self._with_db(_op)


store = SQLiteSessionStore(_lock=threading.Lock())
