"""
Main FastAPI application
"""
import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from app.config import settings
from app.database import init_db, close_db


# Configure logging
os.makedirs("logs", exist_ok=True)
logger.add(
    settings.log_file,
    rotation="100 MB",
    retention="30 days",
    level=settings.log_level,
    format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}"
)

# Отключить логи SQLAlchemy (они засоряют вывод)
logging.getLogger('sqlalchemy.engine').setLevel(logging.ERROR)
logging.getLogger('sqlalchemy.pool').setLevel(logging.ERROR)
logging.getLogger('sqlalchemy.dialects').setLevel(logging.ERROR)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager for startup/shutdown events
    """
    # Startup
    logger.info("Starting NovoFon Voice Bot...")
    logger.info(f"Environment: {settings.app_env}")
    
    # Initialize database
    try:
        await init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise
    
    # Initialize Baresip client (for RTP handling)
    baresip_client = None
    try:
        from app.services.baresip_client import get_baresip_client
        
        baresip_client = get_baresip_client()
        await baresip_client.connect()
        
        logger.info("✅ Baresip client connected successfully")
    except Exception as e:
        logger.warning(f"Baresip not available: {e}")
        logger.info("Bot will work without baresip (RTP handling disabled)")
    
    # Initialize Asterisk ARI (if configured)
    ari_client = None
    try:
        from app.services.asterisk_ari import get_ari_client
        from app.services.asterisk_call_handler import get_call_handler
        
        ari_client = get_ari_client()
        await ari_client.connect()
        
        # Initialize call handler
        get_call_handler(ari_client)
        
        logger.info("Asterisk ARI connected successfully")
    except Exception as e:
        logger.warning(f"Asterisk ARI not available: {e}")
        logger.info("Bot will work in limited mode (no SIP calls)")
    
    # Initialize call queue manager (auto-start)
    try:
        from app.services.call_queue_manager import get_queue_manager
        
        queue_manager = get_queue_manager()
        await queue_manager.start()
        
        logger.info("Call queue manager started")
    except Exception as e:
        logger.warning(f"Call queue manager not started: {e}")
    
    yield
    
    # Shutdown
    logger.info("Shutting down NovoFon Voice Bot...")
    
    # Stop call queue manager
    try:
        from app.services.call_queue_manager import get_queue_manager
        queue_manager = get_queue_manager()
        await queue_manager.stop()
        logger.info("Call queue manager stopped")
    except Exception as e:
        logger.error(f"Error stopping queue manager: {e}")
    
    # Disconnect Baresip client
    if baresip_client:
        try:
            await baresip_client.disconnect()
            logger.info("Baresip client disconnected")
        except Exception as e:
            logger.error(f"Error disconnecting baresip: {e}")
    
    # Disconnect Asterisk ARI
    if ari_client:
        try:
            await ari_client.disconnect()
            logger.info("Asterisk ARI disconnected")
        except Exception as e:
            logger.error(f"Error disconnecting ARI: {e}")
    
    await close_db()
    logger.info("Database connections closed")


# Create FastAPI app
app = FastAPI(
    title="NovoFon Voice Bot",
    description="Голосовой робот-обзвонщик с интеграцией NovoFon + Asterisk + ElevenLabs",
    version="0.1.0",
    debug=settings.debug,
    lifespan=lifespan
)


# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.is_development else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "error": str(exc) if settings.is_development else None
        }
    )


# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "environment": settings.app_env,
        "version": "0.1.0"
    }


# Root endpoint
@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "NovoFon Voice Bot API",
        "version": "0.1.0",
        "docs": "/docs",
        "health": "/health"
    }


# Import routers
from app.routers import calls, system, queue

app.include_router(system.router, tags=["system"])
app.include_router(calls.router, prefix="/api/calls", tags=["calls"])
app.include_router(queue.router, prefix="/api/queue", tags=["queue"])

# TODO: Add more routers
# from app.routers import webhooks
# app.include_router(webhooks.router, prefix="/webhooks", tags=["webhooks"])


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.app_host,
        port=settings.app_port,
        reload=settings.is_development,
        log_level=settings.log_level.lower()
    )

