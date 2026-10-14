"""Testy tematow dodatkowych (przetaguj.py). Model to atrapa (atrapa_przetaguj.py), dane wymyslone.

    uv --directory C:\\dev\\claude-worker\\lore run pytest C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-przeglad\\tests -q
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

TU = Path(__file__).resolve().parent
REPO = TU.parents[2]
sys.path.insert(0, str(TU.parent))
sys.path.insert(0, str(REPO / "wiedza_firmy"))

import przetaguj as T  # noqa: E402
from wiedza_firmy.importuj import parsuj as parsuj_serwera  # noqa: E402

TEMATY = [
    {"id": "grafiki", "nazwa": "Grafiki", "opis": "atrapa", "osobne_uprawnienie": False},
    {"id": "oferty", "nazwa": "Oferty", "opis": "atrapa", "osobne_uprawnienie": False},
    {"id": "zgodnosc", "nazwa": "Zgodnosc", "opis": "atrapa", "osobne_uprawnienie": False},
    {"id": "seo", "nazwa": "SEO", "opis": "atrapa", "osobne_uprawnienie": True},
    {"id": "firma", "nazwa": "Firma i ludzie", "opis": "atrapa", "osobne_uprawnienie": False},
    {"id": "kadry", "nazwa": "Sprawy kadrowe", "opis": "atrapa", "osobne_uprawnienie": True},
]

PLIK_A = """# UWAGA: NIEPELNE - atrapa ostrzezenia
# Wiedza firmy - temat grafiki
autor: Primo
program: claude-code
zrodlo: test
poufnosc: wewnetrzne

## temat: grafiki
- [2026-10-01] [jawne] Komplet zdjęć oferty to MAIN i PT01–PT06. TAG=oferty
- [2026-10-02] Wpis bez poziomu dostaje poziom jawnie. TAG=oferty,seo
- [2026-10-03] [wewnetrzne] Wpis bez tematów dodatkowych zostaje bez zmian.
- [2026-10-04] [wrazliwe] Wpis z ciągiem dalszym TAG=zgodnosc
  w drugiej linii, która zostaje.
- [2026-10-05] [wewnetrzne] Wpis o SDS ewidentnie nie o grafikach. PRZENIES=zgodnosc TAG=grafiki
- [2026-10-06] [jawne] Wpis do tematu, którego w pliku nie ma. PRZENIES=oferty

# === Do decyzji Primo ===
# - [2026-10-07] [wewnetrzne] Zakomentowany wpis zostaje doslownie.
"""

PLIK_B = """autor: Primo
poufnosc: jawne

## temat: oferty
- [2026-10-01] Oferta na PL ma ten sam SKU i ASIN. TAG=grafiki
- [2026-10-02] [wewnetrzne] Drugi wpis ofert.

## temat: zgodnosc
- [2026-10-03] [wewnetrzne] Olejków nie zaleca się na skórę.
"""


@pytest.fixture
def srodowisko(tmp_path, monkeypatch):
    tematy = tmp_path / "tematy.json"
    tematy.write_text(json.dumps(TEMATY), encoding="utf-8")
    wej = tmp_path / "wejscie"
    wej.mkdir()
    (wej / "grafiki.md").write_text(PLIK_A, encoding="utf-8")
    (wej / "wsad-b.md").write_text(PLIK_B, encoding="utf-8")
    log = tmp_path / "wywolania"
    monkeypatch.setenv("WIEDZA_PRZEGLAD_CLAUDE", json.dumps([sys.executable, str(TU / "atrapa_przetaguj.py")]))
    monkeypatch.setenv("ATRAPA_LOG", str(log))
    for zmienna in ("ATRAPA_PADA_NA", "ATRAPA_ZMIEN_TRESC", "ATRAPA_GUB", "ATRAPA_NIEZNANY"):
        monkeypatch.delenv(zmienna, raising=False)

    class S:
        pass
    s = S()
    s.wej, s.wyj, s.log = wej, tmp_path / "otagowane", log
    s.argi = [str(wej / "grafiki.md"), str(wej / "wsad-b.md"), "--wyjscie", str(s.wyj), "--tematy", str(tematy),
              "--rownolegle", "2"]
    s.wywolania = lambda: len(list(log.iterdir())) if log.exists() else 0
    s.podsumowanie = lambda: (s.wyj / "PODSUMOWANIE.txt").read_text(encoding="utf-8")
    return s


def _bez_znacznikow(tekst: str) -> str:
    return re.sub(r"^(- \[[^\]]*\] \[[a-ząćęłńóśźż]+\]) \[\+[^\]]*\]", r"\1", tekst, flags=re.M)


def _serwer(tekst: str) -> list[tuple]:
    return sorted((w.temat, w.poufnosc, w.data_ustalenia, w.tresc, w.autor, w.zrodlo)
                  for w in parsuj_serwera(_bez_znacznikow(tekst)))


# ---------------------------------------------------------------- przebieg poprawny

def test_znaczniki_przeniesienia_i_format_serwera(srodowisko):
    assert T.main(srodowisko.argi) == 0
    a = (srodowisko.wyj / "grafiki.md").read_text(encoding="utf-8")
    linie = a.splitlines()
    assert linie[0].startswith("# UWAGA: NIEPELNE")  # ostrzezenie z wejscia zostaje na samej gorze
    assert linie[1].startswith("# Tematy dodatkowe ([+...]) dopisal przetaguj.py")
    assert "- [2026-10-01] [jawne] [+oferty] Komplet zdjęć oferty to MAIN i PT01–PT06. TAG=oferty" in linie
    assert "- [2026-10-02] [wewnetrzne] [+oferty,seo] Wpis bez poziomu dostaje poziom jawnie. TAG=oferty,seo" in linie
    assert "- [2026-10-03] [wewnetrzne] Wpis bez tematów dodatkowych zostaje bez zmian." in linie
    i = linie.index("- [2026-10-04] [wrazliwe] [+zgodnosc] Wpis z ciągiem dalszym TAG=zgodnosc")
    assert linie[i + 1] == "  w drugiej linii, która zostaje."
    assert "# - [2026-10-07] [wewnetrzne] Zakomentowany wpis zostaje doslownie." in linie
    # przeniesiony do istniejacej sekcji nie ma, wiec nowe sekcje na koncu pliku
    assert a.index("## temat: zgodnosc") > a.index("# === Do decyzji Primo ===")
    assert "[+grafiki] Wpis o SDS" in a
    # serwer (dzisiejszy parser, znaczniki zdjete) widzi te same wpisy co w oryginale, poza tematem przeniesionych
    oryg = _serwer(PLIK_A)
    wynik = _serwer(a)
    assert len(wynik) == len(oryg) == 6
    assert {(w[0], w[3][:10]) for w in wynik if w[0] != "grafiki"} == {("zgodnosc", "Wpis o SDS"),
                                                                        ("oferty", "Wpis do te")}
    assert sorted(w[1:] for w in wynik) == sorted(w[1:] for w in oryg)
    # oryginaly nietkniete
    assert (srodowisko.wej / "grafiki.md").read_text(encoding="utf-8") == PLIK_A
    pod = srodowisko.podsumowanie()
    assert pod.startswith("KOMPLET")
    assert "grafiki -> zgodnosc (atrapa: zly temat)" in pod
    assert "zawezona widocznosc (1)" in pod and "[+oferty,seo]" in pod


def test_przeniesiony_do_istniejacej_sekcji_trafia_na_jej_koniec(srodowisko):
    (srodowisko.wej / "wsad-b.md").write_text(PLIK_B.replace("Drugi wpis ofert.", "Drugi wpis ofert. PRZENIES=zgodnosc"),
                                             encoding="utf-8")
    assert T.main(srodowisko.argi) == 0
    b = (srodowisko.wyj / "wsad-b.md").read_text(encoding="utf-8").splitlines()
    assert b.count("## temat: zgodnosc") == 1
    assert b[-1] == "- [2026-10-02] [wewnetrzne] Drugi wpis ofert. PRZENIES=zgodnosc"
    assert b[-2] == "- [2026-10-03] [wewnetrzne] Olejków nie zaleca się na skórę."


def test_paczki_rownolegle_i_wznowienie(srodowisko):
    assert T.main([*srodowisko.argi, "--paczka", "3"]) == 0
    assert srodowisko.wywolania() == 3  # 9 wpisow po 3
    assert T.main([*srodowisko.argi, "--paczka", "3"]) == 0
    assert srodowisko.wywolania() == 3  # nic od nowa
    tsv = (srodowisko.wyj / ".stan" / "koszt.tsv").read_text(encoding="utf-8").splitlines()
    assert len(tsv) == 4 and all("\t180\t0.0040\tok:" in w for w in tsv[1:])  # zuzycie z koperty, nie zmyslone


def test_na_sucho_bez_wywolan(srodowisko, capsys):
    assert T.main([*srodowisko.argi, "--na-sucho", "--paczka", "4"]) == 0
    out = capsys.readouterr().out
    assert srodowisko.wywolania() == 0
    assert "do zrobienia: 9 w 3 paczkach" in out and "szacunek tokenow" in out
    assert not (srodowisko.wyj / "grafiki.md").exists()


def test_kadry_z_tematu_firma_przeniesione_i_widoczne_jako_specjalne(srodowisko):
    (srodowisko.wej / "firma.md").write_text(
        "autor: Primo\n\n## temat: firma\n- [2026-10-01] [jawne] Ela robi grafiki, Gosia obsługę klienta.\n"
        "- [2026-10-02] [wrazliwe] Umowa Eli kończy się w grudniu. PRZENIES=kadry\n", encoding="utf-8")
    assert T.main([*srodowisko.argi, str(srodowisko.wej / "firma.md")]) == 0
    f = (srodowisko.wyj / "firma.md").read_text(encoding="utf-8")
    assert f.index("## temat: kadry") < f.index("- [2026-10-02] [wrazliwe] Umowa Eli")
    assert f.index("## temat: firma") < f.index("- [2026-10-01] [jawne] Ela robi") < f.index("## temat: kadry")
    pod = srodowisko.podsumowanie()
    assert "firma.md:5 firma -> kadry" in pod
    assert "Z tematem SPECJALNYM (kadry, seo) - zawezona widocznosc (2)" in pod


def test_prompt_ma_regule_kadr_tylko_z_oboma_tematami():
    pelna = T.instrukcja(TEMATY)
    assert "- kadry: sprawy kadrowe" in pelna and "- seo: frazy i wyniki Search Query Performance" in pelna
    assert "przenieś temat główny na kadry" in pelna
    bez_kadr = T.instrukcja([t for t in TEMATY if t["id"] != "kadry"])
    assert "kadry" not in bez_kadr.split("## Tematy")[0]


# ---------------------------------------------------------------- proby negatywne

def _odmowa(srodowisko, oczekiwane: str):
    assert T.main(srodowisko.argi) == 1
    assert not (srodowisko.wyj / "grafiki.md").exists() and not (srodowisko.wyj / "wsad-b.md").exists()
    pod = srodowisko.podsumowanie()
    assert pod.startswith("NIEPELNE") and oczekiwane in pod, pod
    assert list((srodowisko.wyj / ".stan" / "bledy").glob("*.json"))


def test_model_zmienia_tresc_to_odmowa(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_ZMIEN_TRESC", "1")
    _odmowa(srodowisko, "model zmienil tresc albo pomylil wpisy")


def test_model_gubi_wpis_to_odmowa(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_GUB", "1")
    _odmowa(srodowisko, "model zgubil wpisy: W9")


def test_nieznany_temat_to_odmowa(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_NIEZNANY", "1")
    _odmowa(srodowisko, "nieznany temat nie-ma-takiego")


def test_odrzucona_odpowiedz_jest_w_dzienniku_z_tokenami(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_GUB", "1")
    assert T.main(srodowisko.argi) == 1
    tsv = (srodowisko.wyj / ".stan" / "koszt.tsv").read_text(encoding="utf-8")
    assert "\t180\t0.0040\tODRZUCONE:" in tsv  # za odrzucona odpowiedz tez sie placi


def test_nieudana_paczka_widoczna_a_ponowienie_robi_tylko_ja(srodowisko, monkeypatch):
    monkeypatch.setenv("ATRAPA_PADA_NA", "Olejków nie zaleca")  # pada paczka z ostatnim wpisem pliku B
    assert T.main([*srodowisko.argi, "--paczka", "3"]) == 1
    assert (srodowisko.wyj / "grafiki.md").exists()  # jego paczki przeszly
    assert not (srodowisko.wyj / "wsad-b.md").exists()
    pod = srodowisko.podsumowanie()
    assert pod.startswith("NIEPELNE") and "atrapa: awaria na zyczenie" in pod
    assert "wsad-b.md: NIE ZAPISANY" in pod
    przed = srodowisko.wywolania()
    monkeypatch.delenv("ATRAPA_PADA_NA")
    assert T.main([*srodowisko.argi, "--paczka", "3"]) == 0
    assert srodowisko.wywolania() == przed + 1
    assert (srodowisko.wyj / "wsad-b.md").exists() and srodowisko.podsumowanie().startswith("KOMPLET")
    assert not list((srodowisko.wyj / ".stan" / "bledy").glob("*.json"))


def test_stary_wynik_znika_gdy_plik_nieudany(srodowisko, monkeypatch):
    assert T.main(srodowisko.argi) == 0
    assert (srodowisko.wyj / "wsad-b.md").exists()
    (srodowisko.wej / "wsad-b.md").write_text(PLIK_B + "- [2026-10-09] [jawne] Nowy wpis Olejków.\n", encoding="utf-8")
    monkeypatch.setenv("ATRAPA_PADA_NA", "Nowy wpis")
    assert T.main(srodowisko.argi) == 1
    assert not (srodowisko.wyj / "wsad-b.md").exists()  # nie udaje aktualnego


def test_zapis_zmieniajacy_tresc_to_odmowa(srodowisko, monkeypatch):
    prawdziwe = T.zloz
    monkeypatch.setattr(T, "zloz", lambda *a: prawdziwe(*a).replace("Drugi wpis ofert.", "Drugi wpis OFERT."))
    assert T.main(srodowisko.argi) == 1
    assert not (srodowisko.wyj / "wsad-b.md").exists()
    assert (srodowisko.wyj / "grafiki.md").exists()
    assert "wsad-b.md: NIE ZAPISANY - ODMOWA zapisu - wynik rozni sie od wejscia" in srodowisko.podsumowanie()


def test_zapis_gubiacy_wpis_to_odmowa(srodowisko, monkeypatch):
    prawdziwe = T.zloz
    monkeypatch.setattr(T, "zloz", lambda *a: prawdziwe(*a).replace(
        "- [2026-10-02] [wewnetrzne] Drugi wpis ofert.\n", ""))
    assert T.main(srodowisko.argi) == 1
    assert not (srodowisko.wyj / "wsad-b.md").exists()
    assert "liczba wpisow: wejscie 3, wynik 2" in srodowisko.podsumowanie()


def test_przeniesienie_zmieniajace_autora_to_odmowa(srodowisko):
    (srodowisko.wej / "wsad-b.md").write_text(
        "autor: Primo\npoufnosc: jawne\n\n## temat: oferty\n- [2026-10-01] Wpis Primo. PRZENIES=zgodnosc\n\n"
        "autor: Ela\n## temat: zgodnosc\n- [2026-10-02] Wpis Eli.\n", encoding="utf-8")
    assert T.main(srodowisko.argi) == 1
    assert not (srodowisko.wyj / "wsad-b.md").exists()
    assert "brak albo zmieniony wpis w wyniku: 'Wpis Primo. PRZENIES=zgodnosc'" in srodowisko.podsumowanie()


def test_wejscie_juz_otagowane_to_odmowa(srodowisko):
    (srodowisko.wej / "wsad-b.md").write_text(PLIK_B.replace("[wewnetrzne] Drugi", "[wewnetrzne] [+seo] Drugi"),
                                             encoding="utf-8")
    assert T.main(srodowisko.argi) == 1
    assert "wejscie juz ma tematy dodatkowe" in srodowisko.podsumowanie()


def test_nieznany_temat_na_wejsciu_to_odmowa(srodowisko):
    (srodowisko.wej / "wsad-b.md").write_text(PLIK_B.replace("## temat: oferty", "## temat: nie-ma"), encoding="utf-8")
    assert T.main(srodowisko.argi) == 1
    assert "tematy spoza listy: nie-ma" in srodowisko.podsumowanie()


def test_wyjscie_w_katalogu_wejscia_to_odmowa(srodowisko):
    argi = [*srodowisko.argi]
    argi[argi.index("--wyjscie") + 1] = str(srodowisko.wej)
    assert T.main(argi) == 2


# ---------------------------------------------------------------- sprawdzenie odpowiedzi

def _paczka():
    p = T.parsuj(PLIK_B, "b.md")
    return p.wpisy


@pytest.mark.parametrize("zla, powod", [
    ({"wpisy": [{"id": "W1", "poczatek": "Oferta na PL", "temat": "oferty", "dodatkowe": []},
                {"id": "W1", "poczatek": "Oferta na PL", "temat": "oferty", "dodatkowe": []},
                {"id": "W3", "poczatek": "Olejków nie zaleca", "temat": "zgodnosc", "dodatkowe": []}]}, "dwa razy"),
    ({"wpisy": [{"id": "W1", "poczatek": "Oferta", "temat": "oferty", "dodatkowe": []},
                {"id": "W2", "poczatek": "Drugi wpis ofert", "temat": "oferty", "dodatkowe": []},
                {"id": "W3", "poczatek": "Olejków nie zaleca", "temat": "zgodnosc", "dodatkowe": []},
                {"id": "W4", "poczatek": "Dodany", "temat": "oferty", "dodatkowe": []}]}, "nieznany identyfikator"),
    ({"wpisy": [{"id": "W1", "poczatek": "", "temat": "oferty", "dodatkowe": []}]}, "nie pasuje"),
    ({"wpisy": [{"id": "W1", "poczatek": "Oferta na PL", "temat": "inny", "dodatkowe": []}]}, "nieznany temat"),
    ({"zle": []}, "bez listy"),
])
def test_odpowiedz_odrzucona(zla, powod):
    with pytest.raises(T.P.BladModelu, match=powod):
        T.sprawdz_odpowiedz(zla, _paczka(), {t["id"] for t in TEMATY})


def test_odpowiedz_przyjeta_bez_duplikatow_i_tematu_glownego_w_dodatkowych():
    d = T.sprawdz_odpowiedz({"wpisy": [
        {"id": "W1", "poczatek": "„Oferta na PL", "temat": "oferty", "dodatkowe": ["oferty", "grafiki", "grafiki"]},
        {"id": "W2", "poczatek": "Drugi wpis ofert", "temat": "oferty", "dodatkowe": []},
        {"id": "W3", "poczatek": "Olejków nie zaleca", "temat": "oferty", "dodatkowe": []}]},
        _paczka(), {t["id"] for t in TEMATY})
    assert d[0].dodatkowe == ["grafiki"]
    assert d[2].temat == "oferty" and d[2].powod == "(model nie podal powodu)"
