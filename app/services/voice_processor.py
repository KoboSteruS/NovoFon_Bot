"""
Voice processor - bridges Asterisk RTP audio with ElevenLabs ASR/TTS
"""
import asyncio
from typing import Optional, Callable
from loguru import logger
from io import BytesIO

from app.services.elevenlabs_client import (
    ElevenLabsASRClient,
    ElevenLabsTTSClient,
    AudioConverter,
    get_asr_client,
    get_tts_client
)


class VoiceProcessor:
    """
    Processes voice in real-time:
    - Receives RTP audio from Asterisk
    - Sends to ElevenLabs ASR
    - Gets TTS from ElevenLabs
    - Sends back to Asterisk
    """
    
    def __init__(
        self,
        channel_id: str,
        on_transcript: Optional[Callable] = None,
        on_final_transcript: Optional[Callable] = None
    ):
        """
        Initialize voice processor
        
        Args:
            channel_id: Asterisk channel ID
            on_transcript: Callback for partial transcripts
            on_final_transcript: Callback for final transcripts
        """
        self.channel_id = channel_id
        self.on_transcript = on_transcript
        self.on_final_transcript = on_final_transcript
        
        # Clients
        self.asr_client = get_asr_client()
        self.tts_client = get_tts_client()
        
        # Audio buffers
        self.input_buffer = BytesIO()
        self.output_buffer = BytesIO()
        
        # State
        self.is_running = False
        self._processing_task: Optional[asyncio.Task] = None
        
        logger.info(f"Voice processor initialized for channel {channel_id}")
    
    async def start(self):
        """Start voice processing"""
        if self.is_running:
            logger.warning("Voice processor already running")
            return
        
        self.is_running = True
        
        try:
            # Connect ASR
            await self.asr_client.connect()
            
            # Set up callbacks
            self.asr_client.on_final_transcript = self._handle_transcript
            
            # Start processing loop
            self._processing_task = asyncio.create_task(self._processing_loop())
            
            logger.info("Voice processing started")
        
        except Exception as e:
            logger.error(f"Failed to start voice processing: {e}")
            self.is_running = False
            raise
    
    async def stop(self):
        """Stop voice processing"""
        if not self.is_running:
            return
        
        self.is_running = False
        
        # Stop processing task
        if self._processing_task:
            self._processing_task.cancel()
            try:
                await self._processing_task
            except asyncio.CancelledError:
                pass
        
        # Disconnect ASR
        await self.asr_client.disconnect()
        
        logger.info("Voice processing stopped")
    
    async def _processing_loop(self):
        """Main processing loop"""
        try:
            while self.is_running:
                # Process audio from buffer
                if self.input_buffer.tell() > 0:
                    # Get audio from buffer
                    self.input_buffer.seek(0)
                    audio_chunk = self.input_buffer.read()
                    self.input_buffer = BytesIO()  # Reset buffer
                    
                    # Send to ASR
                    try:
                        await self.asr_client.send_audio(audio_chunk)
                    except Exception as e:
                        logger.error(f"Failed to send audio to ASR: {e}")
                
                # Small delay to avoid busy loop
                await asyncio.sleep(0.01)
        
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Error in processing loop: {e}", exc_info=True)
    
    async def receive_rtp_audio(self, audio_data: bytes, codec: str = "pcmu"):
        """
        Receive audio from RTP stream (from Asterisk)
        
        Args:
            audio_data: Raw audio data from RTP
            codec: Audio codec (pcmu, pcma, l16)
        """
        if not self.is_running:
            return
        
        try:
            # Convert codec to PCM16 if needed
            if codec == "pcmu":
                pcm_data = AudioConverter.pcmu_to_pcm16(audio_data)
            elif codec == "pcma":
                # TODO: Add PCMA support
                logger.warning("PCMA codec not yet supported")
                return
            elif codec == "l16":
                pcm_data = audio_data  # Already PCM16
            else:
                logger.warning(f"Unsupported codec: {codec}")
                return
            
            # Resample if needed (RTP is usually 8kHz, ElevenLabs prefers 16kHz)
            pcm_16khz = AudioConverter.resample(pcm_data, 8000, 16000)
            
            # Add to buffer
            self.input_buffer.write(pcm_16khz)
        
        except Exception as e:
            logger.error(f"Error processing RTP audio: {e}", exc_info=True)
    
    async def _handle_transcript(self, text: str):
        """
        Handle final transcript from ASR
        
        Args:
            text: Transcribed text
        """
        logger.info(f"Transcript: {text}")
        
        # Call user callback
        if self.on_final_transcript:
            try:
                await self.on_final_transcript(text)
            except Exception as e:
                logger.error(f"Error in transcript callback: {e}", exc_info=True)
    
    async def speak(self, text: str, streaming: bool = True):
        """
        Convert text to speech and send to Asterisk
        
        Args:
            text: Text to speak
            streaming: Use streaming TTS (faster)
        """
        logger.info(f"Speaking: {text}")
        
        try:
            if streaming:
                # Streaming TTS - send chunks as they arrive
                async for audio_chunk in self.tts_client.text_to_speech_stream(
                    text,
                    output_format="pcm_16000"
                ):
                    # Resample to 8kHz for RTP
                    audio_8khz = AudioConverter.resample(audio_chunk, 16000, 8000)
                    
                    # Convert to PCMU for RTP
                    pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                    
                    # TODO: Send to Asterisk RTP
                    # This will be implemented when we integrate with Asterisk audio streaming
                    self.output_buffer.write(pcmu_data)
            
            else:
                # Non-streaming TTS - wait for complete audio
                audio_data = await self.tts_client.text_to_speech(
                    text,
                    output_format="pcm_16000"
                )
                
                # Resample to 8kHz
                audio_8khz = AudioConverter.resample(audio_data, 16000, 8000)
                
                # Convert to PCMU
                pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                
                # TODO: Send to Asterisk RTP
                self.output_buffer.write(pcmu_data)
            
            logger.info("Speech playback queued")
        
        except Exception as e:
            logger.error(f"Error in TTS: {e}", exc_info=True)
    
    def get_output_audio(self) -> Optional[bytes]:
        """
        Get audio to send to RTP (for Asterisk)
        
        Returns:
            Audio data or None
        """
        if self.output_buffer.tell() > 0:
            self.output_buffer.seek(0)
            audio_data = self.output_buffer.read()
            self.output_buffer = BytesIO()  # Reset buffer
            return audio_data
        return None


class VoiceProcessorManager:
    """
    Manages multiple voice processors (one per call)
    """
    
    def __init__(self):
        self.processors: dict[str, VoiceProcessor] = {}
        logger.info("Voice processor manager initialized")
    
    async def create_processor(
        self,
        channel_id: str,
        on_transcript: Optional[Callable] = None,
        on_final_transcript: Optional[Callable] = None
    ) -> VoiceProcessor:
        """
        Create and start a voice processor for a channel
        
        Args:
            channel_id: Asterisk channel ID
            on_transcript: Callback for partial transcripts
            on_final_transcript: Callback for final transcripts
        
        Returns:
            VoiceProcessor instance
        """
        if channel_id in self.processors:
            logger.warning(f"Processor for {channel_id} already exists")
            return self.processors[channel_id]
        
        processor = VoiceProcessor(
            channel_id,
            on_transcript=on_transcript,
            on_final_transcript=on_final_transcript
        )
        
        await processor.start()
        self.processors[channel_id] = processor
        
        logger.info(f"Created voice processor for {channel_id}")
        return processor
    
    async def remove_processor(self, channel_id: str):
        """
        Stop and remove a voice processor
        
        Args:
            channel_id: Asterisk channel ID
        """
        processor = self.processors.pop(channel_id, None)
        if processor:
            await processor.stop()
            logger.info(f"Removed voice processor for {channel_id}")
    
    def get_processor(self, channel_id: str) -> Optional[VoiceProcessor]:
        """Get processor for a channel"""
        return self.processors.get(channel_id)
    
    async def stop_all(self):
        """Stop all processors"""
        for channel_id in list(self.processors.keys()):
            await self.remove_processor(channel_id)
        logger.info("All voice processors stopped")


# Global manager
voice_manager: Optional[VoiceProcessorManager] = None


def get_voice_manager() -> VoiceProcessorManager:
    """Get or create voice processor manager"""
    global voice_manager
    if voice_manager is None:
        voice_manager = VoiceProcessorManager()
    return voice_manager

