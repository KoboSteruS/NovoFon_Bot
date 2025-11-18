"""
Call management service - orchestrates calls between DB, NovoFon, and other components
"""
import uuid
from datetime import datetime
from typing import Optional, List
from sqlalchemy import select, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession
from loguru import logger

from app.models import Call, CallStatus, Message, MessageRole
from app.services.novofon import NovoFonClient, NovoFonAPIError
from app.services.asterisk_call_handler import get_call_handler, AsteriskCallHandler


class CallManager:
    """
    Manages call lifecycle: creation, tracking, completion
    """
    
    def __init__(
        self, 
        db: AsyncSession, 
        novofon_client: Optional[NovoFonClient] = None,
        asterisk_handler: Optional[AsteriskCallHandler] = None
    ):
        """
        Initialize call manager
        
        Args:
            db: Database session
            novofon_client: NovoFon API client (optional, for legacy support)
            asterisk_handler: Asterisk call handler (for SIP calls)
        """
        self.db = db
        self.novofon = novofon_client
        self.asterisk_handler = asterisk_handler
    
    async def initiate_call(
        self,
        phone: str,
        custom_metadata: Optional[dict] = None
    ) -> Call:
        """
        Initiate a new outbound call
        
        Args:
            phone: Phone number to call
            custom_metadata: Optional metadata
        
        Returns:
            Call object
        
        Raises:
            NovoFonAPIError: If call initiation fails
        """
        # Create call record in database
        call = Call(
            id=uuid.uuid4(),
            phone=phone,
            status=CallStatus.PENDING,
            start_time=datetime.utcnow()
        )
        
        self.db.add(call)
        await self.db.flush()
        
        logger.info(f"Created call record {call.id} for {phone}")
        
        try:
            # Use Asterisk for outbound calls (preferred method)
            if self.asterisk_handler:
                channel_id = await self.asterisk_handler.initiate_call(
                    phone_number=phone,
                    call_id=call.id
                )
                call.asterisk_channel_id = channel_id
                call.status = CallStatus.RINGING
                
                await self.db.commit()
                
                logger.info(f"Call {call.id} initiated via Asterisk: {channel_id}")
            
            # Fallback to NovoFon API (legacy, if Asterisk not available)
            elif self.novofon:
                result = await self.novofon.initiate_call(
                    to_number=phone,
                    custom_id=str(call.id)
                )
                
                call.novofon_call_id = result.get("call_id")
                call.status = CallStatus.RINGING
                
                await self.db.commit()
                
                logger.info(f"Call {call.id} initiated via NovoFon: {call.novofon_call_id}")
            
            else:
                raise ValueError("Neither Asterisk handler nor NovoFon client available")
            
            # Create initial system message
            await self.add_message(
                call_id=call.id,
                role=MessageRole.SYSTEM,
                text=f"Call initiated to {phone}"
            )
            
            return call
        
        except Exception as e:
            logger.error(f"Failed to initiate call {call.id}: {e}")
            
            # Update call status to failed
            call.status = CallStatus.FAILED
            call.error_message = str(e)
            call.end_time = datetime.utcnow()
            
            await self.db.commit()
            
            raise
    
    async def get_call(self, call_id: uuid.UUID) -> Optional[Call]:
        """
        Get call by ID
        
        Args:
            call_id: Call UUID
        
        Returns:
            Call object or None
        """
        result = await self.db.execute(
            select(Call).where(Call.id == call_id)
        )
        return result.scalar_one_or_none()
    
    async def update_call_status(
        self,
        call_id: uuid.UUID,
        status: CallStatus,
        error_message: Optional[str] = None
    ) -> Optional[Call]:
        """
        Update call status
        
        Args:
            call_id: Call UUID
            status: New status
            error_message: Optional error message
        
        Returns:
            Updated call or None
        """
        call = await self.get_call(call_id)
        if not call:
            logger.warning(f"Call {call_id} not found")
            return None
        
        call.status = status
        
        if error_message:
            call.error_message = error_message
        
        # Set end time for terminal statuses
        if status in [CallStatus.COMPLETED, CallStatus.FAILED, 
                      CallStatus.NO_ANSWER, CallStatus.BUSY,
                      CallStatus.USER_HANGUP, CallStatus.BOT_HANGUP]:
            if not call.end_time:
                call.end_time = datetime.utcnow()
                # Calculate duration
                if call.start_time:
                    call.duration = int((call.end_time - call.start_time).total_seconds())
        
        await self.db.commit()
        
        logger.info(f"Call {call_id} status updated to {status}")
        
        return call
    
    async def add_message(
        self,
        call_id: uuid.UUID,
        role: MessageRole,
        text: str,
        audio_duration: Optional[float] = None
    ) -> Message:
        """
        Add message to call conversation
        
        Args:
            call_id: Call UUID
            role: Message role (user/bot/system)
            text: Message text
            audio_duration: Optional audio duration
        
        Returns:
            Message object
        """
        message = Message(
            id=uuid.uuid4(),
            call_id=call_id,
            role=role,
            text=text,
            audio_duration=audio_duration,
            timestamp=datetime.utcnow()
        )
        
        self.db.add(message)
        await self.db.commit()
        
        logger.debug(f"Added {role} message to call {call_id}: {text[:50]}")
        
        return message
    
    async def get_call_messages(self, call_id: uuid.UUID) -> List[Message]:
        """
        Get all messages for a call
        
        Args:
            call_id: Call UUID
        
        Returns:
            List of messages
        """
        result = await self.db.execute(
            select(Message)
            .where(Message.call_id == call_id)
            .order_by(Message.timestamp)
        )
        return list(result.scalars().all())
    
    async def list_calls(
        self,
        status: Optional[CallStatus] = None,
        phone: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> tuple[List[Call], int]:
        """
        List calls with filters
        
        Args:
            status: Filter by status
            phone: Filter by phone
            limit: Max results
            offset: Offset for pagination
        
        Returns:
            Tuple of (calls list, total count)
        """
        # Build query
        query = select(Call)
        conditions = []
        
        if status:
            conditions.append(Call.status == status)
        
        if phone:
            conditions.append(Call.phone == phone)
        
        if conditions:
            query = query.where(and_(*conditions))
        
        # Get total count
        count_result = await self.db.execute(
            select(Call).where(and_(*conditions)) if conditions else select(Call)
        )
        total = len(list(count_result.scalars().all()))
        
        # Get paginated results
        query = query.order_by(Call.start_time.desc()).limit(limit).offset(offset)
        result = await self.db.execute(query)
        calls = list(result.scalars().all())
        
        return calls, total
    
    async def hangup_call(self, call_id: uuid.UUID) -> Optional[Call]:
        """
        Hangup an active call
        
        Args:
            call_id: Call UUID
        
        Returns:
            Updated call or None
        """
        call = await self.get_call(call_id)
        if not call:
            return None
        
        # Hangup via Asterisk if we have channel ID
        if call.asterisk_channel_id and self.asterisk_handler:
            try:
                await self.asterisk_handler.hangup_call(call.asterisk_channel_id)
            except Exception as e:
                logger.error(f"Failed to hangup call via Asterisk: {e}")
        
        # Fallback to NovoFon API
        elif call.novofon_call_id and self.novofon:
            try:
                await self.novofon.hangup_call(call.novofon_call_id)
            except NovoFonAPIError as e:
                logger.error(f"Failed to hangup call via NovoFon: {e}")
        
        # Update status
        await self.update_call_status(
            call_id=call_id,
            status=CallStatus.BOT_HANGUP
        )
        
        # Add system message
        await self.add_message(
            call_id=call_id,
            role=MessageRole.SYSTEM,
            text="Call hung up by bot"
        )
        
        return call

