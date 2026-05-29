-- Notion sync stability migration
-- Safe-by-default approach:
-- 1. Add nullable columns only.
-- 2. Do not delete or rewrite existing quest/notion connection rows.
-- 3. Do not backfill legacy source='notion' rows into external_* columns here,
--    because duplicate legacy mappings may exist and could make a new unique index fail.
--    Application behavior intentionally does not auto-reconcile those legacy
--    rows with new external_id-backed sync rows, because title-based matching
--    is ambiguous and data integrity is preferred over destructive cleanup.
-- 4. No title-based unique constraint was found in the current checked-in migrations.
--    If a title-based unique/index exists in another environment, analyze application impact
--    before changing it. This migration intentionally does not remove or alter any such index.

alter table if exists public.quests
    add column if not exists external_source text,
    add column if not exists external_id text,
    add column if not exists external_url text,
    add column if not exists external_updated_at timestamptz,
    add column if not exists deleted_at timestamptz;

alter table if exists public.notion_connections
    add column if not exists data_source_id text,
    add column if not exists api_version text,
    add column if not exists last_successful_synced_at timestamptz,
    add column if not exists last_error_message text,
    add column if not exists disconnected_at timestamptz;

comment on column public.quests.external_source is
'External system source such as notion. Left nullable for legacy rows until application-level backfill is ready.';

comment on column public.quests.external_id is
'Stable external object identifier, for example a Notion page id.';

comment on column public.quests.external_url is
'Canonical external URL for the synced object.';

comment on column public.quests.external_updated_at is
'Last known updated timestamp from the external system.';

comment on column public.quests.deleted_at is
'Soft-delete timestamp for synced rows that disappeared or were disconnected upstream.';

comment on column public.notion_connections.data_source_id is
'Resolved Notion data source id used for sync after database/data source resolution.';

comment on column public.notion_connections.api_version is
'Notion API version used when the connection was last validated or synced.';

comment on column public.notion_connections.last_successful_synced_at is
'Timestamp of the last successful sync completion.';

comment on column public.notion_connections.last_error_message is
'Last sync/connect error captured for operator debugging.';

comment on column public.notion_connections.disconnected_at is
'Timestamp when the connection was marked disconnected.';

do $$
declare
    duplicate_summary text;
    index_is_unique boolean;
begin
    /*
     * Duplicate investigation query for operators:
     *
     * select
     *     user_id,
     *     external_source,
     *     external_id,
     *     count(*) as duplicate_count
     * from public.quests
     * where external_source is not null
     *   and external_id is not null
     * group by user_id, external_source, external_id
     * having count(*) > 1
     * order by duplicate_count desc, user_id, external_source, external_id;
     */
    select string_agg(
               format(
                   '(user_id=%s, external_source=%s, external_id=%s, count=%s)',
                   duplicates.user_id,
                   duplicates.external_source,
                   duplicates.external_id,
                   duplicates.duplicate_count
               ),
               '; '
               order by duplicates.duplicate_count desc,
                        duplicates.user_id,
                        duplicates.external_source,
                        duplicates.external_id
           )
    into duplicate_summary
    from (
        select
            user_id,
            external_source,
            external_id,
            count(*) as duplicate_count
        from public.quests
        where external_source is not null
          and external_id is not null
        group by user_id, external_source, external_id
        having count(*) > 1
        order by count(*) desc, user_id, external_source, external_id
        limit 10
    ) as duplicates;

    if duplicate_summary is not null then
        raise exception
            using
                message = 'Cannot create quests_user_id_external_source_external_id_idx because duplicate (user_id, external_source, external_id) rows already exist.',
                detail = duplicate_summary,
                hint = 'Deduplicate the reported quest rows, then rerun this migration.';
    end if;

    select idx.indisunique
    into index_is_unique
    from pg_class cls
    join pg_namespace ns
      on ns.oid = cls.relnamespace
    join pg_index idx
      on idx.indexrelid = cls.oid
    where ns.nspname = 'public'
      and cls.relname = 'quests_user_id_external_source_external_id_idx';

    if index_is_unique is false then
        raise exception
            'Existing index quests_user_id_external_source_external_id_idx is not unique. Manual intervention is required before continuing.';
    end if;

    if index_is_unique is null then
        execute '
            create unique index quests_user_id_external_source_external_id_idx
                on public.quests (user_id, external_source, external_id)
                where external_source is not null
                  and external_id is not null
        ';
    end if;

    if not exists (
        select 1
        from pg_class cls
        join pg_namespace ns
          on ns.oid = cls.relnamespace
        join pg_index idx
          on idx.indexrelid = cls.oid
        where ns.nspname = 'public'
          and cls.relname = 'quests_user_id_external_source_external_id_idx'
          and idx.indisunique
    ) then
        raise exception
            'Expected unique index quests_user_id_external_source_external_id_idx to exist after migration, but it was not found.';
    end if;
end
$$;
