import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

from app.api.router import api_router
from app.core.config import settings
from app.core.supabase import get_supabase_client
from app.schemas.common import ErrorDetail
from app.services.notion_sync_service import IntegrationException


logger = logging.getLogger(__name__)


def configure_logging() -> None:
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(IntegrationException)
    async def handle_integration_exception(
        request: Request,
        exc: IntegrationException,
    ) -> JSONResponse:
        logger.warning("Integration error on %s: %s", request.url.path, exc)
        return JSONResponse(
            status_code=400,
            content={
                "success": False,
                "data": None,
                "error": ErrorDetail(
                    code="integration_error",
                    message=str(exc),
                ).model_dump(),
            },
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_exception(
        request: Request,
        exc: Exception,
    ) -> JSONResponse:
        logger.exception("Unhandled error on %s", request.url.path, exc_info=exc)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "data": None,
                "error": ErrorDetail(
                    code="internal_server_error",
                    message="An unexpected server error occurred.",
                ).model_dump(),
            },
        )


def configure_cors(app: FastAPI) -> None:
    allowed_origins = settings.cors_allowed_origins
    if not allowed_origins:
        logger.info("CORS middleware disabled because no web origins were configured.")
        return

    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    logger.info("Enabled CORS for %s", ", ".join(allowed_origins))


def create_app() -> FastAPI:
    configure_logging()
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=settings.app_description,
        docs_url="/docs",
        redoc_url="/redoc",
    )
    register_exception_handlers(app)
    configure_cors(app)

    @app.on_event("startup")
    async def validate_external_clients() -> None:
        # Force client initialization at startup so missing secrets fail fast.
        get_supabase_client()

    @app.get(
        "/",
        summary="Welcome",
        description="Simple welcome endpoint for confirming the API is running.",
    )
    async def root() -> dict[str, str]:
        return {
            "app_name": settings.app_name,
            "version": settings.app_version,
            "environment": settings.environment,
            "message": "Welcome to the Start On API.",
        }

    app.include_router(api_router)
    logger.info(
        "Created FastAPI app '%s' version %s in %s environment.",
        settings.app_name,
        settings.app_version,
        settings.environment,
    )
    return app


app = create_app()


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.api_reload,
    )
