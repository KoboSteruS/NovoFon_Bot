"""
Configuration management using Pydantic Settings
"""
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings"""
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )
    
    # Application
    app_env: str = "development"
    app_host: str = "127.0.0.1"  # Changed from 0.0.0.0 for Windows compatibility
    app_port: int = 8000
    debug: bool = True
    
    # Database
    database_url: str
    
    # NovoFon
    novofon_api_key: str
    novofon_api_url: str = "https://api.novofon.com"
    novofon_from_number: str
    
    # ElevenLabs
    elevenlabs_api_key: str
    elevenlabs_voice_id: str = "21m00Tcm4TlvDq8ikWAM"
    elevenlabs_model: str = "eleven_turbo_v2"
    elevenlabs_agent_id: Optional[str] = None
    elevenlabs_proxy_url: Optional[str] = None
    elevenlabs_proxy_username: Optional[str] = None
    elevenlabs_proxy_password: Optional[str] = None
    
    # Asterisk ARI
    asterisk_ari_url: str = "http://localhost:8088/ari"
    asterisk_ari_username: str = "asterisk"
    asterisk_ari_password: str = "asterisk"
    asterisk_ari_app_name: str = "elevenbot"  # ИСПРАВЛЕНО: соответствует extensions.conf
    
    # Redis
    redis_url: str = "redis://localhost:6379/0"
    
    # Celery
    celery_broker_url: str = "redis://localhost:6379/1"
    celery_result_backend: str = "redis://localhost:6379/2"
    
    # Logging
    log_level: str = "INFO"
    log_file: str = "logs/app.log"
    
    @property
    def is_production(self) -> bool:
        return self.app_env == "production"
    
    @property
    def is_development(self) -> bool:
        return self.app_env == "development"


# Global settings instance
settings = Settings()

