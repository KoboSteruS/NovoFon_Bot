"""
Voice processor - bridges Asterisk RTP audio with ElevenLabs ASR/TTS
"""
import asyncio
import tempfile
import os
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
        on_final_transcript: Optional[Callable] = None,
        ari_client = None  # Asterisk ARI client для отправки аудио
    ):
        """
        Initialize voice processor
        
        Args:
            channel_id: Asterisk channel ID
            on_transcript: Callback for partial transcripts
            on_final_transcript: Callback for final transcripts
            ari_client: Asterisk ARI client для отправки аудио
        """
        self.channel_id = channel_id
        self.on_transcript = on_transcript
        self.on_final_transcript = on_final_transcript
        self.ari_client = ari_client
        
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
            logger.info(f"Connecting to ElevenLabs ASR for channel {self.channel_id}...")
            await self.asr_client.connect()
            logger.info(f"✅ ElevenLabs ASR connected for channel {self.channel_id}")
            
            # Set up callbacks
            self.asr_client.on_final_transcript = self._handle_transcript
            logger.info(f"Callbacks set up for channel {self.channel_id}")
            
            # Start processing loop
            self._processing_task = asyncio.create_task(self._processing_loop())
            
            logger.info(f"✅ Voice processing started for channel {self.channel_id}")
        
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
        logger.info(f"=== SPEAK ===")
        logger.info(f"Channel: {self.channel_id}")
        logger.info(f"Text: {text}")
        logger.info(f"Streaming: {streaming}")
        
        try:
            # Пробуем запросить pcm_8000 напрямую от ElevenLabs
            # Если не поддерживается - используем pcm_16000 и ресемплим
            output_format = "pcm_8000"  # Попробуем запросить 8kHz напрямую
            use_8khz_direct = True
            
            if streaming:
                # Streaming TTS - send chunks as they arrive
                try:
                    audio_chunks = []
                    async for audio_chunk in self.tts_client.text_to_speech_stream(
                        text,
                        output_format=output_format
                    ):
                        audio_chunks.append(audio_chunk)
                    
                    # Объединяем все чанки
                    if audio_chunks:
                        full_audio = b''.join(audio_chunks)
                    else:
                        raise ValueError("No audio chunks received")
                        
                except Exception as e:
                    # Если pcm_8000 не поддерживается - используем pcm_16000
                    logger.warning(f"Failed to get pcm_8000, falling back to pcm_16000: {e}")
                    output_format = "pcm_16000"
                    use_8khz_direct = False
                    
                    audio_chunks = []
                    async for audio_chunk in self.tts_client.text_to_speech_stream(
                        text,
                        output_format=output_format
                    ):
                        audio_chunks.append(audio_chunk)
                    
                    full_audio = b''.join(audio_chunks) if audio_chunks else b''
                
                if full_audio:
                    # Конвертируем в PCMU
                    if use_8khz_direct and output_format == "pcm_8000":
                        # Прямо в PCMU (8kHz PCM16 -> PCMU)
                        # Убеждаемся, что размер кратен 2 байтам (16-bit)
                        if len(full_audio) % 2 != 0:
                            full_audio = full_audio[:-1]
                        pcmu_data = AudioConverter.pcm16_to_pcmu(full_audio)
                    else:
                        # Ресемплим с 16kHz на 8kHz
                        # Убеждаемся, что размер кратен 2 байтам (16-bit)
                        if len(full_audio) % 2 != 0:
                            full_audio = full_audio[:-1]
                        audio_8khz = AudioConverter.resample(full_audio, 16000, 8000)
                        pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                    
                    # Отправляем в Asterisk через ARI
                    await self._send_audio_to_asterisk(pcmu_data)
            
            else:
                # Non-streaming TTS - wait for complete audio
                try:
                    audio_data = await self.tts_client.text_to_speech(
                        text,
                        output_format=output_format
                    )
                except Exception as e:
                    # Если pcm_8000 не поддерживается - используем pcm_16000
                    logger.warning(f"Failed to get pcm_8000, falling back to pcm_16000: {e}")
                    output_format = "pcm_16000"
                    use_8khz_direct = False
                    audio_data = await self.tts_client.text_to_speech(
                        text,
                        output_format=output_format
                    )
                
                # Конвертируем в PCMU
                if use_8khz_direct and output_format == "pcm_8000":
                    # Прямо в PCMU (8kHz PCM16 -> PCMU)
                    # Убеждаемся, что размер кратен 2 байтам (16-bit)
                    if len(audio_data) % 2 != 0:
                        audio_data = audio_data[:-1]
                    pcmu_data = AudioConverter.pcm16_to_pcmu(audio_data)
                else:
                    # Ресемплим с 16kHz на 8kHz
                    # Убеждаемся, что размер кратен 2 байтам (16-bit)
                    if len(audio_data) % 2 != 0:
                        audio_data = audio_data[:-1]
                    audio_8khz = AudioConverter.resample(audio_data, 16000, 8000)
                    pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                
                # Отправляем в Asterisk через ARI
                await self._send_audio_to_asterisk(pcmu_data)
            
            logger.info("✅ Speech sent to Asterisk")
        
        except Exception as e:
            logger.error(f"Error in TTS: {e}", exc_info=True)
    
    async def _send_audio_to_asterisk(self, pcmu_data: bytes):
        """
        Send PCMU audio to Asterisk channel through ARI
        
        Args:
            pcmu_data: PCMU (μ-law) encoded audio data (8kHz)
        """
        if not self.ari_client:
            logger.warning("ARI client not available, cannot send audio to Asterisk")
            return
        
        try:
            # Создаем временный WAV файл с PCMU аудио
            # Asterisk понимает WAV файлы с PCMU кодеком
            import struct
            import wave
            
            # Создаем временный файл
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                wav_path = tmp_file.name
                
                # Создаем WAV файл с PCMU
                # WAV header для PCMU (μ-law) 8kHz mono
                sample_rate = 8000
                num_channels = 1
                sample_width = 1  # PCMU = 1 byte per sample
                num_frames = len(pcmu_data)
                
                # WAV header
                wav_file = wave.open(wav_path, 'wb')
                wav_file.setnchannels(num_channels)
                wav_file.setsampwidth(sample_width)
                wav_file.setframerate(sample_rate)
                wav_file.setcomptype('ULAW', 'ulaw')  # PCMU codec
                wav_file.writeframes(pcmu_data)
                wav_file.close()
                
                logger.info(f"Created temporary WAV file: {wav_path} ({len(pcmu_data)} bytes PCMU)")
            
            # Отправляем в Asterisk через ARI channels.play
            # Используем file:// URI для локального файла
            # Asterisk ARI channels.play поддерживает file:// URI
            media_uri = f"file://{wav_path}"
            
            logger.info(f"Sending audio to Asterisk: {media_uri} ({len(pcmu_data)} bytes)")
            await self.ari_client.play_media(
                channel_id=self.channel_id,
                media=media_uri
            )
            logger.info(f"✅ Audio sent to Asterisk channel {self.channel_id}")
            
            # Удаляем временный файл после небольшой задержки
            # (даем время Asterisk прочитать файл)
            async def cleanup():
                await asyncio.sleep(5)  # Ждем 5 секунд
                try:
                    if os.path.exists(wav_path):
                        os.unlink(wav_path)
                        logger.debug(f"Cleaned up temporary file: {wav_path}")
                except Exception as e:
                    logger.warning(f"Failed to cleanup temp file: {e}")
            
            asyncio.create_task(cleanup())
            
        except Exception as e:
            logger.error(f"Failed to send audio to Asterisk: {e}", exc_info=True)
    
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
            on_final_transcript=on_final_transcript,
            ari_client=ari_client
        )
        
        logger.info(f"Starting voice processor for channel {channel_id}...")
        await processor.start()
        self.processors[channel_id] = processor
        
        logger.info(f"✅ Voice processor created and started for channel {channel_id}")
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

