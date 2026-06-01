import re
from datetime import UTC, datetime

from app.schemas.quest import QuestCategory, QuestDifficulty
from app.schemas.quest_generation import QuestCandidateResponse
from app.services.category_inference import infer_category_from_title
from app.services.difficulty_rules import (
    duration_from_difficulty,
    exp_from_difficulty,
)

_COMPLETION_KEYWORDS = (
    "done",
    "complete",
    "completed",
    "finished",
    "closed",
    "status",
    "state",
    "finish",
    "end",
    "closed",
    "complete",
    "completed",
    "done",
    "finished",
    "status",
    "state",
    "wanryo",
)

_COMPLETION_LABEL_KEYWORDS = (
    "done",
    "complete",
    "completed",
    "finished",
    "closed",
    "true",
    "yes",
    "wanryo",
)

_DURATION_PROPERTY_NAMES = (
    "duration",
    "minutes",
    "time",
    "estimate",
    "durationminutes",
    "estimatedtime",
    "timespent",
)

_DIFFICULTY_PROPERTY_NAMES = (
    "difficulty",
    "level",
    "priority",
    "difficultylevel",
)

_CATEGORY_PROPERTY_NAMES = (
    "category",
    "type",
    "tag",
    "tags",
    "area",
    "topic",
)

_EXP_PROPERTY_NAMES = (
    "exp",
    "xp",
    "reward",
    "points",
)

_DATE_PROPERTY_NAMES = (
    "date",
    "due",
    "deadline",
    "scheduled",
    "schedule",
    "start",
    "startdate",
    "duedate",
    "calendar",
)

_PROPERTY_DEFAULT_MESSAGES = (
    "Defaulted missing status to active.",
    "Defaulted missing or unknown difficulty to normal.",
    "Defaulted missing or unknown category from the title.",
    "Defaulted missing or invalid EXP from difficulty.",
    "Defaulted missing or invalid duration from difficulty.",
)


def parse_notion_pages_to_quests(pages: list[dict]) -> list[QuestCandidateResponse]:
    quests: list[QuestCandidateResponse] = []
    for raw_page in pages:
        page = raw_page if isinstance(raw_page, dict) else {}
        if is_completed_page(page):
            continue
        quests.append(parse_notion_page_to_quest(page))
    return quests


def parse_notion_page_to_quest(page: dict) -> QuestCandidateResponse:
    properties = get_page_properties(page)
    external_id = read_page_id(page)
    title = read_title(properties)
    warnings: list[str] = []

    if not title:
        title = build_fallback_title(external_id)
        warnings.append("Title property was missing or empty.")

    duration_minutes = read_duration_minutes(properties)
    difficulty, used_default_difficulty = read_difficulty(
        properties,
        duration_minutes=duration_minutes,
    )
    if used_default_difficulty:
        warnings.append("Difficulty property was missing or unrecognized.")

    category, used_default_category = read_category(properties, title=title)
    if used_default_category:
        warnings.append("Category property was missing or unrecognized.")

    exp, used_default_exp = read_exp(properties, difficulty=difficulty)
    if used_default_exp:
        warnings.append("EXP property was missing or invalid.")
    due_at = read_due_at(properties)

    default_duration_seconds = duration_from_difficulty(difficulty)
    if duration_minutes > 0:
        duration_seconds = duration_minutes * 60
        used_default_duration = False
    else:
        duration_seconds = default_duration_seconds
        used_default_duration = True
        warnings.append("Duration property was missing or invalid.")

    if not external_id:
        warnings.append("Notion page is missing a stable page ID.")

    if not read_page_url(page):
        warnings.append("Notion page URL was missing.")

    if page.get("last_edited_time") is not None and read_last_edited_time(page) is None:
        warnings.append("last_edited_time could not be parsed.")

    return QuestCandidateResponse(
        title=title,
        difficulty=difficulty,
        category=category,
        exp=exp,
        defaultDurationSeconds=duration_seconds,
        due_at=due_at,
        reason=build_reason(
            warnings,
            used_default_difficulty=used_default_difficulty,
            used_default_category=used_default_category,
            used_default_exp=used_default_exp,
            used_default_duration=used_default_duration,
        ),
        external_source="notion",
        external_id=external_id,
        external_url=read_page_url(page),
        external_updated_at=read_last_edited_time(page),
    )


def is_completed_page(page: dict) -> bool:
    if page.get("archived") is True or page.get("in_trash") is True:
        return True

    for name, raw_property in get_page_properties(page).items():
        if not isinstance(raw_property, dict):
            continue
        if not is_completion_property(normalize_key(name)):
            continue

        property_type = raw_property.get("type", "")
        if property_type == "checkbox" and raw_property.get("checkbox") is True:
            return True

        label = read_select_like_name(raw_property).lower()
        if any(keyword in label for keyword in _COMPLETION_LABEL_KEYWORDS):
            return True

    return False


def get_page_properties(page: dict) -> dict:
    properties = page.get("properties", {})
    return properties if isinstance(properties, dict) else {}


def read_page_id(page: dict) -> str | None:
    value = page.get("id")
    normalized = value.strip() if isinstance(value, str) else ""
    return normalized or None


def read_page_url(page: dict) -> str | None:
    value = page.get("url")
    normalized = value.strip() if isinstance(value, str) else ""
    return normalized or None


def read_last_edited_time(page: dict) -> datetime | None:
    value = page.get("last_edited_time")
    if not isinstance(value, str):
        return None

    normalized = value.strip()
    if not normalized:
        return None

    try:
        if normalized.endswith("Z"):
            normalized = normalized[:-1] + "+00:00"
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def read_title(properties: dict) -> str:
    for raw_property in properties.values():
        if not isinstance(raw_property, dict):
            continue
        if raw_property.get("type") != "title":
            continue
        title_items = raw_property.get("title", [])
        return "".join(
            item.get("plain_text", "")
            for item in title_items
            if isinstance(item, dict)
        ).strip()
    return ""


def read_duration_minutes(properties: dict) -> int:
    property_value = find_property(properties, _DURATION_PROPERTY_NAMES)
    if property_value is None:
        return 0

    property_type = property_value.get("type", "")
    if property_type == "number":
        number = property_value.get("number")
        if isinstance(number, (int, float)):
            return max(0, int(round(number)))
        return 0

    if property_type == "formula":
        formula = property_value.get("formula", {})
        if isinstance(formula, dict):
            if formula.get("type") == "number" and isinstance(formula.get("number"), (int, float)):
                return max(0, int(round(formula["number"])))
            if formula.get("type") == "string" and isinstance(formula.get("string"), str):
                return parse_duration_minutes(formula["string"])

    raw_text = read_plain_text(property_value)
    return parse_duration_minutes(raw_text)


def read_difficulty(
    properties: dict,
    *,
    duration_minutes: int,
) -> tuple[QuestDifficulty, bool]:
    property_value = find_property(properties, _DIFFICULTY_PROPERTY_NAMES)
    raw_value = read_plain_text(property_value).lower() if property_value else ""

    if any(word in raw_value for word in ("easy", "low", "simple", "small")):
        return QuestDifficulty.EASY, False
    if any(word in raw_value for word in ("hard", "high", "difficult", "large")):
        return QuestDifficulty.HARD, False
    if any(word in raw_value for word in ("medium", "mid", "normal", "default")):
        return QuestDifficulty.NORMAL, False

    if duration_minutes <= 0:
        return QuestDifficulty.NORMAL, True
    if duration_minutes <= 30:
        return QuestDifficulty.EASY, True
    if duration_minutes <= 60:
        return QuestDifficulty.NORMAL, True
    return QuestDifficulty.HARD, True


def read_category(properties: dict, *, title: str) -> tuple[QuestCategory, bool]:
    property_value = find_property(properties, _CATEGORY_PROPERTY_NAMES)
    raw_value = read_plain_text(property_value) if property_value else ""
    mapped = map_category(raw_value)
    if mapped is not None:
        return mapped, False
    return infer_category_from_title(title), True


def read_exp(
    properties: dict,
    *,
    difficulty: QuestDifficulty,
) -> tuple[int, bool]:
    property_value = find_property(properties, _EXP_PROPERTY_NAMES)
    if property_value is not None and property_value.get("type") == "number":
        number = property_value.get("number")
        if isinstance(number, (int, float)) and int(round(number)) > 0:
            return int(round(number)), False
    return exp_from_difficulty(difficulty), True


def read_due_at(properties: dict) -> datetime | None:
    property_value = find_property(properties, _DATE_PROPERTY_NAMES)
    if property_value is None:
        property_value = _first_date_property(properties)
    if property_value is None:
        return None

    property_type = property_value.get("type", "")
    if property_type == "date":
        return _parse_notion_date_value(property_value.get("date"))
    if property_type == "formula":
        formula = property_value.get("formula", {})
        if isinstance(formula, dict) and formula.get("type") == "date":
            return _parse_notion_date_value(formula.get("date"))
    return None


def _first_date_property(properties: dict) -> dict | None:
    for raw_property in properties.values():
        if isinstance(raw_property, dict) and raw_property.get("type") == "date":
            return raw_property
    return None


def find_property(properties: dict, candidate_names: tuple[str, ...]) -> dict | None:
    normalized_candidates = {normalize_key(name) for name in candidate_names}
    for name, raw_property in properties.items():
        if not isinstance(raw_property, dict):
            continue
        if normalize_key(name) in normalized_candidates:
            return raw_property
    return None


def read_plain_text(property_value: dict | None) -> str:
    if property_value is None:
        return ""

    property_type = property_value.get("type", "")
    if property_type in {"select", "status"}:
        return read_select_like_name(property_value)
    if property_type == "multi_select":
        values = property_value.get("multi_select", [])
        return " ".join(
            item.get("name", "")
            for item in values
            if isinstance(item, dict) and item.get("name")
        ).strip()
    if property_type == "rich_text":
        values = property_value.get("rich_text", [])
        return "".join(
            item.get("plain_text", "")
            for item in values
            if isinstance(item, dict)
        ).strip()
    if property_type == "number":
        value = property_value.get("number")
        return "" if value is None else str(value)
    if property_type == "checkbox":
        return "true" if property_value.get("checkbox") is True else "false"
    if property_type == "formula":
        formula = property_value.get("formula", {})
        if not isinstance(formula, dict):
            return ""
        if formula.get("type") == "string":
            value = formula.get("string")
            return value.strip() if isinstance(value, str) else ""
        if formula.get("type") == "number":
            value = formula.get("number")
            return "" if value is None else str(value)
        if formula.get("type") == "boolean":
            return "true" if formula.get("boolean") is True else "false"
    return ""


def read_select_like_name(property_value: dict) -> str:
    property_type = property_value.get("type", "")
    nested = property_value.get(property_type, {})
    return nested.get("name", "") if isinstance(nested, dict) else ""


def _parse_notion_date_value(raw_value: object) -> datetime | None:
    if not isinstance(raw_value, dict):
        return None

    start = raw_value.get("start")
    if not isinstance(start, str):
        return None

    normalized = start.strip()
    if not normalized:
        return None

    # Notion all-day dates arrive as YYYY-MM-DD without timezone.
    # Store them at noon UTC so common client timezones preserve the same date.
    if "T" not in normalized:
        try:
            parsed = datetime.fromisoformat(normalized)
        except ValueError:
            return None
        return datetime(parsed.year, parsed.month, parsed.day, 12, 0, tzinfo=UTC)

    try:
        if normalized.endswith("Z"):
            normalized = normalized[:-1] + "+00:00"
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def parse_duration_minutes(raw_text: str) -> int:
    normalized = raw_text.lower().replace(" ", "")
    if not normalized:
        return 0

    hours_match = re.search(r"(\d+)h", normalized)
    minutes_match = re.search(r"(\d+)m", normalized)
    if hours_match or minutes_match:
        hours = int(hours_match.group(1)) if hours_match else 0
        minutes = int(minutes_match.group(1)) if minutes_match else 0
        return hours * 60 + minutes

    colon_match = re.search(r"^(\d+):(\d+)$", normalized)
    if colon_match:
        return int(colon_match.group(1)) * 60 + int(colon_match.group(2))

    hour_words = ("hour", "hours", "hr", "hrs")
    if any(word in normalized for word in hour_words):
        hours_text = re.search(r"\d+", normalized)
        return int(hours_text.group(0)) * 60 if hours_text is not None else 0

    minute_words = ("minute", "minutes", "min", "mins")
    if any(word in normalized for word in minute_words):
        minutes_text = re.search(r"\d+", normalized)
        return int(minutes_text.group(0)) if minutes_text is not None else 0

    first_number_match = re.search(r"\d+", normalized)
    if first_number_match is None:
        return 0
    return int(first_number_match.group(0))


def map_category(value: str) -> QuestCategory | None:
    normalized = value.strip().lower()
    if not normalized:
        return None
    if any(word in normalized for word in ("work", "job", "project", "office", "meeting")):
        return QuestCategory.WORK
    if any(word in normalized for word in ("study", "learn", "research", "course", "read")):
        return QuestCategory.STUDY
    if any(word in normalized for word in ("life", "health", "exercise", "habit", "routine")):
        return QuestCategory.LIFE
    if any(word in normalized for word in ("home", "todo", "house", "clean", "shopping")):
        return QuestCategory.HOME
    return None


def is_completion_property(normalized_name: str) -> bool:
    return any(keyword in normalized_name for keyword in _COMPLETION_KEYWORDS)


def normalize_key(value: str) -> str:
    return "".join(character for character in value.lower() if character.isalnum())


def build_fallback_title(external_id: str | None) -> str:
    if external_id:
        return f"Untitled Notion page ({external_id[:8]})"
    return "Untitled Notion page"


def build_reason(
    warnings: list[str],
    *,
    used_default_difficulty: bool,
    used_default_category: bool,
    used_default_exp: bool,
    used_default_duration: bool,
) -> str:
    reason_parts = ["Generated from Notion sync."]
    if used_default_difficulty:
        reason_parts.append(_PROPERTY_DEFAULT_MESSAGES[1])
    if used_default_category:
        reason_parts.append(_PROPERTY_DEFAULT_MESSAGES[2])
    if used_default_exp:
        reason_parts.append(_PROPERTY_DEFAULT_MESSAGES[3])
    if used_default_duration:
        reason_parts.append(_PROPERTY_DEFAULT_MESSAGES[4])

    if warnings:
        reason_parts.append("Warnings: " + " ".join(warnings))

    return " ".join(reason_parts)
