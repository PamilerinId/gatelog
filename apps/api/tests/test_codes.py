import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from app import codes

VECTORS = json.loads((Path(__file__).parents[3] / "docs" / "code-test-vectors.json").read_text())["vectors"]


def test_vectors_match():
    """The guard app tests against the same file. If this fails, gates stop admitting guests."""
    for v in VECTORS:
        start = datetime.fromtimestamp(v["window_start"], timezone.utc)
        end = datetime.fromtimestamp(v["window_end"], timezone.utc)
        h, vid = UUID(v["home_id"]), UUID(v["visit_id"])
        assert codes.message(h, vid, start, end).decode() == v["message"]
        assert codes.derive(bytes.fromhex(v["key_hex"]), h, vid, start, end) == v["code"]


def test_display_and_clean():
    assert codes.display("482917") == "482 917"
    assert codes.clean(" 482 917 ") == "482917"
    assert codes.clean("48291") is None
