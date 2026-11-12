"""Static checks for the Supabase migration sequence and manual install bundle.

These checks catch repository packaging mistakes. They do not execute SQL or
replace PostgreSQL/RLS integration tests.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"
INSTALL_BUNDLE = ROOT / "supabase" / "INSTALL_OPERATIONS.sql"


class MigrationManifestTests(unittest.TestCase):
    def test_migration_versions_are_unique_and_orderable(self) -> None:
        files = sorted(MIGRATIONS_DIR.glob("*.sql"))
        self.assertTrue(files, "No SQL migrations found")

        versions: list[str] = []
        for path in files:
            match = re.fullmatch(r"(\d{12})_[a-z0-9_]+\.sql", path.name)
            self.assertIsNotNone(
                match,
                f"Migration filename must start with a 12-digit version: {path.name}",
            )
            assert match is not None
            versions.append(match.group(1))

        self.assertEqual(
            len(versions),
            len(set(versions)),
            "Duplicate Supabase migration version detected",
        )
        self.assertEqual(
            versions,
            sorted(versions),
            "Migration files are not in chronological filename order",
        )

    def test_manual_install_bundle_references_existing_migrations(self) -> None:
        self.assertTrue(INSTALL_BUNDLE.is_file(), "INSTALL_OPERATIONS.sql is missing")
        sql = INSTALL_BUNDLE.read_text(encoding="utf-8")
        source_names = re.findall(
            r"^-- SOURCE: supabase/migrations/([^\s]+)$",
            sql,
            flags=re.MULTILINE,
        )
        self.assertTrue(source_names, "No migration source markers found in install bundle")

        for name in source_names:
            with self.subTest(source=name):
                self.assertTrue(
                    (MIGRATIONS_DIR / name).is_file(),
                    f"Install bundle references missing migration: {name}",
                )

        self.assertEqual(
            source_names,
            sorted(source_names),
            "Install bundle migration sections must follow migration filename order",
        )


    def test_install_bundle_has_balanced_dollar_quotes(self) -> None:
        sql = INSTALL_BUNDLE.read_text(encoding="utf-8")
        self.assertEqual(
            sql.count("$") % 2,
            0,
            "Unbalanced PostgreSQL dollar-quoted function or block",
        )
        self.assertNotRegex(sql, r"(?m)^\\$;$")

    def test_task_assignee_tenant_constraint_is_in_both_install_paths(self) -> None:
        migration = MIGRATIONS_DIR / "202611110006_task_assignee_tenant_integrity.sql"
        self.assertTrue(migration.is_file(), "Task tenant-integrity migration is missing")
        migration_sql = migration.read_text(encoding="utf-8")
        bundle_sql = INSTALL_BUNDLE.read_text(encoding="utf-8")

        constraint = "tasks_assigned_user_same_org_fk"
        self.assertIn(constraint, migration_sql)
        self.assertIn(constraint, bundle_sql)


    def test_treatment_safety_requires_registration_evidence_and_audit_rpc(self) -> None:
        migration = MIGRATIONS_DIR / "202611120004_treatment_safety_verification.sql"
        self.assertTrue(migration.is_file(), "Treatment safety verification migration is missing")
        migration_sql = migration.read_text(encoding="utf-8")
        bundle_sql = INSTALL_BUNDLE.read_text(encoding="utf-8")

        for required in (
            "verify_treatment_safety",
            "registration_country",
            "registration_valid_until",
            "source_url",
            "source_checked_at",
            "harvest_wait_minutes",
            "reentry_wait_minutes",
            "revoke insert, update, delete on public.treatment_safety",
            "treatment_safety.verified",
        ):
            with self.subTest(required=required):
                self.assertIn(required, migration_sql)

        self.assertIn(
            "-- SOURCE: supabase/migrations/202611120004_treatment_safety_verification.sql",
            bundle_sql,
        )
        self.assertIn("verify_treatment_safety", bundle_sql)


if __name__ == "__main__":
    unittest.main()
