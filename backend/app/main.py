from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response as StarletteResponse
import logging
import os
from app.routes.health import router as health_router
from app.routes.analyze import router as analyze_router
from app.routes.chat import router as chat_router
from app.routes.stt import router as stt_router
from app.routes.tts import router as tts_router


# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    app = FastAPI(title="Speak2Fill Backend", version="0.1.0")


    app.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "http://localhost:5000",  # Flutter web frontend (dev)
            "http://localhost:8000",  # backend itself (dev)
            os.getenv("FRONTEND_URL", "https://speak2fill.web.app"),  # production frontend
        ],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["*"]
    )



    app.include_router(chat_router)
    app.include_router(health_router)
    app.include_router(analyze_router)
    app.include_router(stt_router)
    app.include_router(tts_router)

    # CORSMiddleware handles preflight and headers; no extra CORS middleware needed

    return app


app = create_app()
