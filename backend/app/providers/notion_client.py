import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass


NOTION_API_BASE_URL = "https://api.notion.com"
NOTION_API_VERSION = "2026-03-11"
DATABASE_ID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}(?:-?[0-9a-fA-F]{4}){3}-?[0-9a-fA-F]{12}",
)


class NotionClientError(Exception):
    pass


@dataclass(frozen=True)
class ResolvedNotionSource:
    database_id: str
    data_source_id: str
    database_title: str
    database_url: str | None
    pages: list[dict]


class NotionClient:
    def validate_integration_secret(
        self,
        *,
        notion_api_token: str,
    ) -> None:
        self._request_json(
            method="GET",
            path="/v1/users/me",
            notion_api_token=notion_api_token,
        )

    def resolve_source(
        self,
        *,
        notion_api_token: str,
        data_source_id: str | None = None,
        database_id: str | None = None,
        database_url: str | None = None,
    ) -> ResolvedNotionSource:
        preferred_data_source_id = normalize_database_id(data_source_id or "")
        extracted_identifiers = extract_notion_identifiers(
            data_source_id=data_source_id,
            database_id=database_id,
            database_url=database_url,
        )
        if not preferred_data_source_id and not extracted_identifiers:
            raise NotionClientError("Unable to resolve a valid Notion database identifier.")

        if preferred_data_source_id:
            try:
                return self._resolve_data_source(
                    notion_api_token=notion_api_token,
                    data_source_id=preferred_data_source_id,
                    fallback_database_url=database_url,
                    fallback_database_id=normalize_database_id(database_id or ""),
                )
            except NotionClientError as error:
                if not should_fallback_to_database(error):
                    raise

        last_error: NotionClientError | None = None
        for extracted_identifier in extracted_identifiers:
            try:
                return self._resolve_data_source(
                    notion_api_token=notion_api_token,
                    data_source_id=extracted_identifier,
                    fallback_database_url=database_url,
                )
            except NotionClientError as error:
                last_error = error
                if not should_fallback_to_database(error):
                    raise

            try:
                return self._resolve_database(
                    notion_api_token=notion_api_token,
                    database_id=extracted_identifier,
                    fallback_database_url=database_url,
                )
            except NotionClientError as error:
                last_error = error
                if not should_fallback_to_page(error):
                    raise

            try:
                return self._resolve_page_parent(
                    notion_api_token=notion_api_token,
                    page_id=extracted_identifier,
                    fallback_database_url=database_url,
                )
            except NotionClientError as error:
                last_error = error

        if last_error is not None:
            raise NotionClientError(
                f"{last_error} Extracted Notion identifiers: {', '.join(extracted_identifiers)}",
            ) from last_error
        raise NotionClientError(
            "Unable to resolve a valid Notion database identifier. "
            f"Extracted Notion identifiers: {', '.join(extracted_identifiers)}",
        )

    def _resolve_data_source(
        self,
        *,
        notion_api_token: str,
        data_source_id: str,
        fallback_database_url: str | None = None,
        fallback_database_id: str | None = None,
    ) -> ResolvedNotionSource:
        data_source = self.fetch_data_source(
            notion_api_token=notion_api_token,
            data_source_id=data_source_id,
        )
        pages = self.query_data_source_pages(
            notion_api_token=notion_api_token,
            data_source_id=data_source_id,
        )
        database_id = (
            extract_parent_database_id(data_source)
            or fallback_database_id
            or data_source_id
        )
        return ResolvedNotionSource(
            database_id=database_id,
            data_source_id=data_source_id,
            database_title=read_title_from_response(
                data_source,
                fallback="Notion Data Source",
            ),
            database_url=fallback_database_url,
            pages=pages,
        )

    def _resolve_database(
        self,
        *,
        notion_api_token: str,
        database_id: str,
        fallback_database_url: str | None = None,
    ) -> ResolvedNotionSource:
        database = self.fetch_database(
            notion_api_token=notion_api_token,
            database_id=database_id,
        )
        data_source_ids = extract_data_source_ids(database)
        if not data_source_ids:
            raise NotionClientError("No data sources were found for the provided Notion database.")

        pages = merge_pages_from_data_sources(
            client=self,
            notion_api_token=notion_api_token,
            data_source_ids=data_source_ids,
        )
        return ResolvedNotionSource(
            database_id=extract_parent_database_id(database) or database_id,
            data_source_id=data_source_ids[0],
            database_title=read_title_from_response(
                database,
                fallback="Notion Database",
            ),
            database_url=fallback_database_url,
            pages=pages,
        )

    def _resolve_page_parent(
        self,
        *,
        notion_api_token: str,
        page_id: str,
        fallback_database_url: str | None = None,
    ) -> ResolvedNotionSource:
        page = self.fetch_page(
            notion_api_token=notion_api_token,
            page_id=page_id,
        )
        parent = page.get("parent")
        if not isinstance(parent, dict):
            raise NotionClientError(
                "The provided Notion page is not connected to a database or data source.",
            )

        data_source_id = normalize_database_id(_read_parent_identifier(parent, "data_source_id"))
        if data_source_id:
            return self._resolve_data_source(
                notion_api_token=notion_api_token,
                data_source_id=data_source_id,
                fallback_database_url=fallback_database_url,
            )

        database_id = normalize_database_id(_read_parent_identifier(parent, "database_id"))
        if database_id:
            return self._resolve_database(
                notion_api_token=notion_api_token,
                database_id=database_id,
                fallback_database_url=fallback_database_url,
            )

        raise NotionClientError(
            "The provided Notion page is not connected to a database or data source.",
        )

    def fetch_data_source(
        self,
        *,
        notion_api_token: str,
        data_source_id: str,
    ) -> dict:
        return self._request_json(
            method="GET",
            path=f"/v1/data_sources/{data_source_id}",
            notion_api_token=notion_api_token,
        )

    def fetch_database(
        self,
        *,
        notion_api_token: str,
        database_id: str,
    ) -> dict:
        return self._request_json(
            method="GET",
            path=f"/v1/databases/{database_id}",
            notion_api_token=notion_api_token,
        )

    def fetch_page(
        self,
        *,
        notion_api_token: str,
        page_id: str,
    ) -> dict:
        return self._request_json(
            method="GET",
            path=f"/v1/pages/{page_id}",
            notion_api_token=notion_api_token,
        )

    def query_data_source_pages(
        self,
        *,
        notion_api_token: str,
        data_source_id: str,
    ) -> list[dict]:
        pages: list[dict] = []
        start_cursor: str | None = None

        while True:
            body: dict[str, object] = {"page_size": 100}
            if start_cursor is not None:
                body["start_cursor"] = start_cursor

            response = self._request_json(
                method="POST",
                path=f"/v1/data_sources/{data_source_id}/query",
                notion_api_token=notion_api_token,
                body=body,
            )
            pages.extend(response.get("results", []))
            if response.get("has_more") is not True:
                break
            start_cursor = response.get("next_cursor")

        return pages

    def _request_json(
        self,
        *,
        method: str,
        path: str,
        notion_api_token: str,
        body: dict[str, object] | None = None,
    ) -> dict:
        request = urllib.request.Request(
            url=f"{NOTION_API_BASE_URL}{path}",
            method=method,
            headers={
                "Authorization": f"Bearer {notion_api_token.strip()}",
                "Notion-Version": NOTION_API_VERSION,
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            data=json.dumps(body).encode("utf-8") if body is not None else None,
        )
        try:
            with urllib.request.urlopen(request) as response:
                raw_body = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            raw_body = error.read().decode("utf-8", errors="ignore")
            try:
                payload = json.loads(raw_body) if raw_body else {}
            except json.JSONDecodeError:
                payload = {}
            code = payload.get("code")
            message = payload.get("message") or "Notion API request failed."
            raise NotionClientError(f"{error.code}:{code}:{message}") from error
        except urllib.error.URLError as error:
            raise NotionClientError("Failed to reach the Notion API.") from error

        try:
            return json.loads(raw_body) if raw_body else {}
        except json.JSONDecodeError as error:
            raise NotionClientError("Failed to decode Notion API response.") from error


def extract_notion_identifier(
    *,
    data_source_id: str | None = None,
    database_id: str | None = None,
    database_url: str | None = None,
) -> str:
    identifiers = extract_notion_identifiers(
        data_source_id=data_source_id,
        database_id=database_id,
        database_url=database_url,
    )
    return identifiers[0] if identifiers else ""


def extract_notion_identifiers(
    *,
    data_source_id: str | None = None,
    database_id: str | None = None,
    database_url: str | None = None,
) -> list[str]:
    identifiers: list[str] = []

    def add_identifier(value: str) -> None:
        if value and value not in identifiers:
            identifiers.append(value)

    normalized_data_source_id = normalize_database_id(data_source_id or "")
    if normalized_data_source_id:
        add_identifier(normalized_data_source_id)

    normalized_database_id = normalize_database_id(database_id or "")
    if normalized_database_id:
        add_identifier(normalized_database_id)

    if database_url:
        for match in DATABASE_ID_PATTERN.finditer(database_url.strip()):
            compact = match.group(0).replace("-", "")
            add_identifier(
                (
                    f"{compact[0:8]}-"
                    f"{compact[8:12]}-"
                    f"{compact[12:16]}-"
                    f"{compact[16:20]}-"
                    f"{compact[20:32]}"
                ),
            )

    return identifiers


def normalize_database_id(value: str) -> str:
    match = DATABASE_ID_PATTERN.search(value.strip())
    if match is None:
        return ""

    compact = match.group(0).replace("-", "")
    return (
        f"{compact[0:8]}-"
        f"{compact[8:12]}-"
        f"{compact[12:16]}-"
        f"{compact[16:20]}-"
        f"{compact[20:32]}"
    )


def extract_data_source_ids(database_payload: dict) -> list[str]:
    data_sources = database_payload.get("data_sources", [])
    return [
        item["id"]
        for item in data_sources
        if isinstance(item, dict) and isinstance(item.get("id"), str) and item["id"]
    ]


def extract_parent_database_id(payload: dict) -> str | None:
    if not isinstance(payload, dict):
        return None

    parent = payload.get("parent")
    if isinstance(parent, dict):
        for key in ("database_id", "data_source_id"):
            value = parent.get(key)
            normalized = normalize_database_id(value) if isinstance(value, str) else ""
            if normalized:
                return normalized

    for key in ("database_id", "source_database_id"):
        value = payload.get(key)
        normalized = normalize_database_id(value) if isinstance(value, str) else ""
        if normalized:
            return normalized
    return None


def read_title_from_response(response: dict, *, fallback: str) -> str:
    title_items = response.get("title", [])
    title = "".join(
        item.get("plain_text", "")
        for item in title_items
        if isinstance(item, dict)
    ).strip()
    return title or fallback


def should_fallback_to_database(error: NotionClientError) -> bool:
    message = str(error)
    return (
        ":object_not_found:" in message
        or ":validation_error:" in message
        or message.startswith("404:")
    )


def should_fallback_to_page(error: NotionClientError) -> bool:
    return should_fallback_to_database(error)


def _read_parent_identifier(parent: dict, key: str) -> str:
    value = parent.get(key)
    if isinstance(value, str):
        return value
    return ""


def merge_pages_from_data_sources(
    *,
    client: NotionClient,
    notion_api_token: str,
    data_source_ids: list[str],
) -> list[dict]:
    pages: list[dict] = []
    seen_page_ids: set[str] = set()
    for data_source_id in data_source_ids:
        results = client.query_data_source_pages(
            notion_api_token=notion_api_token,
            data_source_id=data_source_id,
        )
        for page in results:
            page_id = page.get("id")
            if not isinstance(page_id, str) or page_id in seen_page_ids:
                continue
            seen_page_ids.add(page_id)
            pages.append(page)
    return pages
