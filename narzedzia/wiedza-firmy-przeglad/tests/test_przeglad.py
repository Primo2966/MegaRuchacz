"""Testy przegladu historii -> Wiedza firmy. Model to atrapa (atrapa_claude.py), dane wymyslone.

    uv --directory C:\\dev\\claude-worker\\lore run pytest C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-przeglad\\tests -q
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

TU = Path(__file__).resolve().parent
REPO = TU.parents[2]
sys.path.insert(0, str(TU.parent))
sys.path.insert(0, str(REPO / "wiedza_firmy"))

import przeglad as P  # noqa: E402
from wiedza_firmy.importuj import parsuj  # noqa: E402

TEMATY = [
    {"id": "temat-a", "nazwa": "Temat A", "opis": "atrapa A", "przyklady": ["przyklad A"], "osobne_uprawnienie": False},
    {"id": "temat-b", "nazwa": "Temat B", "opis": "atrapa B", "przyklady": ["przyklad B"], "osobne_uprawnienie": True},
]
ZASADY = "# Reguly (atrapa)\n\nDecyzje na gorze.\n\n## 1. Tematy\n- a\n\n## 2. Reguly\n- wyzszy\n\n## 3. Zestaw\nNIE_W_PROMPCIE\n"


def _chunk(conn, cid, projekt, sesja, linia, ts, rola, tekst, czesc=0):
    conn.execute("INSERT INTO chunks (id, project, session, file, line, part, ts, role, text, indexed_at)"
                 " VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (cid, projekt, sesja, f"{projekt}/{sesja}.jsonl", linia, czesc, ts, rola, tekst, ts))


def zbuduj_baze(sciezka: Path, wiersze: list[tuple]) -> Path:
    conn = sqlite3.connect(sciezka)
    conn.execute("CREATE TABLE chunks (id INTEGER PRIMARY KEY, project TEXT NOT NULL, session TEXT NOT NULL,"
                 " file TEXT NOT NULL, line INTEGER NOT NULL, part INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL,"
                 " role TEXT NOT NULL, text TEXT NOT NULL, indexed_at TEXT NOT NULL DEFAULT '')")
    for w in wiersze:
        _chunk(conn, *w)
    conn.commit()
    conn.close()
    return sciezka


def wiersze_podstawowe() -> list[tuple]:
    return [
        (1, "C--dev-alfa", "s1", 1, "2026-09-01T08:00:00.000Z", "user", "USTALENIE: Etykiety drukujemy w skali 180 procent. TEMAT=temat-a POZIOM=jawne"),
        (2, "C--dev-alfa", "s1", 2, "2026-09-01T08:01:00.000Z", "assistant", "Przyjąłem."),
        (3, "C--dev-alfa", "s1", 3, "2026-09-01T08:02:00.000Z", "tool", "USTALENIE: z narzedzia - nie wolno"),
        (4, "C--dev-alfa", "s1", 4, "2026-09-01T08:03:00.000Z", "result", "USTALENIE: z wyniku - nie wolno"),
        (5, "C--dev-alfa", "s1", 5, "2026-09-01T08:04:00.000Z", "conversation",
         "user: USTALENIE: Paczki FBA nazywamy numerem i dopiskiem FBA. TEMAT=temat-b\n\n"
         "tool: USTALENIE: tura narzedzia - nie wolno\n\nassistant: Dobrze."),
        (6, "C--dev-alfa", "s1", 6, "2026-09-01T08:05:00.000Z", "agent:user", "USTALENIE: brief kierownika - nie wolno"),
        (7, "C--Users-X-AppData-Local-Temp-e2e-cos", "s9", 1, "2026-09-01T08:06:00.000Z", "user", "USTALENIE: smiec tymczasowy - nie wolno"),
        (8, "orca", "s1o", 1, "2026-09-01T08:00:00.000Z", "user", "USTALENIE: Etykiety drukujemy w skali 180 procent. TEMAT=temat-a POZIOM=jawne"),
        (9, "C--dev-alfa", "s2", 1, "2026-09-02T09:00:00.000Z", "user", "<scheduled-task name=x> USTALENIE: automat - nie wolno"),
        (10, "C--dev-beta", "s3", 1, "2026-09-03T10:00:00.000Z", "user", "USTALENIE: Etykiety drukujemy w skali 180 procent. TEMAT=temat-a POZIOM=jawne"),
        (11, "C--dev-beta", "s3", 2, "2026-09-03T10:01:00.000Z", "user", "USTALENIE: Klientom nic nie wysyłamy bez zatwierdzenia Gosi. NIEPEWNE"),
    ]


@pytest.fixture
def srodowisko(tmp_path, monkeypatch):
    baza = zbuduj_baze(tmp_path / "lore.db", wiersze_podstawowe())
    tematy = tmp_path / "tematy.json"
    tematy.write_text(json.dumps(TEMATY), encoding="utf-8")
    zasady = tmp_path / "zasady.md"
    zasady.write_text(ZASADY, encoding="utf-8")
    log = tmp_path / "wywolania"
    monkeypatch.setenv("WIEDZA_PRZEGLAD_CLAUDE", json.dumps([sys.executable, str(TU / "atrapa_claude.py")]))
    monkeypatch.setenv("ATRAPA_LOG", str(log))
    for zmienna in ("ATRAPA_PADA_NA", "ATRAPA_POZIOM_KONS", "ATRAPA_SMIECI"):
        monkeypatch.delenv(zmienna, raising=False)
    wyniki = tmp_path / "wyniki"

    class S:
        pass
    s = S()
    s.baza, s.tematy, s.zasady, s.log, s.wyniki, s.tmp = baza, tematy, zasady, log, wyniki, tmp_path
    s.argi = ["--baza", str(baza), "--wyniki", str(wyniki), "--tematy", str(tematy), "--zasady", str(zasady),
              "--bez-sprawdzenia-formatu", "--rownolegle", "2"]
    s.wywolania = lambda: sorted(f.suffix[1:] for f in log.iterdir()) if log.exists() else []
    return s


# ---------------------------------------------------------------- material

def test_pomija_role_projekty_automaty_i_duplikaty(srodowisko):
    w, st = P.wczytaj(P.polacz_baze(srodowisko.baza))
    teksty = " | ".join(x.tekst for x in w)
    assert "nie wolno" not in teksty
    assert {x.projekt for x in w} == {"C--dev-alfa", "C--dev-beta"}  # orca (kopia) i smiec odpadly
    assert st.pominiete_role == {"tool": 1, "result": 1, "agent:user": 1}
    assert st.pominiete_projekty == {"C--Users-X-AppData-Local-Temp-e2e-cos": 1}
    assert st.duplikaty == 1 and st.automatyczne == 1 and st.pominiete_tury == 1
    assert "Paczki FBA" in teksty  # tura user ze sklejonego chunku "conversation" zostala


def test_wzorce_smieci():
    for p in ("C--Users-Primo-AppData-Local-Temp-claude-x-scratchpad-y", "C--dev-claude-worker--claude-worktrees-agent-1",
              "C--Users-Primo-AppData-Roaming-Claude-scratch-workspaces-1", "c--users-x-appdata-local-temp-e2e-tlo"):
        assert P.smiec(p), p
    for p in ("C--dev-fba-planner", "orca", "c--dev-claude-worker"):
        assert not P.smiec(p), p


def test_wybor_projektow_proby(srodowisko):
    w, _ = P.wczytaj(P.polacz_baze(srodowisko.baza), ["c--dev-BETA"])
    assert {x.projekt for x in w} == {"C--dev-beta"}


def test_dlugie_czesci_sklejone_a_za_dlugie_skrocone_glosno(tmp_path):
    dlugi = "x" * 1500
    druga = dlugi[-P.OVERLAP:] + "y" * 9000
    baza = zbuduj_baze(tmp_path / "l.db", [
        (1, "C--dev-x", "s", 1, "2026-09-01T08:00:00.000Z", "assistant", dlugi, 0),
        (2, "C--dev-x", "s", 1, "2026-09-01T08:00:00.000Z", "assistant", druga, 1),
        (3, "C--dev-x", "s", 2, "2026-09-01T08:01:00.000Z", "user", "<scheduled-task> " + "C" * 1500, 0),
        (4, "C--dev-x", "s", 2, "2026-09-01T08:01:00.000Z", "user", "C" * 200 + "dalsza czesc automatu", 1),
    ])
    w, st = P.wczytaj(P.polacz_baze(baza))
    assert len(w) == 1  # dalsza czesc odrzuconego automatu nie wraca jako osobna wypowiedz
    assert w[0].tekst.startswith("x" * 1500 + "y") and w[0].tekst.endswith("y" * 100)
    assert "wycięto 5000 znaków" in w[0].tekst  # 1500 + 9000 sklejone, minus glowa 4000 i ogon 1500
    assert st.skrocone == 1


def test_paczki_w_obrebie_projektu_chronologicznie_i_pod_sufitem(tmp_path):
    wiersze = []
    for i in range(30):
        projekt = "C--dev-a" if i % 2 else "C--dev-b"
        wiersze.append((i + 1, projekt, f"s{i % 4}", i, f"2026-09-{1 + i // 10:02d}T08:{i:02d}:00.000Z", "user",
                        f"wypowiedz {i} " + "x" * 300))
    w, _ = P.wczytaj(P.polacz_baze(zbuduj_baze(tmp_path / "l.db", wiersze)))
    pacz = P.paczki(w, limit=1500)
    assert len(pacz) > 4
    for p in pacz:
        assert len(p.material) <= 1500
        assert all(x.projekt == p.projekt for x in w if x.chunk_id in p.chunk_ids)
    for projekt in ("C--dev-a", "C--dev-b"):
        kolejne = [cid for p in pacz if p.projekt == projekt for cid in p.chunk_ids]
        assert sorted(kolejne) == sorted({x.chunk_id for x in w if x.projekt == projekt})
        assert len(kolejne) == len(set(kolejne))  # nic nie wpada do dwoch paczek
    assert len({p.klucz for p in pacz}) == len(pacz)
    assert [p.klucz for p in P.paczki(w, limit=1500)] == [p.klucz for p in pacz]  # klucze stale


def test_material_maskuje_sekrety(tmp_path):
    baza = zbuduj_baze(tmp_path / "l.db", [
        (1, "C--dev-x", "s", 1, "2026-09-01T08:00:00.000Z", "user", "zapisz klucz sk-ant-abcdefghijklmnop1234 i hasło: Tajne123!x")])
    w, _ = P.wczytaj(P.polacz_baze(baza))
    assert "abcdefghijklmnop1234" not in w[0].tekst and "Tajne123" not in w[0].tekst


# ---------------------------------------------------------------- sekrety (proba negatywna)

@pytest.mark.parametrize("tresc", [
    "Hasło do panelu: Xk9pQ2zzR7.",
    "Token API to ghp_abcdefghijklmnopqrstuvwxyz123456.",
    "Klucz API: 7f3a9c0b1d2e4f5a6b7c8d9e0f1a2b3c.",
    "password=supertajne1",
    "W pliku .env stoi WA_API_KEY=abcdef123456.",
])
def test_sekret_wykryty(tresc):
    assert P.sekret(tresc)


@pytest.mark.parametrize("tresc", [
    "Kluczowe pojęcie tej pracy to zapachy.",
    "Klucz API do JFTools leży w pliku .env, nigdy w repo.",
    "SKU SET3-Health[010407]/ARO/10/FBA ma ASIN B0GNZ18KY9.",
    "Hasła do Wi-Fi są w sejfie w biurze.",
])
def test_zwykla_tresc_nie_jest_sekretem(tresc):
    assert P.sekret(tresc) == ""


def test_wpis_z_haslem_odrzucony_i_widoczny(srodowisko, tmp_path):
    zbuduj_dodatkowe = sqlite3.connect(srodowisko.baza)
    _chunk(zbuduj_dodatkowe, 50, "C--dev-alfa", "s5", 1, "2026-09-05T08:00:00.000Z", "user", "tu wkleilem SEKRET")
    zbuduj_dodatkowe.commit()
    zbuduj_dodatkowe.close()
    assert P.main(srodowisko.argi) == 0
    calosc = "".join(p.read_text(encoding="utf-8") for p in srodowisko.wyniki.rglob("*") if p.is_file())
    assert "Xk9pQ2zzR7" not in calosc  # nigdzie: ani w plikach tematow, ani w stanie, ani w odrzuconych
    odrzucone = (srodowisko.wyniki / ".stan" / "odrzucone.jsonl").read_text(encoding="utf-8")
    assert "haslo" in odrzucone or "sekret" in odrzucone
    assert "odrzucone przy sprawdzaniu: 1" in (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")


def test_konsolidacja_odrzuca_sekret_dopisany_przez_model():
    wej = [P.Wpis("Panel sklepu ma osobne konto dla Gosi.", "wewnetrzne", "2026-09-01", [["p", 1]])]
    wyn, licz = P.sprawdz_konsolidacje({"wpisy": [
        {"tresc": "Panel sklepu: login gosia, hasło: Abc123xyz9.", "poufnosc": "wewnetrzne",
         "data_ustalenia": "2026-09-01", "zrodla": ["E1"], "niepewne": False}]}, wej, [])
    assert wyn == [] and licz["sekret"] == 1


# ---------------------------------------------------------------- przebieg z atrapa

def test_pelny_przebieg_plik_tematu_w_formacie_importu(srodowisko):
    assert P.main(srodowisko.argi) == 0
    plik = srodowisko.wyniki / "temat-a.md"
    tekst = plik.read_text(encoding="utf-8")
    wpisy = parsuj(tekst, plik.name)  # prawdziwy parser serwera
    tresci = [w.tresc for w in wpisy]
    # to samo ustalenie z dwoch projektow -> jeden wpis, data najnowsza
    assert tresci.count("Etykiety drukujemy w skali 180 procent.") == 1
    etyk = next(w for w in wpisy if w.tresc.startswith("Etykiety"))
    assert etyk.data_ustalenia == "2026-09-03" and etyk.poufnosc == "jawne" and etyk.autor == "Primo"
    # 14.10: Primo nie podejmuje decyzji - wpis oznaczony przez model jako niepewny i tak idzie do importu
    assert any("Gosi" in t for t in tresci)
    decyzje = tekst.split("# === Do decyzji Primo ===", 1)[1]
    assert "Gosi" not in decyzje  # nic nie czeka na decyzje Primo
    assert (srodowisko.wyniki / "temat-b.md").exists()
    zrodla = (srodowisko.wyniki / "zrodla" / "temat-a.tsv").read_text(encoding="utf-8")
    assert "C--dev-alfa #1" in zrodla and "C--dev-beta #10" in zrodla
    pods = (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")
    assert pods.startswith("KOMPLET")
    koszt = (srodowisko.wyniki / ".stan" / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    assert koszt[0].startswith("kiedy\tetap") and len(koszt) == 1 + len(srodowisko.wywolania())
    assert "\t180\t0.0125\t" in koszt[1]  # prawdziwe liczby z koperty: 100 + 10 + 50 + 20


def test_wznowienie_nie_powtarza_zrobionego(srodowisko):
    assert P.main(srodowisko.argi) == 0
    pierwszy = len(srodowisko.wywolania())
    assert pierwszy >= 3
    tekst = (srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8")
    assert P.main(srodowisko.argi) == 0
    assert len(srodowisko.wywolania()) == pierwszy  # ani paczka, ani konsolidacja nie poszly drugi raz
    assert (srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8") == tekst


def test_nieudana_paczka_widoczna_i_ponowiona(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_PADA_NA", "Klientom nic")  # pada paczka projektu beta
    assert P.main(srodowisko.argi) == 1
    pods = (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")
    assert pods.startswith("NIEPELNE") and "C--dev-beta" in pods and "awaria na zyczenie" in pods
    assert "konsolidacja wstrzymana" in pods
    assert not list(srodowisko.wyniki.glob("*.md"))  # zadnych plikow tematow z dziura
    assert len(list((srodowisko.wyniki / ".stan" / "bledy").glob("*.json"))) == 1
    przed = srodowisko.wywolania().count("paczka")
    monkeypatch.delenv("ATRAPA_PADA_NA")
    assert P.main(srodowisko.argi) == 0
    assert srodowisko.wywolania().count("paczka") == przed + 1  # tylko ta jedna, nieudana
    assert not list((srodowisko.wyniki / ".stan" / "bledy").glob("*.json"))


def test_mimo_dziur_pliki_z_ostrzezeniem_i_kod_1(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_PADA_NA", "Klientom nic")
    assert P.main([*srodowisko.argi, "--mimo-dziur"]) == 1
    tekst = (srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8")
    assert tekst.startswith("# UWAGA: NIEPELNE - 1 paczek")
    parsuj(tekst)  # ostrzezenie nie psuje formatu


def test_odpowiedz_nie_json_to_blad_nie_pusta_paczka(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_SMIECI", "1")
    assert P.main(srodowisko.argi) == 1
    assert not list(srodowisko.wyniki.rglob("paczki/*.json"))
    assert "odpowiedz to nie JSON" in (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")


def test_nie_dubluje_wpisow_z_serwera(srodowisko):
    istn = srodowisko.tmp / "wsad.md"
    istn.write_text("# wsad\nautor: Primo\npoufnosc: jawne\n\n## temat: temat-a\n"
                    "- [2026-08-01] [jawne] Etykiety drukujemy w skali 180 procent.\n", encoding="utf-8")
    assert P.main([*srodowisko.argi, "--istniejace", str(istn)]) == 0
    tekst = (srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8")
    assert "Etykiety" not in tekst
    assert "jak_na_serwerze 1" in (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")


def test_konsolidacja_nie_obniza_poufnosci(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_POZIOM_KONS", "jawne")
    zb = sqlite3.connect(srodowisko.baza)
    _chunk(zb, 60, "C--dev-alfa", "s6", 1, "2026-09-06T08:00:00.000Z", "user",
           "USTALENIE: Obrót eBay we wrześniu był rekordowy. POZIOM=wrazliwe")
    zb.commit()
    zb.close()
    assert P.main(srodowisko.argi) == 0
    wpisy = parsuj((srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8"))
    assert next(w for w in wpisy if w.tresc.startswith("Obrót")).poufnosc == "wrazliwe"


def wektory_atrapa(teksty):
    """Worek slow -> wektor (haszowanie), bez modelu: identyczne tresci = identyczne wektory."""
    import hashlib

    import numpy as np

    v = np.zeros((len(teksty), 256), dtype=np.float32)
    for i, t in enumerate(teksty):
        for slowo in t.lower().split():
            v[i, int(hashlib.md5(slowo.encode()).hexdigest(), 16) % 256] += 1
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)


def test_duzy_temat_konsolidowany_w_rundach(srodowisko, monkeypatch):
    monkeypatch.setattr(P, "MAX_KONSOLIDACJA", 10_000)
    monkeypatch.setattr(P, "wektory", wektory_atrapa)
    zb = sqlite3.connect(srodowisko.baza)
    for i in range(120):  # 120 ustalen po ~150 znakow, kazde dwa razy -> runda 1 tnie na czesci
        for powtorka in range(2):
            _chunk(zb, 1000 + i * 2 + powtorka, "C--dev-alfa", f"d{powtorka}", i, f"2026-09-1{powtorka}T08:00:{i % 60:02d}.000Z",
                   "user", f"USTALENIE: Zasada numer {i} dotyczy pakowania kartonów i brzmi tak samo za każdym razem, "
                   f"bo to jedna i ta sama zasada firmy, powtórzona w dwóch rozmowach. Nr {i}.")
    zb.commit()
    zb.close()
    assert P.main(srodowisko.argi) == 0
    wpisy = parsuj((srodowisko.wyniki / "temat-a.md").read_text(encoding="utf-8"))
    zasady = [w for w in wpisy if w.tresc.startswith("Zasada numer")]
    assert len(zasady) == 120  # duplikaty z roznych czesci zlaczone w kolejnej rundzie


def test_na_sucho_bez_wywolan(srodowisko, capsys):
    assert P.main([*srodowisko.argi, "--na-sucho"]) == 0
    out = capsys.readouterr().out
    assert "PACZKI: 2" in out and "szacunek tokenow" in out
    assert srodowisko.wywolania() == []


def test_stary_plik_tematu_z_innego_przebiegu_znika(srodowisko):
    assert P.main(srodowisko.argi) == 0
    assert (srodowisko.wyniki / "temat-b.md").exists()  # temat-b jest tylko w projekcie alfa
    assert P.main([*srodowisko.argi, "--proba", "C--dev-beta"]) == 0
    assert (srodowisko.wyniki / "temat-a.md").exists()
    assert not (srodowisko.wyniki / "temat-b.md").exists()
    assert not (srodowisko.wyniki / "zrodla" / "temat-b.tsv").exists()


def test_na_sucho_po_przebiegu_liczy_z_pomiaru(srodowisko, capsys):
    zb = sqlite3.connect(srodowisko.baza)
    _chunk(zb, 70, "C--dev-gamma", "s7", 1, "2026-09-07T08:00:00.000Z", "user", "USTALENIE: Nowa rzecz w gammie.")
    zb.commit()
    zb.close()
    assert P.main([*srodowisko.argi, "--proba", "C--dev-alfa"]) == 0
    capsys.readouterr()
    assert P.main([*srodowisko.argi, "--na-sucho"]) == 0
    out = capsys.readouterr().out
    assert "PACZKI: 3 (juz przerobione: 1, do zrobienia: 2)" in out
    assert "wedlug pomiaru z 1 przerobionych paczek" in out


def test_proba_nieznanego_projektu_to_odmowa(srodowisko, capsys):
    assert P.main([*srodowisko.argi, "--proba", "C--dev-nie-ma"]) == 2
    assert srodowisko.wywolania() == []


@pytest.mark.skipif(not shutil.which("uv"), reason="brak uv - sprawdzenie prawdziwym importem serwera")
def test_format_przechodzi_prawdziwy_import_na_sucho(srodowisko):
    argi = [a for a in srodowisko.argi if a != "--bez-sprawdzenia-formatu"]
    assert P.main(argi) == 0
    pods = (srodowisko.wyniki / "PODSUMOWANIE.txt").read_text(encoding="utf-8")
    assert "OK dla wszystkich plikow" in pods
    # sabotaz: plik, ktorego serwer nie przyjmie, musi zostac zlapany
    zly = srodowisko.wyniki / "temat-a.md"
    zly.write_text("autor: Primo\n## temat: nie-ma-takiego\n- [2026-09-01] [jawne] cos tam\n", encoding="utf-8")
    assert P.sprawdz_format([zly], srodowisko.tematy)
    zly.write_text("autor: Primo\n## temat: temat-a\nto nie jest wpis\n", encoding="utf-8")
    assert P.sprawdz_format([zly], srodowisko.tematy)
