"""Atrapa `przeglad.py --profil klient --format json` (zadanie Z5) - zero wywolan modelu.

Wymaga WIEDZA_FIRMY_KLIENT_HOME i tematy-cache.json. Kazde wywolanie dopisuje linie do ATRAPA_PRZEGLAD_LOG.
ATRAPA_PRZEGLAD_PADA=1 - konczy sie kodem 1 bez kolejki. ATRAPA_PRZEGLAD_N - liczba wpisow (domyslnie 150).
Kolejka w formacie Z5: <home>\kolejka\przeglad-<czas>.json {format, rodzaj, utworzono, wersja_tematow, wpisy}.
"""

import hashlib
import json
import os
import sys
from pathlib import Path

assert sys.argv[1:] == ["--profil", "klient", "--format", "json"], sys.argv
home = Path(os.environ["WIEDZA_FIRMY_KLIENT_HOME"])
cache = json.loads((home / "tematy-cache.json").read_text(encoding="utf-8"))
assert cache["tematy"] and cache["zasady"], cache
with open(os.environ["ATRAPA_PRZEGLAD_LOG"], "a", encoding="utf-8") as f:
    f.write("wywolanie\n")
print("atrapa przegladu: start")
if os.environ.get("ATRAPA_PRZEGLAD_PADA") == "1":
    print("atrapa przegladu: padam celowo", file=sys.stderr)
    sys.exit(1)
n = int(os.environ.get("ATRAPA_PRZEGLAD_N") or 150)
temat = cache["tematy"][0]["id"]
wpisy = []
for i in range(n):
    tresc = f"Ustalenie numer {i} z przegladu atrapy."
    wpisy.append({"klucz": hashlib.sha256(f"{temat}\n{tresc}".encode()).hexdigest(), "tresc": tresc, "temat": temat,
                  "tematy_dodatkowe": [], "poufnosc": "wewnetrzne", "data": "2026-10-14", "zrodlo": "przeglad",
                  "program": "claude-code"})
kolejka = home / "kolejka"
kolejka.mkdir(parents=True, exist_ok=True)
tmp = kolejka / "przeglad-atrapa.json.tmp"
tmp.write_text(json.dumps({"format": "wiedza-firmy-kolejka/1", "rodzaj": "przeglad", "utworzono": "2026-10-14T10:00:00",
                           "wersja_tematow": cache.get("wersja", ""), "wpisy": wpisy}, ensure_ascii=False), encoding="utf-8")
os.replace(tmp, kolejka / "przeglad-atrapa.json")
print("atrapa przegladu: koniec")
