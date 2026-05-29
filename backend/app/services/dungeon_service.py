from app.repositories.base import DungeonRepository
from app.schemas.dungeon import DungeonClearResponse, DungeonStatusResponse


class DungeonService:
    def __init__(self, dungeon_repository: DungeonRepository) -> None:
        self._dungeon_repository = dungeon_repository

    def list_dungeons(self, user_id: str) -> list[DungeonStatusResponse]:
        return self._dungeon_repository.list_dungeons(user_id)

    def clear_dungeon(self, user_id: str, dungeon_id: str) -> DungeonClearResponse:
        return self._dungeon_repository.clear_dungeon(user_id, dungeon_id)
