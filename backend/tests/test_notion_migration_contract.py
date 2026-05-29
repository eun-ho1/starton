import unittest
from pathlib import Path


MIGRATION_PATH = (
    Path(__file__).resolve().parents[2]
    / "supabase"
    / "migrations"
    / "0005_notion_sync_stability.sql"
)


class NotionMigrationContractTest(unittest.TestCase):
    def test_partial_unique_index_for_external_identity_is_declared(self) -> None:
        migration_sql = MIGRATION_PATH.read_text(encoding="utf-8")

        self.assertIn(
            "create unique index quests_user_id_external_source_external_id_idx",
            migration_sql,
        )
        self.assertIn(
            "on public.quests (user_id, external_source, external_id)",
            migration_sql,
        )
        self.assertIn("where external_source is not null", migration_sql)
        self.assertIn("and external_id is not null", migration_sql)

    def test_migration_fails_when_duplicate_external_identity_rows_exist(self) -> None:
        migration_sql = MIGRATION_PATH.read_text(encoding="utf-8")

        self.assertIn(
            "Cannot create quests_user_id_external_source_external_id_idx because duplicate",
            migration_sql,
        )
        self.assertIn("raise exception", migration_sql)
        self.assertIn("Deduplicate the reported quest rows, then rerun this migration.", migration_sql)

    def test_migration_documents_legacy_row_policy(self) -> None:
        migration_sql = MIGRATION_PATH.read_text(encoding="utf-8")

        self.assertIn("Do not backfill legacy source='notion' rows into external_* columns", migration_sql)
        self.assertIn("does not auto-reconcile", migration_sql)
        self.assertIn("rows with new external_id-backed sync rows, because title-based matching", migration_sql)
        self.assertIn("is ambiguous and data integrity is preferred over destructive cleanup.", migration_sql)


if __name__ == "__main__":
    unittest.main()
