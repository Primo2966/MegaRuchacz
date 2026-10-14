"""Gdzie serwer trzyma swoje dane. Wszystko poza repo - repo jest publiczne.

WIEDZA_FIRMY_HOME > %APPDATA%\\wiedza-firmy. Model: WIEDZA_FIRMY_MODELE > <HOME>\\modele.
Funkcje, nie stale: test i CLI moga zmienic zmienna srodowiskowa przed pierwszym uzyciem.
"""

from __future__ import annotations

import os
from pathlib import Path


def katalog_danych() -> Path:
    wybrany = os.environ.get("WIEDZA_FIRMY_HOME")
    if wybrany:
        return Path(wybrany)
    appdata = os.environ.get("APPDATA")
    baza = Path(appdata) if appdata else Path.home() / "AppData" / "Roaming"
    return baza / "wiedza-firmy"


def plik_bazy() -> Path:
    return katalog_danych() / "wiedza.db"


def plik_tematow() -> Path:
    return katalog_danych() / "tematy.json"


def plik_osob() -> Path:
    return katalog_danych() / "osoby.json"


def katalog_modeli() -> Path:
    wybrany = os.environ.get("WIEDZA_FIRMY_MODELE")
    return Path(wybrany) if wybrany else katalog_danych() / "modele"


def znacznik_serwera() -> Path:
    """'Bylem tu' serwera: czas ostatniego zycia, pid, stan modelu. Nieswiezy = alarm dla straznika."""
    return katalog_danych() / "serwer-zyje.json"


def plik_zasad_klienta() -> Path:
    """Zasady przegladu dla klienta (GET /klient/tematy): co wolno wysylac do wiedzy firmy. Brak = pusty tekst."""
    return katalog_danych() / "zasady-klienta.md"


def dziennik_zgloszen_klientow() -> Path:
    """Kazda proba wydania tokenu komputerowi (POST /klient/token): czas | id | wynik | adres | opis."""
    return katalog_danych() / "zgloszenia-klientow.log"
