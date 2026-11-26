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


    def test_all_sql_dollar_quotes_are_balanced(self) -> None:
        dollar = chr(36)
        sql_paths = list(MIGRATIONS_DIR.glob("*.sql")) + [INSTALL_BUNDLE]

        for path in sql_paths:
            sql = path.read_text(encoding="utf-8")
            with self.subTest(path=path.name):
                self.assertEqual(
                    sql.count(dollar * 2) % 2,
                    0,
                    "Unbalanced PostgreSQL dollar-quoted function or block",
                )
                self.assertNotIn("\ndo " + dollar + "\nbegin", sql)
                self.assertNotIn("\nas " + dollar + "\n", sql)
                self.assertNotIn("\n" + dollar + ";\n", sql)


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
            "registration_status",
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


    def test_treatment_safety_verification_requires_explicit_attestations(self) -> None:
        migration_name = "202611190001_treatment_safety_attestation.sql"
        migration = MIGRATIONS_DIR / migration_name
        self.assertTrue(migration.is_file(), "Treatment safety attestation migration is missing")
        migration_sql = migration.read_text(encoding="utf-8")
        bundle_sql = INSTALL_BUNDLE.read_text(encoding="utf-8")

        for required in (
            "treatment_safety_verified_requires_attestations",
            "p_label_review_attested boolean",
            "p_scope_review_attested boolean",
            "p_intervals_review_attested boolean",
            "p_label_review_attested is not true",
            "p_scope_review_attested is not true",
            "p_intervals_review_attested is not true",
            "treatment_safety.verified",
        ):
            with self.subTest(required=required):
                self.assertIn(required, migration_sql)

        self.assertIn(
            f"-- SOURCE: supabase/migrations/{migration_name}",
            bundle_sql,
        )
        self.assertIn("p_intervals_review_attested", bundle_sql)

    def test_flutter_safety_review_form_calls_the_attested_rpc(self) -> None:
        dialog = ROOT / "app" / "lib" / "treatment_safety_verification_dialog.dart"
        operations_page = ROOT / "app" / "lib" / "agronomy_operations_page.dart"
        product_catalog = ROOT / "app" / "lib" / "crop_batches_page.dart"
        self.assertTrue(dialog.is_file(), "Treatment safety review form is missing")

        dialog_source = dialog.read_text(encoding="utf-8")
        page_source = operations_page.read_text(encoding="utf-8")
        catalog_source = product_catalog.read_text(encoding="utf-8")
        for required in (
            "verify_treatment_safety",
            "p_label_review_attested",
            "p_scope_review_attested",
            "p_intervals_review_attested",
            "p_harvest_wait_minutes",
            "p_reentry_wait_minutes",
        ):
            with self.subTest(required=required):
                self.assertIn(required, dialog_source)
        self.assertIn("TreatmentSafetyVerificationDialog", page_source)
        self.assertIn("canVerify: widget.canManage", page_source)
        self.assertIn("'registration_status':", catalog_source)
        self.assertIn("DropdownMenuItem(value: 'active'", catalog_source)



    def test_treatment_safety_https_guard_is_a_complete_sql_predicate(self) -> None:
        migration = MIGRATIONS_DIR / "202611190001_treatment_safety_attestation.sql"
        migration_sql = migration.read_text(encoding="utf-8")
        bundle_sql = INSTALL_BUNDLE.read_text(encoding="utf-8")

        expected = (
            "or trim(p_source_url) !~* "
            "'^https://[^[:space:]/?#]+([/?#][^[:space:]]*)?
    unittest.main()
 then"
        )
        self.assertIn(expected, migration_sql)
        self.assertIn(expected, bundle_sql)
\nif __name__ == "__main__":
    unittest.main()
