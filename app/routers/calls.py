"""
API endpoints for call management
"""
from uuid import UUID
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from loguru import logger

from app.database import get_db
from app.schemas import (
    CallInitiate,
    CallResponse,
    CallListResponse,
    MessageResponse,
    SuccessResponse,
    ErrorResponse
)
from app.services.novofon import get_novofon_client, NovoFonClient, NovoFonAPIError
from app.services.call_manager import CallManager
from app.models import CallStatus


router = APIRouter()


def get_call_manager(
    db: AsyncSession = Depends(get_db),
    novofon_client: NovoFonClient = Depends(get_novofon_client)
) -> CallManager:
    """Dependency for getting call manager"""
    return CallManager(db, novofon_client)


@router.post("/initiate", response_model=CallResponse, status_code=201)
async def initiate_call(
    call_request: CallInitiate,
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    Initiate a new outbound call
    
    - **phone**: Phone number to call (e.g., "+79991234567")
    - **custom_metadata**: Optional metadata for the call
    
    Returns call information including ID for tracking
    """
    try:
        logger.info(f"Initiating call to {call_request.phone}")
        
        call = await call_manager.initiate_call(
            phone=call_request.phone,
            custom_metadata=call_request.custom_metadata
        )
        
        return CallResponse.model_validate(call)
    
    except NovoFonAPIError as e:
        logger.error(f"NovoFon API error: {e}")
        raise HTTPException(
            status_code=502,
            detail=f"Failed to initiate call via NovoFon: {e.message}"
        )
    
    except Exception as e:
        logger.error(f"Unexpected error initiating call: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )


@router.get("/{call_id}", response_model=CallResponse)
async def get_call(
    call_id: UUID,
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    Get information about a specific call
    
    - **call_id**: UUID of the call
    """
    call = await call_manager.get_call(call_id)
    
    if not call:
        raise HTTPException(
            status_code=404,
            detail=f"Call {call_id} not found"
        )
    
    return CallResponse.model_validate(call)


@router.get("/{call_id}/messages", response_model=list[MessageResponse])
async def get_call_messages(
    call_id: UUID,
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    Get all messages (conversation) for a call
    
    - **call_id**: UUID of the call
    """
    # Check if call exists
    call = await call_manager.get_call(call_id)
    if not call:
        raise HTTPException(
            status_code=404,
            detail=f"Call {call_id} not found"
        )
    
    messages = await call_manager.get_call_messages(call_id)
    
    return [MessageResponse.model_validate(msg) for msg in messages]


@router.get("/", response_model=CallListResponse)
async def list_calls(
    status: Optional[CallStatus] = Query(None, description="Filter by status"),
    phone: Optional[str] = Query(None, description="Filter by phone number"),
    limit: int = Query(100, ge=1, le=1000, description="Max results per page"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    List calls with optional filters and pagination
    
    - **status**: Filter by call status (optional)
    - **phone**: Filter by phone number (optional)
    - **limit**: Maximum number of results (1-1000, default 100)
    - **offset**: Offset for pagination (default 0)
    """
    calls, total = await call_manager.list_calls(
        status=status,
        phone=phone,
        limit=limit,
        offset=offset
    )
    
    return CallListResponse(
        total=total,
        calls=[CallResponse.model_validate(call) for call in calls]
    )


@router.post("/{call_id}/hangup", response_model=SuccessResponse)
async def hangup_call(
    call_id: UUID,
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    Hangup an active call
    
    - **call_id**: UUID of the call to hangup
    """
    call = await call_manager.hangup_call(call_id)
    
    if not call:
        raise HTTPException(
            status_code=404,
            detail=f"Call {call_id} not found"
        )
    
    return SuccessResponse(
        success=True,
        message=f"Call {call_id} hung up successfully"
    )


@router.delete("/{call_id}", response_model=SuccessResponse)
async def delete_call(
    call_id: UUID,
    db: AsyncSession = Depends(get_db),
    call_manager: CallManager = Depends(get_call_manager)
):
    """
    Delete a call record (and all associated messages)
    
    - **call_id**: UUID of the call to delete
    
    ⚠️ This is a destructive operation and cannot be undone
    """
    call = await call_manager.get_call(call_id)
    
    if not call:
        raise HTTPException(
            status_code=404,
            detail=f"Call {call_id} not found"
        )
    
    await db.delete(call)
    await db.commit()
    
    logger.info(f"Deleted call {call_id}")
    
    return SuccessResponse(
        success=True,
        message=f"Call {call_id} deleted successfully"
    )

