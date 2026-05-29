alter table public.completed_quests
    add column if not exists task_id uuid references public.tasks (id) on delete set null;

create index if not exists completed_quests_user_id_task_id_idx
    on public.completed_quests (user_id, task_id)
    where task_id is not null;

comment on column public.completed_quests.task_id is
'Optional final task id when the completion record was created from public.tasks instead of public.quests.';
