"""
Development server runner
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",  # Changed from 0.0.0.0 for Windows compatibility
        port=8000,
        reload=True,
        log_level="info"
    )

