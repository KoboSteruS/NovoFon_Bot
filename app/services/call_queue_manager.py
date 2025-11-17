"""
Call queue manager - handles automatic calling queue
"""
import uuid
import asyncio
from datetime import datetime, timedelta
from typing import Optional, List
from sqlalchemy import select, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession
from loguru import logger

from app.models import CallQueue, QueueStatus, Call, CallStatus
from app.database import AsyncSessionLocal


class CallQueueManager:
    """
    Manages automatic calling queue
    
    Responsibilities:
    - Process pending queue items
    - Retry failed calls
    - Schedule calls
    - Track statistics
    """
    
    def __init__(self):
        """Initialize queue manager"""
        self.is_running = False
        self._processing_task: Optional[asyncio.Task] = None
        self.max_concurrent_calls = 10  # Maximum simultaneous calls
        self.retry_delay_minutes = 5  # Minutes between retries
        
        logger.info("Call queue manager initialized")
    
    async def start(self):
        """Start queue processing"""
        if self.is_running:
            logger.warning("Queue manager already running")
            return
        
        self.is_running = True
        self._processing_task = asyncio.create_task(self._processing_loop())
        logger.info("Call queue manager started")
    
    async def stop(self):
        """Stop queue processing"""
        if not self.is_running:
            return
        
        self.is_running = False
        
        if self._processing_task:
            self._processing_task.cancel()
            try:
                await self._processing_task
            except asyncio.CancelledError:
                pass
        
        logger.info("Call queue manager stopped")
    
    async def _processing_loop(self):
        """Main processing loop"""
        try:
            while self.is_running:
                try:
                    await self._process_queue()
                except Exception as e:
                    logger.error(f"Error in queue processing: {e}", exc_info=True)
                
                # Wait before next iteration
                await asyncio.sleep(5)  # Check every 5 seconds
        
        except asyncio.CancelledError:
            pass
    
    async def _process_queue(self):
        """Process queue items"""
        async with AsyncSessionLocal() as db:
            # Get pending items
            items = await self._get_pending_items(db)
            
            if not items:
                return
            
            logger.info(f"Processing {len(items)} queue items")
            
            # Process each item
            for item in items:
                try:
                    await self._process_queue_item(db, item)
                except Exception as e:
                    logger.error(f"Error processing queue item {item.id}: {e}", exc_info=True)
                    await self._mark_item_error(db, item, str(e))
    
    async def _get_pending_items(self, db: AsyncSession) -> List[CallQueue]:
        """
        Get pending queue items
        
        Args:
            db: Database session
        
        Returns:
            List of pending queue items
        """
        now = datetime.utcnow()
        
        # Query for pending items
        query = select(CallQueue).where(
            and_(
                CallQueue.status == QueueStatus.PENDING,
                or_(
                    CallQueue.scheduled_at == None,
                    CallQueue.scheduled_at <= now
                )
            )
        ).order_by(
            CallQueue.priority.desc(),
            CallQueue.created_at.asc()
        ).limit(self.max_concurrent_calls)
        
        result = await db.execute(query)
        return list(result.scalars().all())
    
    async def _process_queue_item(self, db: AsyncSession, item: CallQueue):
        """
        Process a single queue item
        
        Args:
            db: Database session
            item: Queue item to process
        """
        logger.info(f"Processing queue item {item.id} for {item.phone}")
        
        # Mark as in progress
        item.status = QueueStatus.IN_PROGRESS
        item.started_at = datetime.utcnow()
        await db.commit()
        
        try:
            # Create call record
            call = Call(
                id=uuid.uuid4(),
                phone=item.phone,
                status=CallStatus.PENDING,
                start_time=datetime.utcnow()
            )
            db.add(call)
            await db.flush()
            
            # Link queue item to call
            item.call_id = call.id
            await db.commit()
            
            # TODO: Initiate call through Asterisk
            # This will be done when Asterisk is set up
            logger.info(f"Call {call.id} would be initiated for {item.phone}")
            
            # For now, mark as done
            # In real implementation, this would happen after call completes
            await self._mark_item_done(db, item)
        
        except Exception as e:
            logger.error(f"Failed to process queue item {item.id}: {e}", exc_info=True)
            raise
    
    async def _mark_item_done(self, db: AsyncSession, item: CallQueue):
        """Mark queue item as done"""
        item.status = QueueStatus.DONE
        item.completed_at = datetime.utcnow()
        await db.commit()
        logger.info(f"Queue item {item.id} marked as done")
    
    async def _mark_item_error(self, db: AsyncSession, item: CallQueue, error: str):
        """Mark queue item as error and handle retry"""
        item.retry_count += 1
        item.error_message = error
        
        if item.retry_count < item.max_retries:
            # Schedule retry
            item.status = QueueStatus.PENDING
            item.scheduled_at = datetime.utcnow() + timedelta(minutes=self.retry_delay_minutes)
            logger.info(f"Queue item {item.id} scheduled for retry {item.retry_count}/{item.max_retries}")
        else:
            # Max retries reached
            item.status = QueueStatus.ERROR
            item.completed_at = datetime.utcnow()
            logger.warning(f"Queue item {item.id} failed after {item.retry_count} retries")
        
        await db.commit()
    
    async def add_to_queue(
        self,
        phone: str,
        priority: int = 0,
        scheduled_at: Optional[datetime] = None,
        max_retries: int = 3,
        metadata: Optional[dict] = None
    ) -> CallQueue:
        """
        Add phone number to queue
        
        Args:
            phone: Phone number to call
            priority: Priority (higher = more important)
            scheduled_at: When to call (None = immediately)
            max_retries: Maximum retry attempts
            metadata: Custom metadata
        
        Returns:
            Created queue item
        """
        async with AsyncSessionLocal() as db:
            item = CallQueue(
                id=uuid.uuid4(),
                phone=phone,
                priority=priority,
                status=QueueStatus.PENDING,
                scheduled_at=scheduled_at,
                max_retries=max_retries,
                custom_metadata=str(metadata) if metadata else None
            )
            
            db.add(item)
            await db.commit()
            await db.refresh(item)
            
            logger.info(f"Added {phone} to queue (priority: {priority})")
            return item
    
    async def bulk_add_to_queue(self, phones: List[str], priority: int = 0) -> int:
        """
        Add multiple phone numbers to queue
        
        Args:
            phones: List of phone numbers
            priority: Priority for all items
        
        Returns:
            Number of items added
        """
        async with AsyncSessionLocal() as db:
            items = []
            for phone in phones:
                item = CallQueue(
                    id=uuid.uuid4(),
                    phone=phone,
                    priority=priority,
                    status=QueueStatus.PENDING
                )
                items.append(item)
            
            db.add_all(items)
            await db.commit()
            
            logger.info(f"Bulk added {len(items)} numbers to queue")
            return len(items)
    
    async def cancel_queue_item(self, item_id: uuid.UUID) -> bool:
        """
        Cancel a queue item
        
        Args:
            item_id: Queue item UUID
        
        Returns:
            True if cancelled, False if not found or already processed
        """
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(CallQueue).where(CallQueue.id == item_id)
            )
            item = result.scalar_one_or_none()
            
            if not item:
                return False
            
            if item.status in [QueueStatus.DONE, QueueStatus.ERROR]:
                logger.warning(f"Cannot cancel queue item {item_id}, already {item.status}")
                return False
            
            item.status = QueueStatus.CANCELLED
            item.completed_at = datetime.utcnow()
            await db.commit()
            
            logger.info(f"Cancelled queue item {item_id}")
            return True
    
    async def get_queue_stats(self) -> dict:
        """
        Get queue statistics
        
        Returns:
            Dictionary with queue stats
        """
        async with AsyncSessionLocal() as db:
            # Count by status
            stats = {
                'pending': 0,
                'in_progress': 0,
                'done': 0,
                'error': 0,
                'cancelled': 0
            }
            
            for status in QueueStatus:
                result = await db.execute(
                    select(CallQueue).where(CallQueue.status == status)
                )
                count = len(list(result.scalars().all()))
                stats[status.value] = count
            
            return stats


# Global queue manager
queue_manager: Optional[CallQueueManager] = None


def get_queue_manager() -> CallQueueManager:
    """Get or create queue manager instance"""
    global queue_manager
    if queue_manager is None:
        queue_manager = CallQueueManager()
    return queue_manager

