"""
Baresip WebSocket client for SIP+RTP handling
"""
import asyncio
import json
from typing import Optional, Callable, Dict, Any
from loguru import logger
import websockets
from websockets.exceptions import ConnectionClosed

from app.services.elevenlabs_client import (
    ElevenLabsASRClient,
    ElevenLabsTTSClient,
    AudioConverter,
    get_asr_client,
    get_tts_client
)


class BaresipError(Exception):
    """Baresip client error"""
    pass


class BaresipClient:
    """
    Baresip WebSocket client for real-time SIP+RTP handling
    
    Manages:
    - Incoming calls from Asterisk
    - RTP audio streaming
    - Integration with ElevenLabs ASR/TTS
    """
    
    def __init__(
        self,
        ws_url: str = "ws://127.0.0.1:8000/ws",
        on_call_started: Optional[Callable] = None,
        on_call_ended: Optional[Callable] = None
    ):
        """
        Initialize baresip client
        
        Args:
            ws_url: Baresip WebSocket URL
            on_call_started: Callback when call starts
            on_call_ended: Callback when call ends
        """
        self.ws_url = ws_url
        self.on_call_started = on_call_started
        self.on_call_ended = on_call_ended
        
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.is_connected = False
        self.current_call_id: Optional[str] = None
        
        # ElevenLabs clients
        self.asr_client: Optional[ElevenLabsASRClient] = None
        self.tts_client: Optional[ElevenLabsTTSClient] = None
        self.audio_converter = AudioConverter()
        
        # State
        self._reader_task: Optional[asyncio.Task] = None
        self._asr_task: Optional[asyncio.Task] = None
        
        logger.info(f"Baresip client initialized (WS: {ws_url})")
    
    async def connect(self):
        """Connect to baresip WebSocket"""
        try:
            logger.info(f"Connecting to baresip WebSocket: {self.ws_url}")
            self.ws = await websockets.connect(self.ws_url)
            self.is_connected = True
            logger.info("✅ Connected to baresip WebSocket")
            
            # Start reader task
            self._reader_task = asyncio.create_task(self._reader())
            
        except Exception as e:
            logger.error(f"Failed to connect to baresip: {e}")
            self.is_connected = False
            raise BaresipError(f"Connection failed: {e}")
    
    async def disconnect(self):
        """Disconnect from baresip"""
        if self._asr_task:
            self._asr_task.cancel()
            try:
                await self._asr_task
            except asyncio.CancelledError:
                pass
        
        if self._reader_task:
            self._reader_task.cancel()
            try:
                await self._reader_task
            except asyncio.CancelledError:
                pass
        
        if self.asr_client and self.asr_client.is_connected:
            await self.asr_client.disconnect()
        
        if self.ws:
            await self.ws.close()
        
        self.is_connected = False
        logger.info("Disconnected from baresip")
    
    async def _reader(self):
        """Read messages from baresip WebSocket"""
        try:
            async for message in self.ws:
                try:
                    event = json.loads(message)
                    await self._handle_event(event)
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON from baresip: {e}")
                except Exception as e:
                    logger.error(f"Error handling baresip event: {e}", exc_info=True)
        
        except ConnectionClosed:
            logger.warning("Baresip WebSocket connection closed")
            self.is_connected = False
        except Exception as e:
            logger.error(f"Reader error: {e}", exc_info=True)
            self.is_connected = False
    
    async def _handle_event(self, event: Dict[str, Any]):
        """Handle event from baresip"""
        event_type = event.get("type")
        
        if event_type == "incoming-call":
            call_id = event.get("callid")
            logger.info(f"📞 Incoming call: {call_id}")
            self.current_call_id = call_id
            
            # Accept call
            await self.accept_call(call_id)
            
            # Start ASR
            await self._start_asr()
            
            if self.on_call_started:
                await self.on_call_started(call_id)
        
        elif event_type == "call-established":
            call_id = event.get("callid")
            logger.info(f"✅ Call established: {call_id}")
        
        elif event_type == "call-ended":
            call_id = event.get("callid")
            logger.info(f"📴 Call ended: {call_id}")
            
            # Stop ASR
            if self.asr_client and self.asr_client.is_connected:
                await self.asr_client.disconnect()
            
            if call_id == self.current_call_id:
                self.current_call_id = None
            
            if self.on_call_ended:
                await self.on_call_ended(call_id)
        
        elif event_type == "rtp-recv":
            # Received RTP audio (PCMU)
            call_id = event.get("callid")
            data_hex = event.get("data", "")
            
            if call_id == self.current_call_id and data_hex:
                try:
                    # Convert hex to bytes
                    pcmu_data = bytes.fromhex(data_hex)
                    
                    # Convert PCMU to PCM16 for ElevenLabs
                    # PCMU is 8kHz, ElevenLabs needs 16kHz
                    pcm16_8khz = self.audio_converter.pcmu_to_pcm16(pcmu_data)
                    pcm16_16khz = self.audio_converter.resample_pcm16(
                        pcm16_8khz,
                        from_rate=8000,
                        to_rate=16000
                    )
                    
                    # Send to ASR
                    if self.asr_client and self.asr_client.is_connected:
                        await self.asr_client.send_audio(pcm16_16khz)
                
                except Exception as e:
                    logger.error(f"Error processing RTP: {e}", exc_info=True)
        
        elif event_type == "asr-final":
            # Final transcript from ASR (if baresip has built-in ASR)
            text = event.get("text", "")
            logger.info(f"User says: {text}")
        
        else:
            logger.debug(f"Unhandled baresip event: {event_type}")
    
    async def accept_call(self, call_id: str):
        """Accept incoming call"""
        if not self.is_connected or not self.ws:
            raise BaresipError("Not connected to baresip")
        
        command = {
            "command": "answer",
            "callid": call_id
        }
        
        await self.ws.send(json.dumps(command))
        logger.info(f"✅ Accepted call: {call_id}")
    
    async def hangup_call(self, call_id: Optional[str] = None):
        """Hangup call"""
        if not self.is_connected or not self.ws:
            return
        
        call_id = call_id or self.current_call_id
        if not call_id:
            return
        
        command = {
            "command": "hangup",
            "callid": call_id
        }
        
        await self.ws.send(json.dumps(command))
        logger.info(f"📴 Hung up call: {call_id}")
        
        if call_id == self.current_call_id:
            self.current_call_id = None
    
    async def _start_asr(self):
        """Start ElevenLabs ASR for current call"""
        if not self.current_call_id:
            return
        
        try:
            # Initialize ASR client
            self.asr_client = get_asr_client()
            
            # Set callbacks
            self.asr_client.on_final_transcript = self._on_final_transcript
            
            # Connect to ElevenLabs
            await self.asr_client.connect()
            
            logger.info("✅ ElevenLabs ASR started")
        
        except Exception as e:
            logger.error(f"Failed to start ASR: {e}", exc_info=True)
    
    async def _on_final_transcript(self, text: str):
        """Handle final transcript from ASR"""
        logger.info(f"🎤 User said: {text}")
        
        # Generate TTS and send back
        await self._speak(text)
    
    async def _speak(self, text: str):
        """Generate TTS and send to baresip"""
        if not self.current_call_id:
            logger.warning("No active call for TTS")
            return
        
        try:
            # Get TTS client
            if not self.tts_client:
                self.tts_client = get_tts_client()
            
            logger.info(f"🔊 Generating TTS: {text[:50]}...")
            
            # Request PCM16 8kHz from ElevenLabs (closest to PCMU)
            async for audio_chunk in self.tts_client.text_to_speech_stream(
                text,
                output_format="pcm_16000"
            ):
                if audio_chunk:
                    # Convert PCM16 16kHz to PCMU 8kHz
                    # First resample to 8kHz, then convert to PCMU
                    pcm16_8khz = self.audio_converter.resample_pcm16(
                        audio_chunk,
                        from_rate=16000,
                        to_rate=8000
                    )
                    pcmu_data = self.audio_converter.pcm16_to_pcmu(pcm16_8khz)
                    
                    # Send to baresip
                    await self._send_rtp(pcmu_data)
            
            logger.info("✅ TTS sent to baresip")
        
        except Exception as e:
            logger.error(f"Error in TTS: {e}", exc_info=True)
    
    async def _send_rtp(self, pcmu_data: bytes):
        """Send RTP audio to baresip"""
        if not self.is_connected or not self.ws or not self.current_call_id:
            return
        
        try:
            command = {
                "command": "rtp-send",
                "callid": self.current_call_id,
                "data": pcmu_data.hex()
            }
            
            await self.ws.send(json.dumps(command))
        
        except Exception as e:
            logger.error(f"Failed to send RTP: {e}")

