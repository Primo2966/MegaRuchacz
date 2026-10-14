"""Wiedza firmy - wspolna baza krotkich ustalen pracownikow (serwer MCP przez HTTP).

Silnik wektorow i pelnotekstowego zapytania pochodzi z Lore (katalog `lore/` obok w repo).
Uzywamy z niego wylacznie: db.embed_passages, db.embed_query, db.MODELS, db.fetch_pinned,
db.embedding_model, search._rrf, search._fts_query, masking.mask - nic wiecej.

Gdzie szukamy kodu Lore: WIEDZA_FIRMY_LORE (katalog zawierajacy pakiet `lore/`), a bez niej
katalog `lore` obok `wiedza_firmy` (uklad repo i kopii na serwerze). Brak = glosny blad importu,
nie ciche dzialanie bez wektorow.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

__version__ = "0.1.0"


def _katalog_lore() -> Path:
    wybrany = os.environ.get("WIEDZA_FIRMY_LORE")
    if wybrany:
        return Path(wybrany)
    return Path(__file__).resolve().parents[2] / "lore"


KATALOG_LORE = _katalog_lore()
if not (KATALOG_LORE / "lore" / "db.py").is_file():
    raise ImportError(
        f"wiedza_firmy: nie ma kodu Lore w {KATALOG_LORE} (brak lore/db.py). Ustaw WIEDZA_FIRMY_LORE "
        "na katalog, w ktorym lezy pakiet lore (lore/db.py, search.py, masking.py)"
    )
if str(KATALOG_LORE) not in sys.path:
    sys.path.insert(0, str(KATALOG_LORE))
