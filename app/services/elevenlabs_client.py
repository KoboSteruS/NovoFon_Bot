"""
ElevenLabs client for real-time Speech-to-Text (ASR) and Text-to-Speech (TTS)
"""
import asyncio
import json
from dataclasses import dataclass
from io import BytesIO
from typing import Optional, Callable, AsyncIterator
from urllib.parse import urlparse

import aiohttp
from loguru import logger
import websockets
from websockets.http import BasicAuth as WSBasicAuth

from app.config import settings
@dataclass
class ProxyConfig:
    url: str
    host: str
    port: int
    username: Optional[str] = None
    password: Optional[str] = None



class ElevenLabsError(Exception):
    """ElevenLabs API error"""
    pass


def _build_proxy_config() -> Optional[ProxyConfig]:
    proxy_url = settings.elevenlabs_proxy_url
    if not proxy_url:
        return None
    parsed = urlparse(proxy_url)
    if not parsed.hostname or not parsed.port:
        logger.warning("Invalid ELEVENLABS_PROXY_URL configuration; proxy ignored")
        return None
    username = settings.elevenlabs_proxy_username or parsed.username
    password = settings.elevenlabs_proxy_password or parsed.password
    return ProxyConfig(
        url=proxy_url,
        host=parsed.hostname,
        port=parsed.port,
        username=username,
        password=password,
    )


class ElevenLabsASRClient:
    """
    Real-time Speech-to-Text client using ElevenLabs Conversational AI
    
    WebSocket-based streaming ASR
    """
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize ASR client
        
        Args:
            api_key: ElevenLabs API key (default from settings)
        """
        self.api_key = api_key or settings.elevenlabs_api_key
        self.ws_url = "wss://api.elevenlabs.io/v1/convai/conversation"
        self.proxy = _build_proxy_config()
        self.default_agent_id = settings.elevenlabs_agent_id
        
        self.websocket: Optional[websockets.WebSocketClientProtocol] = None
        self.is_connected = False
        
        # Callbacks
        self.on_transcript: Optional[Callable] = None
        self.on_final_transcript: Optional[Callable] = None
        
        logger.info("ElevenLabs ASR client initialized")
    
    async def connect(self, agent_id: Optional[str] = None):
        """
        Connect to ElevenLabs WebSocket
        
        Args:
            agent_id: Agent ID for conversational AI (optional)
        """
        if self.is_connected:
            logger.warning("ASR already connected")
            return
        
        # Build WebSocket URL with auth
        url = f"{self.ws_url}?api_key={self.api_key}"
        if agent_id or self.default_agent_id:
            url += f"&agent_id={agent_id or self.default_agent_id}"
        
        try:
            connect_kwargs = {}
            if self.proxy:
                connect_kwargs["http_proxy_host"] = self.proxy.host
                connect_kwargs["http_proxy_port"] = self.proxy.port
                if self.proxy.username:
                    connect_kwargs["http_proxy_auth"] = WSBasicAuth(
                        self.proxy.username,
                        self.proxy.password or "",
                    )

            self.websocket = await websockets.connect(
                url,
                ping_interval=20,
                ping_timeout=10,
                **connect_kwargs,
            )
            self.is_connected = True
            logger.info("ASR WebSocket connected")
            
            # Start listening for transcripts
            asyncio.create_task(self._receive_loop())
        
        except Exception as e:
            logger.error(f"Failed to connect ASR WebSocket: {e}")
            raise ElevenLabsError(f"ASR connection failed: {e}")
    
    async def disconnect(self):
        """Disconnect from WebSocket"""
        if self.websocket:
            await self.websocket.close()
            self.is_connected = False
            logger.info("ASR WebSocket disconnected")
    
    async def _receive_loop(self):
        """Receive transcripts from WebSocket"""
        try:
            async for message in self.websocket:
                try:
                    data = json.loads(message)
                    await self._handle_message(data)
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to decode ASR message: {e}")
        except websockets.exceptions.ConnectionClosed:
            logger.info("ASR WebSocket connection closed")
            self.is_connected = False
        except Exception as e:
            logger.error(f"Error in ASR receive loop: {e}", exc_info=True)
            self.is_connected = False
    
    async def _handle_message(self, data: dict):
        """Handle incoming message from ElevenLabs"""
        msg_type = data.get('type')
        
        if msg_type == 'transcript':
            # Partial transcript
            text = data.get('text', '')
            is_final = data.get('is_final', False)
            
            logger.debug(f"Transcript: {text} (final: {is_final})")
            
            if is_final and self.on_final_transcript:
                await self.on_final_transcript(text)
            elif self.on_transcript:
                await self.on_transcript(text, is_final)
        
        elif msg_type == 'error':
            error = data.get('message', 'Unknown error')
            logger.error(f"ASR error: {error}")
    
    async def send_audio(self, audio_chunk: bytes):
        """
        Send audio chunk for transcription
        
        Args:
            audio_chunk: Audio data (PCM 16-bit, 8kHz or 16kHz mono)
        """
        if not self.is_connected or not self.websocket:
            raise ElevenLabsError("ASR not connected")
        
        try:
            # Send binary audio data
            await self.websocket.send(audio_chunk)
        except Exception as e:
            logger.error(f"Failed to send audio to ASR: {e}")
            raise ElevenLabsError(f"Send audio failed: {e}")
    
    async def finalize(self):
        """Signal end of audio stream"""
        if self.websocket and self.is_connected:
            # Send end-of-stream marker
            await self.websocket.send(json.dumps({'type': 'finalize'}))


class ElevenLabsTTSClient:
    """
    Text-to-Speech client using ElevenLabs API
    
    Supports both streaming and non-streaming TTS
    """
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize TTS client
        
        Args:
            api_key: ElevenLabs API key (default from settings)
        """
        self.api_key = api_key or settings.elevenlabs_api_key
        self.base_url = "https://api.elevenlabs.io/v1"
        self.proxy = _build_proxy_config()
        self.session: Optional[aiohttp.ClientSession] = None
        self.proxy_auth: Optional[aiohttp.BasicAuth] = None
        if self.proxy and self.proxy.username:
            self.proxy_auth = aiohttp.BasicAuth(
                self.proxy.username,
                self.proxy.password or "",
            )
        
        logger.info("ElevenLabs TTS client initialized")
    
    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            headers={'xi-api-key': self.api_key},
            trust_env=True,
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    async def text_to_speech(
        self,
        text: str,
        voice_id: Optional[str] = None,
        model_id: Optional[str] = None,
        stability: float = 0.5,
        similarity_boost: float = 0.75,
        output_format: str = "pcm_16000"
    ) -> bytes:
        """
        Convert text to speech (non-streaming)
        
        Args:
            text: Text to convert
            voice_id: Voice ID (default from settings)
            model_id: Model ID (default from settings)
            stability: Voice stability (0-1)
            similarity_boost: Voice similarity boost (0-1)
            output_format: Output format (pcm_16000, pcm_8000, mp3_44100_128, etc.)
        
        Returns:
            Audio data as bytes
        """
        voice_id = voice_id or settings.elevenlabs_voice_id
        model_id = model_id or settings.elevenlabs_model
        
        url = f"{self.base_url}/text-to-speech/{voice_id}"
        
        payload = {
            'text': text,
            'model_id': model_id,
            'voice_settings': {
                'stability': stability,
                'similarity_boost': similarity_boost
            }
        }
        
        params = {'output_format': output_format}
        
        logger.info(f"Generating TTS for text: {text[:50]}...")
        
        if not self.session:
            self.session = aiohttp.ClientSession(
                headers={'xi-api-key': self.api_key}
            )
        
        request_kwargs = {}
        if self.proxy:
            request_kwargs["proxy"] = self.proxy.url
            if self.proxy_auth:
                request_kwargs["proxy_auth"] = self.proxy_auth

        try:
            async with self.session.post(
                url,
                json=payload,
                params=params,
                **request_kwargs,
            ) as resp:
                if resp.status == 200:
                    audio_data = await resp.read()
                    logger.info(f"TTS generated: {len(audio_data)} bytes")
                    return audio_data
                else:
                    error = await resp.text()
                    raise ElevenLabsError(f"TTS failed: {error}")
        
        except Exception as e:
            logger.error(f"TTS error: {e}")
            raise ElevenLabsError(f"TTS request failed: {e}")
    
    async def text_to_speech_stream(
        self,
        text: str,
        voice_id: Optional[str] = None,
        model_id: Optional[str] = None,
        stability: float = 0.5,
        similarity_boost: float = 0.75,
        output_format: str = "pcm_16000"
    ) -> AsyncIterator[bytes]:
        """
        Convert text to speech (streaming)
        
        Yields audio chunks as they're generated
        
        Args:
            text: Text to convert
            voice_id: Voice ID
            model_id: Model ID
            stability: Voice stability
            similarity_boost: Voice similarity boost
            output_format: Output format
        
        Yields:
            Audio chunks (bytes)
        """
        voice_id = voice_id or settings.elevenlabs_voice_id
        model_id = model_id or settings.elevenlabs_model
        
        url = f"{self.base_url}/text-to-speech/{voice_id}/stream"
        
        payload = {
            'text': text,
            'model_id': model_id,
            'voice_settings': {
                'stability': stability,
                'similarity_boost': similarity_boost
            }
        }
        
        params = {'output_format': output_format}
        
        logger.info(f"Streaming TTS for text: {text[:50]}...")
        
        if not self.session:
            self.session = aiohttp.ClientSession(
                headers={'xi-api-key': self.api_key}
            )
        
        request_kwargs = {}
        if self.proxy:
            request_kwargs["proxy"] = self.proxy.url
            if self.proxy_auth:
                request_kwargs["proxy_auth"] = self.proxy_auth

        try:
            async with self.session.post(
                url,
                json=payload,
                params=params,
                **request_kwargs,
            ) as resp:
                if resp.status == 200:
                    # Stream audio chunks
                    async for chunk in resp.content.iter_chunked(4096):
                        yield chunk
                    logger.info("TTS streaming complete")
                else:
                    error = await resp.text()
                    raise ElevenLabsError(f"TTS streaming failed: {error}")
        
        except Exception as e:
            logger.error(f"TTS streaming error: {e}")
            raise ElevenLabsError(f"TTS streaming failed: {e}")
    
    async def get_voices(self) -> list:
        """Get available voices"""
        url = f"{self.base_url}/voices"
        
        if not self.session:
            self.session = aiohttp.ClientSession(
                headers={'xi-api-key': self.api_key}
            )
        
        async with self.session.get(url) as resp:
            if resp.status == 200:
                data = await resp.json()
                return data.get('voices', [])
            else:
                raise ElevenLabsError(f"Failed to get voices: {await resp.text()}")


class AudioConverter:
    """
    Audio format converter for RTP <-> ElevenLabs compatibility
    """
    
    @staticmethod
    def pcmu_to_pcm16(pcmu_data: bytes) -> bytes:
        """
        Convert μ-law (PCMU) to PCM 16-bit
        
        Args:
            pcmu_data: μ-law encoded audio
        
        Returns:
            PCM 16-bit audio
        """
        # μ-law to linear conversion table
        import audioop
        return audioop.ulaw2lin(pcmu_data, 2)
    
    @staticmethod
    def pcm16_to_pcmu(pcm_data: bytes) -> bytes:
        """
        Convert PCM 16-bit to μ-law (PCMU)
        
        Args:
            pcm_data: PCM 16-bit audio
        
        Returns:
            μ-law encoded audio
        """
        import audioop
        return audioop.lin2ulaw(pcm_data, 2)
    
    @staticmethod
    def resample(audio_data: bytes, from_rate: int, to_rate: int, channels: int = 1) -> bytes:
        """
        Resample audio
        
        Args:
            audio_data: Input audio (PCM 16-bit)
            from_rate: Source sample rate
            to_rate: Target sample rate
            channels: Number of channels
        
        Returns:
            Resampled audio
        """
        import audioop
        
        # Calculate rate conversion
        # audioop.ratecv(fragment, width, nchannels, inrate, outrate, state)
        resampled, _ = audioop.ratecv(
            audio_data,
            2,  # 16-bit = 2 bytes
            channels,
            from_rate,
            to_rate,
            None
        )
        return resampled


# Global clients
asr_client: Optional[ElevenLabsASRClient] = None
tts_client: Optional[ElevenLabsTTSClient] = None


def get_asr_client() -> ElevenLabsASRClient:
    """Get or create ASR client instance"""
    global asr_client
    if asr_client is None:
        asr_client = ElevenLabsASRClient()
    return asr_client


def get_tts_client() -> ElevenLabsTTSClient:
    """Get or create TTS client instance"""
    global tts_client
    if tts_client is None:
        tts_client = ElevenLabsTTSClient()
    return tts_client

