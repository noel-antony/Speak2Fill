"""
Session State Management for Form Filling
"""
from typing import Dict, List, Optional, Literal
from pydantic import BaseModel
from enum import Enum


class Phase(str, Enum):
    ASK_INPUT = "ASK_INPUT"
    AWAIT_CONFIRMATION = "AWAIT_CONFIRMATION"


class FormField(BaseModel):
    field_id: str
    label: str
    bbox: List[float]  # [x1, y1, x2, y2]
    input_mode: str
    write_language: str


class SessionState(BaseModel):
    session_id: str
    current_field_index: int
    phase: Phase
    fields: List[FormField]
    collected_values: Dict[str, str]
    image_width: int
    image_height: int


class SessionService:
    """In-memory session state manager"""
    
    def __init__(self):
        self._sessions: Dict[str, SessionState] = {}
    
    def create_session(
        self,
        session_id: str,
        fields: List[FormField],
        image_width: int,
        image_height: int
    ) -> SessionState:
        """Initialize a new form filling session"""
        state = SessionState(
            session_id=session_id,
            current_field_index=0,
            phase=Phase.ASK_INPUT,
            fields=fields,
            collected_values={},
            image_width=image_width,
            image_height=image_height
        )
        self._sessions[session_id] = state
        return state
    
    def get_session(self, session_id: str) -> Optional[SessionState]:
        """Retrieve session state"""
        return self._sessions.get(session_id)
    
    def update_session(self, session_id: str, state: SessionState):
        """Update session state"""
        self._sessions[session_id] = state
    
    def delete_session(self, session_id: str):
        """Remove session from memory"""
        if session_id in self._sessions:
            del self._sessions[session_id]
    
    def get_current_field(self, session_id: str) -> Optional[FormField]:
        """Get the current field being processed"""
        state = self.get_session(session_id)
        if not state:
            return None
        
        if state.current_field_index >= len(state.fields):
            return None
        
        return state.fields[state.current_field_index]
    
    def has_more_fields(self, session_id: str) -> bool:
        """Check if there are more fields to process"""
        state = self.get_session(session_id)
        if not state:
            return False
        
        return state.current_field_index < len(state.fields)
    
    def advance_to_next_field(self, session_id: str):
        """Move to the next field"""
        state = self.get_session(session_id)
        if state:
            state.current_field_index += 1
            state.phase = Phase.ASK_INPUT
            self.update_session(session_id, state)
    
    def set_phase(self, session_id: str, phase: Phase):
        """Update current phase"""
        state = self.get_session(session_id)
        if state:
            state.phase = phase
            self.update_session(session_id, state)
    
    def store_value(self, session_id: str, field_id: str, value: str):
        """Store extracted value for a field"""
        state = self.get_session(session_id)
        if state:
            state.collected_values[field_id] = value
            self.update_session(session_id, state)


# Global singleton instance
session_service = SessionService()
