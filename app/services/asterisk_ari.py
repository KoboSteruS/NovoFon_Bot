"""
Asterisk ARI (Asterisk REST Interface) client
Manages SIP calls through Asterisk
"""
import asyncio
import json
from typing import Optional, Dict, Any, Callable
from loguru import logger
import aiohttp
import websockets

from app.config import settings


class AsteriskARIError(Exception):
    """Asterisk ARI error"""
    pass


class AsteriskARIClient:
    """
    Client for Asterisk REST Interface (ARI)
    
    Manages:
    - WebSocket connection for real-time events
    - REST API calls for call control
    - Channel management
    - Audio streaming
    """
    
    def __init__(
        self,
        base_url: Optional[str] = None,
        username: Optional[str] = None,
        password: Optional[str] = None,
        app_name: Optional[str] = None
    ):
        """
        Initialize ARI client
        
        Args:
            base_url: Asterisk ARI base URL (default from settings)
            username: ARI username (default from settings)
            password: ARI password (default from settings)
            app_name: Stasis application name (default from settings)
        """
        self.base_url = (base_url or settings.asterisk_ari_url).rstrip('/')
        self.username = username or settings.asterisk_ari_username
        self.password = password or settings.asterisk_ari_password
        self.app_name = app_name or settings.asterisk_ari_app_name
        
        self.ws_url = self.base_url.replace('http://', 'ws://').replace('https://', 'wss://')
        
        self.http_session: Optional[aiohttp.ClientSession] = None
        self.ws_connection: Optional[websockets.WebSocketClientProtocol] = None
        self.event_handlers: Dict[str, Callable] = {}
        
        self._running = False
        self._ws_task: Optional[asyncio.Task] = None
        
        logger.info(f"ARI client initialized for {self.base_url}, app: {self.app_name}")
    
    async def connect(self):
        """Connect to Asterisk ARI"""
        if self._running:
            logger.warning("ARI client already connected")
            return
        
        # Create HTTP session
        auth = aiohttp.BasicAuth(self.username, self.password)
        self.http_session = aiohttp.ClientSession(auth=auth)
        
        # Test connection
        try:
            async with self.http_session.get(f"{self.base_url}/asterisk/info") as resp:
                if resp.status == 200:
                    info = await resp.json()
                    logger.info(f"Connected to Asterisk {info.get('version', 'unknown')}")
                else:
                    raise AsteriskARIError(f"Failed to connect: HTTP {resp.status}")
        except Exception as e:
            logger.error(f"Failed to connect to Asterisk ARI: {e}")
            await self.http_session.close()
            raise AsteriskARIError(f"Connection failed: {e}")
        
        # Start WebSocket connection
        self._running = True
        self._ws_task = asyncio.create_task(self._websocket_loop())
        
        logger.info("ARI client connected successfully")
    
    async def disconnect(self):
        """Disconnect from Asterisk ARI"""
        logger.info("Disconnecting ARI client...")
        
        self._running = False
        
        if self._ws_task:
            self._ws_task.cancel()
            try:
                await self._ws_task
            except asyncio.CancelledError:
                pass
        
        if self.ws_connection:
            await self.ws_connection.close()
        
        if self.http_session:
            await self.http_session.close()
        
        logger.info("ARI client disconnected")
    
    async def _websocket_loop(self):
        """WebSocket event loop"""
        ws_url = f"{self.ws_url}/events?app={self.app_name}&api_key={self.username}:{self.password}"
        
        while self._running:
            try:
                logger.info(f"Connecting to ARI WebSocket: {self.app_name}")
                
                async with websockets.connect(
                    ws_url,
                    ping_interval=20,
                    ping_timeout=10
                ) as websocket:
                    self.ws_connection = websocket
                    logger.info("✅ ARI WebSocket connected successfully")
                    logger.info(f"Listening for events on app: {self.app_name}")
                    
                    async for message in websocket:
                        try:
                            event = json.loads(message)
                            await self._handle_event(event)
                        except json.JSONDecodeError as e:
                            logger.error(f"Failed to decode event: {e}")
                        except Exception as e:
                            logger.error(f"Error handling event: {e}", exc_info=True)
            
            except websockets.exceptions.WebSocketException as e:
                logger.error(f"WebSocket error: {e}")
                if self._running:
                    logger.info("Reconnecting in 5 seconds...")
                    await asyncio.sleep(5)
            
            except Exception as e:
                logger.error(f"Unexpected error in WebSocket loop: {e}", exc_info=True)
                if self._running:
                    await asyncio.sleep(5)
    
    async def _handle_event(self, event: Dict[str, Any]):
        """
        Handle incoming ARI event
        
        Args:
            event: Event data from Asterisk
        """
        event_type = event.get('type')
        
        # Логируем важные события на уровне INFO
        if event_type in ['StasisStart', 'StasisEnd', 'ChannelStateChange', 'ChannelHangupRequest']:
            logger.info(f"Received ARI event: {event_type}")
            if event_type == 'StasisStart':
                channel = event.get('channel', {})
                args = event.get('args', [])
                logger.info(f"  Channel: {channel.get('id')}, Args: {args}")
        else:
            logger.debug(f"Received event: {event_type}")
            logger.debug(f"Event data: {event}")
        
        # Call registered handler
        handler = self.event_handlers.get(event_type)
        if handler:
            try:
                await handler(event)
            except Exception as e:
                logger.error(f"Error in event handler for {event_type}: {e}", exc_info=True)
        else:
            # Для важных событий логируем на INFO, для остальных - DEBUG
            if event_type in ['StasisStart', 'StasisEnd']:
                logger.warning(f"⚠️  No handler registered for event type: {event_type}")
            else:
                logger.debug(f"No handler for event type: {event_type}")
    
    def on_event(self, event_type: str):
        """
        Decorator to register event handler
        
        Usage:
            @ari_client.on_event('StasisStart')
            async def handle_stasis_start(event):
                ...
        """
        def decorator(func: Callable):
            self.event_handlers[event_type] = func
            logger.info(f"Registered handler for event: {event_type}")
            return func
        return decorator
    
    async def originate_call(
        self,
        endpoint: str,
        extension: Optional[str] = None,
        context: Optional[str] = None,
        caller_id: Optional[str] = None,
        variables: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        """
        Originate (create) a new call
        
        Args:
            endpoint: SIP endpoint (e.g., "SIP/79991234567@606147" for chan_sip)
            extension: Extension to dial
            context: Dialplan context
            caller_id: Caller ID to set
            variables: Channel variables
        
        Returns:
            Channel information
        """
        data = {
            'endpoint': endpoint,
            'app': self.app_name,
        }
        
        if extension:
            data['extension'] = extension
        if context:
            data['context'] = context
        if caller_id:
            data['callerId'] = caller_id
        if variables:
            data['variables'] = variables
        
        logger.info(f"Originating call to {endpoint}")
        
        try:
            async with self.http_session.post(
                f"{self.base_url}/channels",
                json=data
            ) as resp:
                if resp.status in [200, 201]:
                    channel = await resp.json()
                    logger.info(f"Call originated: {channel.get('id')}")
                    return channel
                else:
                    error = await resp.text()
                    raise AsteriskARIError(f"Failed to originate call: {error}")
        
        except Exception as e:
            logger.error(f"Error originating call: {e}")
            raise AsteriskARIError(f"Originate failed: {e}")
    
    async def answer_channel(self, channel_id: str):
        """Answer a channel"""
        logger.info(f"Answering channel: {channel_id}")
        
        async with self.http_session.post(
            f"{self.base_url}/channels/{channel_id}/answer"
        ) as resp:
            if resp.status != 204:
                raise AsteriskARIError(f"Failed to answer channel: {await resp.text()}")
    
    async def hangup_channel(self, channel_id: str, reason: str = "normal"):
        """Hangup a channel"""
        logger.info(f"Hanging up channel: {channel_id}")
        
        async with self.http_session.delete(
            f"{self.base_url}/channels/{channel_id}",
            params={'reason': reason}
        ) as resp:
            if resp.status != 204:
                logger.warning(f"Failed to hangup channel: {await resp.text()}")
    
    async def play_media(
        self,
        channel_id: str,
        media: str,
        lang: str = "en"
    ) -> Dict[str, Any]:
        """
        Play media on a channel
        
        Args:
            channel_id: Channel ID
            media: Media URI (e.g., "sound:hello-world")
            lang: Language
        
        Returns:
            Playback information
        """
        logger.info(f"Playing {media} on channel {channel_id}")
        
        async with self.http_session.post(
            f"{self.base_url}/channels/{channel_id}/play",
            json={'media': media, 'lang': lang}
        ) as resp:
            if resp.status == 201:
                return await resp.json()
            else:
                raise AsteriskARIError(f"Failed to play media: {await resp.text()}")
    
    async def start_recording(
        self,
        channel_id: str,
        name: str,
        format: str = "wav"
    ) -> Dict[str, Any]:
        """
        Start recording a channel
        
        Args:
            channel_id: Channel ID
            name: Recording name
            format: Audio format (wav, gsm, etc.)
        
        Returns:
            Recording information
        """
        logger.info(f"Starting recording on channel {channel_id}")
        
        async with self.http_session.post(
            f"{self.base_url}/channels/{channel_id}/record",
            json={
                'name': name,
                'format': format,
                'maxDurationSeconds': 3600,
                'maxSilenceSeconds': 30
            }
        ) as resp:
            if resp.status == 201:
                return await resp.json()
            else:
                raise AsteriskARIError(f"Failed to start recording: {await resp.text()}")
    
    async def get_channel_variable(
        self,
        channel_id: str,
        variable: str
    ) -> Optional[str]:
        """Get channel variable value"""
        async with self.http_session.get(
            f"{self.base_url}/channels/{channel_id}/variable",
            params={'variable': variable}
        ) as resp:
            if resp.status == 200:
                data = await resp.json()
                return data.get('value')
            return None
    
    async def set_channel_variable(
        self,
        channel_id: str,
        variable: str,
        value: str
    ):
        """Set channel variable"""
        async with self.http_session.post(
            f"{self.base_url}/channels/{channel_id}/variable",
            json={'variable': variable, 'value': value}
        ) as resp:
            if resp.status != 204:
                raise AsteriskARIError(f"Failed to set variable: {await resp.text()}")
    
    async def create_bridge(self, bridge_type: str = "mixing") -> Dict[str, Any]:
        """Create a new bridge"""
        async with self.http_session.post(
            f"{self.base_url}/bridges",
            json={'type': bridge_type}
        ) as resp:
            if resp.status == 200:
                return await resp.json()
            else:
                raise AsteriskARIError(f"Failed to create bridge: {await resp.text()}")
    
    async def add_channel_to_bridge(self, bridge_id: str, channel_id: str):
        """Add channel to bridge"""
        async with self.http_session.post(
            f"{self.base_url}/bridges/{bridge_id}/addChannel",
            json={'channel': channel_id}
        ) as resp:
            if resp.status != 204:
                raise AsteriskARIError(f"Failed to add channel to bridge: {await resp.text()}")


# Global client instance
ari_client: Optional[AsteriskARIClient] = None


def get_ari_client() -> AsteriskARIClient:
    """Dependency for getting ARI client"""
    global ari_client
    if ari_client is None:
        ari_client = AsteriskARIClient()
    return ari_client

