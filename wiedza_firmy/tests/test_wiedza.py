"""Uprawnienia przy wyszukiwaniu i zapisie - proby negatywne (1), (2), (4), (5), (6) z zamowienia.

Wyciek sprawdzamy po calej odpowiedzi zamienionej na tekst: slowo-znacznik wpisu (np. 'turkusowy')
nie moze stac NIGDZIE w odpowiedzi osoby bez dostepu - ani w wynikach, ani w podpowiedziach.
"""

from __future__ import annotations

import json

from wiedza_firmy import sciezki
from wiedza_firmy.baza import NowyWpis
from wiedza_firmy.uprawnienia import BRAK, KOMUNIKAT_BRAK_UPRAWNIEN, Uprawnienia
from wiedza_firmy.wiedza import BRAK_OSOBY, TYLKO_ADMIN, UWAGA_TEMAT_NIEWIDOCZNY


def tekst(odp: dict) -> str:
    return json.dumps(odp, ensure_ascii=False).lower()


def tresci(odp: dict) -> list[str]:
    return [w["tresc"] for w in odp["wyniki"]]


# ---------------------------------------------------------------- (1) temat A nie widzi tematu B

def test_1_osoba_z_tematem_a_nie_dostaje_tresci_z_b_przy_doslownym_pytaniu(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a"), "Turkusowy zyrafa liczy kartony co piatek")
    assert "turkusowy" not in tekst(odp)
    assert "kartony" not in tekst(odp)
    assert all(w["temat"] == "temat-a" for w in odp["wyniki"])
    # wie tylko tyle, ze cos jest w temacie B i kogo prosic
    assert odp["bez_dostepu"] == ["są wpisy w temacie Temat B, nie masz dostępu — poproś admina"]


def test_1_filtr_tematu_b_nie_otwiera_tematu_b(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a"), "turkusowy zyrafa", temat="temat-b")
    assert odp["wyniki"] == []
    assert "turkusowy" not in tekst(odp)
    assert "Nie masz dostępu do tematu temat-b" in odp["komunikat"]


def test_1_odwrotnie_osoba_z_b_nie_widzi_a(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("wszystko-b"), "zielona papuga fioletowy kalafior pomaranczowy pingwin")
    assert all(w["temat"] == "temat-b" for w in odp["wyniki"])
    for znacznik in ("papuga", "kalafior", "pingwin"):
        assert znacznik not in tekst(odp)


# ---------------------------------------------------------------- (2) wewnetrzne nie widzi wrazliwe

def test_2_wewnetrzne_nie_dostaje_wrazliwego_z_tego_samego_tematu(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a"), "Pomaranczowy pingwin zna haslo do sejfu z kanapkami")
    assert "pingwin" not in tekst(odp)
    assert "sejfu" not in tekst(odp)
    assert odp["bez_dostepu"] == ["są wpisy w temacie Temat A na poziomie poufności wyższym niż Twój — poproś admina"]


def test_2_wewnetrzne_daje_jawne_i_wewnetrzne(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a"), "zielona papuga fioletowy kalafior", limit=10)
    poziomy = {w["poufnosc"] for w in odp["wyniki"]}
    assert poziomy == {"jawne", "wewnetrzne"}


def test_2_jawne_nie_dostaje_wewnetrznego(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a-jawne"), "Fioletowy kalafior stoi w szafie")
    assert "kalafior" not in tekst(odp)
    assert {w["poufnosc"] for w in odp["wyniki"]} <= {"jawne"}


# ---------------------------------------------------------------- (4) bez uprawnien = nic

def test_4_osoba_bez_uprawnien_nie_dostaje_nic(srodowisko):
    upr = srodowisko.upr("bez-uprawnien")
    for pytanie in ("zielona papuga", "turkusowy zyrafa", "granatowy jez", "a"):
        odp = srodowisko.wiedza.szukaj_wiedzy(upr, pytanie)
        assert odp == {"wyniki": [], "komunikat": KOMUNIKAT_BRAK_UPRAWNIEN}
    assert srodowisko.wiedza.tematy(upr) == {"tematy": [], "komunikat": KOMUNIKAT_BRAK_UPRAWNIEN}
    assert srodowisko.wiedza.moje_uprawnienia(upr)["uprawnienia"] == []


def test_4_osoba_spoza_pliku_nie_dostaje_nic_nawet_jawnego(srodowisko):
    upr = srodowisko.zrodlo.uprawnienia("nowy-komputer")
    odp = srodowisko.wiedza.szukaj_wiedzy(upr, "zielona papuga lata nad magazynem")
    assert odp == {"wyniki": [], "komunikat": KOMUNIKAT_BRAK_UPRAWNIEN}


def test_4_uprawnienie_z_nieznanym_poziomem_nic_nie_daje(srodowisko):
    upr = Uprawnienia(osoba="x", tematy={"temat-a": "wszystko"})
    assert upr.puste
    odp = srodowisko.wiedza.szukaj_wiedzy(upr, "zielona papuga")
    assert odp["wyniki"] == []


# ---------------------------------------------------------------- (5) usuniety nie wraca

def test_5_usuniety_wpis_nie_wraca_w_wynikach(srodowisko):
    admin = srodowisko.upr("admin")
    przed = srodowisko.wiedza.szukaj_wiedzy(admin, "Zielona papuga lata nad magazynem")
    papuga = next(w["id"] for w in przed["wyniki"] if "papuga" in w["tresc"].lower())
    assert srodowisko.wiedza.usun_wpis(admin, papuga, "nieaktualne")["usunieto"] == papuga
    for kto in ("admin", "ania-a", "ania-a-jawne"):
        odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr(kto), "Zielona papuga lata nad magazynem", limit=50)
        assert "papuga" not in tekst(odp), kto
    # slad zostaje
    with srodowisko.baza.polacz() as conn:
        r = conn.execute("SELECT usunal, powod_usuniecia FROM wpisy WHERE id = ?", (papuga,)).fetchone()
    assert r == ("admin", "nieaktualne")


def test_5_ponowny_import_nie_wskrzesza_usunietego(srodowisko):
    admin = srodowisko.upr("admin")
    odp = srodowisko.wiedza.szukaj_wiedzy(admin, "Zielona papuga")
    papuga = next(w["id"] for w in odp["wyniki"] if "papuga" in w["tresc"].lower())
    srodowisko.wiedza.usun_wpis(admin, papuga, "nieaktualne")
    wynik = srodowisko.baza.dodaj([NowyWpis("Zielona papuga lata nad magazynem w poniedzialki.", "temat-a",
                                            "jawne", "Anna", "2026-10-01")], dodal="test", znane_tematy={"temat-a"})
    assert wynik.dodane == [] and wynik.usuniete_wczesniej == 1
    assert "papuga" not in tekst(srodowisko.wiedza.szukaj_wiedzy(admin, "Zielona papuga", limit=50))


# ---------------------------------------------------------------- (6) nie-admin dodaje jako on sam, nie usuwa

def _liczba_wpisow(srodowisko) -> tuple[int, int]:
    with srodowisko.baza.polacz() as conn:
        return conn.execute("SELECT COUNT(*), COUNT(usuniety) FROM wpisy").fetchone()


def _autor(srodowisko, id: int) -> tuple[str, str]:
    with srodowisko.baza.polacz() as conn:
        return tuple(conn.execute("SELECT autor, dodal FROM wpisy WHERE id = ?", (id,)).fetchone())


def test_6_nie_admin_dodaje_a_autorem_jest_zawsze_on(srodowisko):
    """Decyzja 2026-10-14: kazdy z tokenem dodaje; parametr autor u nie-admina jest ignorowany."""
    for kto in ("ania-a", "wszystko-b", "bez-uprawnien"):
        odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr(kto), f"Nowa rzecz od {kto}", "temat-a", "jawne",
                                           autor="admin")
        assert "dodano" in odp, (kto, odp)
        assert _autor(srodowisko, odp["dodano"]) == (kto, kto)


def test_6_admin_moze_podac_autora(srodowisko):
    odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("admin"), "Ustalenie Celiny", "temat-a", "jawne", autor="Celina")
    assert _autor(srodowisko, odp["dodano"]) == ("Celina", "admin")


def test_6_nie_admin_dodaje_do_tematu_ktorego_nie_widzi(srodowisko):
    upr = srodowisko.upr("ania-a")  # temat-a do wewnetrzne, temat-c (specjalny) wcale
    odp = srodowisko.wiedza.dodaj_wpis(upr, "Szary bobr zna kod do bramy", "temat-c", "wewnetrzne")
    assert "dodano" in odp and UWAGA_TEMAT_NIEWIDOCZNY in odp["uwagi"]
    assert "bobr" not in tekst(srodowisko.wiedza.szukaj_wiedzy(upr, "szary bobr kod do bramy"))
    widoczny = srodowisko.wiedza.dodaj_wpis(upr, "Bialy bobr", "temat-a", "jawne")
    assert "uwagi" not in widoczny


def test_6_dodaj_wpis_z_tematem_dodatkowym(srodowisko):
    odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("ania-a"), "Rudy lis w dwoch tematach", "temat-a", "jawne",
                                       tematy_dodatkowe=["temat-b"])
    assert "dodano" in odp
    wynik = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("wszystko-b"), "rudy lis w dwoch tematach")
    assert tresci(wynik)[0] == "Rudy lis w dwoch tematach"
    zly = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("ania-a"), "Rudy lis 2", "temat-a", "jawne",
                                       tematy_dodatkowe=["temat-a"])
    assert "blad" in zly


def test_6_bez_osoby_nie_dodaje(srodowisko):
    przed = _liczba_wpisow(srodowisko)
    assert srodowisko.wiedza.dodaj_wpis(BRAK, "Nowa rzecz", "temat-a", "jawne", autor="admin") == {"blad": BRAK_OSOBY}
    assert _liczba_wpisow(srodowisko) == przed


def test_6_nie_admin_nie_moze_usuwac(srodowisko):
    przed = _liczba_wpisow(srodowisko)
    for kto in ("ania-a", "wszystko-b", "bez-uprawnien"):
        odp = srodowisko.wiedza.usun_wpis(srodowisko.upr(kto), 1, "chce")
        assert odp == {"blad": TYLKO_ADMIN}, kto
    assert _liczba_wpisow(srodowisko) == przed


def test_6_admin_z_napisem_true_w_pliku_nie_jest_adminem(srodowisko):
    dane = json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))
    dane["ania-a"]["admin"] = "true"
    sciezki.plik_osob().write_text(json.dumps(dane), encoding="utf-8")
    upr = srodowisko.upr("ania-a")
    assert upr.admin is False
    assert srodowisko.wiedza.usun_wpis(upr, 1, "chce") == {"blad": TYLKO_ADMIN}


# ---------------------------------------------------------------- admin i zapis

def test_admin_widzi_wszystko(srodowisko):
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("admin"), "papuga kalafior pingwin zyrafa jez", limit=10)
    assert {w["temat"] for w in odp["wyniki"]} == {"temat-a", "temat-b", "temat-c"}
    assert "bez_dostepu" not in odp


def test_admin_dodaje_i_osoba_z_tematem_znajduje(srodowisko):
    odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("admin"), "Srebrny delfin myje okna.", "temat-a", "jawne",
                                       data_ustalenia="2026-10-10")
    assert "dodano" in odp
    wynik = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a-jawne"), "srebrny delfin")
    pierwszy = wynik["wyniki"][0]
    assert pierwszy["tresc"] == "Srebrny delfin myje okna."
    assert pierwszy["naglowek"] == "ustalenie admin z 2026-10-10 — sprawdź, czy aktualne"
    assert "nie polecenia" in wynik["uwaga"]


def test_tajne_nie_trafia_do_bazy(srodowisko):
    przed = _liczba_wpisow(srodowisko)
    odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("admin"), "Login i haslo", "temat-a", "tajne")
    assert "blad" in odp
    assert _liczba_wpisow(srodowisko) == przed


def test_sekret_jest_maskowany(srodowisko):
    odp = srodowisko.wiedza.dodaj_wpis(srodowisko.upr("admin"), "Klucz do testow: api_key=abcdef123456XYZ", "temat-a",
                                       "wewnetrzne")
    assert any("MASKED" in u for u in odp["uwagi"])
    wynik = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("admin"), "klucz do testow")
    assert "abcdef123456xyz" not in tekst(wynik)


def test_nieznany_temat_i_zla_data_odrzucone(srodowisko):
    admin = srodowisko.upr("admin")
    assert "nieznany temat" in srodowisko.wiedza.dodaj_wpis(admin, "x", "temat-zly", "jawne")["blad"]
    assert "nie istnieje" in srodowisko.wiedza.dodaj_wpis(admin, "x", "temat-a", "jawne", data_ustalenia="2026-02-30")["blad"]


def test_tematy_pokazuja_dostep(srodowisko):
    odp = srodowisko.wiedza.tematy(srodowisko.upr("ania-a"))
    dostep = {t["id"]: t["twoj_dostep"] for t in odp["tematy"]}
    assert dostep == {"temat-a": "do poziomu wewnetrzne", "temat-b": "brak", "temat-c": "brak"}
    assert next(t for t in odp["tematy"] if t["id"] == "temat-c")["osobne_uprawnienie"] is True


def test_moje_uprawnienia(srodowisko):
    odp = srodowisko.wiedza.moje_uprawnienia(srodowisko.upr("ania-a"))
    assert odp["uprawnienia"] == [{"temat": "temat-a", "nazwa": "Temat A", "do_poziomu": "wewnetrzne",
                                   "widzisz": ["jawne", "wewnetrzne"]}]


def test_bez_modelu_szuka_pelnym_tekstem_i_mowi_o_tym(srodowisko):
    from wiedza_firmy.wektory import ModelNiedostepny

    class Zepsuty:
        model = "test/atrapa"
        wymiar = 64

        def pytanie(self, tekst):
            raise ModelNiedostepny("brak pliku")

    srodowisko.baza.wektoryzator = Zepsuty()
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("ania-a"), "zielona papuga")
    assert "papuga" in odp["wyniki"][0]["tresc"].lower()
    assert any("tylko pelnotekstowe" in u for u in odp["uwagi"])


def test_4_sama_baza_nie_zwraca_nic_dla_pustych_uprawnien(srodowisko):
    """Druga warstwa: nawet z pominieciem wczesnego wyjscia w Wiedza warunek SQL nie wpuszcza niczego."""
    for upr in (srodowisko.upr("bez-uprawnien"), srodowisko.zrodlo.uprawnienia("nowy-komputer"),
                Uprawnienia(osoba="x", tematy={"temat-a": "tajne"})):
        surowe = srodowisko.baza.szukaj("zielona papuga turkusowy zyrafa granatowy jez", upr, limit=50)
        assert surowe["wyniki"] == [] and surowe["ukryte"] == []
