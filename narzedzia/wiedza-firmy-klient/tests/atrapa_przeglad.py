"""Atrapa `przeglad.py --profil klient --format json` (zadanie Z5) - zero wywolan modelu.

Wymaga WIEDZA_FIRMY_KLIENT_HOME i tematy-cache.json. Kazde wywolanie dopisuje linie do ATRAPA_PRZEGLAD_LOG.
ATRAPA_PRZEGLAD_PADA=1 - konczy sie kodem 1 bez kolejki. ATRAPA_PRZEGLAD_N - liczba wpisow (domyslnie 150).
Kolejka w formacie Z5: <home>\kolejka\przeglad-<czas>.json {format, rodzaj, utworzono, wersja_tematow, wpisy}.
Z `--baza <dzien.db>` (krok dzienny klienta): jeden wpis na kazdy chunk rozmowy z tej bazy, linia "dzienny <baza>"
w logu i wiersze koszt.tsv jak w przeglad.py (<home>\przeglad\.stan, <home>\przeglad\tagi\.stan) ze stalymi
liczbami ATRAPA_KOSZT; przy ATRAPA_PRZEGLAD_PADA=1 jedno wywolanie zapisane przed padnieciem.
"""

import hashlib
import json
import os
import sqlite3
import sys
from pathlib import Path

KOLUMNY = ("kiedy", "etap", "klucz", "opis", "sekundy", "znaki_wyslane", "znaki_odebrane", "input_tokens",
           "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens", "tokeny_razem", "koszt_usd", "wynik")
ATRAPA_KOSZT = {"input_tokens": 10, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": 500,
                "output_tokens": 100, "tokeny_razem": 1610, "koszt_usd": "0.1250"}


def koszt(katalog: Path, etap: str) -> None:
    plik = katalog / ".stan" / "koszt.tsv"
    plik.parent.mkdir(parents=True, exist_ok=True)
    nowy = not plik.exists()
    with plik.open("a", encoding="utf-8", newline="") as f:
        if nowy:
            f.write("\t".join(KOLUMNY) + "\n")
        w = {"kiedy": "2026-10-15T05:00:00", "etap": etap, "klucz": "k", "opis": "atrapa", "sekundy": "1.0",
             "znaki_wyslane": "100", "znaki_odebrane": "10", "wynik": "ok", **ATRAPA_KOSZT}
        f.write("\t".join(str(w[k]) for k in KOLUMNY) + "\n")


argv = sys.argv[1:]
assert argv[:4] == ["--profil", "klient", "--format", "json"], sys.argv
assert len(argv) == 4 or (len(argv) == 6 and argv[4] == "--baza"), sys.argv
baza = argv[5] if len(argv) == 6 else None
home = Path(os.environ["WIEDZA_FIRMY_KLIENT_HOME"])
cache = json.loads((home / "tematy-cache.json").read_text(encoding="utf-8"))
assert cache["tematy"] and cache["zasady"], cache
with open(os.environ["ATRAPA_PRZEGLAD_LOG"], "a", encoding="utf-8") as f:
    f.write(f"dzienny {baza}\n" if baza else "wywolanie\n")
print("atrapa przegladu: start")
if os.environ.get("ATRAPA_PRZEGLAD_PADA") == "1":
    if baza:
        koszt(home / "przeglad", "paczka")
    print("atrapa przegladu: padam celowo", file=sys.stderr)
    sys.exit(1)
n = int(os.environ.get("ATRAPA_PRZEGLAD_N") or 150)
temat = cache["tematy"][0]["id"]
teksty = [f"Ustalenie numer {i} z przegladu atrapy." for i in range(n)]
if baza:
    polaczenie = sqlite3.connect(baza)
    teksty = [f"Ustalenie z fragmentu {cid} ({ts})." for cid, ts in polaczenie.execute(
        "SELECT id, ts FROM chunks WHERE role IN ('user', 'assistant', 'conversation') ORDER BY id")]
    polaczenie.close()
    koszt(home / "przeglad", "paczka")
    koszt(home / "przeglad", "konsolidacja")
    koszt(home / "przeglad" / "tagi", "tagi")
wpisy = []
for tresc in teksty:
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
