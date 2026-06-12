"""Configuration loading — API_NOTES.md §7.

Same JSON format and lookup order as the Mac app:
1. Environment variables DARWIN_API_KEY (+ DARWIN_BASE_URL, DARWIN_CRS)
2. ~/.config/leaboard/config.json
3. ./config.json
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_BASE_URL = (
    "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120"
)
DEFAULT_CRS = "LEB"


class ConfigError(Exception):
    pass


@dataclass(frozen=True)
class Config:
    api_key: str
    base_url: str = DEFAULT_BASE_URL
    crs: str = DEFAULT_CRS


def load(environ: dict[str, str] | None = None) -> Config:
    env = os.environ if environ is None else environ

    key = env.get("DARWIN_API_KEY", "")
    if key:
        return Config(
            api_key=key,
            base_url=env.get("DARWIN_BASE_URL") or DEFAULT_BASE_URL,
            crs=env.get("DARWIN_CRS") or DEFAULT_CRS,
        )

    candidates = [
        Path.home() / ".config/leaboard/config.json",
        Path.cwd() / "config.json",
    ]
    for path in candidates:
        if path.is_file():
            return load_file(path)

    searched = ["$DARWIN_API_KEY"] + [str(p) for p in candidates]
    raise ConfigError("No API key configured. Searched: " + ", ".join(searched))


def load_file(path: Path) -> Config:
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError(f"Config file invalid: {path}: {exc}") from exc

    key = raw.get("apiKey", "")
    if not key or key.startswith("YOUR_"):
        raise ConfigError(f"{path}: apiKey is empty or still the placeholder")

    return Config(
        api_key=key,
        base_url=raw.get("baseUrl") or DEFAULT_BASE_URL,
        crs=raw.get("crs") or DEFAULT_CRS,
    )
