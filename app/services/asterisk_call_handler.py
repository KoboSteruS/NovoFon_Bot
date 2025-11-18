"""
Asterisk call handler - manages call flow through ARI
"""
import uuid
from typing import Dict, Optional
from loguru import logger

from app.services.asterisk_ari import AsteriskARIClient
# from app.services.call_manager import CallManager  # Removed to avoid circular import
from app.services.voice_processor import get_voice_manager, VoiceProcessor
from app.services.dialogue_fsm import DialogueFSM, DialogueState
from app.models import CallStatus, MessageRole


class AsteriskCallHandler:
    """
    Handles call flow through Asterisk ARI
    
    Responsibilities:
    - Listen to ARI events
    - Manage call states
    - Handle audio streaming
    - Integrate with CallManager
    """
    
    def __init__(self, ari_client: AsteriskARIClient):
        """
        Initialize call handler
        
        Args:
            ari_client: Asterisk ARI client
        """
        self.ari = ari_client
        self.active_channels: Dict[str, uuid.UUID] = {}  # channel_id -> call_id mapping
        self.voice_manager = get_voice_manager()
        self.fsm_instances: Dict[str, DialogueFSM] = {}  # channel_id -> FSM mapping
        
        # Register event handlers
        self._register_handlers()
        
        logger.info("Asterisk call handler initialized")
    
    def _register_handlers(self):
        """Register ARI event handlers"""
        
        @self.ari.on_event('StasisStart')
        async def handle_stasis_start(event):
            """Handle call entering Stasis application"""
            await self._on_stasis_start(event)
        
        @self.ari.on_event('StasisEnd')
        async def handle_stasis_end(event):
            """Handle call leaving Stasis application"""
            await self._on_stasis_end(event)
        
        @self.ari.on_event('ChannelStateChange')
        async def handle_state_change(event):
            """Handle channel state changes"""
            await self._on_channel_state_change(event)
        
        @self.ari.on_event('ChannelDtmfReceived')
        async def handle_dtmf(event):
            """Handle DTMF (key press) events"""
            await self._on_dtmf_received(event)
        
        @self.ari.on_event('ChannelHangupRequest')
        async def handle_hangup_request(event):
            """Handle hangup request"""
            await self._on_hangup_request(event)
    
    async def _on_stasis_start(self, event: Dict):
        """
        Handle StasisStart event - call entered our application
        
        Args:
            event: ARI event data
        """
        channel = event.get('channel', {})
        channel_id = channel.get('id')
        caller_number = channel.get('caller', {}).get('number')
        args = event.get('args', [])
        
        logger.info(f"Stasis start: {channel_id}, caller: {caller_number}, args: {args}")
        
        # Determine call direction
        direction = args[0] if args else 'unknown'
        
        if direction == 'incoming':
            # Incoming call from NovoFon
            await self._handle_incoming_call(channel_id, caller_number)
        
        elif direction == 'outgoing':
            # Outgoing call through NovoFon
            destination = args[1] if len(args) > 1 else None
            await self._handle_outgoing_call(channel_id, destination)
        
        else:
            logger.warning(f"Unknown call direction: {direction}")
    
    async def _handle_incoming_call(self, channel_id: str, caller_number: str):
        """
        Handle incoming call from NovoFon
        
        Args:
            channel_id: Asterisk channel ID
            caller_number: Caller's phone number
        """
        logger.info(f"Handling incoming call from {caller_number}")
        
        try:
            # Answer the call
            await self.ari.answer_channel(channel_id)
            
            # Create call record in database
            # Note: CallManager is imported lazily to avoid circular import
            # For now, we'll create a minimal call record
            call_id = uuid.uuid4()
            self.active_channels[channel_id] = call_id
            
            # Create FSM for this call
            fsm = DialogueFSM()
            self.fsm_instances[channel_id] = fsm
            
            # Create voice processor for this call
            processor = await self.voice_manager.create_processor(
                channel_id=channel_id,
                on_final_transcript=lambda text: self._handle_user_speech(channel_id, text)
            )
            
            # Start dialogue - FSM will handle greeting
            greeting = fsm.process_user_input("", None)  # Empty input to get initial greeting
            await processor.speak(greeting)
            
            logger.info(f"Incoming call answered: {channel_id}, call_id: {call_id}")
        
        except Exception as e:
            logger.error(f"Error handling incoming call: {e}", exc_info=True)
            await self.ari.hangup_channel(channel_id)
    
    async def _handle_outgoing_call(self, channel_id: str, destination: Optional[str]):
        """
        Handle outgoing call through NovoFon
        
        Args:
            channel_id: Asterisk channel ID
            destination: Destination phone number
        """
        logger.info(f"Handling outgoing call to {destination}")
        
        try:
            # TODO: Find call record in database
            # TODO: Wait for answer
            # TODO: Start ASR/TTS engine
            # TODO: Begin dialogue
            
            logger.info(f"Outgoing call handled: {channel_id}")
        
        except Exception as e:
            logger.error(f"Error handling outgoing call: {e}", exc_info=True)
            await self.ari.hangup_channel(channel_id)
    
    async def _on_stasis_end(self, event: Dict):
        """Handle StasisEnd event - call left our application"""
        channel = event.get('channel', {})
        channel_id = channel.get('id')
        
        logger.info(f"Stasis end: {channel_id}")
        
        # Stop voice processor
        await self.voice_manager.remove_processor(channel_id)
        
        # Get FSM results
        fsm = self.fsm_instances.pop(channel_id, None)
        if fsm:
            call_result = fsm.get_call_result()
            logger.info(f"Call result: {call_result}")
            # TODO: Save to database
        
        # Clean up
        if channel_id in self.active_channels:
            call_id = self.active_channels.pop(channel_id)
            logger.info(f"Call {call_id} ended, channel {channel_id} removed")
            
            # TODO: Update call record in database with result
    
    async def _on_channel_state_change(self, event: Dict):
        """Handle channel state change"""
        channel = event.get('channel', {})
        channel_id = channel.get('id')
        state = channel.get('state')
        
        logger.debug(f"Channel {channel_id} state: {state}")
        
        # TODO: Update call status in database based on state
        # States: Down, Rsrved, OffHook, Dialing, Ring, Ringing, Up, Busy, etc.
    
    async def _on_dtmf_received(self, event: Dict):
        """Handle DTMF digit received"""
        digit = event.get('digit')
        channel = event.get('channel', {})
        channel_id = channel.get('id')
        
        logger.info(f"DTMF received on {channel_id}: {digit}")
        
        # TODO: Handle DTMF input (e.g., menu navigation)
    
    async def _on_hangup_request(self, event: Dict):
        """Handle hangup request"""
        channel = event.get('channel', {})
        channel_id = channel.get('id')
        cause = event.get('cause')
        
        logger.info(f"Hangup request for {channel_id}, cause: {cause}")
    
    async def initiate_call(
        self,
        phone_number: str,
        call_id: uuid.UUID
    ) -> str:
        """
        Initiate outbound call through Asterisk
        
        Args:
            phone_number: Destination phone number
            call_id: Call UUID from database
        
        Returns:
            Channel ID
        """
        logger.info(f"Initiating outbound call to {phone_number} for call {call_id}")
        
        # Format endpoint for NovoFon SIP trunk
        # Example: PJSIP/79991234567@novofon
        endpoint = f"PJSIP/{phone_number.lstrip('+')}@novofon"
        
        try:
            channel = await self.ari.originate_call(
                endpoint=endpoint,
                variables={
                    'CALL_ID': str(call_id)
                }
            )
            
            channel_id = channel.get('id')
            self.active_channels[channel_id] = call_id
            
            logger.info(f"Call originated: channel {channel_id}, call {call_id}")
            
            return channel_id
        
        except Exception as e:
            logger.error(f"Failed to initiate call: {e}", exc_info=True)
            raise
    
    async def hangup_call(self, channel_id: str):
        """
        Hangup active call
        
        Args:
            channel_id: Asterisk channel ID
        """
        logger.info(f"Hanging up call: {channel_id}")
        
        try:
            await self.ari.hangup_channel(channel_id)
            
            if channel_id in self.active_channels:
                self.active_channels.pop(channel_id)
        
        except Exception as e:
            logger.error(f"Error hanging up call: {e}")
    
    async def play_audio(self, channel_id: str, audio_data: bytes):
        """
        Play audio on channel (TTS output)
        
        Args:
            channel_id: Asterisk channel ID
            audio_data: Audio data to play
        """
        # TODO: Implement audio streaming to channel
        # This will be implemented when we add TTS integration
        pass
    
    async def start_audio_stream(self, channel_id: str):
        """
        Start receiving audio stream from channel (for ASR)
        
        Args:
            channel_id: Asterisk channel ID
        """
        # Audio streaming is handled by voice processor
        processor = self.voice_manager.get_processor(channel_id)
        if processor:
            logger.info(f"Audio streaming active for {channel_id}")
        else:
            logger.warning(f"No voice processor for {channel_id}")
    
    async def _handle_user_speech(self, channel_id: str, text: str):
        """
        Handle transcribed user speech
        
        Args:
            channel_id: Asterisk channel ID
            text: Transcribed text
        """
        logger.info(f"User said ({channel_id}): {text}")
        
        # Get FSM for this call
        fsm = self.fsm_instances.get(channel_id)
        if not fsm:
            logger.warning(f"No FSM found for channel {channel_id}")
            return
        
        # Process through FSM
        response = fsm.process_user_input(text)
        
        # Speak response
        processor = self.voice_manager.get_processor(channel_id)
        if processor and response:
            await processor.speak(response)
        
        # Check if dialogue ended
        if fsm.state == DialogueState.END:
            logger.info(f"Dialogue ended for {channel_id}, hanging up")
            await self.hangup_call(channel_id)


# Global handler instance
call_handler: Optional[AsteriskCallHandler] = None


def get_call_handler(ari_client: AsteriskARIClient) -> AsteriskCallHandler:
    """Get or create call handler instance"""
    global call_handler
    if call_handler is None:
        call_handler = AsteriskCallHandler(ari_client)
    return call_handler

