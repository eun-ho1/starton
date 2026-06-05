import re
from enum import StrEnum
from typing import Any

from app.schemas.mediator import MediatorOutput, MediatorSubtask


class SubtaskTimeAllocation(StrEnum):
    EQUAL = "equal"
    MIDDLE_PEAK = "middle_peak"
    PROGRESSIVE = "progressive"


_TIME_ALLOCATION_VALUES = {item.value for item in SubtaskTimeAllocation}
_TIME_ALLOCATION_PATTERN = re.compile(r"time_allocation\s*=\s*([a-z_]+)", re.IGNORECASE)


def resolve_time_allocation(client_metadata: dict[str, Any] | None) -> str | None:
    metadata = client_metadata or {}

    direct_value = _normalized_allocation_value(metadata.get("time_allocation"))
    if direct_value is not None:
        return direct_value

    prompt = metadata.get("subtask_generation_prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        return None

    match = _TIME_ALLOCATION_PATTERN.search(prompt)
    if match is None:
        return None
    return _normalized_allocation_value(match.group(1))


def apply_time_allocation(
    output: MediatorOutput,
    *,
    client_metadata: dict[str, Any] | None = None,
) -> MediatorOutput:
    allocation = resolve_time_allocation(client_metadata)
    if allocation is None or not output.subtasks:
        return output

    total_minutes = _resolve_total_minutes(output, client_metadata or {})
    if total_minutes is None or total_minutes <= 0:
        return output

    subtasks = list(output.subtasks)
    allocated_minutes = _allocated_minutes(
        total_minutes=total_minutes,
        subtasks=subtasks,
        allocation=allocation,
    )
    updated_subtasks = [
        subtask.model_copy(update={"estimated_minutes": allocated_minutes[index]})
        for index, subtask in enumerate(subtasks)
    ]
    return output.model_copy(
        update={
            "subtasks": updated_subtasks,
            "estimated_minutes": sum(allocated_minutes),
        }
    )


def _resolve_total_minutes(
    output: MediatorOutput,
    client_metadata: dict[str, Any],
) -> int | None:
    if isinstance(output.estimated_minutes, int) and output.estimated_minutes > 0:
        return output.estimated_minutes

    subtask_total = sum(
        subtask.estimated_minutes
        for subtask in output.subtasks
        if isinstance(subtask.estimated_minutes, int) and subtask.estimated_minutes > 0
    )
    if subtask_total > 0:
        return subtask_total

    duration_seconds = client_metadata.get("default_duration_seconds")
    if isinstance(duration_seconds, (int, float)) and not isinstance(duration_seconds, bool):
        duration_minutes = int(duration_seconds // 60)
        if duration_minutes > 0:
            return duration_minutes

    return None


def _allocated_minutes(
    *,
    total_minutes: int,
    subtasks: list[MediatorSubtask],
    allocation: str,
) -> list[int]:
    if len(subtasks) == 1:
        return [total_minutes]

    weights = _weights(allocation, len(subtasks))
    next_action_index = _next_action_index(subtasks)
    preserved_minutes = _preserved_next_action_minutes(subtasks, next_action_index)

    if next_action_index is None or preserved_minutes is None:
        return _allocate_by_weights(total_minutes, weights)

    remaining_total = total_minutes - preserved_minutes
    if remaining_total <= 0:
        allocated = _allocate_by_weights(total_minutes, weights)
        allocated[next_action_index] = max(1, min(total_minutes, preserved_minutes))
        return _rebalance_total(allocated, total_minutes)

    other_weights = [weight for index, weight in enumerate(weights) if index != next_action_index]
    other_allocations = _allocate_by_weights(remaining_total, other_weights)

    allocated: list[int] = []
    other_index = 0
    for index in range(len(subtasks)):
        if index == next_action_index:
            allocated.append(preserved_minutes)
            continue
        allocated.append(other_allocations[other_index])
        other_index += 1
    return allocated


def _weights(allocation: str, count: int) -> list[int]:
    if allocation == SubtaskTimeAllocation.EQUAL.value:
        return [1] * count
    if allocation == SubtaskTimeAllocation.MIDDLE_PEAK.value:
        midpoint = (count - 1) / 2
        return [max(1, count - int(abs(index - midpoint) * 2)) for index in range(count)]
    if allocation == SubtaskTimeAllocation.PROGRESSIVE.value:
        return [index + 1 for index in range(count)]
    return [1] * count


def _allocate_by_weights(total_minutes: int, weights: list[int]) -> list[int]:
    count = len(weights)
    if count == 0:
        return []
    if count == 1:
        return [total_minutes]

    baseline = [1] * count if total_minutes >= count else [0] * count
    remaining = total_minutes - sum(baseline)
    if remaining <= 0:
        return _rebalance_total(baseline, total_minutes)

    weight_sum = sum(weights) or count
    raw_shares = [(remaining * weight) / weight_sum for weight in weights]
    floor_shares = [int(share) for share in raw_shares]
    allocations = [baseline[index] + floor_shares[index] for index in range(count)]

    leftover = remaining - sum(floor_shares)
    ranked_indexes = sorted(
        range(count),
        key=lambda index: (raw_shares[index] - floor_shares[index], weights[index], -index),
        reverse=True,
    )
    for index in ranked_indexes[:leftover]:
        allocations[index] += 1
    return allocations


def _rebalance_total(values: list[int], total_minutes: int) -> list[int]:
    allocated = list(values)
    difference = total_minutes - sum(allocated)
    if difference == 0 or not allocated:
        return allocated

    step = 1 if difference > 0 else -1
    index = 0
    while difference != 0 and allocated:
        if step > 0 or allocated[index] > 0:
            allocated[index] += step
            difference -= step
        index = (index + 1) % len(allocated)
    return allocated


def _next_action_index(subtasks: list[MediatorSubtask]) -> int | None:
    for index, subtask in enumerate(subtasks):
        if subtask.is_next_action:
            return index
    return None


def _preserved_next_action_minutes(
    subtasks: list[MediatorSubtask],
    next_action_index: int | None,
) -> int | None:
    if next_action_index is None:
        return None
    estimated_minutes = subtasks[next_action_index].estimated_minutes
    if isinstance(estimated_minutes, int) and 0 < estimated_minutes <= 10:
        return estimated_minutes
    return None


def _normalized_allocation_value(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip().lower()
    if normalized in _TIME_ALLOCATION_VALUES:
        return normalized
    return None
