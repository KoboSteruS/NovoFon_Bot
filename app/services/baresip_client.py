"""
Baresip ctrl_tcp client for SIP+RTP handling
"""
import asyncio
import json
from typing import Optional, Callable, Dict, Any
from loguru import logger

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
    Baresip ctrl_tcp client for real-time SIP+RTP handling
    
    Manages:
    - Incoming calls from Asterisk
    - RTP audio streaming
    - Integration with ElevenLabs ASR/TTS
    """
    
    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 4444,
        on_call_started: Optional[Callable] = None,
        on_call_ended: Optional[Callable] = None
    ):
        """
        Initialize baresip client
        
        Args:
            host: Baresip ctrl_tcp host
            port: Baresip ctrl_tcp port (default 4444)
            on_call_started: Callback when call starts
            on_call_ended: Callback when call ends
        """
        self.host = host
        self.port = port
        self.on_call_started = on_call_started
        self.on_call_ended = on_call_ended
        
        self.reader: Optional[asyncio.StreamReader] = None
        self.writer: Optional[asyncio.StreamWriter] = None
        self.is_connected = False
        self.current_call_id: Optional[str] = None
        
        # ElevenLabs clients
        self.asr_client: Optional[ElevenLabsASRClient] = None
        self.tts_client: Optional[ElevenLabsTTSClient] = None
        self.audio_converter = AudioConverter()
        
        # State
        self._reader_task: Optional[asyncio.Task] = None
        self._asr_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        
        logger.info(f"Baresip client initialized (TCP: {host}:{port})")
    
    async def connect(self):
        """Connect to baresip ctrl_tcp"""
        try:
            logger.info(f"🔌 Подключение к baresip ctrl_tcp: {self.host}:{self.port}")
            self.reader, self.writer = await asyncio.open_connection(
                self.host,
                self.port
            )
            self.is_connected = True
            logger.info(f"✅ Подключено к baresip ctrl_tcp ({self.host}:{self.port})")
            
            # Start reader task
            self._reader_task = asyncio.create_task(self._reader())
            
        except ConnectionRefusedError:
            logger.error(f"❌ Baresip недоступен: соединение отклонено ({self.host}:{self.port})")
            self.is_connected = False
            raise BaresipError(f"Connection refused: baresip не запущен или порт {self.port} закрыт")
        except Exception as e:
            logger.error(f"❌ Ошибка подключения к baresip: {e}")
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
        
        if self.writer:
            self.writer.close()
            try:
                await self.writer.wait_closed()
            except Exception:
                pass
        
        self.is_connected = False
        logger.info("🔌 Отключено от baresip")
    
    async def _reader(self):
        """Read messages from baresip ctrl_tcp"""
        try:
            buffer = ""
            while self.is_connected:
                try:
                    # Read data (up to 64KB)
                    data = await asyncio.wait_for(
                        self.reader.read(65536),
                        timeout=1.0
                    )
                    
                    if not data:
                        logger.warning("Baresip ctrl_tcp connection closed")
                        self.is_connected = False
                        break
                    
                    # Decode and add to buffer
                    buffer += data.decode('utf-8', errors='ignore')
                    
                    # Process complete JSON messages (separated by \n)
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        line = line.strip()
                        
                        if not line:
                            continue
                        
                        try:
                            event = json.loads(line)
                            await self._handle_event(event)
                        except json.JSONDecodeError:
                            # Игнорируем не-JSON сообщения (могут быть системные)
                            pass
                        except Exception as e:
                            logger.error(f"❌ Ошибка обработки события baresip: {e}", exc_info=True)
                
                except asyncio.TimeoutError:
                    # Timeout is OK, just continue reading
                    continue
                except Exception as e:
                    logger.error(f"❌ Ошибка чтения из baresip: {e}", exc_info=True)
                    self.is_connected = False
                    break
        
        except Exception as e:
            logger.error(f"❌ Критическая ошибка reader: {e}", exc_info=True)
            self.is_connected = False
    
    async def _send_command(self, command: str, *args: str) -> Optional[Dict[str, Any]]:
        """
        Send command to baresip via ctrl_tcp
        
        Args:
            command: Command name (e.g., "call_answer", "call_hangup")
            *args: Command arguments
            
        Returns:
            Response from baresip (if any)
        """
        if not self.is_connected or not self.writer:
            raise BaresipError("Not connected to baresip")
        
        async with self._lock:
            try:
                # Format command: "command arg1 arg2 ...\n"
                cmd_line = f"{command} {' '.join(str(arg) for arg in args)}\n"
                
                # Send command
                self.writer.write(cmd_line.encode('utf-8'))
                await self.writer.drain()
                
                # Note: ctrl_tcp may not always send immediate response
                # Events will come through _reader
                return None
            
            except Exception as e:
                logger.error(f"❌ Ошибка отправки команды {command}: {e}")
                raise BaresipError(f"Command failed: {e}")
    
    async def _handle_event(self, event: Dict[str, Any]):
        """Handle event from baresip"""
        # Baresip ctrl_tcp events can come in different formats
        # Try to detect event type from various possible fields
        
        event_type = None
        call_id = None
        
        # Check for different event formats
        if "type" in event:
            event_type = event["type"]
        elif "event" in event:
            event_type = event["event"]
        elif "message" in event:
            # Some events come as messages
            msg = event["message"]
            logger.debug(f"Baresip message: {msg}")
            return
        
        # Extract call ID
        if "callid" in event:
            call_id = event["callid"]
        elif "call_id" in event:
            call_id = event["call_id"]
        elif "id" in event:
            call_id = event["id"]
        
        # Handle different event types
        if "call" in str(event_type).lower() and "incoming" in str(event).lower():
            # Incoming call detected
            logger.info(f"📞 Входящий звонок: {self.current_call_id}")
            self.current_call_id = call_id or "default"
            
            # Accept call
            await self.accept_call(self.current_call_id)
            
            # Start ASR
            await self._start_asr()
            
            if self.on_call_started:
                await self.on_call_started(self.current_call_id)
        
        elif "call" in str(event_type).lower() and "established" in str(event).lower():
            logger.info(f"✅ Звонок установлен: {call_id or self.current_call_id}")
        
        elif "call" in str(event_type).lower() and ("end" in str(event_type).lower() or "hangup" in str(event_type).lower()):
            ended_call_id = call_id or self.current_call_id
            logger.info(f"📴 Звонок завершён: {ended_call_id}")
            
            # Stop ASR
            if self.asr_client and self.asr_client.is_connected:
                await self.asr_client.disconnect()
            
            if call_id == self.current_call_id or not call_id:
                self.current_call_id = None
            
            if self.on_call_ended:
                await self.on_call_ended(ended_call_id)
        
        elif "audio" in str(event_type).lower() or "rtp" in str(event_type).lower():
            # RTP audio event
            await self._handle_rtp_event(event, call_id)
        
        else:
            # Log unhandled events for debugging
            logger.debug(f"Unhandled baresip event: {event}")
    
    async def _handle_rtp_event(self, event: Dict[str, Any], call_id: Optional[str]):
        """Handle RTP audio event"""
        if call_id != self.current_call_id and self.current_call_id:
            return
        
        try:
            # Try to extract audio data
            data_hex = event.get("data", "") or event.get("payload", "")
            
            if data_hex:
                # Convert hex to bytes
                pcmu_data = bytes.fromhex(data_hex)
                
                # Convert PCMU to PCM16 for ElevenLabs
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
            logger.debug(f"Ошибка обработки RTP: {e}")
    
    async def accept_call(self, call_id: str):
        """Accept incoming call"""
        if not self.is_connected:
            raise BaresipError("Not connected to baresip")
        
        try:
            # Baresip ctrl_tcp command: call_answer <callid>
            await self._send_command("call_answer", call_id)
            logger.info(f"✅ Звонок принят: {call_id}")
        
        except Exception as e:
            logger.error(f"❌ Ошибка принятия звонка {call_id}: {e}")
            raise
    
    async def hangup_call(self, call_id: Optional[str] = None):
        """Hangup call"""
        if not self.is_connected:
            return
        
        call_id = call_id or self.current_call_id
        if not call_id:
            return
        
        try:
            # Baresip ctrl_tcp command: call_hangup <callid>
            await self._send_command("call_hangup", call_id)
            logger.info(f"📴 Завершение звонка: {call_id}")
            
            if call_id == self.current_call_id:
                self.current_call_id = None
        
        except Exception as e:
            logger.error(f"❌ Ошибка завершения звонка {call_id}: {e}")
    
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
            
            logger.info(f"🎤 ASR запущен для звонка: {self.current_call_id}")
        
        except Exception as e:
            logger.error(f"❌ Ошибка запуска ASR: {e}", exc_info=True)
    
    async def _on_final_transcript(self, text: str):
        """Handle final transcript from ASR"""
        logger.info(f"👤 Пользователь сказал: {text}")
        
        # Generate TTS and send back
        await self._speak(text)
    
    async def _speak(self, text: str):
        """Generate TTS and send to baresip"""
        if not self.current_call_id:
            logger.warning("⚠️ Нет активного звонка для TTS")
            return
        
        try:
            # Get TTS client
            if not self.tts_client:
                self.tts_client = get_tts_client()
            
            logger.info(f"🔊 Генерация ответа: {text[:60]}{'...' if len(text) > 60 else ''}")
            
            # Request PCM16 16kHz from ElevenLabs
            chunk_count = 0
            async for audio_chunk in self.tts_client.text_to_speech_stream(
                text,
                output_format="pcm_16000"
            ):
                if audio_chunk:
                    # Convert PCM16 16kHz to PCMU 8kHz
                    pcm16_8khz = self.audio_converter.resample_pcm16(
                        audio_chunk,
                        from_rate=16000,
                        to_rate=8000
                    )
                    pcmu_data = self.audio_converter.pcm16_to_pcmu(pcm16_8khz)
                    
                    # Send to baresip
                    await self._send_rtp(pcmu_data)
                    chunk_count += 1
            
            logger.info(f"✅ Ответ отправлен ({chunk_count} аудио блоков)")
        
        except Exception as e:
            logger.error(f"❌ Ошибка генерации TTS: {e}", exc_info=True)
    
    async def _send_rtp(self, pcmu_data: bytes):
        """
        Send RTP audio to baresip
        
        Note: ctrl_tcp doesn't directly support RTP sending.
        This is a placeholder - actual RTP handling may need
        to be done through audio files or other mechanisms.
        """
        if not self.is_connected or not self.current_call_id:
            return
        
        try:
            # Try to send via call_audio_send if available
            # Format: call_audio_send <callid> <hex_data>
            data_hex = pcmu_data.hex()
            await self._send_command("call_audio_send", self.current_call_id, data_hex)
        
        except Exception as e:
            # Alternative: Save to file and play via baresip command
            # This would require file-based approach
            logger.debug(f"RTP отправка через ctrl_tcp не поддерживается: {e}")


def get_baresip_client() -> BaresipClient:
    """
    Get or create baresip client instance
    
    Returns:
        BaresipClient instance
    """
    return BaresipClient(
        host="127.0.0.1",
        port=4444
    )
