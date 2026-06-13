"""Configuration loading — API_NOTES.md §7 (trains) and TFL_API_NOTES.md §7
(buses).

Same JSON file, format and lookup order as the Mac app:
1. Environment variables
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


@dataclass(frozen=True)
class TflStop:
    id: str
    label: str


@dataclass(frozen=True)
class TflConfig:
    app_key: str | None
    direction_a: TflStop
    direction_b: TflStop

    @property
    def stops(self) -> tuple[TflStop, TflStop]:
        return (self.direction_a, self.direction_b)


@dataclass(frozen=True)
class DisplayConfig:
    """Pi board-cycle durations (seconds). Defaults match TFL_API_NOTES §9."""

    train_seconds: int = 15
    bus_seconds: int = 10


def _candidates() -> list[Path]:
    return [
        Path.home() / ".config/leaboard/config.json",
        Path.cwd() / "config.json",
    ]


def _read_config_file(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError(f"Config file invalid: {path}: {exc}") from exc


# --- Trains (Darwin) -------------------------------------------------------


def load(environ: dict[str, str] | None = None) -> Config:
    env = os.environ if environ is None else environ

    key = env.get("DARWIN_API_KEY", "")
    if key:
        return Config(
            api_key=key,
            base_url=env.get("DARWIN_BASE_URL") or DEFAULT_BASE_URL,
            crs=env.get("DARWIN_CRS") or DEFAULT_CRS,
        )

    for path in _candidates():
        if path.is_file():
            return load_file(path)

    searched = ["$DARWIN_API_KEY"] + [str(p) for p in _candidates()]
    raise ConfigError("No API key configured. Searched: " + ", ".join(searched))


def load_file(path: Path) -> Config:
    raw = _read_config_file(path)

    key = raw.get("apiKey", "")
    if not key or key.startswith("YOUR_"):
        raise ConfigError(f"{path}: apiKey is empty or still the placeholder")

    return Config(
        api_key=key,
        base_url=raw.get("baseUrl") or DEFAULT_BASE_URL,
        crs=raw.get("crs") or DEFAULT_CRS,
    )


# --- Buses (TfL) -----------------------------------------------------------


def load_tfl(environ: dict[str, str] | None = None) -> TflConfig:
    env = os.environ if environ is None else environ

    a_id, b_id = env.get("TFL_STOP_A_ID"), env.get("TFL_STOP_B_ID")
    if a_id and b_id:
        return TflConfig(
            app_key=env.get("TFL_APP_KEY") or None,
            direction_a=TflStop(a_id, env.get("TFL_STOP_A_LABEL") or "Direction A"),
            direction_b=TflStop(b_id, env.get("TFL_STOP_B_LABEL") or "Direction B"),
        )

    for path in _candidates():
        if path.is_file():
            return load_tfl_file(path)

    searched = ["$TFL_STOP_A_ID/$TFL_STOP_B_ID"] + [str(p) for p in _candidates()]
    raise ConfigError("No bus stops configured. Searched: " + ", ".join(searched))


def load_tfl_file(path: Path) -> TflConfig:
    raw = _read_config_file(path)

    tfl = raw.get("tfl")
    if not tfl:
        raise ConfigError(f'{path}: no "tfl" block')

    a, b = tfl.get("directionA") or {}, tfl.get("directionB") or {}
    a_id, b_id = a.get("id"), b.get("id")
    if not a_id or not b_id or a_id.startswith("490…") or b_id.startswith("490…"):
        raise ConfigError(f"{path}: tfl stop ids are empty or still placeholders")

    app_key = tfl.get("appKey")
    if not app_key or app_key.startswith("YOUR_"):
        app_key = None

    return TflConfig(
        app_key=app_key,
        direction_a=TflStop(a_id, a.get("label") or "Direction A"),
        direction_b=TflStop(b_id, b.get("label") or "Direction B"),
    )


def load_display(environ: dict[str, str] | None = None) -> DisplayConfig:
    """Board-cycle durations from the config's `display` block, defaulting to
    15 s / 10 s. Tolerant: a missing file or block yields the defaults."""
    for path in _candidates():
        if path.is_file():
            try:
                block = _read_config_file(path).get("display") or {}
            except ConfigError:
                break
            return DisplayConfig(
                train_seconds=int(block.get("trainSeconds", 15)),
                bus_seconds=int(block.get("busSeconds", 10)),
            )
    return DisplayConfig()
