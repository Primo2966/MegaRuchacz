"""Wiele tematow na wpis (0.3.0): zwykle na LUB, specjalne na I, poziom w temacie, przez ktory osoba widzi wpis.

Do tego migracja starej bazy (schemat 0.2.0), format importu z [+tematami], eksport i ustaw_tematy.
Dane wymyslone; slowa-znaczniki stoja w dokladnie jednym wpisie, wiec ich obecnosc w odpowiedzi = wyciek.
"""

from __future__ import annotations

import json
import sqlite3
from contextlib import closing

import numpy as np
import pytest
from conftest import WektoryAtrapa

from wiedza_firmy import eksport, importuj, sciezki, ustaw_tematy
from wiedza_firmy.baza import Baza, NowyWpis, warunek_uprawnien
from wiedza_firmy.importuj import BladFormatu, parsuj
from wiedza_firmy.uprawnienia import Uprawnienia
from wiedza_firmy.wiedza import PODPOWIEDZ_OSOBNE, Wiedza

TEMATY = [
    {"id": "grafiki", "nazwa": "Grafiki", "opis": "x", "przyklady": ["x"], "osobne_uprawnienie": False},
    {"id": "oferty", "nazwa": "Oferty", "opis": "x", "przyklady": ["x"], "osobne_uprawnienie": False},
    {"id": "seo", "nazwa": "Pozycjonowanie", "opis": "x", "przyklady": ["x"], "osobne_uprawnienie": True},
    {"id": "it", "nazwa": "Informatyka", "opis": "x", "przyklady": ["x"], "osobne_uprawnienie": True},
]
ZNANE = {t["id"] for t in TEMATY}
ZWYKLE = frozenset({"grafiki", "oferty"})

# (znacznik, wpis)
WPISY = {
    "tukan": NowyWpis("Szkarlatny tukan opisuje slowa kluczowe na grafice glownej.", "grafiki", "wewnetrzne",
                      "Anna", "2026-10-01", tematy_dodatkowe=("seo",)),
    "wieloryb": NowyWpis("Bursztynowy wieloryb: grafika PT02 porownuje nas z konkurencja.", "grafiki", "wewnetrzne",
                         "Anna", "2026-10-02", tematy_dodatkowe=("oferty",)),
    "nosorozec": NowyWpis("Miedziany nosorozec zna serwer frazy rankingowej.", "seo", "jawne",
                          "Bartek", "2026-10-03", tematy_dodatkowe=("it",)),
    "flaming": NowyWpis("Cytrynowy flaming stoi przy samej grafice.", "grafiki", "jawne", "Celina", "2026-10-04"),
}


def U(**tematy) -> Uprawnienia:
    return Uprawnienia(osoba="test", tematy=tematy)


def tekst(odp: dict) -> str:
    return json.dumps(odp, ensure_ascii=False).lower()


@pytest.fixture
def sr(katalog):
    sciezki.plik_tematow().write_text(json.dumps(TEMATY, ensure_ascii=False), encoding="utf-8")
    baza = Baza(sciezki.plik_bazy(), WektoryAtrapa())
    wynik = baza.dodaj(list(WPISY.values()), dodal="test", znane_tematy=ZNANE)
    assert len(wynik.dodane) == len(WPISY)
    return Wiedza(baza)


def szukaj(sr: Wiedza, upr: Uprawnienia, znacznik: str, **kw) -> dict:
    return sr.szukaj_wiedzy(upr, WPISY[znacznik].tresc, limit=50, **kw)


def widzi(sr: Wiedza, upr: Uprawnienia, znacznik: str) -> bool:
    return znacznik in " ".join(w["tresc"].lower() for w in szukaj(sr, upr, znacznik)["wyniki"])


# ---------------------------------------------------------------- tematy specjalne: I

def test_grafiki_seo_niewidoczny_dla_samych_grafik(sr):
    odp = szukaj(sr, U(grafiki="wrazliwe"), "tukan")
    assert "tukan" not in tekst(odp)
    # nazwy tematu specjalnego, ktorego nie ma, nie zdradzamy - ani w wynikach, ani w podpowiedzi
    assert "seo" not in tekst(odp) and "pozycjonowanie" not in tekst(odp)
    assert odp["bez_dostepu"] == [PODPOWIEDZ_OSOBNE]


def test_grafiki_seo_widoczny_dla_grafiki_i_seo(sr):
    odp = szukaj(sr, U(grafiki="wewnetrzne", seo="wewnetrzne"), "tukan")
    w = next(w for w in odp["wyniki"] if "tukan" in w["tresc"].lower())
    assert [t["id"] for t in w["tematy"]] == ["grafiki", "seo"]
    assert w["tematy"][0]["glowny"] is True and w["temat"] == "grafiki"


def test_grafiki_seo_niewidoczny_dla_samego_seo(sr):
    """Specjalny nie zastepuje zwyklego: wpis ma zwykly temat Grafiki, osoba nie ma zadnego zwyklego."""
    odp = szukaj(sr, U(seo="wrazliwe"), "tukan")
    assert "tukan" not in tekst(odp)
    assert odp["bez_dostepu"] == ["są wpisy w temacie Grafiki, nie masz dostępu — poproś admina"]


def test_poziom_za_niski_w_temacie_specjalnym(sr):
    odp = szukaj(sr, U(grafiki="wrazliwe", seo="jawne"), "tukan")
    assert "tukan" not in tekst(odp)
    assert odp["bez_dostepu"] == ["są wpisy w temacie Pozycjonowanie na poziomie poufności wyższym niż Twój — poproś admina"]


def test_same_specjalne_wymagaja_wszystkich(sr):
    assert not widzi(sr, U(seo="wrazliwe"), "nosorozec")
    assert not widzi(sr, U(it="wrazliwe", grafiki="wrazliwe"), "nosorozec")
    assert widzi(sr, U(seo="jawne", it="jawne"), "nosorozec")


# ---------------------------------------------------------------- tematy zwykle: LUB

def test_grafiki_oferty_widoczny_dla_samych_ofert(sr):
    odp = szukaj(sr, U(oferty="wewnetrzne"), "wieloryb")
    w = next(w for w in odp["wyniki"] if "wieloryb" in w["tresc"].lower())
    # pokazujemy tylko temat, przez ktory osoba widzi wpis
    assert w["tematy"] == [{"id": "oferty", "nazwa": "Oferty", "glowny": False}]
    assert w["temat"] == "oferty"
    assert widzi(sr, U(grafiki="wewnetrzne"), "wieloryb")


def test_poziom_za_niski_w_jedynym_pasujacym_temacie(sr):
    odp = szukaj(sr, U(oferty="jawne"), "wieloryb")
    assert "wieloryb" not in tekst(odp)
    # podpowiedz wskazuje temat, ktory osoba ma (Oferty), a nie ten, ktorego nie ma wcale (Grafiki)
    assert odp["bez_dostepu"] == ["są wpisy w temacie Oferty na poziomie poufności wyższym niż Twój — poproś admina"]


def test_poziom_liczy_sie_w_temacie_przez_ktory_widac(sr):
    """Grafiki tylko jawne (za malo), Oferty wewnetrzne (wystarczy) - wpis widoczny, ale tylko przez Oferty."""
    odp = szukaj(sr, U(grafiki="jawne", oferty="wewnetrzne"), "wieloryb")
    w = next(w for w in odp["wyniki"] if "wieloryb" in w["tresc"].lower())
    assert [t["id"] for t in w["tematy"]] == ["oferty"]


def test_filtr_tematu_przy_wielu_tematach(sr):
    upr = U(oferty="wewnetrzne")
    odp = szukaj(sr, upr, "wieloryb", temat="oferty")
    assert any("wieloryb" in w["tresc"].lower() for w in odp["wyniki"])
    assert all("flaming" not in w["tresc"].lower() for w in odp["wyniki"])  # flaming ma tylko Grafiki
    odp = szukaj(sr, upr, "wieloryb", temat="grafiki")
    assert odp["wyniki"] == [] and "Nie masz dostępu do tematu grafiki" in odp["komunikat"]
    # temat, ktory osoba ma, ale przez ktory nie widzi wpisu (za niski poziom), nie otwiera go
    odp = szukaj(sr, U(grafiki="jawne", oferty="wewnetrzne"), "wieloryb", temat="grafiki")
    assert "wieloryb" not in " ".join(w["tresc"].lower() for w in odp["wyniki"])


def test_admin_widzi_wszystko_ze_wszystkimi_tematami(sr):
    odp = sr.szukaj_wiedzy(Uprawnienia(osoba="szef", admin=True), "tukan wieloryb nosorozec flaming", limit=50)
    tematy = {w["tresc"].split()[1].lower(): [t["id"] for t in w["tematy"]] for w in odp["wyniki"]}
    assert tematy == {"tukan": ["grafiki", "seo"], "wieloryb:": ["grafiki", "oferty"], "nosorozec": ["seo", "it"],
                      "flaming": ["grafiki"]}


# ---------------------------------------------------------------- filtr w SQL, przed rankingiem

def _id(baza: Baza, znacznik: str) -> int:
    return next(i for i, w in baza.wpisy_z_tematami().items() if znacznik in w["tresc"].lower())


def test_filtr_w_obu_kanalach_przed_rankingiem(sr):
    baza = sr.baza
    tukan = _id(baza, "tukan")
    warunek = warunek_uprawnien(U(grafiki="wrazliwe"), zwykle=ZWYKLE)
    with closing(baza.polacz()) as conn:
        assert tukan not in baza._kanal_fts(conn, "szkarlatny tukan", warunek, 50)
        ids, _ = baza._podobienstwa(conn, baza.wektoryzator.pytanie("szkarlatny tukan"), warunek)
        assert tukan not in ids and ids  # inne wpisy sa, tukana nie ma
        pelny = warunek_uprawnien(U(grafiki="wrazliwe", seo="wrazliwe"), zwykle=ZWYKLE)
        assert tukan in baza._kanal_fts(conn, "szkarlatny tukan", pelny, 50)


def test_lista_tematow_nieczytelna_zaweza_nie_poszerza(sr):
    """Bez listy tematow (zwykle puste) kazdy temat liczy sie jak specjalny - Grafiki+Oferty wymaga obu."""
    baza = sr.baza
    wieloryb = _id(baza, "wieloryb")
    ids = lambda zw: {w["id"] for w in baza.szukaj(WPISY["wieloryb"].tresc, U(oferty="wrazliwe"), limit=50,  # noqa: E731
                                                     zwykle=zw)["wyniki"]}
    assert wieloryb in ids(ZWYKLE)
    assert wieloryb not in ids(frozenset())
    sciezki.plik_tematow().write_text("{zepsuty", encoding="utf-8")
    assert not widzi(sr, U(oferty="wrazliwe"), "wieloryb")


def test_wpis_bez_tematow_widzi_tylko_admin(sr):
    """Baza niespojna (wpis bez wierszy w wpisy_tematy) - zaden temat nie otwiera wpisu, poza adminem."""
    baza = sr.baza
    flaming = _id(baza, "flaming")
    with closing(baza.polacz()) as conn:
        conn.execute("DELETE FROM wpisy_tematy WHERE wpis_id = ?", (flaming,))
    wszystko = U(grafiki="wrazliwe", oferty="wrazliwe", seo="wrazliwe", it="wrazliwe")
    assert not widzi(sr, wszystko, "flaming")
    assert widzi(sr, Uprawnienia(osoba="szef", admin=True), "flaming")


# ---------------------------------------------------------------- migracja starej bazy

SCHEMAT_0_2 = """
CREATE TABLE wpisy (id INTEGER PRIMARY KEY, tresc TEXT NOT NULL, temat TEXT NOT NULL,
    poufnosc TEXT NOT NULL CHECK (poufnosc IN ('jawne', 'wewnetrzne', 'wrazliwe')), autor TEXT NOT NULL,
    data_ustalenia TEXT NOT NULL, zrodlo TEXT NOT NULL DEFAULT '', program TEXT NOT NULL DEFAULT '',
    dodano TEXT NOT NULL, dodal TEXT NOT NULL DEFAULT '', usuniety TEXT, usunal TEXT, powod_usuniecia TEXT);
CREATE INDEX idx_wpisy_temat ON wpisy(temat, poufnosc);
CREATE VIRTUAL TABLE wpisy_fts USING fts5(tresc, content='wpisy', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2');
CREATE TABLE wektory (wpis_id INTEGER PRIMARY KEY REFERENCES wpisy(id), emb BLOB NOT NULL);
CREATE TABLE meta (klucz TEXT PRIMARY KEY, wartosc TEXT);
"""


def _stara_baza(sciezka, ile: int = 98) -> None:
    """Baza w schemacie 0.2.0: `ile` wpisow (ostatni usuniety), kazdy z wektorem."""
    atrapa = WektoryAtrapa()
    with closing(sqlite3.connect(sciezka)) as conn:
        conn.executescript(SCHEMAT_0_2)
        for i in range(1, ile + 1):
            tresc = f"Stary wpis numer {i} o rzeczy{i}."
            temat = ("grafiki", "oferty", "seo")[i % 3]
            conn.execute("INSERT INTO wpisy (id, tresc, temat, poufnosc, autor, data_ustalenia, dodano, usuniety) "
                         "VALUES (?, ?, ?, 'jawne', 'Anna', '2026-10-01', 'x', ?)",
                         (i, tresc, temat, "2026-10-10" if i == ile else None))
            conn.execute("INSERT INTO wpisy_fts (rowid, tresc) VALUES (?, ?)", (i, tresc))
            conn.execute("INSERT INTO wektory (wpis_id, emb) VALUES (?, ?)",
                         (i, np.asarray(atrapa._wektor(tresc), dtype=np.float32).tobytes()))
        conn.execute("INSERT INTO meta VALUES ('model_wektorow', 'test/atrapa')")
        conn.commit()


def _stan(sciezka) -> dict:
    with closing(sqlite3.connect(sciezka)) as conn:
        return {
            "wpisy": conn.execute("SELECT * FROM wpisy ORDER BY id").fetchall(),
            "wektory": conn.execute("SELECT * FROM wektory ORDER BY wpis_id").fetchall(),
            "fts": conn.execute("SELECT rowid FROM wpisy_fts WHERE wpisy_fts MATCH 'stary' ORDER BY rowid").fetchall(),
            "tematy": (conn.execute("SELECT * FROM wpisy_tematy ORDER BY wpis_id, temat_id").fetchall()
                       if conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'wpisy_tematy'").fetchone() else None),
        }


def test_migracja_starej_bazy_zachowuje_wszystko(katalog):
    sciezki.plik_tematow().write_text(json.dumps(TEMATY, ensure_ascii=False), encoding="utf-8")
    plik = sciezki.plik_bazy()
    _stara_baza(plik)
    przed = _stan(plik)
    assert len(przed["wpisy"]) == 98 and len(przed["wektory"]) == 98 and przed["tematy"] is None

    baza = Baza(plik, WektoryAtrapa())
    po = _stan(plik)
    assert po["wpisy"] == przed["wpisy"] and po["wektory"] == przed["wektory"] and po["fts"] == przed["fts"]
    # dotychczasowy temat = jedyny i glowny
    assert po["tematy"] == [(w[0], w[2], 1) for w in przed["wpisy"]]
    # kopia sprzed migracji: stara baza bajt w bajt co do tresci
    assert baza.kopia_migracji is not None and baza.kopia_migracji.exists()
    assert _stan(baza.kopia_migracji) == przed
    # wyszukiwanie dziala jak przedtem
    odp = Wiedza(baza).szukaj_wiedzy(U(oferty="jawne"), "Stary wpis numer 1 o rzeczy1", limit=50)
    assert odp["wyniki"] and all(w["temat"] == "oferty" for w in odp["wyniki"])
    assert baza.uzupelnij_wektory() == 0  # wektory przetrwaly, nic do liczenia

    kopie = sorted(plik.parent.glob("wiedza.db.kopia-*"))
    druga = Baza(plik, WektoryAtrapa())
    assert druga.kopia_migracji is None
    assert _stan(plik) == po
    assert sorted(plik.parent.glob("wiedza.db.kopia-*")) == kopie  # druga migracja nie robi nawet kopii


def test_nowa_baza_bez_kopii(katalog):
    baza = Baza(sciezki.plik_bazy(), None)
    assert baza.kopia_migracji is None
    assert not list(sciezki.plik_bazy().parent.glob("wiedza.db.kopia-*"))


# ---------------------------------------------------------------- format importu

def test_import_tematy_dodatkowe_parsuja_sie():
    wpisy = parsuj("autor: A\n## temat: grafiki\n- [2026-10-01] [jawne] [+oferty,seo] tresc jedna\n"
                   "- [2026-10-03] [wewnetrzne] bez dodatkowych\n"
                   "poufnosc: jawne\n- [2026-10-04] [+oferty] domyslny poziom\n", "w")
    assert wpisy[0].tematy_dodatkowe == ("oferty", "seo")
    assert wpisy[0].tresc == "tresc jedna" and wpisy[0].temat == "grafiki"
    assert wpisy[1].tematy_dodatkowe == ()
    assert wpisy[2].tematy_dodatkowe == ("oferty",) and wpisy[2].poufnosc == "jawne"
    assert wpisy[2].tresc == "domyslny poziom"


@pytest.mark.parametrize("linia, fragment", [
    ("- [2026-10-01] [jawne] [+oferty,nie-ma] x", "w:3: nieznany temat 'nie-ma'"),
    ("- [2026-10-01] [jawne] [+grafiki] x", "w:3: temat glowny 'grafiki' powtorzony"),
    ("- [2026-10-01] [jawne] [+oferty,oferty] x", "w:3: temat dodatkowy 'oferty' powtorzony"),
    ("- [2026-10-01] [jawne] [+oferty,] x", "w:3: pusty temat"),
])
def test_import_zle_tematy_dodatkowe_z_numerem_linii(linia, fragment):
    with pytest.raises(BladFormatu, match=fragment):
        parsuj(f"autor: A\n## temat: grafiki\n{linia}\n", "w", ZNANE)


def test_import_cli_nieznany_temat_odmowa_calosci(katalog, tmp_path, capsys):
    sciezki.plik_tematow().write_text(json.dumps(TEMATY, ensure_ascii=False), encoding="utf-8")
    plik = tmp_path / "wsad.md"
    plik.write_text("autor: A\n## temat: grafiki\n- [2026-10-01] [jawne] dobry wpis\n"
                    "- [2026-10-02] [jawne] [+oferty,marketing] zly temat dodatkowy\n", encoding="utf-8")
    assert importuj.main([str(plik), "--bez-modelu"]) == 1
    assert "wsad.md:4: nieznany temat 'marketing'" in capsys.readouterr().err
    assert not sciezki.plik_bazy().exists() or Baza(sciezki.plik_bazy(), None).statystyka()["wpisy"] == 0
    plik.write_text("autor: A\n## temat: grafiki\n- [2026-10-01] [jawne] dobry wpis\n## temat: marketing\n"
                    "- [2026-10-02] [jawne] zly temat glowny\n", encoding="utf-8")
    assert importuj.main([str(plik), "--bez-modelu"]) == 1
    assert "wsad.md:5: nieznany temat 'marketing'" in capsys.readouterr().err
    plik.write_text("autor: A\n## temat: grafiki\n- [2026-10-01] [jawne] [+oferty,seo] dobry wpis\n", encoding="utf-8")
    assert importuj.main([str(plik), "--bez-modelu"]) == 0
    baza = Baza(sciezki.plik_bazy(), None)
    assert [w["tematy"] for w in baza.wpisy_z_tematami().values()] == [[("grafiki", True), ("oferty", False), ("seo", False)]]


def test_baza_odrzuca_nieznany_temat_dodatkowy(sr):
    from wiedza_firmy.baza import BladWpisu

    with pytest.raises(BladWpisu, match="nieznany temat dodatkowy"):
        sr.baza.dodaj([NowyWpis("Nowy wpis", "grafiki", "jawne", "A", "2026-10-01", tematy_dodatkowe=("nie-ma",))],
                      dodal="t", znane_tematy=ZNANE)


# ---------------------------------------------------------------- eksport i ustaw_tematy

def test_eksport_i_ustaw_tematy(sr, tmp_path, capsys):
    plik = tmp_path / "eksport.md"
    assert eksport.main([str(plik)]) == 0
    tekst_pliku = plik.read_text(encoding="utf-8")
    assert "[+seo]" in tekst_pliku and "[+oferty]" in tekst_pliku and "[#" in tekst_pliku
    assert eksport.main([str(plik)]) == 1  # bez --nadpisz nie zastepuje
    przed = sr.baza.wpisy_z_tematami()

    # nic nie zmienione w pliku = nic do zmiany
    assert ustaw_tematy.main([str(plik)]) == 0
    assert "nic do zmiany" in capsys.readouterr().out

    flaming = _id(sr.baza, "flaming")
    zmieniony = tekst_pliku.replace(f"[#{flaming}] [2026-10-04] [jawne] ", f"[#{flaming}] [2026-10-04] [jawne] [+oferty] ")
    assert zmieniony != tekst_pliku
    plik.write_text(zmieniony, encoding="utf-8")
    assert ustaw_tematy.main([str(plik), "--na-sucho"]) == 0
    assert "grafiki -> grafiki +oferty" in capsys.readouterr().out
    assert sr.baza.wpisy_z_tematami() == przed

    assert ustaw_tematy.main([str(plik)]) == 0
    assert "zmieniono tematy 1 wpisow" in capsys.readouterr().out
    po = sr.baza.wpisy_z_tematami()
    assert po[flaming]["tematy"] == [("grafiki", True), ("oferty", False)]
    assert {i: {k: v for k, v in w.items() if k != "tematy"} for i, w in po.items()} == \
        {i: {k: v for k, v in w.items() if k != "tematy"} for i, w in przed.items()}  # tresci nie ruszone
    assert list(sciezki.plik_bazy().parent.glob("wiedza.db.kopia-przed-ustaw-tematy-*"))
    assert widzi(sr, U(oferty="jawne"), "flaming")

    # zmiana tematu glownego: wpisy.temat idzie za nim
    plik.write_text(zmieniony.replace(f"- [#{flaming}] [2026-10-04] [jawne] [+oferty] {WPISY['flaming'].tresc}\n", "")
                    + f"\n## temat: oferty\n- [#{flaming}] [2026-10-04] [jawne] [+grafiki] {WPISY['flaming'].tresc}\n",
                    encoding="utf-8")
    assert ustaw_tematy.main([str(plik)]) == 0
    w = sr.baza.wpisy_z_tematami([flaming])[flaming]
    assert w["temat"] == "oferty" and w["tematy"] == [("oferty", True), ("grafiki", False)]


@pytest.mark.parametrize("zmiana, fragment", [
    (lambda t, i: t.replace(f"[#{i}] ", "", 1), "wpis bez [#id]"),
    (lambda t, i: t.replace(f"[#{i}] ", "[#9999] ", 1), "nie ma wpisu 9999"),
    (lambda t, i: t.replace("Cytrynowy flaming", "Zmieniony flaming"), "inna tresc"),
    (lambda t, i: t.replace(f"[#{i}] [2026-10-04] [jawne] ", f"[#{i}] [2026-10-04] [jawne] [+marketing] "),
     "nieznany temat 'marketing'"),
    (lambda t, i: t + f"- [#{i}] [2026-10-04] [jawne] {WPISY['flaming'].tresc}\n", "juz bylo w linii"),
])
def test_ustaw_tematy_odmowy(sr, tmp_path, capsys, zmiana, fragment):
    plik = tmp_path / "eksport.md"
    assert eksport.main([str(plik)]) == 0
    przed = sr.baza.wpisy_z_tematami()
    flaming = _id(sr.baza, "flaming")
    plik.write_text(zmiana(plik.read_text(encoding="utf-8"), flaming)
                    .replace(f"[#{flaming}] [2026-10-04] [jawne] Cy", f"[#{flaming}] [2026-10-04] [jawne] [+oferty] Cy"),
                    encoding="utf-8")
    assert ustaw_tematy.main([str(plik)]) == 1
    assert fragment in capsys.readouterr().err
    assert sr.baza.wpisy_z_tematami() == przed


def test_eksport_wczytuje_sie_importem_do_pustej_bazy(sr, tmp_path, monkeypatch, capsys):
    plik = tmp_path / "eksport.md"
    assert eksport.main([str(plik)]) == 0
    stare = sorted((w["tresc"], w["poufnosc"], tuple(w["tematy"])) for w in sr.baza.wpisy_z_tematami().values())
    monkeypatch.setenv("WIEDZA_FIRMY_HOME", str(tmp_path / "druga"))
    sciezki.katalog_danych().mkdir()
    sciezki.plik_tematow().write_text(json.dumps(TEMATY, ensure_ascii=False), encoding="utf-8")
    assert importuj.main([str(plik), "--bez-modelu"]) == 0
    assert "[#id]" in capsys.readouterr().err  # mowi, ze id pomija
    nowe = sorted((w["tresc"], w["poufnosc"], tuple(w["tematy"]))
                  for w in Baza(sciezki.plik_bazy(), None).wpisy_z_tematami().values())
    assert nowe == stare
