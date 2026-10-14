"""Tematy dodatkowe dla ustalen Wiedzy firmy: tanie przejscie AI po plikach w formacie importu.

Przeglad historii (przeglad.py) i wsady startowe daja kazdemu wpisowi jeden temat. To narzedzie
czyta takie pliki i dopisuje wpisom TEMATY DODATKOWE znacznikiem po poziomie (umowa z serwerem 0.3.0):

    - [RRRR-MM-DD] [poziom] [+temat2,temat3] tresc

Tresci, daty ani poziomu poufnosci nie zmienia. Jedyny wyjatek: temat glowny ewidentnie zly - wtedy
wpis przechodzi do sekcji `## temat: <nowy>` (powod jest w PODSUMOWANIE.txt). Oryginalow nie
nadpisuje: wyniki ida do <wyjscie>\\<ta sama nazwa>.md.

Wpisy (ze wszystkich plikow razem) ida do `claude -p --model sonnet` w paczkach po ok. 150, kilka
paczek naraz. Wznawialne: decyzja dla kazdego wpisu lezy w <wyjscie>\\.stan\\paczki, kolejny przebieg
pyta model tylko o wpisy bez decyzji. Cisza zakazana: odpowiedz, ktora gubi wpis, myli wpisy
(kontrola poczatku tresci), podaje nieznany temat albo w ogole nie przyszla, to nieudana paczka -
jest w .stan\\bledy i w podsumowaniu, plik z jej wpisami NIE powstaje, kod wyjscia 1. Przed zapisem
kazdy plik wynikowy jest parsowany od nowa i porownany z wejsciem (liczba wpisow, tresci, daty,
poziomy, autor/zrodlo) - roznica to odmowa zapisu.

Uruchomienie:
    uv --directory C:\\dev\\claude-worker\\lore run python
        C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-przeglad\\przetaguj.py
        [pliki.md ...] [--na-sucho] [--rownolegle 4] [--paczka 150] [--wyjscie KATALOG]
Bez plikow: wszystkie *.md z wynikow przegladu oraz wsad startowy grafik.
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import math
import re
import sys
import time
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import przeglad as P  # noqa: E402

WYJSCIE = P.WYNIKI / "otagowane"
WEJSCIA_STALE = (P.RAPORTY / "wiedza-firmy-wsad-grafiki.md",)
PACZKA = 150
ROWNOLEGLE = 4
LIMIT_CZASU_S = 900
# Zmiana promptu = inny klucz wpisu = wpis tagowany od nowa (stare decyzje zostaja na dysku).
WERSJA = "1"
# Szacunek na sucho: id, trzy slowa poczatku, temat i 0-2 dodatkowe w JSON-ie to ok. 40 tokenow wyjscia.
WYJSCIE_NA_WPIS = 40

# Te same regexy co wiedza_firmy.importuj (parser serwera) - plus znacznik [+tematy] z umowy 0.3.0.
_WPIS = re.compile(r"^- \[(?P<data>[^\]]*)\]\s*(?:\[(?P<poziom>[a-ząćęłńóśźż]+)\]\s*)?"
                   r"(?:\[\+(?P<tagi>[^\]]*)\]\s*)?(?P<tresc>.*)$")
_KLUCZ = re.compile(r"^(?P<klucz>autor|program|zrodlo|poufnosc|temat):\s*(?P<wartosc>.*)$")
_TEMAT = re.compile(r"^##\s+temat:\s*(?P<temat>\S+)\s*$")

# Bez ^ & | < > % - schemat idzie w argv przez claude.cmd, czyli przez cmd.exe.
SCHEMAT_SZKIELET = {
    "type": "object",
    "properties": {
        "wpisy": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "id": {"type": "string"},
                "poczatek": {"type": "string"},
                "temat": {"type": "string", "enum": []},
                "dodatkowe": {"type": "array", "items": {"type": "string", "enum": []}},
                "powod": {"type": "string"},
            },
            "required": ["id", "poczatek", "temat", "dodatkowe"],
            "additionalProperties": False,
        }},
    },
    "required": ["wpisy"],
    "additionalProperties": False,
}

PROMPT = """Na wejściu (pod tą instrukcją) dostajesz ustalenia z bazy wiedzy firmy handlu internetowego (marka AROMAHOLIK: olejki eteryczne, kadzidełka, mentol; Amazon, eBay, Allegro). Każde ustalenie to jedna linia: identyfikator W<numer>, w nawiasie kwadratowym jego temat główny, potem treść.

Dla KAŻDEGO wpisu, dokładnie raz i w tej samej kolejności, zwróć:
- "id": jego identyfikator W<numer>;
- "poczatek": pierwsze trzy słowa treści wpisu, przepisane dosłownie (kontrola, że nie pomyliłeś wpisów);
- "temat": temat główny — przepisz ten z wejścia. Zmień go tylko wtedy, gdy jest ewidentnie zły (wpis w ogóle nie dotyczy tego tematu), i wtedy krótko podaj powód w "powod";
- "dodatkowe": lista id tematów dodatkowych (bez tematu głównego), zwykle 0–2, często pusta.

Dodatkowy temat dajesz tylko wtedy, gdy wpis naprawdę przydałby się osobie pracującej w tym temacie — nie dlatego, że pada w nim jakieś słowo. Tematy SPECJALNE dodawaj TYLKO wtedy, gdy wpis zawiera dane tego rodzaju, bo ich dodanie ZAWĘŻA widoczność wpisu. To samo dotyczy przeniesienia tematu głównego do tematu specjalnego. Tematy specjalne i dane, które je uzasadniają:
{specjalne}{reguly}

Treści ani poufności nie zmieniasz. Primo nie podejmuje żadnych decyzji — rozstrzygasz sam. To jest automat: odpowiedź leci prosto do pliku. Nie zadawaj pytań i nie sięgaj po narzędzia."""


# Jakie dane uzasadniaja temat specjalny (osobne_uprawnienie w tematach). Temat specjalny spoza tej
# listy dostaje w prompcie opis z pliku tematow.
DANE_SPECJALNE = {
    "seo": "frazy i wyniki Search Query Performance",
    "dostawcy": "dostawcy, ich ceny i warunki",
    "it": "adresy, sieć, komputery",
    "kadry": "sprawy kadrowe: wynagrodzenia, umowy, urlopy, oceny, zatrudnianie i zwalnianie, dane osobowe pracowników",
}
# Decyzja Primo 2026-10-14: sprawy kadrowe to temat kadry; wpis kadrowy z tematem glownym firma ma ewidentnie
# zly temat glowny. Regula wchodzi do promptu tylko, gdy oba tematy sa na liscie.
REGULA_KADRY = ("\n\nWpis o sprawach kadrowych dostaje temat kadry. Jeśli taki wpis ma temat główny firma, przenieś "
                "temat główny na kadry — to jest właśnie przypadek ewidentnie złego tematu głównego (powód: sprawy kadrowe).")


# ---------------------------------------------------------------- pliki w formacie importu

class BladFormatu(ValueError):
    pass


@dataclass
class Wpis:
    plik: str
    nr: int  # numer pierwszej linii wpisu (od 1)
    temat: str
    data: str  # doslownie z nawiasu
    poziom: str  # jawny z linii albo ""
    poziom_efektywny: str
    tresc_linii: str  # tresc z pierwszej linii
    kontynuacje: list  # linie z wcieciem - ciag dalszy, doslownie
    kontekst: tuple  # (autor, program, zrodlo) obowiazujace dla wpisu
    tagi: list = field(default_factory=list)  # z wejscia - musi byc puste
    oryginal: str = ""  # pierwsza linia doslownie
    klucz: str = ""

    @property
    def tresc(self) -> str:
        """Tresc tak, jak sklei ja serwer (ciag dalszy doklejony spacja)."""
        return " ".join([self.tresc_linii, *(k.strip() for k in self.kontynuacje)]).strip()

    def tozsamosc(self) -> tuple:
        return (*self.kontekst, self.data.strip(), self.poziom_efektywny, self.tresc)


@dataclass
class Plik:
    sciezka: Path
    elementy: list  # ("linia", tekst) | ("sekcja", temat, tekst) | ("wpis", indeks w wpisy)
    wpisy: list


def parsuj(tekst: str, nazwa: str) -> Plik:
    """Ta sama logika co wiedza_firmy.importuj.parsuj, ale bez gubienia linii: kazda linia pliku
    zostaje elementem, zeby plik dalo sie zlozyc z powrotem doslownie."""
    ust = {"autor": "", "program": "", "zrodlo": "", "poufnosc": "", "temat": ""}
    elementy: list = []
    wpisy: list[Wpis] = []
    ostatni: Wpis | None = None
    for nr, linia in enumerate(tekst.splitlines(), 1):
        gdzie = f"{nazwa}:{nr}"
        if not linia.strip():
            ostatni = None
            elementy.append(("linia", linia))
            continue
        if ostatni is not None and linia.startswith("  ") and not linia.lstrip().startswith("- ["):
            ostatni.kontynuacje.append(linia)
            continue
        ostatni = None
        if linia.startswith("# "):
            elementy.append(("linia", linia))
            continue
        if linia.startswith("#"):
            m = _TEMAT.match(linia)
            if not m:
                raise BladFormatu(f"{gdzie}: naglowek inny niz '## temat: <id>' - {linia!r}")
            ust["temat"] = m["temat"]
            elementy.append(("sekcja", m["temat"], linia))
            continue
        m = _KLUCZ.match(linia)
        if m:
            ust[m["klucz"]] = m["wartosc"].strip()
            elementy.append(("sekcja", ust["temat"], linia) if m["klucz"] == "temat" else ("linia", linia))
            continue
        m = _WPIS.match(linia)
        if not m:
            raise BladFormatu(f"{gdzie}: nie rozumiem linii - {linia!r}")
        poziom = m["poziom"] or ust["poufnosc"]
        if not poziom:
            raise BladFormatu(f"{gdzie}: wpis bez poziomu poufnosci i bez 'poufnosc:' wyzej")
        if not ust["temat"]:
            raise BladFormatu(f"{gdzie}: wpis przed pierwszym '## temat: <id>'")
        if not m["tresc"].strip():
            raise BladFormatu(f"{gdzie}: pusta tresc wpisu")
        tagi = [t.strip() for t in (m["tagi"] or "").split(",") if t.strip()] if m["tagi"] is not None else []
        ostatni = Wpis(nazwa, nr, ust["temat"], m["data"], m["poziom"] or "", poziom, m["tresc"].strip(), [],
                       (ust["autor"], ust["program"], ust["zrodlo"]), tagi, linia)
        if m["tagi"] is not None and not tagi:
            ostatni.tagi = ["(pusty znacznik)"]
        elementy.append(("wpis", len(wpisy)))
        wpisy.append(ostatni)
    return Plik(Path(nazwa), elementy, wpisy)


@dataclass
class Decyzja:
    temat: str
    dodatkowe: list
    powod: str = ""


def linie_wpisu(w: Wpis, d: Decyzja) -> list[str]:
    przeniesiony = d.temat != w.temat
    if not d.dodatkowe and not przeniesiony:
        return [w.oryginal, *w.kontynuacje]
    # Poziom zawsze jawny: domyslny 'poufnosc:' u celu moglby byc inny niz u zrodla.
    znacznik = f" [+{','.join(d.dodatkowe)}]" if d.dodatkowe else ""
    return [f"- [{w.data}] [{w.poziom_efektywny}]{znacznik} {w.tresc_linii}", *w.kontynuacje]


def zloz(plik: Plik, decyzje: list[Decyzja], naglowek: str) -> str:
    """Plik wynikowy: wszystkie linie jak w oryginale, wpisy ze znacznikiem tematow dodatkowych,
    przeniesione wpisy na koncu sekcji nowego tematu (albo w nowej sekcji na koncu pliku)."""
    przeniesione: dict[str, list[int]] = {}
    for i, (w, d) in enumerate(zip(plik.wpisy, decyzje)):
        if d.temat != w.temat:
            przeniesione.setdefault(d.temat, []).append(i)
    # miejsce wstawienia: za ostatnim elementem ostatniej sekcji danego tematu
    ostatnia_sekcja: dict[str, int] = {}
    koniec_sekcji: dict[int, int] = {}  # indeks elementu sekcji -> indeks ostatniego jej wpisu
    biezaca = -1
    for j, e in enumerate(plik.elementy):
        if e[0] == "sekcja":
            biezaca = j
            ostatnia_sekcja[e[1]] = j
            koniec_sekcji[j] = j
        elif e[0] == "wpis" and biezaca >= 0:
            koniec_sekcji[biezaca] = j
    wstaw: dict[int, list[int]] = {}
    nowe_sekcje: list[str] = []
    for temat, ktore in przeniesione.items():
        if temat in ostatnia_sekcja:
            wstaw.setdefault(koniec_sekcji[ostatnia_sekcja[temat]], []).extend(ktore)
        else:
            nowe_sekcje.append(temat)

    out: list[str] = []
    # komunikat narzedzia za ostrzezeniami z poczatku pliku (ostrzezenia zostaja na samej gorze)
    j0 = 0
    while j0 < len(plik.elementy) and plik.elementy[j0][0] == "linia" and plik.elementy[j0][1].startswith("# UWAGA"):
        out.append(plik.elementy[j0][1])
        j0 += 1
    out.append(naglowek)
    for j in range(j0, len(plik.elementy)):
        e = plik.elementy[j]
        if e[0] == "linia":
            out.append(e[1])
        elif e[0] == "sekcja":
            out.append(e[2])
        else:
            w, d = plik.wpisy[e[1]], decyzje[e[1]]
            if d.temat == w.temat:
                out.extend(linie_wpisu(w, d))
        for i in wstaw.get(j, []):
            out.extend(linie_wpisu(plik.wpisy[i], decyzje[i]))
    for temat in nowe_sekcje:
        out += ["", f"## temat: {temat}"]
        for i in przeniesione[temat]:
            out.extend(linie_wpisu(plik.wpisy[i], decyzje[i]))
    return "\n".join(out) + "\n"


def sprawdz_wynik(tekst: str, wejscie: Plik, decyzje: list[Decyzja], tematy: set[str]) -> list[str]:
    """Plik wynikowy parsowany od nowa: te same wpisy (liczba, tresc, data, poziom, autor/zrodlo),
    tematy i znaczniki dokladnie jak w decyzjach. Pusta lista = mozna zapisac."""
    try:
        wynik = parsuj(tekst, wejscie.sciezka.name)
    except BladFormatu as e:
        return [f"wynik nie parsuje sie: {e}"]
    problemy = []
    if len(wynik.wpisy) != len(wejscie.wpisy):
        problemy.append(f"liczba wpisow: wejscie {len(wejscie.wpisy)}, wynik {len(wynik.wpisy)}")
    oczekiwane = Counter((*w.tozsamosc(), d.temat, tuple(d.dodatkowe)) for w, d in zip(wejscie.wpisy, decyzje))
    jest = Counter((*w.tozsamosc(), w.temat, tuple(w.tagi)) for w in wynik.wpisy)
    for k in (oczekiwane - jest):
        problemy.append(f"brak albo zmieniony wpis w wyniku: {k[5][:100]!r} (temat {k[6]}, +{','.join(k[7])})")
    for k in (jest - oczekiwane):
        problemy.append(f"wpis w wyniku, ktorego nie bylo na wejsciu: {k[5][:100]!r}")
    for w in wynik.wpisy:
        obce = [t for t in [w.temat, *w.tagi] if t not in tematy]
        if obce:
            problemy.append(f"nieznany temat {', '.join(obce)} w wyniku: {w.tresc[:80]!r}")
    return problemy


# ---------------------------------------------------------------- model

def specjalne(tematy: list[dict]) -> list[str]:
    return [t["id"] for t in tematy if t.get("osobne_uprawnienie")]


def instrukcja(tematy: list[dict]) -> str:
    po_id = {t["id"]: t for t in tematy}
    spec = "\n".join(f"- {i}: {DANE_SPECJALNE.get(i) or po_id[i].get('opis', '')}" for i in specjalne(tematy)) or "- (brak)"
    reguly = REGULA_KADRY if {"kadry", "firma"} <= set(po_id) else ""
    return (f"{PROMPT.format(specjalne=spec, reguly=reguly)}\n\n## Tematy (obowiązuje ta lista id)\n{P.opis_tematow(tematy)}\n\n"
            f"## Materiał\n")


def schemat(tematy: list[dict]) -> str:
    s = json.loads(json.dumps(SCHEMAT_SZKIELET))
    pola = s["properties"]["wpisy"]["items"]["properties"]
    pola["temat"]["enum"] = [t["id"] for t in tematy]
    pola["dodatkowe"]["items"]["enum"] = [t["id"] for t in tematy]
    return json.dumps(s, ensure_ascii=False)


def material(paczka: list[Wpis]) -> str:
    return "\n".join(f"W{i} [{w.temat}] {w.tresc}" for i, w in enumerate(paczka, 1))


def _znaki(s: str) -> str:
    return re.sub(r"[\W_]+", "", s.casefold())


def sprawdz_odpowiedz(dane: dict, paczka: list[Wpis], tematy: set[str]) -> list[Decyzja]:
    """Decyzje w kolejnosci paczki albo BladModelu - paczka jest cala albo wcale."""
    surowe = dane.get("wpisy") if isinstance(dane, dict) else None
    if not isinstance(surowe, list):
        raise P.BladModelu("odpowiedz bez listy 'wpisy'")
    decyzje: dict[int, Decyzja] = {}
    problemy = []
    for s in surowe:
        if not isinstance(s, dict):
            problemy.append(f"element nie jest obiektem: {str(s)[:60]}")
            continue
        m = re.fullmatch(r"W(\d+)", str(s.get("id") or "").strip())
        if not m or not 1 <= int(m.group(1)) <= len(paczka):
            problemy.append(f"nieznany identyfikator {s.get('id')!r}")
            continue
        i = int(m.group(1)) - 1
        if i in decyzje:
            problemy.append(f"W{i + 1} dwa razy")
            continue
        w = paczka[i]
        poczatek = _znaki(str(s.get("poczatek") or ""))
        tresc = _znaki(w.tresc)
        if not poczatek or not tresc.startswith(poczatek) or len(poczatek) < min(6, len(tresc)):
            problemy.append(f"W{i + 1}: poczatek {str(s.get('poczatek'))[:40]!r} nie pasuje do tresci "
                            f"{w.tresc[:40]!r} - model zmienil tresc albo pomylil wpisy")
            continue
        temat = s.get("temat")
        dodatkowe = s.get("dodatkowe")
        if not isinstance(dodatkowe, list):
            problemy.append(f"W{i + 1}: 'dodatkowe' to nie lista")
            continue
        obce = [str(t) for t in [temat, *dodatkowe] if t not in tematy]
        if obce:
            problemy.append(f"W{i + 1}: nieznany temat {', '.join(obce)}")
            continue
        dod = []
        for t in dodatkowe:
            if t != temat and t not in dod:
                dod.append(t)
        powod = " ".join(str(s.get("powod") or "").split())
        if temat != w.temat and not powod:
            powod = "(model nie podal powodu)"
        decyzje[i] = Decyzja(temat, dod, powod if temat != w.temat else "")
    brak = [f"W{i + 1}" for i in range(len(paczka)) if i not in decyzje and not any(
        p.startswith(f"W{i + 1}:") or p == f"W{i + 1} dwa razy" for p in problemy)]
    if brak:
        problemy.append(f"model zgubil wpisy: {', '.join(brak[:20])}{' ...' if len(brak) > 20 else ''}")
    if problemy:
        raise P.BladModelu(f"odpowiedz odrzucona ({len(problemy)} problemow): " + "; ".join(problemy[:5]))
    return [decyzje[i] for i in range(len(paczka))]


# ---------------------------------------------------------------- stan

def klucz_wpisu(sol: str, w: Wpis) -> str:
    return hashlib.sha1(f"{sol}\n{w.temat}\n{w.tresc}".encode("utf-8")).hexdigest()[:16]


def wczytaj_decyzje(stan: P.Stan) -> tuple[dict[str, Decyzja], list[str]]:
    """klucz wpisu -> decyzja ze wszystkich udanych paczek; plus nazwy plikow stanu nie do odczytania."""
    out, zle = {}, []
    katalog = stan.katalog / "paczki"
    for f in sorted(katalog.glob("*.json")) if katalog.exists() else []:
        dane = P._czytaj_json(f)
        if not isinstance(dane, dict) or not isinstance(dane.get("wyniki"), dict):
            zle.append(f.name)
            continue
        for k, d in dane["wyniki"].items():
            try:
                out[k] = Decyzja(d["temat"], list(d["dodatkowe"]), d.get("powod") or "")
            except (KeyError, TypeError):
                zle.append(f.name)
                break
    return out, zle


def przerob_paczke(paczka: list[Wpis], klucz: str, instr: str, schem: str, tematy: set[str], stan: P.Stan,
                   koszt: P.Koszt, limit_s: int, opis: str) -> tuple[bool, str]:
    mat = material(paczka)
    wyslane = len(instr) + len(mat)
    start = time.monotonic()
    try:
        odp = P.zapytaj(instr, mat, schem, limit_s)
    except P.BladModelu as e:
        sek = time.monotonic() - start
        koszt.dodaj(None, sek)
        stan.zapisz_blad(klucz, {"opis": opis, "blad": str(e), "kiedy": datetime.now().isoformat(timespec="seconds")})
        stan.dziennik(P._wiersz_kosztu("tagi", klucz, opis, wyslane, None, f"BLAD: {e}", sek))
        return False, str(e)
    try:
        decyzje = sprawdz_odpowiedz(odp.dane, paczka, tematy)
    except P.BladModelu as e:  # tokeny zuzyte naprawde - w dzienniku z liczbami, paczka nieudana
        koszt.dodaj(odp)
        with koszt._zamek:
            koszt.bledy += 1
        stan.zapisz_blad(klucz, {"opis": opis, "blad": str(e), "kiedy": datetime.now().isoformat(timespec="seconds"),
                                 "odpowiedz": odp.dane})
        stan.dziennik(P._wiersz_kosztu("tagi", klucz, opis, wyslane, odp, f"ODRZUCONE: {e}"))
        return False, str(e)
    koszt.dodaj(odp)
    P._zapisz_json(stan.katalog / "paczki" / f"{klucz}.json", {
        "klucz": klucz, "opis": opis, "kiedy": datetime.now().isoformat(timespec="seconds"),
        "wyniki": {w.klucz: {"temat": d.temat, "dodatkowe": d.dodatkowe, "powod": d.powod}
                   for w, d in zip(paczka, decyzje)},
        "usage": odp.usage, "koszt_usd": odp.koszt_usd, "sekundy": round(odp.sekundy, 1)})
    stan.plik_bledu(klucz).unlink(missing_ok=True)
    z_dod = sum(1 for d in decyzje if d.dodatkowe)
    przen = sum(1 for w, d in zip(paczka, decyzje) if d.temat != w.temat)
    stan.dziennik(P._wiersz_kosztu("tagi", klucz, opis, wyslane, odp,
                                   f"ok: {len(paczka)} wpisow, z dodatkowymi {z_dod}, przeniesione {przen}"))
    return True, f"{len(paczka)} wpisow, z dodatkowymi {z_dod}, przeniesione {przen}, {sum(odp.usage.values())} tok"


def sumy_dziennika(stan: P.Stan) -> tuple[int, int, float, float]:
    """(wywolania z odpowiedzia modelu, tokeny, USD, sekundy) etapu 'tagi' ze wszystkich przebiegow -
    razem z odrzuconymi, bo za nie tez sie placi."""
    try:
        wiersze = (stan.katalog / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    except OSError:
        return 0, 0, 0.0, 0.0
    if not wiersze:
        return 0, 0, 0.0, 0.0
    kol = wiersze[0].split("\t")
    n, tok, usd, sek = 0, 0, 0.0, 0.0
    for w in wiersze[1:]:
        d = dict(zip(kol, w.split("\t")))
        if d.get("etap") != "tagi" or not d.get("tokeny_razem"):
            continue
        try:
            tok += int(d["tokeny_razem"])
            usd += float(d["koszt_usd"])
            sek += float(d["sekundy"])
            n += 1
        except (KeyError, ValueError):
            continue
    return n, tok, usd, sek


def pomiar(stan: P.Stan) -> tuple[float, float] | None:
    """(tokeny, USD) na znak wyslany - z udanych wywolan w dzienniku."""
    try:
        wiersze = (stan.katalog / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    if not wiersze:
        return None
    kol = wiersze[0].split("\t")
    znaki = tok = usd = 0.0
    for w in wiersze[1:]:
        d = dict(zip(kol, w.split("\t")))
        if d.get("etap") != "tagi" or not d.get("wynik", "").startswith("ok"):
            continue
        try:
            znaki += float(d["znaki_wyslane"])
            tok += float(d["tokeny_razem"])
            usd += float(d["koszt_usd"])
        except (KeyError, ValueError):
            continue
    return (tok / znaki, usd / znaki) if znaki else None


# ---------------------------------------------------------------- przebieg

def main(argv: list[str] | None = None) -> int:
    for strumien in (sys.stdout, sys.stderr):
        try:
            strumien.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    a = argparse.ArgumentParser(prog="przetaguj.py", description=__doc__.splitlines()[0])
    a.add_argument("pliki", type=Path, nargs="*", help="pliki w formacie importu (domyslnie wyniki przegladu + wsad grafik)")
    a.add_argument("--na-sucho", action="store_true", help="tylko policz wpisy, paczki i tokeny")
    a.add_argument("--rownolegle", type=int, default=ROWNOLEGLE)
    a.add_argument("--paczka", type=int, default=PACZKA, help="wpisow na jedno wywolanie modelu")
    a.add_argument("--wyjscie", type=Path, default=WYJSCIE)
    a.add_argument("--tematy", type=Path, default=P.TEMATY)
    a.add_argument("--limit-czasu", type=int, default=LIMIT_CZASU_S)
    o = a.parse_intermixed_args(argv)
    if o.rownolegle < 1 or o.paczka < 1:
        print("ODMOWA: --rownolegle i --paczka musza byc >= 1", file=sys.stderr)
        return 2
    sciezki = o.pliki or [*sorted(P.WYNIKI.glob("*.md")), *WEJSCIA_STALE]
    brak = [str(s) for s in sciezki if not s.is_file()]
    nazwy = Counter(s.name for s in sciezki)
    if brak or any(n > 1 for n in nazwy.values()):
        print(f"ODMOWA: brak plikow: {', '.join(brak)}" if brak else
              f"ODMOWA: dwa pliki o tej samej nazwie (wynik by sie nadpisal): "
              f"{', '.join(n for n, k in nazwy.items() if k > 1)}", file=sys.stderr)
        return 2
    if o.wyjscie.resolve() in {s.parent.resolve() for s in sciezki}:
        print("ODMOWA: katalog wyjscia to katalog wejscia - oryginaly by sie nadpisaly", file=sys.stderr)
        return 2
    try:
        tematy = P.wczytaj_tematy(o.tematy)
    except (OSError, ValueError) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 2
    ids = {t["id"] for t in tematy}
    instr, schem = instrukcja(tematy), schemat(tematy)
    sol = hashlib.sha1(f"{WERSJA}\n{instr}\n{schem}".encode("utf-8")).hexdigest()[:12]
    stan = P.Stan(o.wyjscie)
    start = time.monotonic()

    pliki: list[Plik] = []
    problemy_plikow: dict[str, str] = {}
    for s in sciezki:
        try:
            p = parsuj(s.read_text(encoding="utf-8-sig"), s.name)
        except (OSError, BladFormatu) as e:
            problemy_plikow[s.name] = f"nie da sie wczytac: {e}"
            continue
        p.sciezka = s
        juz = [w for w in p.wpisy if w.tagi]
        obce = sorted({w.temat for w in p.wpisy} - ids)
        if juz:
            problemy_plikow[s.name] = f"wejscie juz ma tematy dodatkowe ({len(juz)} wpisow, np. linia {juz[0].nr})"
        elif obce:
            problemy_plikow[s.name] = f"tematy spoza listy: {', '.join(obce)}"
        elif not p.wpisy:
            problemy_plikow[s.name] = "brak wpisow"
        else:
            for w in p.wpisy:
                w.klucz = klucz_wpisu(sol, w)
            pliki.append(p)

    gotowe, zle_stany = wczytaj_decyzje(stan)
    do_zrobienia, widziane = [], set()
    for p in pliki:
        for w in p.wpisy:
            if w.klucz not in gotowe and w.klucz not in widziane:
                widziane.add(w.klucz)
                do_zrobienia.append(w)
    paczki = [do_zrobienia[i:i + o.paczka] for i in range(0, len(do_zrobienia), o.paczka)]
    wszystkie = sum(len(p.wpisy) for p in pliki)

    if o.na_sucho:
        print(raport_na_sucho(pliki, problemy_plikow, paczki, wszystkie, instr, stan, o.paczka))
        return 1 if problemy_plikow else 0

    for f in (stan.katalog / "bledy").glob("*.json") if (stan.katalog / "bledy").exists() else []:
        f.unlink()  # bledy liczone od nowa w kazdym przebiegu - stare nie udaja biezacych
    koszt = P.Koszt()
    nieudane: list[tuple[str, str]] = []
    przerwano = False
    print(f"wpisow: {wszystkie} w {len(pliki)} plikach, z decyzja z poprzednich przebiegow: "
          f"{wszystkie - sum(1 for p in pliki for w in p.wpisy if w.klucz not in gotowe)}, teraz do zrobienia: "
          f"{len(do_zrobienia)} w {len(paczki)} paczkach ({o.rownolegle} naraz)", file=sys.stderr)
    wykonawca = cf.ThreadPoolExecutor(max_workers=o.rownolegle)
    try:
        przyszle = {}
        for n, pz in enumerate(paczki, 1):
            klucz = hashlib.sha1(f"{sol}\n{material(pz)}".encode("utf-8")).hexdigest()[:16]
            opis = f"paczka {n}/{len(paczki)} ({len(pz)} wpisow, od {pz[0].plik}:{pz[0].nr})"
            przyszle[wykonawca.submit(przerob_paczke, pz, klucz, instr, schem, ids, stan, koszt, o.limit_czasu,
                                      opis)] = (klucz, opis)
        for n, f in enumerate(cf.as_completed(przyszle), 1):
            klucz, opis = przyszle[f]
            try:
                ok, wynik = f.result()
            except Exception as e:  # nieprzewidziany blad - tez widoczny
                ok, wynik = False, f"{type(e).__name__}: {e}"
                stan.zapisz_blad(klucz, {"opis": opis, "blad": wynik, "kiedy": datetime.now().isoformat(timespec="seconds")})
            if not ok:
                nieudane.append((opis, wynik))
            print(f"[{n}/{len(paczki)}] {'ok  ' if ok else 'BLAD'} {opis}: {wynik}", file=sys.stderr)
    except KeyboardInterrupt:
        przerwano = True
        print("PRZERWANO - zrobione paczki sa zapisane, kolejny przebieg ich nie powtorzy", file=sys.stderr)
        wykonawca.shutdown(wait=False, cancel_futures=True)
    else:
        wykonawca.shutdown(wait=True)

    gotowe, zle_stany = wczytaj_decyzje(stan)
    o.wyjscie.mkdir(parents=True, exist_ok=True)
    dzis = date.today().isoformat()
    zapisane: list[tuple[Plik, list[Decyzja]]] = []
    for p in pliki:
        cel = o.wyjscie / p.sciezka.name
        bez = [w for w in p.wpisy if w.klucz not in gotowe]
        if bez:
            problemy_plikow[p.sciezka.name] = f"{len(bez)} z {len(p.wpisy)} wpisow bez decyzji modelu (nieudane paczki)"
            cel.unlink(missing_ok=True)  # stary wynik nie moze udawac aktualnego
            continue
        decyzje = [gotowe[w.klucz] for w in p.wpisy]
        z_dod = sum(1 for d in decyzje if d.dodatkowe)
        przen = sum(1 for w, d in zip(p.wpisy, decyzje) if d.temat != w.temat)
        naglowek = (f"# Tematy dodatkowe ([+...]) dopisal przetaguj.py {dzis}: wpisow {len(p.wpisy)}, z dodatkowymi "
                    f"{z_dod}, przeniesione do innego tematu glownego {przen} (lista w PODSUMOWANIE.txt).")
        tekst = zloz(p, decyzje, naglowek)
        problemy = sprawdz_wynik(tekst, p, decyzje, ids)
        if problemy:
            problemy_plikow[p.sciezka.name] = "ODMOWA zapisu - wynik rozni sie od wejscia: " + "; ".join(problemy[:5])
            cel.unlink(missing_ok=True)
            continue
        cel.write_text(tekst, encoding="utf-8")
        zapisane.append((p, decyzje))

    for nazwa in problemy_plikow:
        (o.wyjscie / nazwa).unlink(missing_ok=True)
    sekundy = time.monotonic() - start
    podsumowanie = podsumuj(zapisane, problemy_plikow, nieudane, przerwano, zle_stany, tematy, koszt, stan, sekundy,
                            len(do_zrobienia), len(paczki))
    (o.wyjscie / "PODSUMOWANIE.txt").write_text(podsumowanie, encoding="utf-8")
    print(podsumowanie)
    return 1 if (problemy_plikow or nieudane or przerwano) else 0


def raport_na_sucho(pliki, problemy_plikow, paczki, wszystkie, instr, stan, rozmiar) -> str:
    linie = ["NA SUCHO - bez wywolan modelu", "", f"{'plik':<40} {'wpisow':>7}"]
    for p in pliki:
        linie.append(f"{p.sciezka.name[:40]:<40} {len(p.wpisy):>7}")
    for nazwa, pr in problemy_plikow.items():
        linie.append(f"{nazwa[:40]:<40}   POMINIETY: {pr}")
    do = sum(len(p) for p in paczki)
    znaki = sum(len(material(p)) + len(instr) for p in paczki)
    linie += [
        "",
        f"wpisow: {wszystkie}, z decyzja z poprzednich przebiegow: {wszystkie - do}, do zrobienia: {do}"
        f" w {len(paczki)} paczkach po najwyzej {rozmiar}",
        f"znaki wyslane (z instrukcja {len(instr)} zn. na paczke): {P._tys(znaki)}",
        f"szacunek tokenow: wejscie (znaki / {P.facts.CHARS_PER_TOKEN}) {P._tys(math.ceil(znaki / P.facts.CHARS_PER_TOKEN))},"
        f" wyjscie (~{WYJSCIE_NA_WPIS} na wpis) {P._tys(do * WYJSCIE_NA_WPIS)} - bez narzutu claude -p",
    ]
    m = pomiar(stan)
    if m:
        linie.append(f"wedlug pomiaru z dziennika (z wyjsciem i narzutem claude -p): ok. {P._tys(znaki * m[0])} tokenow,"
                     f" ok. ${znaki * m[1]:.2f} wg claude")
    else:
        linie.append("pomiaru jeszcze nie ma - prawdziwe liczby da pierwszy przebieg (.stan\\koszt.tsv)")
    return "\n".join(linie)


def podsumuj(zapisane, problemy_plikow, nieudane, przerwano, zle_stany, tematy, koszt: P.Koszt, stan: P.Stan,
             sekundy, do_zrobienia, paczek) -> str:
    linie = []
    if problemy_plikow or nieudane or przerwano:
        linie.append("NIEPELNE - nie wszystkie pliki otagowane, NIE zglaszac jako gotowe:")
        if przerwano:
            linie.append("  - przebieg przerwany")
        for opis, blad in nieudane:
            linie.append(f"  - nieudana {opis}: {blad[:400]}")
        for nazwa, pr in problemy_plikow.items():
            linie.append(f"  - {nazwa}: NIE ZAPISANY - {pr}")
        linie.append(f"  (ponow ten sam przebieg; szczegoly w {stan.katalog / 'bledy'})")
        linie.append("")
    else:
        linie += ["KOMPLET - wszystkie pliki otagowane i sprawdzone (wpisy i tresci identyczne jak na wejsciu)", ""]
    if zle_stany:
        linie += [f"UWAGA: pliki stanu nie do odczytania (ich wpisy beda tagowane od nowa): {', '.join(zle_stany)}", ""]
    spec = set(specjalne(tematy))
    wpisy_razem = sum(len(p.wpisy) for p, _ in zapisane)
    linie.append(f"{'plik':<40} {'wpisow':>7} {'z dodat.':>8} {'przenies.':>9}")
    licznik, ile_dod, przeniesienia, specjalne_wpisy = Counter(), Counter(), [], []
    for p, decyzje in zapisane:
        z = sum(1 for d in decyzje if d.dodatkowe)
        pr = [(w, d) for w, d in zip(p.wpisy, decyzje) if d.temat != w.temat]
        linie.append(f"{p.sciezka.name[:40]:<40} {len(p.wpisy):>7} {z:>8} {len(pr):>9}")
        for w, d in zip(p.wpisy, decyzje):
            licznik.update(d.dodatkowe)
            ile_dod[len(d.dodatkowe)] += 1
            if spec & set(d.dodatkowe) or (d.temat != w.temat and d.temat in spec):
                specjalne_wpisy.append((p, w, d))
        przeniesienia += [(p, w, d) for w, d in pr]
    linie += [
        "",
        f"Wpisow w zapisanych plikach: {wpisy_razem}. Liczba tematow dodatkowych na wpis: "
        + ", ".join(f"{k}: {ile_dod[k]}" for k in sorted(ile_dod)) + ".",
        "Tematy dodatkowe: " + (", ".join(f"{t} {n}" for t, n in licznik.most_common()) or "brak") + ".",
    ]
    if przeniesienia:
        linie += ["", f"PRZENIESIONE do innego tematu glownego ({len(przeniesienia)}):"]
        for p, w, d in przeniesienia:
            linie.append(f"  {p.sciezka.name}:{w.nr} {w.temat} -> {d.temat} ({d.powod}): {w.tresc[:100]}")
    if specjalne_wpisy:
        linie += ["", f"Z tematem SPECJALNYM ({', '.join(sorted(spec))}) - zawezona widocznosc ({len(specjalne_wpisy)}):"]
        for p, w, d in specjalne_wpisy:
            linie.append(f"  {p.sciezka.name}:{w.nr} [{d.temat}] [+{','.join(d.dodatkowe)}] {w.tresc[:100]}")
    t = koszt.tokeny
    n, tok, usd, sek = sumy_dziennika(stan)
    linie += [
        "",
        f"Ten przebieg: wpisow do modelu {do_zrobienia} w {paczek} paczkach; wywolan modelu {koszt.wywolania}"
        f" (nieudanych albo odrzuconych {koszt.bledy}), czas calkowity {sekundy:.0f} s, suma czasow wywolan {koszt.sekundy:.0f} s.",
        f"Tokeny (zmierzone, z koperty claude -p): wejscie {P._tys(t['input_tokens'])}, zapis cache "
        f"{P._tys(t['cache_creation_input_tokens'])}, odczyt cache {P._tys(t['cache_read_input_tokens'])}, "
        f"wyjscie {P._tys(t['output_tokens'])}; razem {P._tys(koszt.razem())}. Koszt wg claude: ${koszt.usd:.2f}.",
        f"Lacznie w dzienniku (wszystkie przebiegi, z odrzuconymi): wywolan z odpowiedzia {n}, tokenow {P._tys(tok)},"
        f" ${usd:.2f} wg claude, suma czasow {sek:.0f} s. Kazde wywolanie: {stan.katalog / 'koszt.tsv'}",
    ]
    return "\n".join(linie) + "\n"


if __name__ == "__main__":
    sys.exit(main())
