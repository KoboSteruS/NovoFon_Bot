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
            # Пробуем запросить pcm_8000 напрямую от ElevenLabs (если поддерживается)
            # Если нет - используем pcm_16000 и ресемплим
            output_format = "pcm_8000"  # Попробуем получить 8kHz напрямую
            use_8khz_direct = True
            
            if streaming:
                # Streaming TTS - накапливаем чанки и обрабатываем
                audio_buffer = bytearray()
                
                try:
                    async for audio_chunk in self.tts_client.text_to_speech_stream(
                        text,
                        output_format=output_format
                    ):
                        if audio_chunk:
                            audio_buffer.extend(audio_chunk)
                            logger.debug(f"Received audio chunk: {len(audio_chunk)} bytes, total: {len(audio_buffer)} bytes")
                    
                    if not audio_buffer:
                        raise ValueError("No audio chunks received")
                    
                    # Конвертируем в bytes и обрабатываем
                    full_audio = bytes(audio_buffer)
                    if use_8khz_direct and output_format == "pcm_8000":
                        logger.info(f"Total audio received: {len(full_audio)} bytes (PCM16, 8kHz)")
                    else:
                        logger.info(f"Total audio received: {len(full_audio)} bytes (PCM16, 16kHz)")
                    
                except Exception as e:
                    logger.error(f"Failed to get TTS audio: {e}", exc_info=True)
                    # Если pcm_8000 не поддерживается - пробуем pcm_16000
                    if use_8khz_direct and output_format == "pcm_8000":
                        logger.warning(f"pcm_8000 not supported, falling back to pcm_16000: {e}")
                        output_format = "pcm_16000"
                        use_8khz_direct = False
                        audio_buffer = bytearray()
                        async for audio_chunk in self.tts_client.text_to_speech_stream(
                            text,
                            output_format=output_format
                        ):
                            if audio_chunk:
                                audio_buffer.extend(audio_chunk)
                        if audio_buffer:
                            full_audio = bytes(audio_buffer)
                            logger.info(f"Total audio received: {len(full_audio)} bytes (PCM16, 16kHz)")
                        else:
                            raise ValueError("No audio chunks received after fallback")
                    else:
                        raise
                
                # Обрабатываем аудио: конвертируем в PCMU
                try:
                    # Если получили pcm_8000 - конвертируем напрямую в PCMU
                    # Если получили pcm_16000 - ресемплим сначала
                    if use_8khz_direct and output_format == "pcm_8000":
                        # Прямо в PCMU (8kHz PCM16 -> PCMU)
                        # Убеждаемся, что размер кратен 2 байтам (16-bit)
                        if len(full_audio) % 2 != 0:
                            logger.warning(f"Audio size not even ({len(full_audio)} bytes), trimming last byte")
                            full_audio = full_audio[:-1]
                        
                        if len(full_audio) < 2:
                            raise ValueError(f"Audio too short: {len(full_audio)} bytes")
                        
                        logger.info(f"Converting PCM16 (8kHz) to PCMU...")
                        pcmu_data = AudioConverter.pcm16_to_pcmu(full_audio)
                        logger.info(f"PCMU audio ready: {len(pcmu_data)} bytes (PCMU, 8kHz)")
                    else:
                        # Ресемплим с 16kHz на 8kHz
                        # Убеждаемся, что размер кратен 2 байтам (16-bit PCM)
                        if len(full_audio) % 2 != 0:
                            logger.warning(f"Audio size not even ({len(full_audio)} bytes), trimming last byte")
                            full_audio = full_audio[:-1]
                        
                        if len(full_audio) < 2:
                            raise ValueError(f"Audio too short: {len(full_audio)} bytes")
                        
                        # Ресемплим с 16kHz на 8kHz
                        logger.info(f"Resampling from 16kHz to 8kHz...")
                        audio_8khz = AudioConverter.resample(full_audio, 16000, 8000)
                        logger.info(f"Resampled audio: {len(audio_8khz)} bytes (PCM16, 8kHz)")
                        
                        # Конвертируем PCM16 в PCMU (μ-law)
                        logger.info(f"Converting PCM16 to PCMU...")
                        pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                        logger.info(f"PCMU audio ready: {len(pcmu_data)} bytes (PCMU, 8kHz)")
                    
                    # Отправляем в Asterisk через ARI
                    await self._send_audio_to_asterisk(pcmu_data)
                    
                except Exception as e:
                    logger.error(f"Error processing audio: {e}", exc_info=True)
                    # Если pcm_8000 не поддерживается - пробуем pcm_16000
                    if use_8khz_direct and output_format == "pcm_8000":
                        logger.warning(f"pcm_8000 not supported, falling back to pcm_16000: {e}")
                        output_format = "pcm_16000"
                        use_8khz_direct = False
                        # Повторяем запрос с pcm_16000
                        raise  # Пока просто пробрасываем ошибку, можно добавить retry логику
                    else:
                        raise
            
            else:
                # Non-streaming TTS - wait for complete audio
                try:
                    audio_data = await self.tts_client.text_to_speech(
                        text,
                        output_format=output_format
                    )
                    if use_8khz_direct and output_format == "pcm_8000":
                        logger.info(f"Total audio received: {len(audio_data)} bytes (PCM16, 8kHz)")
                    else:
                        logger.info(f"Total audio received: {len(audio_data)} bytes (PCM16, 16kHz)")
                except Exception as e:
                    logger.error(f"Failed to get TTS audio: {e}", exc_info=True)
                    # Если pcm_8000 не поддерживается - пробуем pcm_16000
                    if use_8khz_direct and output_format == "pcm_8000":
                        logger.warning(f"pcm_8000 not supported, falling back to pcm_16000: {e}")
                        output_format = "pcm_16000"
                        use_8khz_direct = False
                        audio_data = await self.tts_client.text_to_speech(
                            text,
                            output_format=output_format
                        )
                        logger.info(f"Total audio received: {len(audio_data)} bytes (PCM16, 16kHz)")
                    else:
                        raise
                
                # Обрабатываем аудио: конвертируем в PCMU
                try:
                    # Если получили pcm_8000 - конвертируем напрямую в PCMU
                    # Если получили pcm_16000 - ресемплим сначала
                    if use_8khz_direct and output_format == "pcm_8000":
                        # Прямо в PCMU (8kHz PCM16 -> PCMU)
                        # Убеждаемся, что размер кратен 2 байтам (16-bit)
                        if len(audio_data) % 2 != 0:
                            logger.warning(f"Audio size not even ({len(audio_data)} bytes), trimming last byte")
                            audio_data = audio_data[:-1]
                        
                        if len(audio_data) < 2:
                            raise ValueError(f"Audio too short: {len(audio_data)} bytes")
                        
                        logger.info(f"Converting PCM16 (8kHz) to PCMU...")
                        pcmu_data = AudioConverter.pcm16_to_pcmu(audio_data)
                        logger.info(f"PCMU audio ready: {len(pcmu_data)} bytes (PCMU, 8kHz)")
                    else:
                        # Ресемплим с 16kHz на 8kHz
                        # Убеждаемся, что размер кратен 2 байтам (16-bit PCM)
                        if len(audio_data) % 2 != 0:
                            logger.warning(f"Audio size not even ({len(audio_data)} bytes), trimming last byte")
                            audio_data = audio_data[:-1]
                        
                        if len(audio_data) < 2:
                            raise ValueError(f"Audio too short: {len(audio_data)} bytes")
                        
                        # Ресемплим с 16kHz на 8kHz
                        logger.info(f"Resampling from 16kHz to 8kHz...")
                        audio_8khz = AudioConverter.resample(audio_data, 16000, 8000)
                        logger.info(f"Resampled audio: {len(audio_8khz)} bytes (PCM16, 8kHz)")
                        
                        # Конвертируем PCM16 в PCMU (μ-law)
                        logger.info(f"Converting PCM16 to PCMU...")
                        pcmu_data = AudioConverter.pcm16_to_pcmu(audio_8khz)
                        logger.info(f"PCMU audio ready: {len(pcmu_data)} bytes (PCMU, 8kHz)")
                    
                    # Отправляем в Asterisk через ARI
                    await self._send_audio_to_asterisk(pcmu_data)
                    
                except Exception as e:
                    logger.error(f"Error processing audio: {e}", exc_info=True)
                    raise
            
            logger.info("✅ Speech sent to Asterisk")
        
        except Exception as e:
            logger.error(f"Error in TTS: {e}", exc_info=True)
    
    async def _send_audio_to_asterisk(self, pcmu_data: bytes):
        """
        Send PCMU audio to Asterisk channel through ARI using WAV file with PCMU format
        
        Args:
            pcmu_data: PCMU (μ-law) encoded audio data (8kHz, mono)
        """
        if not self.ari_client:
            logger.warning("ARI client not available, cannot send audio to Asterisk")
            return
        
        try:
            import uuid
            import struct
            
            # Создаем уникальное имя файла
            file_id = str(uuid.uuid4())[:8]
            wav_filename = f"tts_{file_id}"
            
            # Путь к директории звуков Asterisk
            sounds_dir = "/var/lib/asterisk/sounds/tts"
            wav_path = f"{sounds_dir}/{wav_filename}.wav"
            
            # Создаем директорию если её нет
            os.makedirs(sounds_dir, exist_ok=True)
            
            # Создаем WAV файл с PCMU (μ-law) форматом
            # WAV header для PCMU: format 7, 8kHz, mono, 8-bit
            sample_rate = 8000
            num_channels = 1
            bits_per_sample = 8
            byte_rate = sample_rate * num_channels * bits_per_sample // 8
            block_align = num_channels * bits_per_sample // 8
            data_size = len(pcmu_data)
            
            # WAV file structure
            # RIFF header
            wav_file = b'RIFF'
            file_size = 36 + data_size  # 36 = header size without data
            wav_file += struct.pack('<I', file_size)
            wav_file += b'WAVE'
            
            # fmt chunk (18 bytes for PCMU)
            wav_file += b'fmt '
            wav_file += struct.pack('<I', 18)  # fmt chunk size
            wav_file += struct.pack('<H', 7)   # Audio format: 7 = μ-law (PCMU)
            wav_file += struct.pack('<H', num_channels)  # Channels: 1 = mono
            wav_file += struct.pack('<I', sample_rate)  # Sample rate: 8000
            wav_file += struct.pack('<I', byte_rate)  # Byte rate
            wav_file += struct.pack('<H', block_align)  # Block align
            wav_file += struct.pack('<H', bits_per_sample)  # Bits per sample: 8
            wav_file += struct.pack('<H', 0)  # Extension size (0 for PCMU)
            
            # data chunk
            wav_file += b'data'
            wav_file += struct.pack('<I', data_size)
            wav_file += pcmu_data  # Raw PCMU data
            
            # Записываем WAV файл
            with open(wav_path, 'wb') as f:
                f.write(wav_file)
            
            # Проверяем, что файл создался
            if not os.path.exists(wav_path):
                raise FileNotFoundError(f"Failed to create WAV file: {wav_path}")
            
            file_size = os.path.getsize(wav_path)
            expected_size = 44 + data_size  # 44 = WAV header size
            if file_size != expected_size:
                logger.warning(f"File size mismatch: expected {expected_size}, got {file_size}")
            
            logger.info(f"✅ Created WAV file (PCMU): {wav_path} ({file_size} bytes, {data_size} bytes PCMU data)")
            
            # Отправляем в Asterisk через sound: URI
            # Asterisk автоматически найдет файл с расширением .wav
            # Формат: sound:tts/filename (без расширения)
            media_uri = f"sound:tts/{wav_filename}"
            
            logger.info(f"Sending audio to Asterisk: {media_uri} ({data_size} bytes PCMU, {file_size} bytes WAV)")
            logger.info(f"File path: {wav_path}")
            
            try:
                playback_info = await self.ari_client.play_media(
                    channel_id=self.channel_id,
                    media=media_uri
                )
                logger.info(f"✅ Audio playback started: {playback_info.get('id', 'unknown')}")
            except Exception as play_error:
                logger.error(f"Failed to play media: {play_error}", exc_info=True)
                raise
            
            # ВРЕМЕННО ОТКЛЮЧЕНО: Удаление файлов для проверки
            # Удаляем временный файл после небольшой задержки
            # (даем время Asterisk прочитать файл)
            # async def cleanup():
            #     await asyncio.sleep(20)  # Ждем 20 секунд
            #     try:
            #         if os.path.exists(wav_path):
            #             os.unlink(wav_path)
            #             logger.debug(f"Cleaned up temporary file: {wav_path}")
            #     except Exception as e:
            #         logger.warning(f"Failed to cleanup temp file: {e}")
            # 
            # asyncio.create_task(cleanup())
            logger.info(f"⚠️ File cleanup DISABLED - file will remain: {wav_path}")
            
        except Exception as e:
            logger.error(f"Failed to send audio to Asterisk: {e}", exc_info=True)
            raise
    
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
        on_final_transcript: Optional[Callable] = None,
        ari_client = None
    ) -> VoiceProcessor:
        """
        Create and start a voice processor for a channel
        
        Args:
            channel_id: Asterisk channel ID
            on_transcript: Callback for partial transcripts
            on_final_transcript: Callback for final transcripts
            ari_client: Asterisk ARI client for sending audio
        
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

