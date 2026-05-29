# Notion Sync Verification

Supabase SQL Editor or a read-only SQL client can use the queries below to
manually verify the Notion integration state in production.

Safety rules:
- All queries are read-only `SELECT` statements.
- Do not replace these queries with token-decrypting or secret-printing SQL.
- Do not select encrypted token values directly in production dashboards.

## 1. Check `notion_connections`

Use this query to inspect the latest Notion connection rows for a user without
printing any credential values.

```sql
select
  id,
  user_id,
  profile_id,
  database_id,
  data_source_id,
  database_title,
  database_url,
  api_version,
  sync_status,
  last_synced_at,
  last_successful_synced_at,
  disconnected_at,
  created_at,
  updated_at
from public.notion_connections
where user_id = '<USER_ID>'
order by updated_at desc, created_at desc;
```

## 2. Check whether the encrypted token is null

This query verifies whether credentials were cleared without exposing the
encrypted values themselves.

```sql
select
  id,
  user_id,
  access_token_encrypted is null as access_token_removed,
  refresh_token_encrypted is null as refresh_token_removed,
  disconnected_at,
  sync_status,
  updated_at
from public.notion_connections
where user_id = '<USER_ID>'
order by updated_at desc, created_at desc;
```

## 3. Check `disconnected_at`

Use this when validating that disconnect completed and the row is no longer
treated as connected.

```sql
select
  id,
  user_id,
  disconnected_at,
  sync_status,
  last_error_message,
  updated_at
from public.notion_connections
where user_id = '<USER_ID>'
order by updated_at desc, created_at desc;
```

Expected result:
- `disconnected_at` is non-null after disconnect.
- `sync_status` is typically `disconnected`.

## 4. Check quest `external_source` and `external_id`

This query confirms that Notion-imported quests are stored with external
identity fields and keeps the result focused on sync metadata.

```sql
select
  id,
  user_id,
  title,
  external_source,
  external_id,
  external_url,
  external_updated_at,
  created_at,
  updated_at
from public.quests
where user_id = '<USER_ID>'
  and external_source = 'notion'
order by updated_at desc, created_at desc;
```

Expected result:
- `external_source = 'notion'`
- `external_id` is populated for current Notion-synced rows

## 5. Check duplicate external identity rows

This query detects duplicate `(user_id, external_source, external_id)` groups
that would violate the intended Notion upsert identity.

```sql
select
  user_id,
  external_source,
  external_id,
  count(*) as row_count
from public.quests
where external_source is not null
  and external_id is not null
group by user_id, external_source, external_id
having count(*) > 1
order by row_count desc, user_id, external_source, external_id;
```

Expected result:
- zero rows

Note:
- Legacy rows without `external_id` are intentionally excluded.
- Legacy title-based rows are not auto-merged with newer Notion rows.

## 6. Check that the partial unique index exists

This query confirms the unique index backing Notion external identity upserts.

```sql
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'quests'
  and indexname = 'quests_user_id_external_source_external_id_idx';
```

Expected result:
- one row
- `indexdef` includes:
  `where ((external_source is not null) and (external_id is not null))`

## Optional: quick latest-state snapshot

This compact query is useful during manual QA after connect, sync, or
disconnect.

```sql
select
  nc.user_id,
  nc.id as connection_id,
  nc.database_id,
  nc.data_source_id,
  nc.sync_status,
  nc.disconnected_at,
  nc.last_successful_synced_at,
  (
    select count(*)
    from public.quests q
    where q.user_id = nc.user_id
      and q.external_source = 'notion'
  ) as notion_quest_count
from public.notion_connections nc
where nc.user_id = '<USER_ID>'
order by nc.updated_at desc, nc.created_at desc
limit 1;
```
