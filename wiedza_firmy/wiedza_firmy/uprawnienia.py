"""Kto czego moze: poziomy poufnosci, uprawnienia osoby i zrodlo uprawnien.

Poziomy rosna: jawne < wewnetrzne < wrazliwe. Uprawnienie "temat: wewnetrzne" daje w tym temacie
jawne i wewnetrzne. "tajne" nie istnieje w bazie - takie wpisy nie powstaja.

Zasada: domyslnie NIC. Nieznany token, osoba bez wpisu, uszkodzony plik osob, uprawnienie
z nieznanym poziomem - kazde z nich konczy sie brakiem dostepu, nigdy dostepem "na wszelki wypadek".

Zrodlo uprawnien to protokol `ZrodloUprawnien`. Krok 1: `ZrodloPlikowe` (osoby.json na serwerze).
Krok 2 (JFTools) podstawia wlasna klase z tymi dwiema metodami - wyszukiwanie i serwer sie nie zmieniaja.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping, Protocol

from .pliki import czytaj_json, log

POZIOMY: tuple[str, ...] = ("jawne", "wewnetrzne", "wrazliwe")
TAJNE = "tajne"

KOMUNIKAT_BRAK_UPRAWNIEN = "Nie masz jeszcze uprawnień — poproś admina."

_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def poziomy_do(najwyzszy: str | None) -> tuple[str, ...]:
    """Poziomy widoczne przy danym najwyzszym: 'wewnetrzne' -> (jawne, wewnetrzne). Nieznany -> nic."""
    if najwyzszy not in POZIOMY:
        return ()
    return POZIOMY[: POZIOMY.index(najwyzszy) + 1]


def skrot_tokenu(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Uprawnienia:
    """Uprawnienia jednej osoby. Admin widzi wszystkie tematy i poziomy oraz moze dodawac i usuwac."""

    osoba: str | None
    admin: bool = False
    tematy: Mapping[str, str] = field(default_factory=dict)  # temat_id -> najwyzszy poziom

    @property
    def puste(self) -> bool:
        return not self.admin and not any(poziomy_do(p) for p in self.tematy.values())

    def poziomy(self, temat: str) -> tuple[str, ...]:
        if self.admin:
            return POZIOMY
        return poziomy_do(self.tematy.get(temat))

    def widzi(self, temat: str, poufnosc: str) -> bool:
        return poufnosc in self.poziomy(temat)


BRAK = Uprawnienia(osoba=None)


class ZrodloUprawnien(Protocol):
    """Skad serwer wie, kim jest pytajacy i co mu wolno."""

    def osoba_dla_tokenu(self, token: str) -> str | None:
        """Osoba z tym tokenem albo None (= 401)."""

    def uprawnienia(self, osoba: str) -> Uprawnienia:
        """Uprawnienia osoby; nieznana osoba = Uprawnienia bez zadnego tematu."""


class ZrodloPlikowe:
    """osoby.json: {osoba: {token_sha256, admin, uprawnienia: {temat_id: najwyzszy_poziom}}}.

    Plik czytany od nowa po kazdej zmianie (rozmiar + czas) - nadanie uprawnienia z CLI dziala bez
    restartu serwera. Brak pliku albo blad w nim = nikt nie wchodzi, a blad idzie do dziennika raz
    na kazda wersje pliku (nie przy kazdym zapytaniu).
    """

    def __init__(self, sciezka: Path) -> None:
        self.sciezka = Path(sciezka)
        self._stan: tuple | None = None
        self._osoby: dict[str, dict] = {}
        self._blad: str | None = None
        self._zamek = threading.Lock()

    @property
    def blad(self) -> str | None:
        """Ostatni problem z plikiem osob (do meldunku), None gdy plik w porzadku."""
        self._odswiez()
        return self._blad

    def _odswiez(self) -> dict[str, dict]:
        with self._zamek:
            try:
                st = self.sciezka.stat()
                stan: tuple = (st.st_mtime_ns, st.st_size)
            except FileNotFoundError:
                stan = ("brak",)
            if stan == self._stan:
                return self._osoby
            self._stan = stan
            self._osoby, self._blad = _wczytaj_osoby(self.sciezka, stan == ("brak",))
            if self._blad:
                log(f"UWAGA osoby: {self._blad}")
            return self._osoby

    def osoba_dla_tokenu(self, token: str) -> str | None:
        if not token:
            return None
        skrot = skrot_tokenu(token)
        znaleziona = None
        for osoba, wpis in self._odswiez().items():
            # porownanie w stalym czasie i bez przerywania petli - czas odpowiedzi nie zdradza osoby
            if hmac.compare_digest(skrot, wpis["token_sha256"]):
                znaleziona = osoba
        return znaleziona

    def uprawnienia(self, osoba: str) -> Uprawnienia:
        wpis = self._odswiez().get(osoba)
        if wpis is None:
            return Uprawnienia(osoba=osoba)
        return Uprawnienia(osoba=osoba, admin=wpis["admin"], tematy=dict(wpis["uprawnienia"]))


def _wczytaj_osoby(sciezka: Path, brak: bool) -> tuple[dict[str, dict], str | None]:
    """Sprawdzone wpisy osob + opis problemu. Wpis z bledem wypada w calosci albo traci zly kawalek."""
    if brak:
        return {}, f"nie ma pliku {sciezka} - nikt nie ma dostepu (python -m wiedza_firmy.osoby nowa ...)"
    try:
        surowe = czytaj_json(sciezka)
    except (OSError, ValueError) as e:
        return {}, f"nie da sie odczytac {sciezka} ({e!r}) - nikt nie ma dostepu, dopoki plik nie bedzie poprawny"
    if not isinstance(surowe, dict):
        return {}, f"{sciezka}: oczekiwany obiekt osoba -> wpis - nikt nie ma dostepu"
    osoby: dict[str, dict] = {}
    problemy: list[str] = []
    for osoba, wpis in surowe.items():
        if not isinstance(wpis, dict) or not _SHA256.match(str(wpis.get("token_sha256", ""))):
            problemy.append(f"{osoba}: brak poprawnego token_sha256 - osoba bez dostepu")
            continue
        admin = wpis.get("admin", False)
        if not isinstance(admin, bool):
            problemy.append(f"{osoba}: admin={admin!r} nie jest true/false - traktuje jako false")
            admin = False
        uprawnienia: dict[str, str] = {}
        surowe_upr = wpis.get("uprawnienia") or {}
        if not isinstance(surowe_upr, dict):
            problemy.append(f"{osoba}: uprawnienia nie sa obiektem temat -> poziom - pomijam")
            surowe_upr = {}
        for temat, poziom in surowe_upr.items():
            if poziom in POZIOMY:
                uprawnienia[str(temat)] = poziom
            else:
                problemy.append(f"{osoba}: {temat}={poziom!r} to nie poziom ({', '.join(POZIOMY)}) - pomijam")
        osoby[str(osoba)] = {"token_sha256": wpis["token_sha256"], "admin": admin, "uprawnienia": uprawnienia}
    return osoby, ("; ".join(problemy) or None)
