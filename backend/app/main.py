from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response as StarletteResponse

from app.routes.health import router as health_router
from app.routes.analyze import router as analyze_router
from app.routes.chat import router as chat_router


def create_app() -> FastAPI:
    app = FastAPI(title="Speak2Fill Backend", version="0.1.0")

    # Enable CORS for local development (frontend running on localhost)
    from fastapi.middleware.cors import CORSMiddleware

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "http://localhost:38327",  # Flutter web dev server
            "http://localhost:3000",   # fallback (if needed)
            "http://localhost:8000",   # backend itself
        ],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


    app.include_router(health_router)
    app.include_router(analyze_router)
    app.include_router(chat_router)

    # Extra safety: ensure CORS headers exist on all responses (fallback)
    @app.middleware("http")
    async def add_cors_headers(request: Request, call_next):
        # Handle simple OPTIONS preflight quickly
        if request.method == "OPTIONS":
            return StarletteResponse(status_code=200, headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Headers": "*",
            })

        response = await call_next(request)
        response.headers.setdefault("Access-Control-Allow-Origin", "*")
        response.headers.setdefault("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
        response.headers.setdefault("Access-Control-Allow-Headers", "*")
        return response

    return app


app = create_app()
