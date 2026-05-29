import sys
import types
import unittest

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
from app.schemas.notion import NotionConnectionStatusResponse


def _make_app(service) -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_current_user_id] = lambda: "user-1"
    app.dependency_overrides[get_notion_backend_service] = lambda: service
    return app


class _StatusRouteServiceStub:
    def __init__(self, response: NotionConnectionStatusResponse) -> None:
        self.response = response

    def get_status(self, user_id: str) -> NotionConnectionStatusResponse:
        return self.response


class NotionStatusRouteTest(unittest.TestCase):
    def test_status_response_uses_snake_case_and_excludes_token_fields(self) -> None:
        app = _make_app(
            _StatusRouteServiceStub(
                NotionConnectionStatusResponse(
                    connected=True,
                    connection_id="connection-1",
                    database_id="database-1",
                    data_source_id="data-source-1",
                    database_title="Tasks",
                    database_url="https://www.notion.so/tasks",
                    last_synced_at="2026-05-18T01:02:03+00:00",
                    last_successful_synced_at="2026-05-18T01:03:03+00:00",
                    sync_status="success",
                    last_error_message=None,
                ),
            ),
        )

        response = TestClient(app).get("/integrations/notion/status")

        self.assertEqual(response.status_code, 200)
        payload = response.json()["data"]
        self.assertEqual(payload["connection_id"], "connection-1")
        self.assertEqual(payload["database_id"], "database-1")
        self.assertEqual(payload["data_source_id"], "data-source-1")
        self.assertEqual(payload["database_title"], "Tasks")
        self.assertEqual(payload["database_url"], "https://www.notion.so/tasks")
        self.assertEqual(payload["last_synced_at"], "2026-05-18T01:02:03+00:00")
        self.assertEqual(
            payload["last_successful_synced_at"],
            "2026-05-18T01:03:03+00:00",
        )
        self.assertEqual(payload["sync_status"], "success")
        self.assertIn("last_error_message", payload)
        self.assertNotIn("access_token_encrypted", payload)
        self.assertNotIn("refresh_token_encrypted", payload)
        self.assertNotIn("notion_api_token", payload)
        self.assertNotIn("token", payload)
        self.assertNotIn("encrypted", payload)

    def test_status_response_can_return_connected_false_without_connection(self) -> None:
        app = _make_app(
            _StatusRouteServiceStub(
                NotionConnectionStatusResponse(connected=False),
            ),
        )

        response = TestClient(app).get("/integrations/notion/status")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"]["connected"], False)


if __name__ == "__main__":
    unittest.main()
