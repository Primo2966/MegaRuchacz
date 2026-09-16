"""Przyrostowość: otwarty ogon pliku, wznowienie i brak duplikatów."""

from __future__ import annotations

import os
import time

DLUGA = "x" * 2000  # dłuższa niż kawałek — własna grupa, cięta na dwie części
INNA_DLUGA = "y" * 2000
DAWNO = 48 * 60 * 60


def test_otwarty_ogon_nie_trafia_do_bazy(srodowisko):
    p = srodowisko.transkrypt(("user", "Czy przepinamy indekser?"), ("assistant", "Proponuję e5-small."))

    assert srodowisko.indeksuj(p) == 0  # grupa może jeszcze urosnąć
    assert srodowisko.teksty() == []
    assert srodowisko.stan_pliku(p)[2] == 0  # offset stoi przed otwartą grupą


def test_domkniecie_grupy_zapisuje_sklejona_pare(srodowisko):
    p = srodowisko.transkrypt(("user", "Czy przepinamy indekser?"), ("assistant", "Proponuję e5-small."))
    srodowisko.indeksuj(p)
    srodowisko.dopisz(p, ("assistant", DLUGA))

    assert srodowisko.indeksuj(p) == 3  # sklejona para + dwie części długiej wypowiedzi
    linia, czesc, rola, tekst = srodowisko.wiersze()[0]
    assert (linia, czesc, rola) == (1, 0, "rozmowa")
    assert tekst == "user: Czy przepinamy indekser?\n\nassistant: Proponuję e5-small."


def test_wznowienie_dokłada_dane_i_nie_dubluje(srodowisko):
    p = srodowisko.transkrypt(("user", "Czy przepinamy indekser?"), ("assistant", "Proponuję e5-small."))
    srodowisko.indeksuj(p)
    srodowisko.dopisz(p, ("assistant", DLUGA))
    srodowisko.indeksuj(p)
    po_domknieciu = srodowisko.teksty()

    srodowisko.dopisz(p, ("user", "tak, rób to"))
    assert srodowisko.indeksuj(p) == 0  # znów otwarty ogon
    assert srodowisko.teksty() == po_domknieciu

    srodowisko.dopisz(p, ("assistant", "Zrobione, indekser chodzi."), ("user", INNA_DLUGA))
    assert srodowisko.indeksuj(p) == 3  # nowa sklejona para + długa wypowiedź
    teksty = srodowisko.teksty()
    assert teksty[:len(po_domknieciu)] == po_domknieciu
    assert teksty[len(po_domknieciu)] == "user: tak, rób to\n\nassistant: Zrobione, indekser chodzi."
    assert len(teksty) == len(set(teksty))


def test_brak_duplikatow_przy_dwukrotnym_indeksowaniu(srodowisko):
    p = srodowisko.transkrypt(
        ("user", "Czy przepinamy indekser?"),
        ("assistant", "Proponuję e5-small."),
        ("user", "tak, rób to"),
        ("assistant", DLUGA),
    )
    assert srodowisko.indeksuj(p) == 3
    pierwsze = srodowisko.wiersze()

    assert srodowisko.indeksuj(p) == 0  # nic się nie zmieniło
    assert srodowisko.wiersze() == pierwsze

    # wymuszone ponowne przeczytanie całego pliku (np. po utracie stanu) nie dokłada drugiej kopii
    srodowisko.conn.execute("UPDATE pliki SET mtime=0, offset=0, linia=0 WHERE sciezka=?", (str(p),))
    assert srodowisko.indeksuj(p) == 3
    assert [(c, r, t) for _, c, r, t in srodowisko.wiersze()] == [(c, r, t) for _, c, r, t in pierwsze]


def test_stary_plik_domyka_ogon(srodowisko):
    p = srodowisko.transkrypt(("user", "Czy przepinamy indekser?"), ("assistant", "Proponuję e5-small."))
    assert srodowisko.indeksuj(p) == 0

    dawno = time.time() - DAWNO
    os.utime(p, (dawno, dawno))
    # stan w bazie zgadza się z plikiem — ogon domykamy mimo braku zmian
    srodowisko.conn.execute(
        "UPDATE pliki SET mtime=?, rozmiar=? WHERE sciezka=?", (p.stat().st_mtime, p.stat().st_size, str(p))
    )

    assert srodowisko.indeksuj(p) == 1
    assert srodowisko.teksty() == ["user: Czy przepinamy indekser?\n\nassistant: Proponuję e5-small."]
    assert srodowisko.stan_pliku(p)[2] == p.stat().st_size
    assert srodowisko.indeksuj(p) == 0  # domknięty ogon nie wraca


def test_pojedyncza_dluga_wypowiedz_zapisuje_sie_od_razu(srodowisko):
    p = srodowisko.transkrypt(("assistant", DLUGA))

    assert srodowisko.indeksuj(p) == 2  # długiej wypowiedzi nie ma z czym sklejać
    assert [(c, r) for _, c, r, _ in srodowisko.wiersze()] == [(0, "assistant"), (1, "assistant")]
