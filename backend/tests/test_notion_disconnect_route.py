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


def _make_app(service) -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_current_user_id] = lambda: "user-1"
    app.dependency_overrides[get_notion_backend_service] = lambda: service
    return app


class _DisconnectRouteServiceStub:
    def __init__(self) -> None:
        self.disconnect_calls: list[str] = []

    def disconnect(self, user_id: str) -> None:
        self.disconnect_calls.append(user_id)


class NotionDisconnectRouteTest(unittest.TestCase):
    def test_disconnect_response_excludes_secret_fields(self) -> None:
        service = _DisconnectRouteServiceStub()
        app = _make_app(service)

        response = TestClient(app).delete("/integrations/notion/connection")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(service.disconnect_calls, ["user-1"])
        payload = response.json()["data"]
        self.assertEqual(payload, {})
        self.assertNotIn("secret", response.text.lower())
        self.assertNotIn("token", response.text.lower())
        self.assertNotIn("encrypted", response.text.lower())


if __name__ == "__main__":
    unittest.main()
