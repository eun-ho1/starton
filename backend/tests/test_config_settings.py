import unittest

from app.core.config import Settings


class SettingsValidationTest(unittest.TestCase):
    @staticmethod
    def _valid_fernet_key() -> str:
        return "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

    def test_settings_reject_missing_required_environment_variables(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "Missing required environment variables: SUPABASE_URL",
        ):
            Settings(
                _env_file=None,
                SUPABASE_SERVICE_ROLE_KEY="service-role",
                SUPABASE_ANON_KEY="anon-key",
                NOTION_TOKEN_ENCRYPTION_KEY=self._valid_fernet_key(),
            )

    def test_settings_reject_empty_notion_token_encryption_key(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "Missing required environment variables: NOTION_TOKEN_ENCRYPTION_KEY",
        ):
            Settings(
                _env_file=None,
                SUPABASE_URL="https://example.supabase.co",
                SUPABASE_SERVICE_ROLE_KEY="service-role",
                SUPABASE_ANON_KEY="anon-key",
                NOTION_TOKEN_ENCRYPTION_KEY="   ",
            )

    def test_settings_accept_valid_required_environment_variables(self) -> None:
        settings = Settings(
            _env_file=None,
            SUPABASE_URL="https://example.supabase.co",
            SUPABASE_SERVICE_ROLE_KEY="service-role",
            SUPABASE_ANON_KEY="anon-key",
            NOTION_TOKEN_ENCRYPTION_KEY=self._valid_fernet_key(),
        )

        self.assertEqual(settings.supabase_url, "https://example.supabase.co")
        self.assertEqual(settings.supabase_service_role_key, "service-role")
        self.assertEqual(settings.supabase_anon_key, "anon-key")
        self.assertTrue(settings.notion_token_encryption_key)

    def test_settings_default_ai_suggestion_gemini_options(self) -> None:
        settings = Settings(
            _env_file=None,
            SUPABASE_URL="https://example.supabase.co",
            SUPABASE_SERVICE_ROLE_KEY="service-role",
            SUPABASE_ANON_KEY="anon-key",
            NOTION_TOKEN_ENCRYPTION_KEY=self._valid_fernet_key(),
        )

        self.assertEqual(settings.gemini_model_name, "gemini-3.5-flash")
        self.assertEqual(settings.gemini_thinking_level, "low")
        self.assertEqual(settings.gemini_max_output_tokens, 2048)

    def test_settings_accept_railway_port_environment_variable(self) -> None:
        settings = Settings(
            _env_file=None,
            PORT="4321",
            SUPABASE_URL="https://example.supabase.co",
            SUPABASE_SERVICE_ROLE_KEY="service-role",
            SUPABASE_ANON_KEY="anon-key",
            NOTION_TOKEN_ENCRYPTION_KEY=self._valid_fernet_key(),
        )

        self.assertEqual(settings.api_port, 4321)

    def test_settings_parse_cors_origins_from_comma_separated_string(self) -> None:
        settings = Settings(
            _env_file=None,
            WEB_CORS_ALLOWED_ORIGINS=(
                "https://start-on.vercel.app, https://preview-start-on.vercel.app"
            ),
            SUPABASE_URL="https://example.supabase.co",
            SUPABASE_SERVICE_ROLE_KEY="service-role",
            SUPABASE_ANON_KEY="anon-key",
            NOTION_TOKEN_ENCRYPTION_KEY=self._valid_fernet_key(),
        )

        self.assertEqual(
            settings.cors_allowed_origins,
            [
                "https://start-on.vercel.app",
                "https://preview-start-on.vercel.app",
            ],
        )

    def test_settings_reject_invalid_notion_token_encryption_key_format(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "NOTION_TOKEN_ENCRYPTION_KEY must be a valid Fernet key",
        ):
            Settings(
                _env_file=None,
                SUPABASE_URL="https://example.supabase.co",
                SUPABASE_SERVICE_ROLE_KEY="service-role",
                SUPABASE_ANON_KEY="anon-key",
                NOTION_TOKEN_ENCRYPTION_KEY="not-a-valid-fernet-key",
            )


if __name__ == "__main__":
    unittest.main()
