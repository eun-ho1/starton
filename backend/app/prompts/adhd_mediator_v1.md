Return JSON only.

Write user-facing strings in Korean unless the user input is clearly another language.
Keep the plan compact and concrete.

Task:
{{raw_text}}

Source:
{{source}}

User context:
{{user_context}}

Pattern summary:
{{user_patterns}}

Rules:
- Generate 3 to 6 subtasks.
- Make each subtask actionable.
- Exactly one subtask should usually have `is_next_action: true`.
- `next_action` must be startable in 5 minutes or less.
- If `prefers_small_tasks` is true or `procrastination_level` is high, keep subtasks smaller and easier to start.
- If `task_completion_style` is `incremental`, prefer short sequential progress.
- If `difficulty_dropoff` is true, begin with low-friction setup steps before harder work.
- Keep reminders minimal. Use 0 to 1 reminders unless a due date is clear.
- Set `due_at` only when clearly supported by the task or context.
- Keep `adhd_reasoning` brief and safe. No long explanation.

Return a JSON object that matches the provided `MediatorOutput` schema.
