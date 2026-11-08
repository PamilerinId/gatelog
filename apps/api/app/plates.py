"""Vehicle plates, stored as entered but in one form so a search finds them: upper case,
no spaces or dashes ("lnd 123 ab" -> "LND123AB"). Used only for the estate's own log."""

import re


def normalise_plate(raw: str | None) -> str | None:
    if not raw:
        return None
    p = re.sub(r"[\s\-.]", "", raw).upper()
    return p[:16] or None
