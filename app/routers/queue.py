"""
API endpoints for call queue management
"""
from datetime import datetime
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from loguru import logger

from app.database import get_db
from app.schemas import (
    QueueItemCreate,
    QueueItemResponse,
    QueueListResponse,
    SuccessResponse
)
from app.services.call_queue_manager import get_queue_manager, CallQueueManager
from app.models import CallQueue, QueueStatus


router = APIRouter()


@router.post("/add", response_model=QueueItemResponse, status_code=201)
async def add_to_queue(
    item: QueueItemCreate,
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Add phone number to call queue
    
    - **phone**: Phone number to call
    - **priority**: Priority (higher = more important, default: 0)
    - **scheduled_at**: When to call (optional, default: now)
    - **max_retries**: Maximum retry attempts (default: 3)
    - **custom_metadata**: Custom metadata (optional)
    """
    try:
        logger.info(f"Adding {item.phone} to queue")
        
        queue_item = await queue_manager.add_to_queue(
            phone=item.phone,
            priority=item.priority,
            scheduled_at=item.scheduled_at,
            max_retries=item.max_retries,
            metadata=item.custom_metadata
        )
        
        return QueueItemResponse.model_validate(queue_item)
    
    except Exception as e:
        logger.error(f"Error adding to queue: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to add to queue: {str(e)}"
        )


@router.post("/bulk-add", response_model=SuccessResponse)
async def bulk_add_to_queue(
    phones: List[str],
    priority: int = Query(0, description="Priority for all items"),
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Add multiple phone numbers to queue at once
    
    - **phones**: List of phone numbers
    - **priority**: Priority for all items (default: 0)
    """
    if not phones:
        raise HTTPException(status_code=400, detail="Phone list is empty")
    
    try:
        count = await queue_manager.bulk_add_to_queue(phones, priority)
        return SuccessResponse(
            success=True,
            message=f"Added {count} numbers to queue"
        )
    
    except Exception as e:
        logger.error(f"Error in bulk add: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to bulk add: {str(e)}"
        )


@router.get("/", response_model=QueueListResponse)
async def list_queue(
    status: Optional[QueueStatus] = Query(None, description="Filter by status"),
    limit: int = Query(100, ge=1, le=1000, description="Max results"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    db: AsyncSession = Depends(get_db)
):
    """
    List queue items with optional filters
    
    - **status**: Filter by status (optional)
    - **limit**: Maximum number of results (1-1000, default 100)
    - **offset**: Offset for pagination (default 0)
    """
    from sqlalchemy import select
    
    # Build query
    query = select(CallQueue)
    
    if status:
        query = query.where(CallQueue.status == status)
    
    # Count total
    count_result = await db.execute(query)
    total = len(list(count_result.scalars().all()))
    
    # Get paginated results
    query = query.order_by(
        CallQueue.priority.desc(),
        CallQueue.created_at.desc()
    ).limit(limit).offset(offset)
    
    result = await db.execute(query)
    items = list(result.scalars().all())
    
    return QueueListResponse(
        total=total,
        items=[QueueItemResponse.model_validate(item) for item in items]
    )


@router.get("/{item_id}", response_model=QueueItemResponse)
async def get_queue_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db)
):
    """
    Get queue item by ID
    
    - **item_id**: Queue item UUID
    """
    from sqlalchemy import select
    
    result = await db.execute(
        select(CallQueue).where(CallQueue.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=404,
            detail=f"Queue item {item_id} not found"
        )
    
    return QueueItemResponse.model_validate(item)


@router.post("/{item_id}/cancel", response_model=SuccessResponse)
async def cancel_queue_item(
    item_id: UUID,
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Cancel a queue item
    
    - **item_id**: Queue item UUID to cancel
    """
    success = await queue_manager.cancel_queue_item(item_id)
    
    if not success:
        raise HTTPException(
            status_code=404,
            detail=f"Queue item {item_id} not found or already processed"
        )
    
    return SuccessResponse(
        success=True,
        message=f"Queue item {item_id} cancelled"
    )


@router.delete("/{item_id}", response_model=SuccessResponse)
async def delete_queue_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db)
):
    """
    Delete a queue item
    
    - **item_id**: Queue item UUID to delete
    
    ⚠️ This is a destructive operation
    """
    from sqlalchemy import select
    
    result = await db.execute(
        select(CallQueue).where(CallQueue.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=404,
            detail=f"Queue item {item_id} not found"
        )
    
    await db.delete(item)
    await db.commit()
    
    logger.info(f"Deleted queue item {item_id}")
    
    return SuccessResponse(
        success=True,
        message=f"Queue item {item_id} deleted"
    )


@router.get("/stats/summary")
async def get_queue_stats(
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Get queue statistics
    
    Returns counts by status:
    - pending: Waiting to be called
    - in_progress: Currently being called
    - done: Successfully completed
    - error: Failed after retries
    - cancelled: Manually cancelled
    """
    stats = await queue_manager.get_queue_stats()
    return stats


@router.post("/control/start", response_model=SuccessResponse)
async def start_queue_processing(
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Start queue processing
    
    Begins automatic processing of pending queue items
    """
    try:
        await queue_manager.start()
        return SuccessResponse(
            success=True,
            message="Queue processing started"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to start queue: {str(e)}"
        )


@router.post("/control/stop", response_model=SuccessResponse)
async def stop_queue_processing(
    queue_manager: CallQueueManager = Depends(get_queue_manager)
):
    """
    Stop queue processing
    
    Stops automatic processing (in-progress calls will continue)
    """
    try:
        await queue_manager.stop()
        return SuccessResponse(
            success=True,
            message="Queue processing stopped"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to stop queue: {str(e)}"
        )

