# Notion Sync Stability Notes

This document summarizes the Notion sync stability work that was implemented and reviewed in this repository.

## Scope

The changes cover:

- stable Notion quest identity using `external_source` + `external_id`
- DB-level uniqueness for synced Notion rows
- validation and rejection of malformed Notion sync payloads
- protection against disconnect/sync race conditions
- protection against stale overwrite from older sync completions
- sanitized status/error handling
- frontend settings behavior that treats server status as the source of truth

## Data Model and Identity

### Quest identity

Synced Notion quests are identified by:

- `user_id`
- `external_source`
- `external_id`

For Notion rows:

- `external_source` is expected to be `"notion"`
- `external_id` is expected to be the stable Notion page id

Implications:

- same title + different `external_id` => separate quests
- same `external_id` re-sync => same logical row

### Legacy rows

Older Notion-imported rows may exist without `external_source` or `external_id`.

Current policy:

- do not auto-merge legacy title-based rows with new external-id-backed rows
- do not perform destructive cleanup automatically
- prefer duplicate tolerance over ambiguous overwrite

This means the first sync after rollout can leave:

- one legacy row
- one new external-id-backed row

for the same apparent task title.

That behavior is intentional.

## Migration Behavior

File:

- `supabase/migrations/0005_notion_sync_stability.sql`

### What it does

- adds `external_*` quest columns
- adds Notion connection state columns
- creates a partial unique index for rows where:
  - `external_source IS NOT NULL`
  - `external_id IS NOT NULL`

### Integrity guarantee

The migration no longer silently skips unique index creation.

Current behavior:

- if duplicates exist for `(user_id, external_source, external_id)`, migration fails
- failure includes duplicate key samples in the error detail
- if migration succeeds, the unique index must exist

This provides DB-level protection for concurrent syncs.

## Backend Behavior

### External id validation

Repository and service boundaries reject malformed Notion quest identity.

Rejected cases for Notion quests:

- `external_id == null`
- `external_id == ""`
- `external_id == "   "`

### Disconnect and sync race handling

Files:

- `backend/app/services/notion_backend_service.py`
- `backend/app/repositories/notion_connection_repository.py`

Current behavior:

1. sync checks that the connection is still connected before starting
2. sync checks again before writing quest results
3. success metadata is written only if the connection is still connected
4. disconnect clears encrypted token fields and sets `disconnected_at`

Implication:

- if disconnect happens while sync is in progress, the in-flight sync must not mark the connection as successfully synced afterward

### Status endpoint

File:

- `backend/app/schemas/notion.py`

Status JSON uses snake_case keys:

- `connected`
- `connection_id`
- `database_id`
- `data_source_id`
- `database_title`
- `database_url`
- `last_synced_at`
- `last_successful_synced_at`
- `sync_status`
- `last_error_message`

Current rules:

- `disconnected_at` present => `connected = false`
- `last_error_message` is sanitized before returning to clients
- raw internal exception detail should remain in server logs only

### Stale overwrite protection

File:

- `backend/app/repositories/quest_repository.py`

When the same `(user_id, external_source, external_id)` row already exists:

- existing timestamp is `null` => incoming update allowed
- incoming timestamp is `null` => overwrite blocked
- incoming timestamp older than existing => overwrite blocked
- incoming timestamp equal to existing => idempotent overwrite allowed
- incoming timestamp newer than existing => overwrite allowed

This reduces risk from older sync requests finishing after newer ones.

## Frontend Behavior

Files:

- `frontend/lib/pages/settings_screen.dart`
- `frontend/lib/services/notion_sync_service.dart`

### Source of truth

The settings screen treats server status as the source of truth for connection state.

Current behavior on screen entry:

- do not trust cached connected state for immediate display
- show a checking/loading state first
- update UI from server status once available
- if status fetch fails, show a retryable error state instead of silently trusting stale local connection state

### Local secret handling

The cached local Notion secret is not used as proof of connection state.

After disconnect success:

- local cached token is cleared
- local cached database metadata is cleared

After disconnect failure:

- the screen does not blindly wipe existing connection state

### Button race protection

During status checking or active sync/disconnect work:

- connect/sync/disconnect actions are disabled

This reduces duplicate-tap race conditions in the settings UI.

## Frontend Parser Compatibility

File:

- `frontend/lib/services/notion_sync_service.dart`

The backend returns snake_case JSON.
The frontend maps those keys into camelCase Dart fields.

Datetime policy:

- transport fields remain `String?`
- optional convenience getters expose parsed `DateTime?`
- invalid datetime strings do not crash parsing; getters return `null`

## Review Checklist Mapping

The reviewed implementation is intended to satisfy the following:

- same Notion page title + different `external_id` => separate quests
- same `external_id` re-sync => same row, subject to stale-update protection
- missing `external_id` => rejected
- disconnect does not delete already imported quests
- disconnect makes saved token unusable for later sync
- status endpoint does not return raw secrets/tokens
- unique index creation is fail-fast, not silent
- DB-level integrity exists for non-null external identity rows
- frontend uses server status as connection source of truth

## Known Limits

The current implementation intentionally does not:

- auto-deduplicate legacy title-based Notion rows
- delete already imported Notion quests on disconnect
- guarantee that every unrelated backend test suite can run in this environment without optional dependencies installed

## Recommended Manual Verification

Before production rollout, a human should still verify:

1. the migration succeeds on a production-like database with no duplicate external identity rows
2. the partial unique index exists after migration
3. a real Notion connect -> sync -> disconnect -> sync-again flow behaves as expected against the live backend
4. the Flutter settings screen renders correctly on device during:
   - initial checking state
   - disconnected state
   - retryable status failure
   - active sync/disconnect busy state
