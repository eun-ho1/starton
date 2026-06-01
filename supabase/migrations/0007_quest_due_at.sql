alter table public.quests
    add column if not exists due_at timestamptz;

create index if not exists quests_user_id_due_at_idx
    on public.quests (user_id, due_at)
    where due_at is not null;
