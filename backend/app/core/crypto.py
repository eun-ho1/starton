from app.core.config import settings


class SecretCipher:
    def __init__(self, key: str) -> None:
        from cryptography.fernet import Fernet

        self._fernet = Fernet(key.encode("utf-8"))

    def encrypt(self, value: str) -> str:
        return self._fernet.encrypt(value.encode("utf-8")).decode("utf-8")

    def decrypt(self, value: str) -> str:
        return self._fernet.decrypt(value.encode("utf-8")).decode("utf-8")


def get_secret_cipher() -> SecretCipher:
    return SecretCipher(settings.notion_token_encryption_key)
