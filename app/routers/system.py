"""
System and health check endpoints
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from loguru import logger

from app.database import get_db
from app.services.novofon import get_novofon_client, NovoFonClient


router = APIRouter()


@router.get("/health")
async def health_check(
    db: AsyncSession = Depends(get_db),
    novofon: NovoFonClient = Depends(get_novofon_client)
):
    """
    Comprehensive health check
    
    Checks:
    - API server status
    - Database connectivity
    - NovoFon API accessibility
    """
    health_status = {
        "status": "healthy",
        "checks": {}
    }
    
    # Check database
    try:
        await db.execute(text("SELECT 1"))
        health_status["checks"]["database"] = "healthy"
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        health_status["checks"]["database"] = "unhealthy"
        health_status["status"] = "degraded"
    
    # Check NovoFon API
    try:
        is_accessible = await novofon.health_check()
        health_status["checks"]["novofon_api"] = "healthy" if is_accessible else "unhealthy"
        if not is_accessible:
            health_status["status"] = "degraded"
    except Exception as e:
        logger.error(f"NovoFon health check failed: {e}")
        health_status["checks"]["novofon_api"] = "unhealthy"
        health_status["status"] = "degraded"
    
    return health_status


@router.get("/health/database")
async def database_health_check(db: AsyncSession = Depends(get_db)):
    """
    Database connectivity check
    """
    try:
        result = await db.execute(text("SELECT version()"))
        version = result.scalar()
        return {
            "status": "healthy",
            "database": "postgresql",
            "version": version
        }
    except Exception as e:
        logger.error(f"Database check failed: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }


@router.get("/health/novofon")
async def novofon_health_check(novofon: NovoFonClient = Depends(get_novofon_client)):
    """
    NovoFon API accessibility check
    """
    try:
        is_accessible = await novofon.health_check()
        return {
            "status": "healthy" if is_accessible else "unhealthy",
            "api_url": novofon.api_url
        }
    except Exception as e:
        logger.error(f"NovoFon check failed: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }

