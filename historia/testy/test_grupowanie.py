"""Sklejanie kolejnych wypowiedzi w jeden kawałek."""

from __future__ import annotations

from historia.indeksuj import (
    DLUGOSC_KAWALKA,
    ROLA_MIESZANA,
    ZAKLADKA,
    Wypowiedz,
    _fragmenty_z_grupy,
    pogrupuj,
)

TS = "2026-09-16T10:00:00.000Z"


def w(rola: str, tekst: str, linia: int = 1) -> Wypowiedz:
    return Wypowiedz(linia, TS, rola, tekst)


def kawalki(grupa, prefiks_roli: str = "") -> list[str]:
    return [f.tekst for f in _fragmenty_z_grupy(grupa, prefiks_roli)]


def test_krotkie_wypowiedzi_lada_w_jednym_kawalku():
    wypowiedzi = [
        w("user", "Czy mam przepiąć indekser na nowy model?", 1),
        w("assistant", "Proponuję e5-small, jest mniejszy.", 2),
        w("user", "tak, rób to", 3),
    ]
    grupy = pogrupuj(wypowiedzi)
    assert len(grupy) == 1
    (tekst,) = kawalki(grupy[0])
    assert tekst == (
        "user: Czy mam przepiąć indekser na nowy model?\n\n"
        "assistant: Proponuję e5-small, jest mniejszy.\n\n"
        "user: tak, rób to"
    )


def test_pojedyncza_wypowiedz_bez_prefiksu_roli():
    (grupa,) = pogrupuj([w("user", "samotne zdanie")])
    assert kawalki(grupa) == ["samotne zdanie"]


def test_grupa_nie_przekracza_limitu():
    wypowiedzi = [w("assistant" if i % 2 else "user", "a" * 200, i + 1) for i in range(30)]
    grupy = pogrupuj(wypowiedzi)
    assert len(grupy) > 1
    for g in grupy:
        for tekst in kawalki(g):
            assert len(tekst) <= DLUGOSC_KAWALKA


def test_dluga_wypowiedz_tnie_sie_z_zakladka_i_nie_skleja_sie():
    dluga = "x" * 4000
    wypowiedzi = [w("user", "krótkie przed", 1), w("assistant", dluga, 2), w("user", "krótkie po", 3)]
    grupy = pogrupuj(wypowiedzi)
    assert [len(g) for g in grupy] == [1, 1, 1]
    czesci = kawalki(grupy[1])
    assert len(czesci) > 1
    assert all(len(c) <= DLUGOSC_KAWALKA for c in czesci)
    assert czesci[0] == dluga[:DLUGOSC_KAWALKA]
    assert czesci[1][:ZAKLADKA] == czesci[0][-ZAKLADKA:]  # zakładka 200 znaków
    assert "assistant:" not in czesci[0]


def test_rola_jednorodna_i_mieszana():
    (jednorodna,) = pogrupuj([w("user", "pierwsze", 1), w("user", "drugie", 2)])
    assert _fragmenty_z_grupy(jednorodna, "")[0].rola == "user"

    (mieszana,) = pogrupuj([w("user", "pytanie", 1), w("assistant", "odpowiedź", 2)])
    assert _fragmenty_z_grupy(mieszana, "")[0].rola == ROLA_MIESZANA


def test_rola_mieszana_zachowuje_prefiks_subagenta():
    (grupa,) = pogrupuj([w("agent:user", "pytanie", 1), w("agent:assistant", "odpowiedź", 2)])
    assert _fragmenty_z_grupy(grupa, "agent:")[0].rola == "agent:" + ROLA_MIESZANA


def test_numer_linii_i_czesci_z_poczatku_grupy():
    (grupa,) = pogrupuj([w("user", "pierwsze", 7), w("assistant", "drugie", 8)])
    fragmenty = _fragmenty_z_grupy(grupa, "")
    assert [(f.linia, f.czesc) for f in fragmenty] == [(7, 0)]
