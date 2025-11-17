"""
NovoFon API client service
Documentation: https://novofon.com/instructions/api/
"""
import httpx
from typing import Optional, Dict, Any
from loguru import logger

from app.config import settings


class NovoFonAPIError(Exception):
    """NovoFon API error"""
    def __init__(self, message: str, status_code: Optional[int] = None, response_data: Optional[Dict] = None):
        self.message = message
        self.status_code = status_code
        self.response_data = response_data
        super().__init__(self.message)


class NovoFonClient:
    """
    NovoFon API client for making outbound calls
    """
    
    def __init__(self, api_key: Optional[str] = None, api_url: Optional[str] = None):
        """
        Initialize NovoFon client
        
        Args:
            api_key: NovoFon API key (defaults to settings)
            api_url: NovoFon API URL (defaults to settings)
        """
        self.api_key = api_key or settings.novofon_api_key
        self.api_url = api_url or settings.novofon_api_url
        self.from_number = settings.novofon_from_number
        
        if not self.api_key:
            raise ValueError("NovoFon API key is required")
        
        self.client = httpx.AsyncClient(
            base_url=self.api_url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            },
            timeout=30.0
        )
        
        logger.info("NovoFon client initialized")
    
    async def close(self):
        """Close HTTP client"""
        await self.client.aclose()
    
    async def __aenter__(self):
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()
    
    async def initiate_call(
        self,
        to_number: str,
        from_number: Optional[str] = None,
        custom_id: Optional[str] = None,
        line_number: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Initiate outbound call via NovoFon API
        
        Args:
            to_number: Destination phone number (e.g., "+79991234567")
            from_number: Source number (defaults to configured number)
            custom_id: Custom call identifier
            line_number: Specific line to use
        
        Returns:
            Dict with call information including call_id
        
        Raises:
            NovoFonAPIError: If API request fails
        """
        if not to_number:
            raise ValueError("to_number is required")
        
        # Validate phone format (basic check)
        if not to_number.startswith("+"):
            to_number = f"+{to_number}"
        
        from_num = from_number or self.from_number
        
        payload = {
            "from": from_num,
            "to": to_number
        }
        
        if custom_id:
            payload["custom_id"] = custom_id
        
        if line_number:
            payload["line_number"] = line_number
        
        logger.info(f"Initiating call to {to_number} from {from_num}")
        logger.debug(f"Payload: {payload}")
        
        try:
            # Try different possible endpoints
            # NovoFon API documentation: https://novofon.com/instructions/api/
            response = await self.client.post("/v1/call", json=payload)
            
            logger.debug(f"NovoFon response status: {response.status_code}")
            logger.debug(f"NovoFon response body: {response.text}")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Call initiated successfully: {data}")
                return {
                    "status": "success",
                    "call_id": data.get("call_id"),
                    "message": data.get("message", "Call initiated"),
                    "data": data
                }
            
            elif response.status_code == 401:
                raise NovoFonAPIError(
                    "Authentication failed - check API key",
                    status_code=response.status_code,
                    response_data=response.json() if response.text else None
                )
            
            elif response.status_code == 400:
                error_data = response.json() if response.text else {}
                raise NovoFonAPIError(
                    f"Bad request: {error_data.get('error', 'Invalid parameters')}",
                    status_code=response.status_code,
                    response_data=error_data
                )
            
            else:
                error_data = response.json() if response.text else {}
                raise NovoFonAPIError(
                    f"API request failed: {error_data.get('error', 'Unknown error')}",
                    status_code=response.status_code,
                    response_data=error_data
                )
        
        except httpx.HTTPError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise NovoFonAPIError(f"Network error: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error: {e}", exc_info=True)
            raise NovoFonAPIError(f"Unexpected error: {str(e)}")
    
    async def get_call_info(self, call_id: str) -> Dict[str, Any]:
        """
        Get information about a call
        
        Args:
            call_id: NovoFon call ID
        
        Returns:
            Dict with call information
        
        Raises:
            NovoFonAPIError: If API request fails
        """
        try:
            response = await self.client.get(f"/call/{call_id}")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Retrieved call info for {call_id}")
                return data
            
            elif response.status_code == 404:
                raise NovoFonAPIError(
                    f"Call {call_id} not found",
                    status_code=404
                )
            
            else:
                error_data = response.json() if response.text else {}
                raise NovoFonAPIError(
                    f"Failed to get call info: {error_data.get('error', 'Unknown error')}",
                    status_code=response.status_code,
                    response_data=error_data
                )
        
        except httpx.HTTPError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise NovoFonAPIError(f"Network error: {str(e)}")
    
    async def hangup_call(self, call_id: str) -> Dict[str, Any]:
        """
        Hangup an active call
        
        Args:
            call_id: NovoFon call ID
        
        Returns:
            Dict with hangup confirmation
        
        Raises:
            NovoFonAPIError: If API request fails
        """
        try:
            response = await self.client.post(f"/call/{call_id}/hangup")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Call {call_id} hung up successfully")
                return data
            
            else:
                error_data = response.json() if response.text else {}
                raise NovoFonAPIError(
                    f"Failed to hangup call: {error_data.get('error', 'Unknown error')}",
                    status_code=response.status_code,
                    response_data=error_data
                )
        
        except httpx.HTTPError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise NovoFonAPIError(f"Network error: {str(e)}")
    
    async def health_check(self) -> bool:
        """
        Check if NovoFon API is accessible
        
        Returns:
            True if API is accessible, False otherwise
        """
        try:
            response = await self.client.get("/")
            return response.status_code < 500
        except Exception as e:
            logger.error(f"NovoFon health check failed: {e}")
            return False


# Global client instance (will be initialized in app startup)
novofon_client: Optional[NovoFonClient] = None


def get_novofon_client() -> NovoFonClient:
    """
    Dependency for getting NovoFon client
    """
    global novofon_client
    if novofon_client is None:
        novofon_client = NovoFonClient()
    return novofon_client

