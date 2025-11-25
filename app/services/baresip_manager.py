"""
Baresip manager - main service for handling calls via baresip
"""
import asyncio
from typing import Optional
from loguru import logger

from app.services.baresip_client import BaresipClient
from app.config import settings


class BaresipManager:
    """
    Manages baresip client and call handling
    """
    
    def __init__(self):
        """Initialize baresip manager"""
        self.client: Optional[BaresipClient] = None
        self.is_running = False
    
    async def start(self):
        """Start baresip manager"""
        if self.is_running:
            logger.warning("Baresip manager already running")
            return
        
        try:
            # Create baresip client
            ws_url = getattr(settings, 'baresip_ws_url', 'ws://127.0.0.1:8000/ws')
            
            self.client = BaresipClient(
                ws_url=ws_url,
                on_call_started=self._on_call_started,
                on_call_ended=self._on_call_ended
            )
            
            # Connect to baresip
            await self.client.connect()
            
            self.is_running = True
            logger.info("✅ Baresip manager started")
        
        except Exception as e:
            logger.error(f"Failed to start baresip manager: {e}", exc_info=True)
            raise
    
    async def stop(self):
        """Stop baresip manager"""
        if not self.is_running:
            return
        
        try:
            if self.client:
                await self.client.disconnect()
            
            self.is_running = False
            logger.info("Baresip manager stopped")
        
        except Exception as e:
            logger.error(f"Error stopping baresip manager: {e}")
    
    async def _on_call_started(self, call_id: str):
        """Handle call started"""
        logger.info(f"📞 Call started: {call_id}")
    
    async def _on_call_ended(self, call_id: str):
        """Handle call ended"""
        logger.info(f"📴 Call ended: {call_id}")

