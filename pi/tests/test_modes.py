"""Display-mode selection: config parsing, active-board mapping, and that a
single-board mode only renders that board."""

from leaboard import config
from leaboard.config import DisplayConfig, normalize_mode
from leaboard.main import _active_boards, main


def test_display_defaults():
    d = DisplayConfig()
    assert (d.mode, d.train_seconds, d.bus_seconds) == ("alternate", 15, 10)


def test_normalize_mode():
    assert normalize_mode("trains") == "trains"
    assert normalize_mode("BUSES") == "buses"
    assert normalize_mode("  alternate ") == "alternate"
    assert normalize_mode("nonsense") == "alternate"  # invalid -> default
    assert normalize_mode(None) == "alternate"


def test_active_boards():
    assert _active_boards("trains") == ("trains",)
    assert _active_boards("buses") == ("buses",)
    assert _active_boards("alternate") == ("trains", "buses")


def test_once_trains_only(capsys):
    main(["--demo", "--once", "--mode", "trains"])
    out = capsys.readouterr().out
    assert "TRAINS" in out
    assert "LEA BRIDGE BUSES" not in out


def test_once_buses_only(capsys):
    main(["--demo", "--once", "--mode", "buses"])
    out = capsys.readouterr().out
    assert "LEA BRIDGE BUSES" in out
    assert "TRAINS" not in out


def test_once_alternate_shows_both(capsys):
    main(["--demo", "--once", "--mode", "alternate"])
    out = capsys.readouterr().out
    assert "TRAINS" in out
    assert "LEA BRIDGE BUSES" in out
