alter table public.tasks
    add column if not exists elapsed_seconds integer not null default 0;

alter table public.tasks
    drop constraint if exists tasks_elapsed_seconds_check;

alter table public.tasks
    add constraint tasks_elapsed_seconds_check check (elapsed_seconds >= 0);

create index if not exists tasks_user_id_active_visible_idx
    on public.tasks (user_id, status, completed_at, created_at desc)
    where status in ('todo', 'doing', 'paused') and completed_at is null;

-- Preserve task-backed quest metadata that was originally submitted by Flutter
-- through raw_task_inputs.client_metadata. This keeps category, EXP, and default
-- duration available when /tasks is loaded after an APK cold start.
update public.tasks as t
set metadata =
    coalesce(t.metadata, '{}'::jsonb)
    || coalesce(r.client_metadata, '{}'::jsonb)
    || jsonb_build_object(
        'client_metadata',
        coalesce(t.metadata->'client_metadata', '{}'::jsonb)
        || coalesce(r.client_metadata, '{}'::jsonb)
    )
from public.raw_task_inputs as r
where t.raw_input_id = r.id
  and t.user_id = r.user_id
  and coalesce(r.client_metadata, '{}'::jsonb) <> '{}'::jsonb;

-- Repair legacy rows where a completed record exists but the original quest row
-- still remained active, which caused completed quests to reappear on Home.
update public.quests as q
set status = 'completed'
from public.completed_quests as cq
where cq.user_id = q.user_id
  and q.status = 'active'
  and (
    cq.quest_id = q.id
    or cq.client_quest_id = q.id::text
    or cq.client_quest_id = q.client_quest_id
  );

-- Same repair for task-backed quests. Completed task snapshots should prevent
-- tasks from being returned by GET /tasks even if an old completion flow failed
-- before marking tasks.status = done.
update public.tasks as t
set
    status = 'done',
    completed_at = coalesce(t.completed_at, cq.completed_at),
    elapsed_seconds = greatest(
        coalesce(t.elapsed_seconds, 0),
        coalesce(cq.elapsed_seconds, 0)
    )
from public.completed_quests as cq
where cq.user_id = t.user_id
  and t.status in ('todo', 'doing', 'paused')
  and (
    cq.task_id = t.id
    or cq.client_quest_id = t.id::text
  );

comment on column public.tasks.elapsed_seconds is
'Accumulated timer progress for task-backed quests displayed in Flutter as QuestItem.';
