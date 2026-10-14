"""Testy profilu klient (przeglad na komputerze pracownika -> kolejka wysylki). Model to atrapa
(atrapa_claude.py, tematy dodatkowe: atrapa_przetaguj.py), dane wymyslone.

    uv --directory C:\\dev\\claude-worker\\lore run pytest C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-przeglad\\tests -q
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

import pytest

TU = Path(__file__).resolve().parent
sys.path.insert(0, str(TU.parent))

import przeglad as P  # noqa: E402
import przetaguj as T  # noqa: E402
from test_przeglad import TEMATY, _chunk, zbuduj_baze  # noqa: E402

ZASADY_KLIENTA = "Reguly poufnosci z serwera (atrapa): dane klientow nigdy, ceny zakupu wrazliwe."
ZNACZNIK = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\|(ok|blad)\|(.*)\n$")


def wiersze_klienta() -> list[tuple]:
    return [
        (1, "C--Users-Ela-dokumenty", "s1", 1, "2026-09-01T08:00:00.000Z", "user",
         "USTALENIE: Etykiety drukujemy w skali 180 procent. TAG=temat-b TEMAT=temat-a POZIOM=jawne"),
        (2, "C--Users-Ela-dokumenty", "s1", 2, "2026-09-01T08:01:00.000Z", "assistant", "Przyjąłem."),
        (3, "C--Users-Ela-wysylki", "s2", 1, "2026-09-02T09:00:00.000Z", "user",
         "USTALENIE: Paczki FBA nazywamy numerem i dopiskiem FBA. TEMAT=temat-b POZIOM=wewnetrzne"),
        (4, "C--Users-Ela-wysylki", "s2", 2, "2026-09-02T09:01:00.000Z", "user",
         "USTALENIE: Klientom nic nie wysyłamy bez zatwierdzenia Gosi."),
    ]


@pytest.fixture
def klient(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    (home / "tematy-cache.json").write_text(json.dumps(
        {"tematy": TEMATY, "zasady": ZASADY_KLIENTA, "wersja": "abc123"}), encoding="utf-8")
    baza = zbuduj_baze(tmp_path / "lore.db", wiersze_klienta())
    log = tmp_path / "wywolania"
    monkeypatch.setenv(P.KLIENT_HOME_ZMIENNA, str(home))
    monkeypatch.setenv("WIEDZA_PRZEGLAD_CLAUDE", json.dumps([sys.executable, str(TU / "atrapa_claude.py")]))
    monkeypatch.setenv("ATRAPA_LOG", str(log))
    for zmienna in ("ATRAPA_PADA_NA", "ATRAPA_POZIOM_KONS", "ATRAPA_SMIECI", "ATRAPA_ZMIEN_TRESC", "ATRAPA_GUB",
                    "ATRAPA_NIEZNANY"):
        monkeypatch.delenv(zmienna, raising=False)

    class S:
        pass
    s = S()
    s.home, s.baza, s.tmp = home, baza, tmp_path
    s.argi = ["--profil", "klient", "--baza", str(baza)]
    s.wywolania = lambda: sorted(f.suffix[1:] for f in log.iterdir()) if log.exists() else []
    s.kolejka = lambda: sorted((home / "kolejka").glob("przeglad-*.json")) if (home / "kolejka").exists() else []
    s.znacznik = lambda: ZNACZNIK.match((home / "znaczniki" / "przeglad.txt").read_text(encoding="utf-8"))
    s.stan = lambda: json.loads((home / "przeglad" / "stan.json").read_text(encoding="utf-8"))
    return s


def test_kolejka_w_formacie_umowy_bez_autora(klient, capsys):
    assert P.main(klient.argi) == 0
    assert "(2 naraz)" in capsys.readouterr().err  # limit kosztu na komputerze pracownika
    pliki = klient.kolejka()
    assert len(pliki) == 1
    tekst = pliki[0].read_text(encoding="utf-8")
    assert "autor" not in tekst and "Primo" not in tekst  # autora ustawia serwer
    dane = json.loads(tekst)
    assert dane["format"] == P.FORMAT_KOLEJKI and dane["wersja_tematow"] == "abc123"
    wpisy = dane["wpisy"]
    assert len(wpisy) == 3
    for w in wpisy:
        assert set(w) == {"klucz", "tresc", "temat", "tematy_dodatkowe", "poufnosc", "data", "zrodlo", "program"}
        assert w["klucz"] == hashlib.sha256(f"{w['temat']}\n{w['tresc']}".encode("utf-8")).hexdigest()
        assert w["program"] == "claude-code" and w["zrodlo"].startswith("przeglad historii rozmow (Lore)")
    etyk = next(w for w in wpisy if w["tresc"].startswith("Etykiety"))
    # tematy dodatkowe policzone w tym samym przebiegu - klient nie potrzebuje drugiego kroku
    assert etyk["temat"] == "temat-a" and etyk["tematy_dodatkowe"] == ["temat-b"]
    assert etyk["poufnosc"] == "jawne" and etyk["data"] == "2026-09-01"
    assert {w["temat"] for w in wpisy} == {"temat-a", "temat-b"}
    assert P.sprawdz_kolejke(wpisy, {"temat-a", "temat-b"}) == []
    # wszystko pod katalogiem klienta: stan, dziennik kosztow, znacznik
    assert (klient.home / "przeglad" / ".stan" / "koszt.tsv").exists()
    assert (klient.home / "przeglad" / "tagi" / ".stan" / "koszt.tsv").exists()
    assert sorted(p.name for p in klient.tmp.iterdir()) == ["home", "lore.db", "wywolania"]
    st = klient.stan()
    assert st["status"] == "komplet" and st["paczki"] == {"wszystkie": 2, "ok": 2, "bledy": 0, "do_zrobienia": 0}
    assert st["kolejka"] == str(pliki[0]) and st["wpisow_w_kolejce"] == 3
    m = klient.znacznik()
    assert m and m[1] == "ok" and m[2].startswith("komplet")
    assert not list((klient.home / "kolejka").glob("*.tmp"))  # zapis atomowy nie zostawia smieci


def test_prompty_klienta_bez_primo(klient):
    assert "Primo" not in P.instrukcja_paczki(TEMATY, ZASADY_KLIENTA, klient=True)
    assert "Primo" not in P.PROMPT_KONSOLIDACJI_KLIENT
    assert "Primo" not in T.instrukcja(TEMATY, klient=True)
    assert "Primo" in P.instrukcja_paczki(TEMATY, ZASADY_KLIENTA)  # tryb Primo bez zmian
    w, _ = P.wczytaj(P.polacz_baze(klient.baza))
    material = "".join(p.material for p in P.paczki(w, osoba=P.OSOBA_KLIENT))
    assert " Osoba] " in material and " Primo] " not in material
    with pytest.raises(AssertionError):  # zmieniony prompt Primo nie przechodzi cicho do klienta
        P.zamien("tekst bez frazy", [("Primo", "ta osoba")])


def test_wznowienie_bez_powtorek_i_bez_dubli_w_kolejce(klient):
    assert P.main(klient.argi) == 0
    pierwszy = klient.wywolania()
    assert pierwszy.count("paczka") == 2 and "tagi" in pierwszy
    assert P.main(klient.argi) == 0
    assert klient.wywolania() == pierwszy  # ani paczka, ani konsolidacja, ani tagi drugi raz
    assert len(klient.kolejka()) == 1  # podwojny przebieg nie dubluje kolejki
    m = klient.znacznik()
    assert m[1] == "ok" and "nic nowego" in m[2]
    assert klient.stan()["wpisow_w_kolejce"] == 0


def test_nowa_historia_dopisuje_tylko_nowe_wpisy(klient):
    assert P.main(klient.argi) == 0
    zb = __import__("sqlite3").connect(klient.baza)
    _chunk(zb, 9, "C--Users-Ela-nowy", "s9", 1, "2026-09-09T08:00:00.000Z", "user",
           "USTALENIE: Zwroty przyjmujemy tylko z numerem zamówienia.")
    zb.commit()
    zb.close()
    assert P.main(klient.argi) == 0
    pliki = klient.kolejka()
    assert len(pliki) == 2
    nowe = json.loads(pliki[-1].read_text(encoding="utf-8"))["wpisy"]
    assert [w["tresc"] for w in nowe] == ["Zwroty przyjmujemy tylko z numerem zamówienia."]


def test_pliki_kolejki_sortuja_sie_w_kolejnosci_zapisu_mimo_tej_samej_chwili(tmp_path, monkeypatch):
    class StalyCzas(P.datetime):  # zegar zatrzymany - kazdy zapis w tej samej chwili, bez zaleznosci od szybkosci
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 10, 14, 15, 7, 44, 999999)

    monkeypatch.setattr(P, "datetime", StalyCzas)
    zapisane = [P.zapisz_kolejke(tmp_path, [{"nr": i}], "w") for i in range(4)]
    assert len(set(zapisane)) == 4
    assert sorted(zapisane) == zapisane  # nazwa = kolejnosc zapisu
    assert [json.loads(p.read_text(encoding="utf-8"))["wpisy"][0]["nr"] for p in sorted(tmp_path.glob("przeglad-*.json"))] \
        == [0, 1, 2, 3]


def test_nieudana_paczka_znacznik_blad_bez_kolejki_i_wznowienie(klient, monkeypatch):
    monkeypatch.setenv("ATRAPA_PADA_NA", "Klientom nic")  # pada paczka projektu wysylki
    assert P.main(klient.argi) == 1
    assert klient.kolejka() == []  # z dziurami nic nie idzie do kolejki
    m = klient.znacznik()
    assert m[1] == "blad" and "NIEPELNE" in m[2]
    st = klient.stan()
    assert st["status"] == "dziury" and st["paczki"]["bledy"] == 1 and st["paczki"]["ok"] == 1
    przed = klient.wywolania().count("paczka")
    monkeypatch.delenv("ATRAPA_PADA_NA")
    assert P.main(klient.argi) == 0
    assert klient.wywolania().count("paczka") == przed + 1  # tylko ta jedna, nieudana
    assert len(klient.kolejka()) == 1 and klient.znacznik()[1] == "ok"


def test_nieudane_tematy_dodatkowe_to_dziura(klient, monkeypatch):
    monkeypatch.setenv("ATRAPA_PADA_NA", "W1 [")  # tylko material tematow dodatkowych
    assert P.main(klient.argi) == 1
    assert klient.kolejka() == []
    assert klient.znacznik()[1] == "blad"
    pods = (klient.home / "przeglad" / "PODSUMOWANIE.txt").read_text(encoding="utf-8")
    assert pods.startswith("NIEPELNE") and "bez tematow dodatkowych" in pods
    przed = klient.wywolania()
    monkeypatch.delenv("ATRAPA_PADA_NA")
    assert P.main(klient.argi) == 0
    po = klient.wywolania()
    assert po.count("paczka") == przed.count("paczka") and po.count("konsolidacja") == przed.count("konsolidacja")
    assert len(klient.kolejka()) == 1


def test_model_gubi_wpis_przy_tagach_to_dziura(klient, monkeypatch):
    monkeypatch.setenv("ATRAPA_GUB", "1")
    assert P.main(klient.argi) == 1
    assert klient.kolejka() == [] and klient.znacznik()[1] == "blad"


@pytest.mark.parametrize("cache, powod", [
    (None, "tematy-cache.json"),
    ({"tematy": TEMATY, "zasady": "", "wersja": "x"}, "zasady"),
    ({"tematy": [], "zasady": "z", "wersja": "x"}, "tematy"),
    (["to", "nie", "obiekt"], "oczekiwany obiekt"),
])
def test_zly_cache_tematow_to_odmowa_ze_znacznikiem(klient, capsys, cache, powod):
    plik = klient.home / "tematy-cache.json"
    if cache is None:
        plik.unlink()
    else:
        plik.write_text(json.dumps(cache), encoding="utf-8")
    assert P.main(klient.argi) == 2
    assert powod in capsys.readouterr().err
    m = klient.znacznik()
    assert m[1] == "blad" and m[2].startswith("ODMOWA")
    assert klient.wywolania() == []


def test_tematy_jako_same_id_w_cache(klient):
    (klient.home / "tematy-cache.json").write_text(json.dumps(
        {"tematy": ["temat-a", "temat-b"], "zasady": ZASADY_KLIENTA, "wersja": "x"}), encoding="utf-8")
    assert P.main(klient.argi) == 0
    assert len(klient.kolejka()) == 1


@pytest.mark.parametrize("argi", [["--format", "md"], ["--tematy", "x.json"], ["--mimo-dziur"], ["--rownolegle", "0"]])
def test_niedozwolone_opcje_klienta(klient, argi):
    assert P.main([*klient.argi, *argi]) == 2
    assert klient.znacznik()[1] == "blad"
    assert klient.wywolania() == []


def test_sprawdz_kolejke_lapie_autora_i_zly_klucz():
    dobry = P.wpisy_kolejki([("temat-a", ["temat-b"], P.Wpis("Etykiety drukujemy w skali 180 procent.", "jawne",
                                                             "2026-09-01", []))], "zrodlo")
    assert P.sprawdz_kolejke(dobry, {"temat-a", "temat-b"}) == []
    z_autorem = [{**dobry[0], "autor": "Ela"}]
    assert P.sprawdz_kolejke(z_autorem, {"temat-a", "temat-b"})
    zly_klucz = [{**dobry[0], "tresc": "Etykiety drukujemy w skali 200 procent."}]
    assert P.sprawdz_kolejke(zly_klucz, {"temat-a", "temat-b"})
    obcy = [{**dobry[0], "tematy_dodatkowe": ["nie-ma"]}]
    assert P.sprawdz_kolejke(obcy, {"temat-a", "temat-b"})
