from fastapi import FastAPI

from app.routes.health import router as health_router
from app.routes.upload import router as upload_router
from app.routes.chat import router as chat_router


def create_app() -> FastAPI:
    app = FastAPI(title="Speak2Fill Backend", version="0.1.0")

    app.include_router(health_router)
    app.include_router(upload_router)
    app.include_router(chat_router)

    return app


app = create_app()
