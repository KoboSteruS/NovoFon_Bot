"""
SQLAlchemy models for database tables
"""
import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import (
    String, 
    Integer, 
    DateTime, 
    Text, 
    Enum,
    ForeignKey,
    Float
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database import Base


class CallStatus(str, enum.Enum):
    """Call status enumeration"""
    PENDING = "pending"
    RINGING = "ringing"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    NO_ANSWER = "no_answer"
    BUSY = "busy"
    FAILED = "failed"
    USER_HANGUP = "user_hangup"
    BOT_HANGUP = "bot_hangup"


class QueueStatus(str, enum.Enum):
    """Queue status enumeration"""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    DONE = "done"
    ERROR = "error"
    CANCELLED = "cancelled"


class MessageRole(str, enum.Enum):
    """Message role enumeration"""
    USER = "user"
    BOT = "bot"
    SYSTEM = "system"


class Call(Base):
    """
    Calls table - stores information about each call
    """
    __tablename__ = "calls"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), 
        primary_key=True, 
        default=uuid.uuid4
    )
    phone: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    
    # Timing
    start_time: Mapped[datetime] = mapped_column(
        DateTime, 
        nullable=False, 
        default=datetime.utcnow
    )
    end_time: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    duration: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # seconds
    
    # Status
    status: Mapped[CallStatus] = mapped_column(
        Enum(CallStatus),
        nullable=False,
        default=CallStatus.PENDING,
        index=True
    )
    
    # Scenario result (JSON string or simple status)
    scenario_result: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # NovoFon call ID
    novofon_call_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    
    # Asterisk channel ID
    asterisk_channel_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    
    # Additional metadata
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # Relationships
    messages: Mapped[list["Message"]] = relationship(
        "Message",
        back_populates="call",
        cascade="all, delete-orphan"
    )
    
    def __repr__(self):
        return f"<Call {self.id} {self.phone} {self.status}>"


class Message(Base):
    """
    Messages table - stores conversation messages
    """
    __tablename__ = "messages"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    call_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("calls.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    role: Mapped[MessageRole] = mapped_column(
        Enum(MessageRole),
        nullable=False
    )
    text: Mapped[str] = mapped_column(Text, nullable=False)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow
    )
    
    # Audio duration (for TTS/ASR tracking)
    audio_duration: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    
    # Relationships
    call: Mapped["Call"] = relationship("Call", back_populates="messages")
    
    def __repr__(self):
        return f"<Message {self.id} {self.role} {self.text[:30]}...>"


class CallQueue(Base):
    """
    Call queue table - manages outbound call queue
    """
    __tablename__ = "call_queue"
    
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )
    phone: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    
    # Priority (higher = more important)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0, index=True)
    
    # Status
    status: Mapped[QueueStatus] = mapped_column(
        Enum(QueueStatus),
        nullable=False,
        default=QueueStatus.PENDING,
        index=True
    )
    
    # Timing
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow
    )
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    
    # Retry logic
    retry_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_retries: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    
    # Result
    call_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("calls.id", ondelete="SET NULL"),
        nullable=True
    )
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # Additional metadata (JSON string) - renamed from 'metadata' to avoid SQLAlchemy conflict
    custom_metadata: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    def __repr__(self):
        return f"<CallQueue {self.id} {self.phone} {self.status}>"

