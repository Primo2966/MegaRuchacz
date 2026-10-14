"""Przeglad CALEJ historii rozmow Primo z Lore -> ustalenia do "Wiedzy firmy", plik na temat.

Dwa etapy, oba przez `claude -p --model sonnet` w osobnych, niezaleznych wywolaniach (tak jak dzienny
automat faktow, lore.facts) - zadna rozmowa nie przechodzi przez kontekst agenta, ktory to uruchamia:

1. PACZKI: historia (tabela chunks w lore.db, role user/assistant/conversation, bez projektow-smieci)
   dzielona w obrebie projektu, chronologicznie, na paczki do lore.facts.MAX_INPUT_CHARS znakow.
   Z kazdej paczki model wypisuje ustalenia: tresc, temat, poufnosc, data, zrodlo (chunk_id).
2. KONSOLIDACJA na temat: duplikaty razem, z decyzji zmienianych w czasie zostaje najnowsza, bez
   tego, co juz jest na serwerze (--istniejace). Wynik: <wyniki>\\<temat>.md w formacie importu
   serwera (wiedza_firmy.importuj) + sekcja "Do decyzji Primo" (zakomentowana - nie wchodzi do
   importu, dopoki Primo nie zdejmie "# ").

Wznawialne: kazda przerobiona paczka i kazda czesc konsolidacji lezy na dysku (<wyniki>\\.stan),
ponowny przebieg ich nie powtarza. Cisza zakazana: nieudana paczka zostaje w .stan\\bledy, jest
w podsumowaniu, ponawia ja kolejny przebieg, a przebieg z dziurami konczy sie kodem 1 i bez
konsolidacji (chyba ze --mimo-dziur; wtedy pliki tematow dostaja ostrzezenie na poczatku).

Uruchomienie (z katalogu dowolnego):
    uv --directory C:\\dev\\claude-worker\\lore run python
        C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-przeglad\\przeglad.py
        [--na-sucho] [--proba PROJ1,PROJ2] [--rownolegle 4] [--limit-paczek N] [--mimo-dziur]

Niczego nie wysyla na serwer wiedzy. Nie zmienia niczego w lore\\ - tylko importuje.
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import fnmatch
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import asdict, dataclass, field
from datetime import date, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "lore"))

from lore import facts, selection  # noqa: E402
from lore.db import DB_PATH, ts_to_local  # noqa: E402
from lore.index import OVERLAP  # noqa: E402
from lore.masking import mask  # noqa: E402

RAPORTY = REPO / ".megaruchacz" / "raporty"
WYNIKI = RAPORTY / "wiedza-firmy-przeglad"
TEMATY = RAPORTY / "wiedza-firmy-tematy.json"
ZASADY = RAPORTY / "wiedza-firmy-tematy-i-poufnosc.md"
ISTNIEJACE = (RAPORTY / "wiedza-firmy-wsad-grafiki.md",)
WIEDZA_FIRMY = REPO / "wiedza_firmy"

ROLE = ("user", "assistant", selection.MIXED_ROLE)  # wszystko inne (tool, result, agent:*) pomijamy
TURY = {"user": "Primo", "assistant": "AI"}  # tury sklejonego chunku "conversation", ktore zostaja
SMIECI = ("*-Temp-*", "*scratchpad*", "*worktrees*", "*e2e*", "*Roaming-Claude-scratch*")
# Komunikaty Claude Code zapisane pod rola "user", ale niewypowiedziane przez czlowieka.
SZUM = ("<local-command", "<command-name>", "<command-message>", "Caveat: The messages below",
        "[Request interrupted")
# Orca trzyma wlasna kopie transkryptu - ta sama wypowiedz w dwoch projektach to jedna wypowiedz.
# Przy duplikacie wygrywa projekt nie-Orca (ma prawdziwa nazwe katalogu).
ORCA = "orca"

MAX_PACZKA = facts.MAX_INPUT_CHARS  # ten sam sufit kosztu jednego wywolania co dzienny automat
# Jedna wklejka potrafi miec 72 000 znakow (strony Seller Central, logi). Glowa i ogon zostaja,
# srodek jest wyciety GLOSNO (znacznik mowi ile) - jak w lore.selection, tylko z szerszym oknem,
# bo tu czytamy cala historie, a nie same poprawki.
MAX_WIADOMOSC, GLOWA, OGON = 6000, 4000, 1500
# Konsolidacja zwraca prawie tyle, ile dostala, gdy duplikatow jest malo - wyjscie modelu jest
# krotsze niz wejscie, wiec czesc konsolidacji jest mniejsza niz paczka.
MAX_KONSOLIDACJA = 40_000
MAX_RUND = 5
ROWNOLEGLE = 4
LIMIT_CZASU_PACZKA_S = 900
LIMIT_CZASU_KONSOLIDACJA_S = 1200
POZIOMY = ("jawne", "wewnetrzne", "wrazliwe")
# Zmiana promptu = inny klucz paczki = paczka przerabiana od nowa (stare wyniki zostaja na dysku).
WERSJA = "1"

# Flagi z lore.facts.MODEL_ARGS (safe-mode, bez zapisu sesji, sonnet, json) - bez jego schematu.
assert facts.MODEL_ARGS[-2] == "--json-schema", "lore.facts.MODEL_ARGS zmienil ksztalt"
FLAGI_MODELU = facts.MODEL_ARGS[:-1]
POLA_TOKENOW = facts.TOKEN_FIELDS

# Bez ^ & | < > % - schemat idzie w argv przez claude.cmd, czyli przez cmd.exe.
SCHEMAT_PACZKI_SZKIELET = {
    "type": "object",
    "properties": {
        "ustalenia": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "tresc": {"type": "string"},
                "temat": {"type": "string", "enum": []},
                "poufnosc": {"type": "string", "enum": list(POZIOMY)},
                "data_ustalenia": {"type": "string"},
                "chunk_id": {"type": "integer"},
                "niepewne": {"type": "boolean"},
                "powod": {"type": "string"},
            },
            "required": ["tresc", "temat", "poufnosc", "data_ustalenia", "chunk_id", "niepewne"],
            "additionalProperties": False,
        }},
        "pominiete_tajne": {"type": "integer"},
    },
    "required": ["ustalenia"],
    "additionalProperties": False,
}
SCHEMAT_KONSOLIDACJI = json.dumps({
    "type": "object",
    "properties": {
        "wpisy": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "tresc": {"type": "string"},
                "poufnosc": {"type": "string", "enum": list(POZIOMY)},
                "data_ustalenia": {"type": "string"},
                "zrodla": {"type": "array", "items": {"type": "string"}},
                "niepewne": {"type": "boolean"},
                "powod": {"type": "string"},
            },
            "required": ["tresc", "poufnosc", "data_ustalenia", "zrodla", "niepewne"],
            "additionalProperties": False,
        }},
    },
    "required": ["wpisy"],
    "additionalProperties": False,
}, ensure_ascii=False)

PROMPT_PACZKI = """Na wejściu (pod tą instrukcją) dostajesz fragment historii rozmów Primo — właściciela firmy handlu internetowego — z asystentem AI. Każda wypowiedź ma nagłówek [#numer data kto], gdzie kto to "Primo" albo "AI". Rozmowy są pocięte na fragmenty, więc wątek może zaczynać się w połowie.

Wypisz USTALENIA do wspólnej bazy wiedzy firmy, którą czytają pracownicy i ich asystenci AI. Ustalenie to coś trwałego, co warto wiedzieć w przyszłej pracy: zasada, decyzja, konwencja, sposób postępowania, fakt o produktach, procesach, narzędziach, platformach sprzedażowych albo o tym, kto za co odpowiada.

NIE są ustaleniami: stan zadań (co jest w toku, co zrobiono dziś, co czeka), przebieg debugowania, szczegóły kodu (nazwy funkcji i plików źródłowych, struktura repozytorium), jednorazowe polecenia, pomysły odrzucone, uprzejmości. Nie wpisuj też bieżących list i stanów (które SKU są akurat zablokowane, czego dziś brakuje, co jest w drodze) - zapisz tylko trwałą regułę, która z nich wynika. Propozycja AI jest ustaleniem tylko wtedy, gdy Primo ją przyjął albo gdy to sprawdzony wynik (zmierzony, potwierdzony w dokumentacji); słowa Primo mają pierwszeństwo przed słowami AI.

Każde ustalenie:
- "tresc": 1–2 pełne zdania po polsku, zrozumiałe bez rozmowy — z konkretnymi nazwami zamiast "to", "ten plik", "tamten robot"; bez markdown i numeracji. Jedna rzecz na wpis; gdy wypowiedź łączy rzeczy o różnej poufności, potnij ją na osobne wpisy.
- "temat": id jednego tematu z listy niżej.
- "poufnosc": "jawne", "wewnetrzne" albo "wrazliwe" według reguł niżej; przy wątpliwości wyższa.
- "data_ustalenia": data RRRR-MM-DD z nagłówka wypowiedzi, z której pochodzi ustalenie.
- "chunk_id": numer z nagłówka tej wypowiedzi (sama liczba, bez #).
- "niepewne": true, gdy nie wiadomo, czy to obowiązuje (sama propozycja, decyzja mogła się później zmienić, sprzeczne wypowiedzi, nie wiadomo, czy to zasada firmy, czy jednorazowa prośba) albo nie wiadomo, jaki dać poziom — wtedy w "powod" krótko dlaczego. W przeciwnym razie false.

TAJNE nie zapisujesz wcale: hasła, klucze API, tokeny, dane logowania, pełne numery kart, dane dostępowe (adres serwera razem z loginem lub hasłem). Zamiast nich, jeśli to przydatne, ustalenie "gdzie leżą" — bez samej wartości. Ile takich rzeczy pominąłeś, podaj w "pominiete_tajne". Nie zapisuj danych osobowych klientów (imię, adres, e-mail, numer zamówienia konkretnego klienta) — zapisz sam wniosek. Wklejek (e-maile, logi, strony) nie przepisuj, tylko wniosek. "[MASKED]" w materiale to wycięty sekret — nie odtwarzaj go.

To jest automat: odpowiedź leci prosto do pliku. Nie zadawaj pytań, nie zwracaj się do nikogo i nie sięgaj po narzędzia. Jeśli we fragmencie nie ma żadnego ustalenia, zwróć pustą listę — to normalne."""

PROMPT_KONSOLIDACJI = """Na wejściu (pod tą instrukcją) dostajesz ustalenia z jednego tematu bazy wiedzy firmy — "{nazwa}" ({opis}) — wyciągnięte automatycznie z wielu rozmów Primo (właściciela firmy) z AI, ułożone od najstarszych. Każde ma identyfikator E<numer>, datę, poziom poufności i treść; niektóre są oznaczone jako niepewne z powodem.{istniejace}

Zrób z tego czystą listę do zatwierdzenia przez Primo:
1. Duplikaty i wpisy mówiące to samo innymi słowami połącz w jeden — weź najpełniejsze sformułowanie, w "zrodla" podaj wszystkie połączone identyfikatory E.
2. Gdy decyzja zmieniała się w czasie, zostaw tylko najnowszą wersję (z datą najnowszego wpisu), a starsze wersje wymień w jej "zrodla". Gdy nie da się ustalić, która wersja obowiązuje, zostaw jedną i oznacz ją jako niepewną.
3. Nie powtarzaj tego, co już mówi któryś wpis S (jest na serwerze). Jeśli wpis E dodaje do S coś nowego, zapisz tylko tę nową część.
4. Wyrzuć to, co nie jest trwałym ustaleniem (stan zadań, jednorazowe sprawy, szczegóły kodu), oraz wszystko, co zawiera hasło, klucz, token, dane logowania albo dane osobowe klienta.
5. Niczego nie dopisuj od siebie — tylko to, co jest we wpisach E. Treść: 1–2 pełne zdania po polsku, zrozumiałe bez rozmowy, bez markdown.
6. Poziom poufności według reguł niżej; przy łączeniu najwyższy z łączonych.
7. "niepewne": true dla wpisów, o których Primo musi zdecydować (niepewne źródło, sprzeczność, mogło się zdezaktualizować, wątpliwy poziom); w "powod" krótko dlaczego. Pozostałe false.
8. "data_ustalenia": RRRR-MM-DD. Każdy wpis wyniku musi mieć w "zrodla" co najmniej jeden identyfikator E.

To jest automat: odpowiedź leci prosto do pliku. Nie zadawaj pytań i nie sięgaj po narzędzia. Jeśli nie zostaje nic, zwróć pustą listę."""

ISTNIEJACE_NOTA = """ Na końcu materiału są też wpisy S<numer>, które JUŻ SĄ na serwerze wiedzy firmy w tym temacie — ich nie powtarzaj."""

_DATA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Wartosc po "haslo:" / "haslo do panelu: ..." / "token=" itd. Lore.masking lapie klucze z nazwa
# po angielsku i znane przedrostki; tu jeszcze polskie slowa, kilka slow miedzy slowem a dwukropkiem
# i krotsze wartosci. Dwukropek albo "=" sa wymagane - inaczej "kluczowe pojecie" i "hasla do Wi-Fi
# leza w sejfie" bylyby sekretem. Falszywe trafienie nie ginie po cichu: jest w odrzuconych.
_SEKRET_SLOWO = re.compile(r"(?i)\b(has[lł]o|password|passwd|token|pin|klucz(?:\s+api)?|"
                           r"api[\s_-]?key|secret|sekret)\b[^:=\n.]{0,40}[:=]\s*\S{4,}")


def sekret(tresc: str) -> str:
    """Powod odrzucenia, gdy tresc wyglada na sekret; pusty napis, gdy czysta."""
    if mask(tresc) != tresc:
        return "wzorzec sekretu (lore.masking)"
    if selection._LONG_TOKEN.search(tresc):
        return "dlugi ciag liter i cyfr (token?)"
    if _SEKRET_SLOWO.search(tresc):
        return "wartosc po slowie haslo/klucz/token"
    return ""


def smiec(projekt: str) -> bool:
    return any(fnmatch.fnmatch(projekt.casefold(), w.casefold()) for w in SMIECI)


def _klucz_tekstu(tekst: str) -> str:
    return hashlib.sha1(" ".join(tekst.split()).encode("utf-8")).hexdigest()


def skroc(tekst: str) -> tuple[str, int]:
    """(tekst, ile wycieto) - za dluga wiadomosc traci srodek, glosno."""
    if len(tekst) <= MAX_WIADOMOSC:
        return tekst, 0
    wyciete = len(tekst) - GLOWA - OGON
    return f"{tekst[:GLOWA]}\n[… wycięto {wyciete} znaków …]\n{tekst[-OGON:]}", wyciete


# ---------------------------------------------------------------- material

@dataclass
class Wiadomosc:
    chunk_id: int
    projekt: str
    sesja: str
    plik: str
    linia: int
    ts: str
    kto: str  # "user" albo "assistant"
    tekst: str


@dataclass
class Statystyka:
    wiersze: int = 0
    wiadomosci: int = 0
    znaki: int = 0
    pominiete_role: dict = field(default_factory=dict)  # rola -> liczba chunkow
    pominiete_projekty: dict = field(default_factory=dict)  # projekt -> liczba chunkow
    pominiete_tury: int = 0  # tool/result/summary wewnatrz chunkow "conversation"
    automatyczne: int = 0  # zadania z Harmonogramu i komunikaty Claude Code pod rola user
    duplikaty: int = 0  # ta sama wypowiedz w dwoch projektach (Orca)
    skrocone: int = 0
    wyciete_znaki: int = 0


def polacz_baze(sciezka: Path) -> sqlite3.Connection:
    """Tylko odczyt - przeglad nigdy nie pisze do bazy Lore."""
    if not sciezka.exists():
        raise FileNotFoundError(f"brak bazy Lore: {sciezka}")
    return sqlite3.connect(f"file:{sciezka.as_posix()}?mode=ro", uri=True)


def wczytaj(conn: sqlite3.Connection, projekty: list[str] | None = None) -> tuple[list[Wiadomosc], Statystyka]:
    st = Statystyka()
    wybrane = {p.casefold() for p in projekty} if projekty else None
    for rola, projekt, n in conn.execute("SELECT role, project, count(*) FROM chunks GROUP BY role, project"):
        if wybrane is not None and projekt.casefold() not in wybrane:
            continue
        if rola not in ROLE:
            st.pominiete_role[rola] = st.pominiete_role.get(rola, 0) + n
        elif smiec(projekt):
            st.pominiete_projekty[projekt] = st.pominiete_projekty.get(projekt, 0) + n
    znaki = ",".join("?" * len(ROLE))
    wiersze = conn.execute(
        f"SELECT id, project, session, file, line, part, ts, role, text FROM chunks"
        f" WHERE role IN ({znaki}) ORDER BY project, file, line, part", ROLE).fetchall()
    out: list[Wiadomosc] = []
    pominieta = None  # (plik, linia, rola) wypowiedzi odrzuconej w calosci - jej dalsze czesci tez
    for cid, projekt, sesja, plik, linia, czesc, ts, rola, tekst in wiersze:
        if (wybrane is not None and projekt.casefold() not in wybrane) or smiec(projekt):
            continue
        st.wiersze += 1
        if rola in TURY:
            if czesc and pominieta == (plik, linia, rola):
                continue
            ostatnia = out[-1] if out else None
            if czesc and ostatnia and (ostatnia.plik, ostatnia.linia, ostatnia.kto) == (plik, linia, rola):
                ostatnia.tekst += tekst[OVERLAP:]  # kolejna czesc tej samej dlugiej wypowiedzi
                continue
            tury = [(rola, tekst)]
        else:
            tury = selection.turns(rola, tekst)
        for kto, powiedziane in tury:
            if kto not in TURY:
                st.pominiete_tury += 1
                continue
            if not powiedziane.strip():
                continue
            if kto == "user" and (selection.automated(powiedziane) or powiedziane.lstrip().startswith(SZUM)):
                st.automatyczne += 1
                pominieta = (plik, linia, rola)
                continue
            out.append(Wiadomosc(cid, projekt, sesja, plik, linia, ts, kto, powiedziane))
    # Orca: ta sama wypowiedz w tej samej chwili w dwoch projektach - zostaje jedna
    out.sort(key=lambda w: (w.projekt.casefold() == ORCA,))
    widziane, unikalne = set(), []
    for w in out:
        k = (w.ts, _klucz_tekstu(w.tekst))
        if k in widziane:
            st.duplikaty += 1
            continue
        widziane.add(k)
        unikalne.append(w)
    for w in unikalne:
        w.tekst, wyciete = skroc(selection.redact(w.tekst))
        if wyciete:
            st.skrocone += 1
            st.wyciete_znaki += wyciete
    st.wiadomosci = len(unikalne)
    st.znaki = sum(len(w.tekst) for w in unikalne)
    return unikalne, st


@dataclass
class Paczka:
    projekt: str
    chunk_ids: list[int]
    material: str
    od: str
    do: str
    daty: dict = field(default_factory=dict)  # chunk_id -> RRRR-MM-DD (czas lokalny)
    klucz: str = ""

    def nazwa(self) -> str:
        return f"{self.projekt} #{self.chunk_ids[0]}..#{self.chunk_ids[-1]}"


def _linia(w: Wiadomosc) -> str:
    return f"[#{w.chunk_id} {ts_to_local(w.ts)} {TURY[w.kto]}] {w.tekst}"


def paczki(wiadomosci: list[Wiadomosc], limit: int = MAX_PACZKA) -> list[Paczka]:
    """Paczki w obrebie projektu; rozmowy po kolei wedlug ich pierwszej wypowiedzi, w rozmowie po
    kolei. Rozmowa nie jest rwana na sile - paczka konczy sie dopiero, gdy nastepna wypowiedz
    by sie nie zmiescila."""
    po_projekcie: dict[str, dict[str, list[Wiadomosc]]] = {}
    for w in wiadomosci:
        po_projekcie.setdefault(w.projekt, {}).setdefault(w.sesja, []).append(w)
    out: list[Paczka] = []
    for projekt in sorted(po_projekcie, key=str.casefold):
        sesje = po_projekcie[projekt]
        for s in sesje.values():
            s.sort(key=lambda w: (w.ts, w.plik, w.linia))
        kolejnosc = sorted(sesje, key=lambda s: (sesje[s][0].ts, s))
        biezace: list[str] = []
        ids: list[int] = []
        nalezace: list[Wiadomosc] = []

        def zamknij():
            if nalezace:
                material = "\n\n".join(biezace)
                p = Paczka(projekt, list(ids), material, nalezace[0].ts, nalezace[-1].ts,
                           {w.chunk_id: ts_to_local(w.ts)[:10] for w in nalezace})
                p.klucz = hashlib.sha1(f"{WERSJA}\n{projekt}\n{material}".encode("utf-8")).hexdigest()[:16]
                out.append(p)
            biezace.clear()
            ids.clear()
            nalezace.clear()

        for sesja in kolejnosc:
            naglowek = f"=== rozmowa {sesja[:8]} ==="
            pierwsza = True
            for w in sesje[sesja]:
                kawalki = ([naglowek] if pierwsza else []) + [_linia(w)]
                dlugosc = sum(len(k) + 2 for k in kawalki)
                if biezace and sum(len(b) + 2 for b in biezace) + dlugosc > limit:
                    zamknij()
                    kawalki = [naglowek + " (ciąg dalszy)" if not pierwsza else naglowek, _linia(w)]
                biezace.extend(kawalki)
                if w.chunk_id not in ids:
                    ids.append(w.chunk_id)
                nalezace.append(w)
                pierwsza = False
        zamknij()
    return out


# ---------------------------------------------------------------- instrukcje

def wczytaj_tematy(sciezka: Path) -> list[dict]:
    tematy = json.loads(sciezka.read_text(encoding="utf-8-sig"))
    if not isinstance(tematy, list) or not tematy or not all(isinstance(t, dict) and t.get("id") for t in tematy):
        raise ValueError(f"{sciezka}: oczekiwana niepusta lista obiektow z polem 'id'")
    return tematy


def wyciag_zasad(sciezka: Path) -> str:
    """Decyzje na gorze oraz sekcje 1-2 (tematy i reguly) - wszystko przed '## 3.'."""
    tekst = sciezka.read_text(encoding="utf-8-sig")
    m = re.search(r"^## 3\.", tekst, re.M)
    if not m:
        raise ValueError(f"{sciezka}: nie ma sekcji '## 3.' - nie wiem, gdzie koncza sie reguly")
    return tekst[:m.start()].strip()


def opis_tematow(tematy: list[dict]) -> str:
    linie = []
    for t in tematy:
        osobne = " [osobne uprawnienie — nadawane tylko wprost]" if t.get("osobne_uprawnienie") else ""
        przyklady = "; ".join(t.get("przyklady") or [])
        linie.append(f"- {t['id']} — {t.get('nazwa', '')}{osobne}: {t.get('opis', '')}"
                     + (f" Przykłady: {przyklady}." if przyklady else ""))
    return "\n".join(linie)


def instrukcja_paczki(tematy: list[dict], zasady: str) -> str:
    return (f"{PROMPT_PACZKI}\n\n## Tematy (obowiązuje ta lista id, nie numeracja z reguł niżej)\n"
            f"{opis_tematow(tematy)}\n\n## Reguły poufności ustalone z właścicielem\n{zasady}\n\n"
            f"## Materiał\n")


def schemat_paczki(tematy: list[dict]) -> str:
    s = json.loads(json.dumps(SCHEMAT_PACZKI_SZKIELET))
    s["properties"]["ustalenia"]["items"]["properties"]["temat"]["enum"] = [t["id"] for t in tematy]
    return json.dumps(s, ensure_ascii=False)


# ---------------------------------------------------------------- model

class BladModelu(RuntimeError):
    pass


@dataclass
class Odpowiedz:
    dane: dict
    usage: dict
    koszt_usd: float
    sekundy: float
    znaki_odebrane: int


def komenda_claude() -> list[str]:
    """Atrapa w testach: WIEDZA_PRZEGLAD_CLAUDE = JSON z lista argv (np. [python, atrapa.py])."""
    wlasna = os.environ.get("WIEDZA_PRZEGLAD_CLAUDE")
    if wlasna:
        return list(json.loads(wlasna))
    exe = shutil.which("claude")
    if not exe:
        raise BladModelu("nie ma `claude` w PATH")
    return [exe]


def zapytaj(instrukcja: str, material: str, schemat: str, limit_s: int) -> Odpowiedz:
    """Jedno niezalezne wywolanie `claude -p` w pustym katalogu; instrukcja i material na stdin
    (claude.cmd idzie przez cmd.exe, ktore ucina linie polecen na 8191 znakach)."""
    argv = [*komenda_claude(), *FLAGI_MODELU, schemat]
    pusty = tempfile.mkdtemp(prefix="wiedza-przeglad-")
    start = time.monotonic()
    try:
        try:
            r = subprocess.run(argv, input=f"{instrukcja}{material}", capture_output=True, cwd=pusty,
                               text=True, encoding="utf-8", errors="replace", timeout=limit_s)
        except subprocess.TimeoutExpired as e:
            raise BladModelu(f"przekroczony czas {limit_s} s") from e
        except OSError as e:
            raise BladModelu(f"nie da sie uruchomic {argv[0]}: {e}") from e
    finally:
        shutil.rmtree(pusty, ignore_errors=True)
    sekundy = time.monotonic() - start
    stdout = r.stdout or ""
    if r.returncode != 0:
        raise BladModelu(f"claude zwrocil {r.returncode}: {(r.stderr or stdout).strip()[:300]}")
    try:
        koperta = json.loads(stdout)
    except ValueError as e:
        raise BladModelu(f"odpowiedz to nie JSON: {stdout.strip()[:300]}") from e
    if not isinstance(koperta, dict):
        raise BladModelu(f"odpowiedz to nie obiekt JSON: {stdout.strip()[:300]}")
    if koperta.get("is_error"):
        raise BladModelu(f"claude zglosil blad ({koperta.get('subtype')}): {str(koperta.get('result'))[:300]}")
    dane = koperta.get("structured_output")
    if not isinstance(dane, dict):
        dane = facts._json_in(koperta.get("result") or "") if isinstance(koperta.get("result"), str) else None
    if not isinstance(dane, dict):
        raise BladModelu(f"brak odpowiedzi w ksztalcie schematu: {str(koperta.get('result'))[:300]}")
    usage = koperta.get("usage") if isinstance(koperta.get("usage"), dict) else {}
    try:
        koszt = float(koperta.get("total_cost_usd") or 0)
    except (TypeError, ValueError):
        koszt = 0.0
    return Odpowiedz(dane, {k: int(usage.get(k) or 0) for k in POLA_TOKENOW}, koszt, sekundy,
                     len(json.dumps(dane, ensure_ascii=False)))


# ---------------------------------------------------------------- stan na dysku

def _zapisz_json(sciezka: Path, dane) -> None:
    sciezka.parent.mkdir(parents=True, exist_ok=True)
    tymczasowy = sciezka.with_name(sciezka.name + ".tmp")
    tymczasowy.write_text(json.dumps(dane, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tymczasowy, sciezka)


def _czytaj_json(sciezka: Path):
    try:
        return json.loads(sciezka.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


KOLUMNY_DZIENNIKA = ("kiedy", "etap", "klucz", "opis", "sekundy", "znaki_wyslane", "znaki_odebrane",
                     *POLA_TOKENOW, "tokeny_razem", "koszt_usd", "wynik")


class Stan:
    """Katalog .stan w wynikach: paczki\\<klucz>.json (gotowe), bledy\\<klucz>.json (do ponowienia),
    konsolidacja\\<temat>-<hash>.json, koszt.tsv (kazde wywolanie modelu), odrzucone.jsonl."""

    def __init__(self, wyniki: Path):
        self.wyniki = wyniki
        self.katalog = wyniki / ".stan"
        self._zamek = threading.Lock()

    def plik_paczki(self, klucz: str) -> Path:
        return self.katalog / "paczki" / f"{klucz}.json"

    def plik_bledu(self, klucz: str) -> Path:
        return self.katalog / "bledy" / f"{klucz}.json"

    def plik_konsolidacji(self, temat: str, klucz: str) -> Path:
        return self.katalog / "konsolidacja" / f"{temat}-{klucz}.json"

    def gotowa(self, klucz: str) -> dict | None:
        dane = _czytaj_json(self.plik_paczki(klucz))
        return dane if isinstance(dane, dict) and isinstance(dane.get("ustalenia"), list) else None

    def zapisz_paczke(self, klucz: str, dane: dict) -> None:
        _zapisz_json(self.plik_paczki(klucz), dane)
        self.plik_bledu(klucz).unlink(missing_ok=True)

    def zapisz_blad(self, klucz: str, dane: dict) -> None:
        _zapisz_json(self.plik_bledu(klucz), dane)

    def dziennik(self, wiersz: dict) -> None:
        sciezka = self.katalog / "koszt.tsv"
        with self._zamek:
            sciezka.parent.mkdir(parents=True, exist_ok=True)
            nowy = not sciezka.exists()
            with sciezka.open("a", encoding="utf-8", newline="") as f:
                if nowy:
                    f.write("\t".join(KOLUMNY_DZIENNIKA) + "\n")
                f.write("\t".join(" ".join(str(wiersz.get(k, "")).split()) for k in KOLUMNY_DZIENNIKA) + "\n")

    def odrzucone(self, wpisy: list[dict]) -> None:
        if not wpisy:
            return
        with self._zamek:
            sciezka = self.katalog / "odrzucone.jsonl"
            sciezka.parent.mkdir(parents=True, exist_ok=True)
            with sciezka.open("a", encoding="utf-8") as f:
                for w in wpisy:
                    f.write(json.dumps(w, ensure_ascii=False) + "\n")


@dataclass
class Koszt:
    wywolania: int = 0
    bledy: int = 0
    sekundy: float = 0.0
    usd: float = 0.0
    tokeny: dict = field(default_factory=lambda: {k: 0 for k in POLA_TOKENOW})
    _zamek: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def dodaj(self, odp: Odpowiedz | None, sekundy: float = 0.0) -> None:
        with self._zamek:
            self.wywolania += 1
            if odp is None:
                self.bledy += 1
                self.sekundy += sekundy
                return
            self.sekundy += odp.sekundy
            self.usd += odp.koszt_usd
            for k in POLA_TOKENOW:
                self.tokeny[k] += odp.usage.get(k, 0)

    def razem(self) -> int:
        return sum(self.tokeny.values())


def _wiersz_kosztu(etap: str, klucz: str, opis: str, wyslane: int, odp: Odpowiedz | None,
                   wynik: str, sekundy: float = 0.0) -> dict:
    w = {"kiedy": datetime.now().isoformat(timespec="seconds"), "etap": etap, "klucz": klucz, "opis": opis,
         "znaki_wyslane": wyslane, "wynik": wynik}
    if odp is not None:
        w.update(odp.usage)
        w.update(sekundy=round(odp.sekundy, 1), znaki_odebrane=odp.znaki_odebrane,
                 tokeny_razem=sum(odp.usage.values()), koszt_usd=f"{odp.koszt_usd:.4f}")
    else:
        w["sekundy"] = round(sekundy, 1)
    return w


# ---------------------------------------------------------------- etap 1: paczki

def sprawdz_ustalenia(dane: dict, p: Paczka, tematy: set[str]) -> tuple[list[dict], list[dict]]:
    """(przyjete, odrzucone). Odrzucone maja zamaskowana tresc - nic z sekretem nie zostaje na dysku."""
    przyjete, odrzucone = [], []
    surowe = dane.get("ustalenia")
    if not isinstance(surowe, list):
        raise BladModelu("odpowiedz bez listy 'ustalenia'")
    for s in surowe:
        if not isinstance(s, dict):
            odrzucone.append({"powod": "wpis nie jest obiektem", "tresc": selection.redact_sample(str(s))[:300]})
            continue
        tresc = " ".join(str(s.get("tresc") or "").split())
        powod = ""
        if len(tresc) < facts.MIN_FACT_CHARS:
            powod = "pusta albo za krotka tresc"
        elif s.get("temat") not in tematy:
            powod = f"nieznany temat {s.get('temat')!r}"
        elif s.get("poufnosc") not in POZIOMY:
            powod = f"poziom {s.get('poufnosc')!r}"
        else:
            powod = sekret(tresc)
        if powod:
            odrzucone.append({"powod": powod, "projekt": p.projekt, "chunk_id": s.get("chunk_id"),
                              "tresc": selection.redact_sample(tresc)[:300]})
            continue
        chunk = s.get("chunk_id")
        niepewne, uwaga = bool(s.get("niepewne")), " ".join(str(s.get("powod") or "").split())
        if chunk not in p.daty:
            niepewne = True
            uwaga = (uwaga + "; " if uwaga else "") + f"model podal zrodlo #{chunk} spoza paczki"
            data = str(s.get("data_ustalenia") or "")
            if not _poprawna_data(data):
                data = ts_to_local(p.do)[:10]
            chunk = None
        else:
            data = p.daty[chunk]
        przyjete.append({"tresc": tresc, "temat": s["temat"], "poufnosc": s["poufnosc"],
                         "data_ustalenia": data, "projekt": p.projekt, "chunk_id": chunk,
                         "niepewne": niepewne, "powod": uwaga})
    return przyjete, odrzucone


def _poprawna_data(d: str) -> bool:
    if not _DATA.match(d or ""):
        return False
    try:
        date.fromisoformat(d)
        return True
    except ValueError:
        return False


def przerob_paczke(p: Paczka, instrukcja: str, schemat: str, tematy: set[str], stan: Stan,
                   koszt: Koszt, limit_s: int) -> tuple[bool, str]:
    start = time.monotonic()
    wyslane = len(instrukcja) + len(p.material)
    try:
        odp = zapytaj(instrukcja, p.material, schemat, limit_s)
        przyjete, odrzucone = sprawdz_ustalenia(odp.dane, p, tematy)
    except BladModelu as e:
        sek = time.monotonic() - start
        koszt.dodaj(None, sek)
        stan.zapisz_blad(p.klucz, {"projekt": p.projekt, "chunk_ids": [p.chunk_ids[0], p.chunk_ids[-1]],
                                   "blad": str(e), "kiedy": datetime.now().isoformat(timespec="seconds")})
        stan.dziennik(_wiersz_kosztu("paczka", p.klucz, p.nazwa(), wyslane, None, f"BLAD: {e}", sek))
        return False, str(e)
    koszt.dodaj(odp)
    try:
        tajne = int(odp.dane.get("pominiete_tajne") or 0)
    except (TypeError, ValueError):
        tajne = 0
    stan.odrzucone(odrzucone)
    stan.zapisz_paczke(p.klucz, {
        "klucz": p.klucz, "projekt": p.projekt, "chunk_ids": p.chunk_ids, "od": p.od, "do": p.do,
        "ustalenia": przyjete, "odrzucone": len(odrzucone),
        "powody_odrzucenia": sorted({o["powod"] for o in odrzucone}), "pominiete_tajne": tajne,
        "usage": odp.usage, "koszt_usd": odp.koszt_usd, "sekundy": round(odp.sekundy, 1)})
    stan.dziennik(_wiersz_kosztu("paczka", p.klucz, p.nazwa(), wyslane, odp,
                                 f"ok: {len(przyjete)} ustalen, odrzucone {len(odrzucone)}"))
    return True, f"{len(przyjete)} ustalen, odrzucone {len(odrzucone)}, {sum(odp.usage.values())} tok"


# ---------------------------------------------------------------- etap 2: konsolidacja

@dataclass
class Wpis:
    tresc: str
    poufnosc: str
    data: str
    zrodla: list  # [[projekt, chunk_id], ...]
    niepewne: bool = False
    powod: str = ""


def _ranga(poziom: str) -> int:
    return POZIOMY.index(poziom) if poziom in POZIOMY else len(POZIOMY) - 1


def wczytaj_istniejace(pliki: list[Path]) -> dict[str, list[str]]:
    """Wpisy juz wgrane na serwer, w formacie importu: temat -> lista tresci (do 'nie dubluj')."""
    out: dict[str, list[str]] = {}
    wpis = re.compile(r"^- \[[^\]]*\]\s*(?:\[[a-ząćęłńóśźż]+\]\s*)?(.*)$")
    for sciezka in pliki:
        temat, ostatni = "", None
        for linia in sciezka.read_text(encoding="utf-8-sig").splitlines():
            m = re.match(r"^##\s+temat:\s*(\S+)", linia)
            if m:
                temat, ostatni = m.group(1), None
                continue
            m = re.match(r"^temat:\s*(\S+)", linia)
            if m:
                temat, ostatni = m.group(1), None
                continue
            m = wpis.match(linia)
            if m and temat:
                out.setdefault(temat, []).append(m.group(1).strip())
                ostatni = (temat, len(out[temat]) - 1)
                continue
            if ostatni and linia.startswith("  ") and linia.strip():
                t, i = ostatni
                out[t][i] += " " + linia.strip()
            else:
                ostatni = None
    return out


def _material_konsolidacji(wpisy: list[Wpis], istniejace: list[str]) -> str:
    linie = []
    for i, w in enumerate(wpisy, 1):
        niep = f" [niepewne: {w.powod or 'bez powodu'}]" if w.niepewne else ""
        linie.append(f"E{i} [{w.data}] [{w.poufnosc}]{niep} {w.tresc}")
    if istniejace:
        linie.append("\n--- Już na serwerze (nie powtarzaj) ---")
        linie.extend(f"S{i} {t}" for i, t in enumerate(istniejace, 1))
    return "\n".join(linie)


def wektory(teksty: list[str]):
    """Wektory znaczenia z modelu Lore (lokalny, bez wywolan sieci) - tylko do ukladania wpisow."""
    from lore.db import embed_passages

    return embed_passages(teksty)


def wedlug_podobienstwa(wpisy: list[Wpis]) -> tuple[list[Wpis], str]:
    """Wpisy ulozone lancuchem najblizszych sasiadow: podobne obok siebie, wiec przy podziale na
    czesci duplikaty trafiaja do tej samej czesci. Bez modelu wektorow - po dacie i z uwaga."""
    if len(wpisy) < 3:
        return list(wpisy), ""
    import numpy as np

    try:
        v = np.asarray(wektory([w.tresc for w in wpisy]), dtype=np.float32)
        podobne = v @ v.T
    except Exception as e:  # model Lore niedostepny - dziala dalej, ale glosno (uwaga w pliku tematu)
        return sorted(wpisy, key=lambda w: w.data), f"bez modelu wektorow ({type(e).__name__}: {e}) - czesci po dacie"
    uzyte = np.zeros(len(wpisy), dtype=bool)
    kolejnosc, biezacy = [0], 0
    uzyte[0] = True
    for _ in range(len(wpisy) - 1):
        biezacy = int(np.argmax(np.where(uzyte, -np.inf, podobne[biezacy])))
        uzyte[biezacy] = True
        kolejnosc.append(biezacy)
    return [wpisy[i] for i in kolejnosc], ""


def podziel(wpisy: list[Wpis], budzet: int) -> list[list[Wpis]]:
    czesci, biezaca, dlugosc = [], [], 0
    for w in wpisy:
        d = len(w.tresc) + 40
        if biezaca and dlugosc + d > budzet:
            czesci.append(biezaca)
            biezaca, dlugosc = [], 0
        biezaca.append(w)
        dlugosc += d
    if biezaca:
        czesci.append(biezaca)
    return czesci


def sprawdz_konsolidacje(dane: dict, wejscie: list[Wpis], istniejace: list[str]) -> tuple[list[Wpis], dict]:
    surowe = dane.get("wpisy")
    if not isinstance(surowe, list):
        raise BladModelu("odpowiedz bez listy 'wpisy'")
    licz = {"bez_zrodla": 0, "sekret": 0, "zly_poziom": 0, "jak_na_serwerze": 0, "powtorzone": 0}
    znane = {facts.normalize(t) for t in istniejace}
    out, widziane = [], set()
    for s in surowe:
        if not isinstance(s, dict):
            licz["bez_zrodla"] += 1
            continue
        tresc = " ".join(str(s.get("tresc") or "").split())
        zr = []
        for z in s.get("zrodla") or []:
            m = re.fullmatch(r"E(\d+)", str(z).strip())
            if m and 1 <= int(m.group(1)) <= len(wejscie):
                zr.append(wejscie[int(m.group(1)) - 1])
        if len(tresc) < facts.MIN_FACT_CHARS or not zr:
            licz["bez_zrodla"] += 1
            continue
        if sekret(tresc):
            licz["sekret"] += 1
            continue
        if s.get("poufnosc") not in POZIOMY:
            licz["zly_poziom"] += 1
            continue
        if facts.normalize(tresc) in znane:
            licz["jak_na_serwerze"] += 1
            continue
        if facts.normalize(tresc) in widziane:
            licz["powtorzone"] += 1
            continue
        widziane.add(facts.normalize(tresc))
        # przy watpliwosci wyzsza: nigdy nizej niz najwyzszy z laczonych wpisow
        poziom = max([s["poufnosc"], *(w.poufnosc for w in zr)], key=_ranga)
        data = str(s.get("data_ustalenia") or "")
        if not _poprawna_data(data):
            data = max(w.data for w in zr)
        zrodla = []
        for w in zr:
            for z in w.zrodla:
                if z not in zrodla:
                    zrodla.append(z)
        niepewne = bool(s.get("niepewne")) or all(w.niepewne for w in zr)
        powod = " ".join(str(s.get("powod") or "").split())
        if niepewne and not powod:
            powod = "; ".join(sorted({w.powod for w in zr if w.powod})) or "oznaczone przez model jako niepewne"
        out.append(Wpis(tresc, poziom, data, zrodla, niepewne, powod if niepewne else ""))
    return out, licz


@dataclass
class WynikTematu:
    temat: str
    wejscie: int = 0
    wpisy: list = field(default_factory=list)
    rundy: int = 0
    wywolania: int = 0
    licz: dict = field(default_factory=dict)
    blad: str = ""
    uwaga: str = ""


def konsoliduj_temat(temat: dict, wpisy: list[Wpis], istniejace: list[str], stan: Stan, koszt: Koszt,
                     zasady: str, limit_s: int, wykonawca: cf.Executor) -> WynikTematu:
    wynik = WynikTematu(temat["id"], wejscie=len(wpisy))
    nota = ISTNIEJACE_NOTA if istniejace else ""
    instrukcja = (PROMPT_KONSOLIDACJI.format(nazwa=temat.get("nazwa", temat["id"]), opis=temat.get("opis", ""),
                                             istniejace=nota)
                  + f"\n\n## Reguły poufności ustalone z właścicielem\n{zasady}\n\n## Materiał\n")
    budzet = max(10_000, MAX_KONSOLIDACJA - sum(len(t) + 8 for t in istniejace))
    biezace = sorted(wpisy, key=lambda w: w.data)
    poprzednio = sum(len(w.tresc) for w in biezace)
    uwagi = []
    while True:
        wynik.rundy += 1
        czesci = podziel(biezace, budzet)
        if len(czesci) > 1:  # podobne do jednej czesci, w czesci od najstarszego (najnowsze wygrywa)
            ulozone, uwaga = wedlug_podobienstwa(biezace)
            if uwaga and uwaga not in uwagi:
                uwagi.append(uwaga)
            czesci = [sorted(c, key=lambda w: w.data) for c in podziel(ulozone, budzet)]
        zadania = [wykonawca.submit(_konsoliduj_czesc, temat["id"], c, istniejace, instrukcja, stan, koszt,
                                    limit_s, f"{temat['id']} runda {wynik.rundy} czesc {i}/{len(czesci)}")
                   for i, c in enumerate(czesci, 1)]
        nowe: list[Wpis] = []
        for z in zadania:
            try:
                wpisy_czesci, licz, wywolane = z.result()
            except BladModelu as e:
                wynik.blad = str(e)
                return wynik
            wynik.wywolania += wywolane
            for k, v in licz.items():
                wynik.licz[k] = wynik.licz.get(k, 0) + v
            nowe.extend(wpisy_czesci)
        biezace = sorted(nowe, key=lambda w: w.data) if len(czesci) > 1 else nowe
        if len(czesci) == 1:
            break
        teraz = sum(len(w.tresc) for w in biezace)
        if teraz >= 0.9 * poprzednio or wynik.rundy >= MAX_RUND:
            uwagi.append(f"temat za duzy na jedna konsolidacje ({len(czesci)} czesci po rundzie {wynik.rundy})"
                         f" - mozliwe duplikaty miedzy czesciami")
            break
        poprzednio = teraz
    wynik.uwaga = "; ".join(uwagi)
    wynik.wpisy = biezace
    return wynik


def _konsoliduj_czesc(temat: str, czesc: list[Wpis], istniejace: list[str], instrukcja: str, stan: Stan,
                      koszt: Koszt, limit_s: int, opis: str) -> tuple[list[Wpis], dict, int]:
    material = _material_konsolidacji(czesc, istniejace)
    klucz = hashlib.sha1(f"{WERSJA}\n{temat}\n{instrukcja}\n{material}".encode("utf-8")).hexdigest()[:16]
    sciezka = stan.plik_konsolidacji(temat, klucz)
    zapisane = _czytaj_json(sciezka)
    if isinstance(zapisane, dict) and isinstance(zapisane.get("dane"), dict):
        wpisy, licz = sprawdz_konsolidacje(zapisane["dane"], czesc, istniejace)
        return wpisy, licz, 0
    start = time.monotonic()
    try:
        odp = zapytaj(instrukcja, material, SCHEMAT_KONSOLIDACJI, limit_s)
        wpisy, licz = sprawdz_konsolidacje(odp.dane, czesc, istniejace)
    except BladModelu as e:
        sek = time.monotonic() - start
        koszt.dodaj(None, sek)
        stan.dziennik(_wiersz_kosztu("konsolidacja", klucz, opis, len(instrukcja) + len(material), None,
                                     f"BLAD: {e}", sek))
        raise
    koszt.dodaj(odp)
    _zapisz_json(sciezka, {"temat": temat, "opis": opis, "dane": odp.dane, "usage": odp.usage,
                           "koszt_usd": odp.koszt_usd})
    stan.dziennik(_wiersz_kosztu("konsolidacja", klucz, opis, len(instrukcja) + len(material), odp,
                                 f"ok: {len(czesc)} -> {len(wpisy)}"))
    return wpisy, licz, 1


# ---------------------------------------------------------------- pliki wynikowe

def plik_tematu(temat: dict, wynik: WynikTematu, zakres: str, dziury: int, dzis: str) -> str:
    pewne = [w for w in wynik.wpisy if not w.niepewne]
    niepewne = [w for w in wynik.wpisy if w.niepewne]
    linie = []
    if dziury:
        linie.append(f"# UWAGA: NIEPELNE - {dziury} paczek historii nie zostalo przerobionych; ten plik moze "
                     f"nie miec wszystkich ustalen. Nie zatwierdzaj przed ponowieniem przebiegu.")
    if wynik.uwaga:
        linie.append(f"# UWAGA: {wynik.uwaga}")
    linie += [
        f"# Wiedza firmy z rozmów Primo - temat: {temat.get('nazwa', temat['id'])} ({temat['id']})",
        f"# Do zatwierdzenia. Do wgrania: {len(pewne)}; do decyzji: {len(niepewne)} (na końcu, "
        f"zakomentowane). Zakres: {zakres}. Przegląd {dzis}.",
        "autor: Primo",
        "program: claude-code",
        f"zrodlo: przeglad historii rozmow Primo (Lore) {dzis}",
        "poufnosc: wewnetrzne",
        "",
        f"## temat: {temat['id']}",
    ]
    linie += [f"- [{w.data}] [{w.poufnosc}] {w.tresc}" for w in pewne]
    linie += ["", "# === Do decyzji Primo ===",
              "# Wpisy niepewne. NIE zostaną wgrane, dopóki nie usuniesz \"# \" z początku linii z wpisem",
              "# (linię z powodem zostaw albo usuń w całości)."]
    if not niepewne:
        linie.append("# (brak)")
    for w in niepewne:
        linie.append(f"#   powód: {w.powod}")
        linie.append(f"# - [{w.data}] [{w.poufnosc}] {w.tresc}")
    return "\n".join(linie) + "\n"


def plik_zrodel(wynik: WynikTematu) -> str:
    linie = ["data\tpoufnosc\tniepewne\tzrodla\ttresc"]
    for w in wynik.wpisy:
        zr = ", ".join(f"{p} #{c}" if c is not None else f"{p} #?" for p, c in w.zrodla)
        linie.append(f"{w.data}\t{w.poufnosc}\t{'tak' if w.niepewne else ''}\t{zr}\t{w.tresc}")
    return "\n".join(linie) + "\n"


def sprawdz_format(pliki: list[Path], tematy_json: Path) -> list[str]:
    """Kazdy plik przez prawdziwy import serwera na sucho, z tematami wczytanymi do pustego
    katalogu danych. Zwraca liste problemow (pusta = wszystko przeszlo)."""
    if not pliki:
        return []
    uv = shutil.which("uv")
    if not uv:
        return ["nie ma `uv` w PATH - format plikow NIE zostal sprawdzony"]
    problemy = []
    with tempfile.TemporaryDirectory(prefix="wiedza-przeglad-format-") as tmp:
        env = {**os.environ, "APPDATA": tmp}
        for zmienna in ("WIEDZA_FIRMY_HOME", "VIRTUAL_ENV"):  # uv ma wziac srodowisko wiedza_firmy
            env.pop(zmienna, None)
        baza = [uv, "--directory", str(WIEDZA_FIRMY), "run", "python", "-m"]
        r = subprocess.run([*baza, "wiedza_firmy.tematy", "wczytaj", str(tematy_json)], env=env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0:
            return [f"wczytanie tematow do serwera-atrapy nie przeszlo: {(r.stderr or r.stdout).strip()[:300]}"]
        for plik in pliki:
            r = subprocess.run([*baza, "wiedza_firmy.importuj", str(plik), "--na-sucho", "--bez-modelu"],
                               env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if r.returncode != 0 or "na sucho:" not in (r.stdout or ""):
                problemy.append(f"{plik.name}: {(r.stderr or r.stdout).strip()[:300]}")
    return problemy


# ---------------------------------------------------------------- przebieg

def _tys(n: float) -> str:
    return f"{n:,.0f}".replace(",", " ")


def raport_na_sucho(pacz: list[Paczka], st: Statystyka, instrukcja: str, stan: Stan) -> str:
    po_proj: dict[str, list[Paczka]] = {}
    for p in pacz:
        po_proj.setdefault(p.projekt, []).append(p)
    znaki_mat = sum(len(p.material) for p in pacz)
    znaki_wys = znaki_mat + len(instrukcja) * len(pacz)
    gotowe = sum(1 for p in pacz if stan.gotowa(p.klucz))
    linie = ["NA SUCHO - bez wywolan modelu", "",
             f"{'projekt':<70} {'paczek':>6} {'znaki':>11}"]
    for proj, ps in sorted(po_proj.items(), key=lambda kv: -sum(len(p.material) for p in kv[1])):
        linie.append(f"{proj[:70]:<70} {len(ps):>6} {_tys(sum(len(p.material) for p in ps)):>11}")
    linie += [
        "",
        f"wiadomosci: {_tys(st.wiadomosci)} (z {_tys(st.wiersze)} chunkow); duplikaty (ta sama chwila i tresc, np. kopia Orca) pominiete: "
        f"{_tys(st.duplikaty)}; automatyczne/komunikaty pominiete: {_tys(st.automatyczne)}; tury tool/result "
        f"w sklejonych chunkach pominiete: {_tys(st.pominiete_tury)}",
        f"za dlugie wiadomosci skrocone: {_tys(st.skrocone)} (wyciete {_tys(st.wyciete_znaki)} znakow ze srodka)",
        f"pominiete role (chunki): " + ", ".join(f"{r} {_tys(n)}" for r, n in sorted(st.pominiete_role.items())),
        f"pominiete projekty-smieci: {len(st.pominiete_projekty)} ({_tys(sum(st.pominiete_projekty.values()))} chunkow)",
        "",
        f"PACZKI: {len(pacz)} (juz przerobione: {gotowe}, do zrobienia: {len(pacz) - gotowe})",
        f"znaki materialu: {_tys(znaki_mat)}; z instrukcja ({_tys(len(instrukcja))} zn. na paczke): {_tys(znaki_wys)}",
        f"szacunek tokenow wejscia (znaki / {facts.CHARS_PER_TOKEN}): {_tys(math.ceil(znaki_wys / facts.CHARS_PER_TOKEN))}"
        " - bez wyjscia modelu, bez narzutu claude -p i bez konsolidacji",
    ]
    pomiar = pomiar_paczek(stan)
    if pomiar:
        zostalo = sum(len(p.material) + len(instrukcja) for p in pacz if not stan.gotowa(p.klucz))
        tok, usd, n = pomiar
        linie.append(f"wedlug pomiaru z {n} przerobionych paczek ({tok:.2f} tokenu i ${usd * 1e6:.2f} na milion znakow"
                     f" wyslanych, z wyjsciem i narzutem claude -p): pozostale paczki ok. {_tys(zostalo * tok)} tokenow,"
                     f" ok. ${zostalo * usd:.0f} wg claude; konsolidacja dochodzi osobno")
    else:
        linie.append("pomiaru jeszcze nie ma - prawdziwe liczby da proba (koszt.tsv)")
    return "\n".join(linie)


def sumy_dziennika(stan: Stan) -> dict[str, tuple[int, float, float, float]]:
    """etap -> (udane wywolania, tokeny, USD, sekundy) z calego koszt.tsv."""
    try:
        wiersze = (stan.katalog / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    except OSError:
        return {}
    if not wiersze:
        return {}
    kol, out = wiersze[0].split("\t"), {}
    for w in wiersze[1:]:
        d = dict(zip(kol, w.split("\t")))
        if not d.get("wynik", "").startswith("ok"):
            continue
        try:
            n, tok, usd, sek = out.get(d["etap"], (0, 0.0, 0.0, 0.0))
            out[d["etap"]] = (n + 1, tok + float(d["tokeny_razem"]), usd + float(d["koszt_usd"]),
                              sek + float(d["sekundy"]))
        except (KeyError, ValueError):
            continue
    return out


def pomiar_paczek(stan: Stan) -> tuple[float, float, int] | None:
    """(tokeny na znak wyslany, USD na znak, ile paczek) z udanych paczek w koszt.tsv; None bez danych."""
    try:
        wiersze = (stan.katalog / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    if not wiersze:
        return None
    kol = wiersze[0].split("\t")
    znaki = tokeny = usd = 0.0
    n = 0
    for w in wiersze[1:]:
        d = dict(zip(kol, w.split("\t")))
        if d.get("etap") != "paczka" or not d.get("wynik", "").startswith("ok"):
            continue
        try:
            znaki += float(d["znaki_wyslane"])
            tokeny += float(d["tokeny_razem"])
            usd += float(d["koszt_usd"])
            n += 1
        except (KeyError, ValueError):
            continue
    return (tokeny / znaki, usd / znaki, n) if n and znaki else None


def zbierz_ustalenia(pacz: list[Paczka], stan: Stan) -> tuple[dict[str, list[Wpis]], dict]:
    po_temacie: dict[str, list[Wpis]] = {}
    sumy = {"ustalenia": 0, "odrzucone": 0, "pominiete_tajne": 0, "niepewne": 0}
    for p in pacz:
        d = stan.gotowa(p.klucz)
        if not d:
            continue
        sumy["odrzucone"] += int(d.get("odrzucone") or 0)
        sumy["pominiete_tajne"] += int(d.get("pominiete_tajne") or 0)
        for u in d["ustalenia"]:
            sumy["ustalenia"] += 1
            sumy["niepewne"] += bool(u.get("niepewne"))
            po_temacie.setdefault(u["temat"], []).append(Wpis(
                u["tresc"], u["poufnosc"], u["data_ustalenia"], [[u.get("projekt"), u.get("chunk_id")]],
                bool(u.get("niepewne")), u.get("powod") or ""))
    return po_temacie, sumy


def main(argv: list[str] | None = None) -> int:
    for strumien in (sys.stdout, sys.stderr):
        try:
            strumien.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    a = argparse.ArgumentParser(prog="przeglad.py", description=__doc__.splitlines()[0])
    a.add_argument("--na-sucho", action="store_true", help="tylko policz paczki, znaki i tokeny")
    a.add_argument("--proba", default="", help="tylko te projekty (nazwy z Lore, po przecinku)")
    a.add_argument("--rownolegle", type=int, default=ROWNOLEGLE)
    a.add_argument("--limit-paczek", type=int, default=0, help="przerob najwyzej N brakujacych paczek")
    a.add_argument("--mimo-dziur", action="store_true", help="konsoliduj mimo nieudanych paczek (pliki z ostrzezeniem)")
    a.add_argument("--bez-sprawdzenia-formatu", action="store_true")
    a.add_argument("--baza", type=Path, default=DB_PATH)
    a.add_argument("--wyniki", type=Path, default=WYNIKI)
    a.add_argument("--tematy", type=Path, default=TEMATY)
    a.add_argument("--zasady", type=Path, default=ZASADY)
    a.add_argument("--istniejace", type=Path, nargs="*", default=list(ISTNIEJACE))
    a.add_argument("--limit-czasu", type=int, default=LIMIT_CZASU_PACZKA_S)
    o = a.parse_args(argv)
    if o.rownolegle < 1:
        print("ODMOWA: --rownolegle musi byc >= 1", file=sys.stderr)
        return 2

    start = time.monotonic()
    try:
        tematy = wczytaj_tematy(o.tematy)
        zasady = wyciag_zasad(o.zasady)
        istniejace = wczytaj_istniejace(o.istniejace)
        conn = polacz_baze(o.baza)
    except (OSError, ValueError) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 2
    projekty = [p.strip() for p in o.proba.split(",") if p.strip()] or None
    with conn:
        wiadomosci, st = wczytaj(conn, projekty)
    conn.close()
    if projekty:
        znalezione = {w.projekt.casefold() for w in wiadomosci}
        brak = [p for p in projekty if p.casefold() not in znalezione]
        if brak:
            print(f"ODMOWA: w Lore nie ma wypowiedzi z projektow: {', '.join(brak)}", file=sys.stderr)
            return 2
    pacz = paczki(wiadomosci)
    instrukcja = instrukcja_paczki(tematy, zasady)
    schemat = schemat_paczki(tematy)
    stan = Stan(o.wyniki)
    if o.na_sucho:
        print(raport_na_sucho(pacz, st, instrukcja, stan))
        return 0

    ids_tematow = {t["id"] for t in tematy}
    koszt = Koszt()
    brakujace = [p for p in pacz if not stan.gotowa(p.klucz)]
    if o.limit_paczek:
        brakujace = brakujace[:o.limit_paczek]
    print(f"paczek: {len(pacz)}, gotowych z poprzednich przebiegow: {len(pacz) - len([p for p in pacz if not stan.gotowa(p.klucz)])}, "
          f"teraz do zrobienia: {len(brakujace)} ({o.rownolegle} naraz)", file=sys.stderr)
    nieudane: list[tuple[Paczka, str]] = []
    przerwano = False
    wykonawca = cf.ThreadPoolExecutor(max_workers=o.rownolegle)
    try:
        przyszle = {wykonawca.submit(przerob_paczke, p, instrukcja, schemat, ids_tematow, stan, koszt,
                                     o.limit_czasu): p for p in brakujace}
        for n, f in enumerate(cf.as_completed(przyszle), 1):
            p = przyszle[f]
            try:
                ok, opis = f.result()
            except Exception as e:  # nieprzewidziany blad - tez widoczny i do ponowienia
                ok, opis = False, f"{type(e).__name__}: {e}"
                stan.zapisz_blad(p.klucz, {"projekt": p.projekt, "chunk_ids": [p.chunk_ids[0], p.chunk_ids[-1]],
                                           "blad": opis, "kiedy": datetime.now().isoformat(timespec="seconds")})
            if not ok:
                nieudane.append((p, opis))
            print(f"[{n}/{len(brakujace)}] {'ok  ' if ok else 'BLAD'} {p.nazwa()}: {opis}", file=sys.stderr)
    except KeyboardInterrupt:
        przerwano = True
        print("PRZERWANO - zrobione paczki sa zapisane, kolejny przebieg ich nie powtorzy", file=sys.stderr)
        wykonawca.shutdown(wait=False, cancel_futures=True)
    else:
        wykonawca.shutdown(wait=True)

    niegotowe = [p for p in pacz if not stan.gotowa(p.klucz)]
    po_temacie, sumy = zbierz_ustalenia(pacz, stan)
    wyniki_tematow: list[WynikTematu] = []
    problemy_formatu: list[str] = []
    zapisane: list[Path] = []
    dzis = date.today().isoformat()
    zakres = f"projekty {', '.join(projekty)}" if projekty else "cała historia"
    konsoliduj = not przerwano and (not niegotowe or o.mimo_dziur)
    if konsoliduj:
        o.wyniki.mkdir(parents=True, exist_ok=True)
        tematy_po_id = {t["id"]: t for t in tematy}
        with cf.ThreadPoolExecutor(max_workers=o.rownolegle) as wewn, \
                cf.ThreadPoolExecutor(max_workers=max(1, len(po_temacie))) as zewn:
            zadania = {zewn.submit(konsoliduj_temat, tematy_po_id[t], w, istniejace.get(t, []), stan, koszt,
                                   zasady, LIMIT_CZASU_KONSOLIDACJA_S, wewn): t
                       for t, w in sorted(po_temacie.items())}
            for f in cf.as_completed(zadania):
                wyniki_tematow.append(f.result())
        napisane = set()
        for w in sorted(wyniki_tematow, key=lambda w: w.temat):
            plik = o.wyniki / f"{w.temat}.md"
            if w.blad:
                print(f"BLAD konsolidacji tematu {w.temat}: {w.blad}", file=sys.stderr)
                continue
            if not w.wpisy:  # pusty plik tematu do zatwierdzania to szum - temat jest w podsumowaniu
                continue
            plik.write_text(plik_tematu(tematy_po_id[w.temat], w, zakres, len(niegotowe), dzis), encoding="utf-8")
            (o.wyniki / "zrodla").mkdir(exist_ok=True)
            (o.wyniki / "zrodla" / f"{w.temat}.tsv").write_text(plik_zrodel(w), encoding="utf-8")
            napisane.add(w.temat)
            if any(not x.niepewne for x in w.wpisy):
                zapisane.append(plik)
        # pliki tematow z poprzedniego przebiegu (inna proba, nieudana konsolidacja, temat juz pusty)
        # nie moga udawac aktualnych - w katalogu zostaje dokladnie wynik tego przebiegu
        for tid in tematy_po_id:
            if tid not in napisane:
                (o.wyniki / f"{tid}.md").unlink(missing_ok=True)
                (o.wyniki / "zrodla" / f"{tid}.tsv").unlink(missing_ok=True)
        if not o.bez_sprawdzenia_formatu:
            problemy_formatu = sprawdz_format(zapisane, o.tematy)

    sekundy = time.monotonic() - start
    podsumowanie = podsumuj(pacz, nieudane, niegotowe, sumy, wyniki_tematow, problemy_formatu, koszt, sekundy,
                            zakres, konsoliduj, przerwano, stan, o.bez_sprawdzenia_formatu)
    o.wyniki.mkdir(parents=True, exist_ok=True)
    (o.wyniki / "PODSUMOWANIE.txt").write_text(podsumowanie, encoding="utf-8")
    print(podsumowanie)
    dziury = bool(niegotowe) or przerwano or any(w.blad for w in wyniki_tematow) or bool(problemy_formatu)
    return 1 if dziury else 0


def podsumuj(pacz, nieudane, niegotowe, sumy, wyniki_tematow, problemy_formatu, koszt: Koszt, sekundy,
             zakres, konsoliduj, przerwano, stan: Stan, bez_formatu) -> str:
    linie = []
    bledy_tematow = [w for w in wyniki_tematow if w.blad]
    if niegotowe or przerwano or bledy_tematow or problemy_formatu:
        linie.append("NIEPELNE - przebieg ma dziury, NIE zglaszac jako gotowe:")
        if przerwano:
            linie.append("  - przebieg przerwany")
        if niegotowe:
            linie.append(f"  - {len(niegotowe)} z {len(pacz)} paczek nieprzerobionych (ponow ten sam przebieg;"
                         f" bledy w {stan.katalog / 'bledy'})")
            for p in niegotowe[:20]:
                blad = _czytaj_json(stan.plik_bledu(p.klucz)) or {}
                linie.append(f"      {p.nazwa()}: {blad.get('blad', 'jeszcze nie probowana')}")
            if not konsoliduj:
                linie.append("  - konsolidacja wstrzymana (--mimo-dziur, zeby ja wymusic)")
        for w in bledy_tematow:
            linie.append(f"  - konsolidacja tematu {w.temat} nieudana: {w.blad}")
        for pr in problemy_formatu:
            linie.append(f"  - format: {pr}")
        linie.append("")
    else:
        linie.append("KOMPLET - wszystkie paczki przerobione, wszystkie tematy skonsolidowane")
        linie.append("")
    linie += [
        f"Zakres: {zakres}. Paczek: {len(pacz)}, nieudane w tym przebiegu: {len(nieudane)}.",
        f"Ustalenia z paczek: {sumy['ustalenia']} (w tym niepewne {sumy['niepewne']}); odrzucone przy sprawdzaniu: "
        f"{sumy['odrzucone']} (powody w .stan\\odrzucone.jsonl); tajne pominiete przez model: {sumy['pominiete_tajne']}.",
    ]
    if wyniki_tematow:
        linie += ["", f"{'temat':<18} {'wejscie':>7} {'do wgrania':>10} {'do decyzji':>10} {'rundy':>5}  uwagi"]
        for w in sorted(wyniki_tematow, key=lambda w: w.temat):
            pewne = sum(1 for x in w.wpisy if not x.niepewne)
            uw = w.blad and f"BLAD: {w.blad}" or w.uwaga
            odrz = ", ".join(f"{k} {v}" for k, v in w.licz.items() if v)
            linie.append(f"{w.temat:<18} {w.wejscie:>7} {pewne:>10} {len(w.wpisy) - pewne:>10} {w.rundy:>5}  "
                         f"{uw}{'; odrzucone: ' + odrz if odrz else ''}")
        poziomy = {}
        for w in wyniki_tematow:
            for x in w.wpisy:
                poziomy[x.poufnosc] = poziomy.get(x.poufnosc, 0) + 1
        linie.append("poziomy: " + ", ".join(f"{k} {poziomy.get(k, 0)}" for k in POZIOMY))
    if konsoliduj and not bez_formatu:
        linie.append("format importu (wiedza_firmy.importuj --na-sucho): "
                     + ("OK dla wszystkich plikow z wpisami" if not problemy_formatu else "PROBLEMY - wyzej"))
    t = koszt.tokeny
    linie += [
        "",
        f"Ten przebieg: wywolan modelu {koszt.wywolania} (nieudanych {koszt.bledy}), czas calkowity {sekundy:.0f} s,"
        f" suma czasow wywolan {koszt.sekundy:.0f} s.",
        f"Tokeny (zmierzone, z koperty claude -p): wejscie {_tys(t['input_tokens'])}, zapis cache "
        f"{_tys(t['cache_creation_input_tokens'])}, odczyt cache {_tys(t['cache_read_input_tokens'])}, "
        f"wyjscie {_tys(t['output_tokens'])}; razem {_tys(koszt.razem())}. Koszt wg claude: ${koszt.usd:.2f}.",
        f"Kazde wywolanie: {stan.katalog / 'koszt.tsv'}",
    ]
    for etap, (n, tok, usd, sek) in sorted(sumy_dziennika(stan).items()):
        linie.append(f"Lacznie w dzienniku (wszystkie przebiegi), {etap}: udanych wywolan {n}, tokenow {_tys(tok)},"
                     f" ${usd:.2f} wg claude, suma czasow wywolan {sek:.0f} s.")
    return "\n".join(linie) + "\n"


if __name__ == "__main__":
    sys.exit(main())
