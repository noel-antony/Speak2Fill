"""Deprecated module.

The backend used to store sessions in process memory. It now uses SQLite via
`app.services.storage_service.store`.

This module remains as a tiny compatibility shim.
"""

from app.services.storage_service import store as memory
