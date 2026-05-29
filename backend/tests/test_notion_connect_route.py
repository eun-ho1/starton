import unittest
import sys
import types

from fastapi import FastAPI
from fastapi.testclient import TestClient

google_module = types.ModuleType("google")
google_genai_module = types.ModuleType("google.genai")
google_genai_types_module = types.ModuleType("google.genai.types")
google_genai_module.Client = object
google_genai_module.types = google_genai_types_module
google_module.genai = google_genai_module
sys.modules.setdefault("google", google_module)
sys.modules.setdefault("google.genai", google_genai_module)
sys.modules.setdefault("google.genai.types", google_genai_types_module)

from app.api.dependencies import get_current_user_id, get_notion_backend_service
from app.api.routes.integrations_notion import router
from app.schemas.notion import NotionConnectResponse
from app.services.notion_sync_service import IntegrationException


def _make_app(service) -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_current_user_id] = lambda: "user-1"
    app.dependency_overrides[get_notion_backend_service] = lambda: service
    return app


class _ConnectRouteServiceStub:
    def __init__(self, *, response=None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error

    def connect(self, user_id: str, payload) -> NotionConnectResponse:
        if self.error is not None:
            raise self.error
        return self.response


class NotionConnectRouteTest(unittest.TestCase):
    def test_connect_success_response_excludes_secret_fields(self) -> None:
        app = _make_app(
            _ConnectRouteServiceStub(
                response=NotionConnectResponse(
                    connection_id="connection-1",
                    database_id="35bdd41f-ce07-8152-92ae-dabdfc826f3b",
                    database_title="Tasks",
                    sync_status="active",
                ),
            ),
        )

        response = TestClient(app).post(
            "/integrations/notion/connect",
            json={
                "notion_api_token": "secret_123",
                "database_id": "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()["data"]
        self.assertEqual(payload["connection_id"], "connection-1")
        self.assertNotIn("secret", payload)
        self.assertNotIn("token", payload)
        self.assertNotIn("encrypted", payload)

    def test_connect_invalid_secret_returns_user_friendly_error(self) -> None:
        app = _make_app(
            _ConnectRouteServiceStub(
                error=IntegrationException("401:unauthorized:Invalid auth"),
            ),
        )

        response = TestClient(app).post(
            "/integrations/notion/connect",
            json={
                "notion_api_token": "bad-secret",
                "database_id": "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["detail"]["message"],
            "The provided Notion integration secret is invalid. Check the secret and try again.",
        )

    def test_connect_permission_error_returns_user_friendly_error(self) -> None:
        app = _make_app(
            _ConnectRouteServiceStub(
                error=IntegrationException(
                    "404:object_not_found:Could not find database",
                ),
            ),
        )

        response = TestClient(app).post(
            "/integrations/notion/connect",
            json={
                "notion_api_token": "secret_123",
                "database_id": "35bdd41f-ce07-8152-92ae-dabdfc826f3b",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn(
            "does not have access",
            response.json()["detail"]["message"],
        )

    def test_connect_error_message_includes_extracted_identifier_hint(self) -> None:
        app = _make_app(
            _ConnectRouteServiceStub(
                error=IntegrationException(
                    "404:object_not_found:Could not find database "
                    "Extracted Notion identifiers: 36c9dc17-7c56-8071-ba7f-cfc985bad111",
                ),
            ),
        )

        response = TestClient(app).post(
            "/integrations/notion/connect",
            json={
                "notion_api_token": "secret_123",
                "database_url": "https://www.notion.so/test-36c9dc177c568071ba7fcfc985bad111",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn(
            "Extracted ID: 36c9dc17-7c56-8071-ba7f-cfc985bad111",
            response.json()["detail"]["message"],
        )


class _SyncRouteServiceStub:
    def __init__(self, *, error: Exception | None = None) -> None:
        self.error = error

    def sync(self, user_id: str, payload) -> None:
        if self.error is not None:
            raise self.error
        return None


class NotionSyncRouteTest(unittest.TestCase):
    def test_sync_unexpected_error_returns_safe_message_instead_of_unexpectedly(self) -> None:
        app = _make_app(
            _SyncRouteServiceStub(
                error=RuntimeError("401:unauthorized:token leaked"),
            ),
        )

        response = TestClient(app).post(
            "/integrations/notion/sync",
            json={},
        )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(
            response.json()["detail"]["message"],
            "Notion access was denied. Reconnect the integration and try again.",
        )


if __name__ == "__main__":
    unittest.main()
