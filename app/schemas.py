"""
Pydantic schemas for API requests/responses
"""
from datetime import datetime
from typing import Optional, List
from uuid import UUID
from pydantic import BaseModel, Field

from app.models import CallStatus, QueueStatus, MessageRole


# ========== Call Schemas ==========

class CallBase(BaseModel):
    """Base call schema"""
    phone: str = Field(..., description="Phone number to call")


class CallCreate(CallBase):
    """Schema for creating a call"""
    pass


class CallInitiate(CallBase):
    """Schema for initiating a call via NovoFon"""
    custom_metadata: Optional[dict] = Field(None, description="Custom metadata for the call")


class CallResponse(BaseModel):
    """Schema for call response"""
    id: UUID
    phone: str
    status: CallStatus
    start_time: datetime
    end_time: Optional[datetime] = None
    duration: Optional[int] = None
    scenario_result: Optional[str] = None
    novofon_call_id: Optional[str] = None
    error_message: Optional[str] = None
    
    model_config = {"from_attributes": True}


class CallListResponse(BaseModel):
    """Schema for list of calls"""
    total: int
    calls: List[CallResponse]


# ========== Message Schemas ==========

class MessageBase(BaseModel):
    """Base message schema"""
    role: MessageRole
    text: str


class MessageCreate(MessageBase):
    """Schema for creating a message"""
    call_id: UUID
    audio_duration: Optional[float] = None


class MessageResponse(BaseModel):
    """Schema for message response"""
    id: UUID
    call_id: UUID
    role: MessageRole
    text: str
    timestamp: datetime
    audio_duration: Optional[float] = None
    
    model_config = {"from_attributes": True}


# ========== Queue Schemas ==========

class QueueItemBase(BaseModel):
    """Base queue item schema"""
    phone: str
    priority: int = Field(default=0, description="Priority (higher = more important)")


class QueueItemCreate(QueueItemBase):
    """Schema for creating queue item"""
    scheduled_at: Optional[datetime] = Field(None, description="When to call (if not immediate)")
    max_retries: int = Field(default=3, description="Maximum retry attempts")
    custom_metadata: Optional[dict] = Field(None, description="Custom metadata")


class QueueItemResponse(BaseModel):
    """Schema for queue item response"""
    id: UUID
    phone: str
    priority: int
    status: QueueStatus
    created_at: datetime
    scheduled_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    retry_count: int
    max_retries: int
    call_id: Optional[UUID] = None
    error_message: Optional[str] = None
    
    model_config = {"from_attributes": True}


class QueueListResponse(BaseModel):
    """Schema for list of queue items"""
    total: int
    items: List[QueueItemResponse]


# ========== NovoFon API Schemas ==========

class NovoFonCallRequest(BaseModel):
    """Schema for NovoFon API call request"""
    from_number: str = Field(..., alias="from")
    to_number: str = Field(..., alias="to")
    line_number: Optional[str] = None
    custom_id: Optional[str] = None


class NovoFonCallResponse(BaseModel):
    """Schema for NovoFon API call response"""
    status: str
    call_id: Optional[str] = None
    message: Optional[str] = None
    error: Optional[str] = None


# ========== Generic Responses ==========

class SuccessResponse(BaseModel):
    """Generic success response"""
    success: bool = True
    message: str


class ErrorResponse(BaseModel):
    """Generic error response"""
    success: bool = False
    error: str
    detail: Optional[str] = None

