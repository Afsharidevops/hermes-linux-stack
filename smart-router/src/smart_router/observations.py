from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any


class ObservationWriter:
    """Append privacy-safe routing metadata. Raw prompts/responses are never accepted here."""

    def __init__(self, path: Path, max_bytes: int, enabled: bool):
        self.path = path
        self.max_bytes = max_bytes
        self.enabled = enabled
        if enabled:
            path.parent.mkdir(parents=True, exist_ok=True)

    def _rotate(self) -> None:
        if not self.path.exists() or self.path.stat().st_size < self.max_bytes:
            return
        backup = self.path.with_suffix(self.path.suffix + ".1")
        try:
            backup.unlink(missing_ok=True)
            os.replace(self.path, backup)
        except OSError:
            pass

    def write(self, event: dict[str, Any]) -> None:
        if not self.enabled:
            return
        self._rotate()
        safe = {"ts": int(time.time()), **event}
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(safe, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
