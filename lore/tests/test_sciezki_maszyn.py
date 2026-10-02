"""A fact may name the path on each of the user's two machines — the other machine's path is not
a broken fact. A missing path with no such tie must still be flagged."""

from __future__ import annotations

import json

import pytest

from lore import verify

HOME = "D:\\OrcaSpace\\MegaRuchacz"
MISSING = "C:\\nie-ma-takiego-katalogu\\plik.js"


def existing(tmp_path) -> str:
    p = tmp_path / "claude-worker"
    p.mkdir()
    return str(p)


def audit(line: str):
    return verify.audit_rules(["### Nad czym pracuje", "", line, ""], day="2026-09-25")


def test_a_path_on_the_home_machine_is_not_flagged(tmp_path):
    here = existing(tmp_path)
    line = (f"- **MegaRuchacz** — repozytorium `Primo2966/MegaRuchacz`; na biurowej w `{here}`, "
            f"na domowej w `{HOME}`.")

    a = audit(line)

    assert a.stale == []
    assert "niepotwierdzone" not in "\n".join(a.body)


def test_a_home_path_alone_is_not_flagged_either():
    for text in (f"Na domowej repo leży w `{HOME}`.",
                 f"W domu kopia stoi w {HOME}.",
                 f"Domowy komputer trzyma kopię w `{HOME}`."):
        assert verify.verify(text).missing == [], text


def test_a_plain_missing_path_is_still_flagged():
    a = audit(f"- Robot do Alibaby leży w `{MISSING}`.")

    assert a.stale == [(f"Robot do Alibaby leży w `{MISSING}`.", [MISSING])]
    assert f"<!-- niepotwierdzone 2026-09-25: nie ma {MISSING} -->" in "\n".join(a.body)


def test_a_missing_path_next_to_a_home_path_is_still_flagged():
    # the home path is let go, the office one — named without any tie — is not
    text = f"Na biurowej robot leży w `{MISSING}`; na domowej w `{HOME}`."
    assert verify.verify(text).missing == [MISSING]


def test_a_home_directory_is_not_the_home_machine():
    # 'katalog domowy' is the user's profile folder on THIS machine — must still be checked
    assert verify.verify(f"Katalog domowy to `{MISSING}`.").missing == [MISSING]


def test_the_false_alarm_of_2026_09_25_heals(tmp_path):
    here = existing(tmp_path)
    line = (f"- Repozytorium na biurowej w `{here}`, na domowej w `{HOME}`. "
            f"<!-- niepotwierdzone 2026-09-25: nie ma {HOME} -->")

    a = audit(line)

    assert a.stale == []
    assert len(a.healed) == 1
    assert "niepotwierdzone" not in "\n".join(a.body)


# ---------------------------------------------------------------- the words of THIS machine (P67)
# The names of the user's other computers and his account on the second machine are not written in
# the code (the repository is public) - they come from ~/.claude/mr/lokalne.json.

def local_settings(tmp_path, monkeypatch, content) -> None:
    p = tmp_path / "lokalne.json"
    if isinstance(content, bytes):
        p.write_bytes(content)
    else:
        p.write_text(json.dumps(content), encoding="utf-8")
    monkeypatch.setattr(verify, "LOCAL_SETTINGS", p)


def test_probe_without_local_settings_no_personal_name_ties_a_path(tmp_path, monkeypatch):
    monkeypatch.setattr(verify, "LOCAL_SETTINGS", tmp_path / "nie-ma.json")
    assert verify.machine_words().problem == ""  # no file is not a fault
    assert verify.verify(f"U jan repo leży w `{MISSING}`.").missing == [MISSING]
    assert verify.verify(f"Na magazyn2 robot leży w `{MISSING}`.").missing == [MISSING]


def test_the_account_on_the_second_machine_comes_from_local_settings(tmp_path, monkeypatch):
    local_settings(tmp_path, monkeypatch, {"lore": {"druga_maszyna": ["jan"]}})

    assert verify.verify(f"U jan repo leży w `{MISSING}`.").missing == []
    # the path with no tie to that machine is still flagged
    assert verify.verify(f"Na biurowej robot leży w `{MISSING}`; u jan w `{HOME}`.").missing == [MISSING]


def test_another_computer_from_local_settings_makes_the_fact_uncheckable(tmp_path, monkeypatch):
    local_settings(tmp_path, monkeypatch, {"lore": {"inne_komputery": ["magazyn2"]}})

    assert verify.verify(f"Na Magazyn2 robot leży w `{MISSING}`.").checks == []


@pytest.mark.parametrize("content", [b'{"lore": \x00\x00\x00\x00', b"to nie jest json", b"[1, 2]",
                                     b'{"lore": {"druga_maszyna": "jan"}}'])
def test_probe_unreadable_local_settings_are_not_silent(tmp_path, monkeypatch, content):
    local_settings(tmp_path, monkeypatch, content)

    words = verify.machine_words()

    assert words.problem and words.elsewhere == () and words.other_machine == ()
    # the general words go on working
    assert verify.verify(f"Na domowej repo leży w `{HOME}`.").missing == []
