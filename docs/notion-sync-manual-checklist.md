# Notion Sync Manual Test Checklist

This checklist is for end-to-end manual QA of the Notion integration before
release. Use it together with [notion-sync-verification.md](./notion-sync-verification.md)
when database verification is needed.

## 1. Connect succeeds with a valid secret and database URL

Preparation
- A working Notion Integration has been created.
- The Integration secret is available.
- A Notion database exists and is shared with the Integration.
- The database contains at least one visible page.

Steps
1. Open the app Settings screen.
2. Turn on the Notion Connection switch.
3. Enter the valid Integration secret.
4. Enter the Notion database URL.
5. Confirm the connection.

Expected result
- The connect flow succeeds without an error toast.
- The UI shows the database title or connected state.
- A follow-up sync completes successfully.
- `GET /integrations/notion/status` shows `connected=true`.

## 2. Connect fails with an invalid secret

Preparation
- A Notion database URL is available.
- An invalid or intentionally modified Integration secret is prepared.

Steps
1. Open the Notion connect dialog.
2. Enter the invalid secret.
3. Enter the database URL.
4. Submit the connection.

Expected result
- The connect flow fails.
- The user sees a friendly invalid-secret error message.
- The UI remains disconnected.
- Status still resolves to `connected=false`.

## 3. Connect fails when the Integration does not have database access

Preparation
- A valid Integration secret is available.
- A Notion database exists but is not shared with that Integration.

Steps
1. Open the Notion connect dialog.
2. Enter the valid secret.
3. Enter the unshared database URL or ID.
4. Submit the connection.

Expected result
- The connect flow fails.
- The user sees a friendly access or permission guidance message.
- No usable connected state appears in the UI.

## 4. Sync one page and create one quest

Preparation
- The Notion connection is already connected.
- The target database contains exactly one active page that is not completed.

Steps
1. Open Settings.
2. Tap `Sync Now`.
3. Wait for sync to finish.
4. Inspect the local quest list.

Expected result
- One quest is imported.
- The quest title matches the Notion page title or parser fallback title.
- The imported quest is stored as a Notion-backed quest.

## 5. Re-sync the same page without creating a duplicate

Preparation
- Scenario 4 has already completed.
- The same Notion page still exists with the same page id.

Steps
1. Tap `Sync Now` again.
2. Open the quest list.
3. Optionally verify quest rows in Supabase using the verification SQL.

Expected result
- No duplicate quest is created.
- The same quest row is updated in place if needed.
- The Notion quest count remains unchanged.

## 6. Two pages with the same title create two quests

Preparation
- The Notion database contains two different pages.
- Both pages have the same title text.
- Their page ids are different.

Steps
1. Sync the database.
2. Open the quest list.
3. Optionally inspect `external_id` values in Supabase.

Expected result
- Two separate quests exist.
- They may share the same title, but they do not overwrite each other.
- Each quest has a different Notion external identity.

## 7. Editing a Notion title updates the quest on sync

Preparation
- A Notion-backed quest already exists from a previous sync.
- The corresponding Notion page title can be edited.

Steps
1. Change the page title in Notion.
2. Wait for Notion to update `last_edited_time`.
3. Trigger sync from the app.
4. Re-open the quest list.

Expected result
- The existing quest title is updated.
- No duplicate quest is created.
- The updated content reflects the latest Notion page state.

## 8. Disconnect makes status report `connected=false`

Preparation
- A Notion connection is currently active.

Steps
1. Open Settings.
2. Tap `Disconnect`.
3. Re-open Settings or trigger a status refresh.

Expected result
- Disconnect succeeds.
- The UI shows disconnected state.
- The server status resolves to `connected=false`.

## 9. Disconnect keeps existing imported quests

Preparation
- At least one Notion quest has already been synced.
- The connection is currently active.

Steps
1. Disconnect the Notion connection.
2. Open the quest list.

Expected result
- Existing imported quests remain in the app and database.
- Disconnect does not delete prior quest rows.

## 10. Sync fails after disconnect

Preparation
- The Notion connection has already been disconnected.

Steps
1. Attempt to sync again from the app.
2. If needed, call the sync endpoint manually with the same authenticated user.

Expected result
- Sync fails with a friendly disconnected message.
- No new success metadata is written.

## 11. Reconnect and sync succeed again

Preparation
- The previous connection was disconnected.
- A valid Integration secret and valid database URL or ID are available.

Steps
1. Open the connect flow again.
2. Enter the valid secret.
3. Enter the database URL or ID.
4. Confirm the connection.
5. Trigger sync.

Expected result
- Reconnect succeeds.
- Status becomes `connected=true`.
- Sync succeeds again using the restored connection.

## 12. Disconnect during sync race test

Preparation
- A connected Notion database exists with enough pages that sync takes noticeable time.
- Two test sessions are available, or one session plus direct API access.

Steps
1. Start a sync.
2. Before sync fully completes, trigger disconnect from another session or API call.
3. Inspect the final server status and connection metadata.
4. Inspect whether quests were partially written.

Expected result
- Sync does not end in a false success state after disconnect.
- `last_successful_synced_at` is not updated after disconnect wins the race.
- If quest writes had not started yet, no quest rows are written.
- If quest writes had already started, success metadata is still blocked.

## 13. Stale overwrite protection test

Preparation
- A Notion-backed quest already exists.
- You can produce two sync runs where one payload is older than the other, or
  simulate this in staging with controlled timestamps.

Steps
1. Sync a newer version of a Notion page.
2. Attempt another sync using an older `last_edited_time` snapshot of the same page.
3. Inspect the quest title, status-related fields, and external metadata.

Expected result
- Older sync data does not overwrite newer quest data.
- Title and external metadata remain at the newer values.
- Same-timestamp re-sync remains idempotent.

## 14. Frontend checking, error, and busy states

Preparation
- A build is available where Settings can reach the backend.
- You can simulate successful status, failed status, and long-running sync or disconnect.

Steps
1. Open Settings and watch the Notion section immediately after screen entry.
2. Verify the loading or checking state before status completes.
3. Simulate or trigger a status fetch failure.
4. Verify that retry UI appears and can be tapped.
5. Trigger connect, sync, or disconnect and attempt repeated taps while the action is in flight.

Expected result
- The screen shows a checking or loading state first.
- Local cache is not treated as proof of connected state on entry.
- Server status drives the displayed Notion connection state.
- Status fetch failure shows retryable error UI.
- Connect, sync, and disconnect controls are disabled while busy.

## Suggested QA notes to capture

Preparation
- Have a place to record test results for each scenario.

Steps
1. Record the app build version.
2. Record the backend environment or branch.
3. Record the Notion workspace and database used for QA.
4. Save screenshots for any unexpected UI state.

Expected result
- Every scenario above has a clear pass or fail note.
- Any failure includes enough context for reproduction.
