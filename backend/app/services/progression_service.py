from datetime import UTC, datetime, timedelta, tzinfo
from zoneinfo import ZoneInfo
from zoneinfo import ZoneInfoNotFoundError

from app.repositories.base import ProfileState, StatsState


def apply_exp(
    *,
    level: int,
    current_exp: int,
    max_exp: int,
    gained_exp: int,
) -> tuple[int, int, int]:
    next_level = level
    next_current_exp = current_exp + gained_exp
    next_max_exp = max_exp

    while next_current_exp >= next_max_exp and next_max_exp > 0:
        next_current_exp -= next_max_exp
        next_level += 1
        next_max_exp = 500 + (next_level * 100)

    return next_level, next_current_exp, next_max_exp




def remove_exp(
    *,
    level: int,
    current_exp: int,
    max_exp: int,
    lost_exp: int,
) -> tuple[int, int, int]:
    next_level = max(0, int(level))
    next_current_exp = max(0, int(current_exp))
    next_max_exp = max(1, int(max_exp))
    remaining_loss = max(0, int(lost_exp))

    while remaining_loss > next_current_exp and next_level > 0:
        remaining_loss -= next_current_exp
        next_level -= 1
        next_max_exp = 500 + (next_level * 100)
        next_current_exp = next_max_exp

    next_current_exp = max(0, next_current_exp - remaining_loss)
    return next_level, next_current_exp, next_max_exp


def subtract_category_stats(
    *,
    diligence_stat: int,
    order_stat: int,
    intelligence_stat: int,
    health_stat: int,
    category: str,
    difficulty: str,
) -> tuple[int, int, int, int]:
    difficulty_key = difficulty.lower()
    diligence_gain = {"easy": 4, "normal": 6, "hard": 9}.get(difficulty_key, 9)
    category_gain = {"easy": 5, "normal": 8, "hard": 12}.get(difficulty_key, 12)
    normalized_category = category.lower()

    next_diligence = max(
        0,
        diligence_stat - diligence_gain - (category_gain if normalized_category == "work" else 0),
    )
    next_order = (
        max(0, order_stat - category_gain)
        if normalized_category == "home"
        else order_stat
    )
    next_intelligence = (
        max(0, intelligence_stat - category_gain)
        if normalized_category == "study"
        else intelligence_stat
    )
    next_health = (
        max(0, health_stat - category_gain)
        if normalized_category == "life"
        else health_stat
    )

    return next_diligence, next_order, next_intelligence, next_health

def normalized_weekly_counts(counts: list[int]) -> list[int]:
    normalized = list(counts[:7]) if counts else [0] * 7
    while len(normalized) < 7:
        normalized.append(0)
    return normalized


def build_weekly_bars(counts: list[int]) -> list[float]:
    max_count = max(counts) if counts else 0
    if max_count <= 0:
        return [0.0] * 7
    return [count / max_count for count in counts[:7]]


def calculate_weekly_completion_rate(
    completed_count: int,
    weekly_target: int,
) -> int:
    if weekly_target <= 0:
        return 0
    return min(100, round((completed_count / weekly_target) * 100))


def apply_category_stats(
    *,
    diligence_stat: int,
    order_stat: int,
    intelligence_stat: int,
    health_stat: int,
    category: str,
    difficulty: str,
) -> tuple[int, int, int, int]:
    difficulty_key = difficulty.lower()
    diligence_gain = {"easy": 4, "normal": 6, "hard": 9}.get(difficulty_key, 9)
    category_gain = {"easy": 5, "normal": 8, "hard": 12}.get(difficulty_key, 12)
    normalized_category = category.lower()

    next_diligence = min(
        100,
        diligence_stat + diligence_gain + (category_gain if normalized_category == "work" else 0),
    )
    next_order = min(100, order_stat + category_gain) if normalized_category == "home" else order_stat
    next_intelligence = (
        min(100, intelligence_stat + category_gain)
        if normalized_category == "study"
        else intelligence_stat
    )
    next_health = min(100, health_stat + category_gain) if normalized_category == "life" else health_stat

    return next_diligence, next_order, next_intelligence, next_health


def role_for_level(level: int) -> str:
    if level >= 8:
        return "Master"
    if level >= 5:
        return "Expert"
    if level >= 2:
        return "Adventurer"
    return "Beginner"


def date_key(value: datetime) -> str:
    return value.strftime("%Y-%m-%d")


def month_key(value: datetime) -> str:
    return value.strftime("%Y-%m")


def week_key(value: datetime) -> str:
    start_of_week = value.replace(hour=0, minute=0, second=0, microsecond=0)
    start_of_week = start_of_week - timedelta(days=value.weekday())
    return date_key(start_of_week)


def service_timezone() -> tzinfo:
    try:
        return ZoneInfo("Asia/Seoul")
    except ZoneInfoNotFoundError:
        return UTC


def normalize_progress(
    profile: ProfileState,
    stats: StatsState,
    today_key: str,
    week_key_value: str,
    month_key_value: str,
) -> tuple[ProfileState, StatsState]:
    if profile.daily_reset_key != today_key:
        stats.daily_reward_count = 0
        profile.daily_reset_key = today_key

    if profile.weekly_reset_key != week_key_value:
        stats.weekly_reward_count = 0
        stats.weekly_completed_count = 0
        stats.previous_weekly_completion_rate = stats.weekly_completion_rate
        stats.weekly_completion_rate = 0
        stats.weekly_rate_delta = 0
        stats.weekly_activity_counts = [0] * 7
        stats.weekly_activity_bars = [0.0] * 7
        profile.weekly_reset_key = week_key_value

    if profile.monthly_reset_key != month_key_value:
        stats.monthly_reward_count = 0
        profile.monthly_reset_key = month_key_value

    if not profile.daily_reset_key:
        profile.daily_reset_key = today_key
    if not profile.weekly_reset_key:
        profile.weekly_reset_key = week_key_value
    if not profile.monthly_reset_key:
        profile.monthly_reset_key = month_key_value

    return profile, stats
