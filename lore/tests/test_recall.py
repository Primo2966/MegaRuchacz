"""Automatic recall glued to every message: what it finds, what it refuses, and that the hook
survives it failing. Own database in tmp_path; the real ~/.claude is never touched."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from lore import db, recall

NOW = datetime(2026, 9, 24, 12, 0, tzinfo=timezone.utc)
LORE_DIR = Path(__file__).resolve().parents[1]
HOOK = LORE_DIR.parent / "narzedzia" / "przypomnienie.js"
RULES = "ZASADY: odpowiadaj w sekundach, rozdawaj w tle."

FILLER = [
    "Dzisiaj porzadkowalismy pliki konfiguracyjne serwera i nic wiecej sie nie wydarzylo.",
    "Kolejka zadan jest pusta, logi czyste, kopia zapasowa zrobiona o polnocy.",
    "Uzytkownik poprosil o krotkie podsumowanie tygodnia bez szczegolow technicznych.",
]


def add(environment, text: str, session: str = "old-session", role: str = "assistant",
        days_ago: int = 10, project: str = "c--dev-sklep") -> int:
    conn = environment.conn
    ts = (NOW - timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    line = conn.execute("SELECT coalesce(max(line), 0) + 1 FROM chunks").fetchone()[0]
    cid = conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at) VALUES (?,?,?,?,?,?,?,?,?)",
        (project, session, f"{session}.jsonl", line, 0, ts, role, text, ts),
    ).lastrowid
    conn.execute("INSERT INTO chunks_fts(rowid, text) VALUES (?,?)", (cid, text))
    return cid


@pytest.fixture
def archive(environment):
    for i, t in enumerate(FILLER * 5):
        add(environment, t, session=f"filler-{i}")
    return environment


def ask(environment, prompt: str, session: str = "current", budget: int = 450, exclude=None) -> dict:
    return recall.recall(prompt, session, budget, environment.conn, exclude=exclude, now=NOW)


# ---------------------------------------------------------------- what it finds


def test_finds_the_old_decision_and_labels_it_as_a_lead(archive):
    cid = add(archive, "Tytuly ofert na eBayu maja limit 80 znakow, najmocniejsza fraza z zakupami idzie na poczatek.",
              days_ago=7)
    out = ask(archive, "ustaw tytul oferty na ebayu, limit znakow")
    assert out["status"] == "hits"
    assert out["ids"] == [cid]
    block = out["block"]
    assert block.startswith(recall.HEADER)
    assert "trop, nie dowod" in block and "nieaktualne" in block
    assert f"#{cid}" in block and "sprzed 7 dni" in block and "2026-09-17" in block


def test_short_messages_are_not_searched_at_all(archive):
    for prompt in ("ok", "tak", ".", "dzieki!"):
        out = ask(archive, prompt)
        assert out["status"] == "skipped" and out["block"] == ""


def test_one_shared_word_is_not_enough(archive):
    add(archive, "Faktura za serwer przyszla wczoraj i jest oplacona.")
    out = ask(archive, "ustaw tytul oferty na ebayu, faktura")
    assert out["status"] == "empty" and out["block"] == ""


def test_the_current_conversation_is_an_echo_not_memory(archive):
    add(archive, "Tytuly ofert na eBayu maja limit 80 znakow.", session="current")
    out = ask(archive, "tytuly ofert na ebayu limit znakow", session="current")
    assert out["block"] == ""


def test_what_was_already_glued_in_is_not_repeated(archive):
    first = add(archive, "Tytuly ofert na eBayu maja limit 80 znakow, fraza z zakupami na poczatek.", session="a")
    second = add(archive, "Na eBayu tytul oferty ma limit 80 znakow; wolne miejsce wypelnia konkretny zapach.", session="b")
    one = ask(archive, "tytul oferty ebay limit znakow")
    assert one["ids"] and set(one["ids"]) <= {first, second}
    again = ask(archive, "tytul oferty ebay limit znakow", exclude=one["ids"])
    assert not set(again["ids"]) & set(one["ids"])


def test_tool_output_is_not_a_memory(archive):
    add(archive, "tytul oferty ebay limit znakow 80 " * 5, role="tool")
    add(archive, "tytul oferty ebay limit znakow 80 " * 5, role="result")
    out = ask(archive, "tytul oferty ebay limit znakow")
    assert out["block"] == ""


def test_the_block_never_exceeds_the_budget(archive):
    for i in range(6):
        add(archive, ("Kadzidelka backflow biala szalwia numer 31 zdjecia na dysku. " * 12) + str(i), session=f"s{i}")
    for budget in (200, 260, 300, 450, 800):
        out = ask(archive, "kadzidelka backflow biala szalwia numer 31 zdjecia", budget=budget)
        assert len(out["block"]) <= budget, budget
    assert ask(archive, "kadzidelka backflow biala szalwia numer 31", budget=80)["status"] == "skipped"


def test_the_same_fact_told_twice_is_glued_in_once(archive):
    text = "Numeracja kadzidelek nie pokrywa sie z numeracja olejkow: 31 to szalwia albo biala szalwia."
    add(archive, text, session="a")
    add(archive, "Przypomnienie. " + text, session="b")
    out = ask(archive, "kadzidelka biala szalwia numer 31 numeracja olejkow")
    assert len(out["ids"]) == 1


# ---------------------------------------------------------------- plumbing


def test_polish_endings_still_match():
    assert recall._terms("zapachy ebayu robot") == ["zapac*", "ebay*", "robot*"]
    assert recall.fold("Łódź żółć") == "lodz zolc"


def test_data_home_follows_the_same_rule_as_lore_db(tmp_path, monkeypatch):
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path))
    monkeypatch.delenv("LORE_HOME", raising=False)
    monkeypatch.delenv("CLAUDE_HISTORIA_HOME", raising=False)
    assert recall.data_home() == db._data_home() == tmp_path / ".lore"
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "lore.db").write_text("", encoding="utf-8")
    assert recall.data_home() == db._data_home() == tmp_path / ".claude"
    monkeypatch.setenv("LORE_HOME", str(tmp_path / "x"))
    assert recall.data_home() == db._data_home() == tmp_path / "x"


def test_the_database_is_opened_read_only(archive, tmp_path):
    conn = recall.open_readonly(tmp_path / "lore.db")
    with pytest.raises(Exception):
        conn.execute("DELETE FROM chunks")
    conn.close()


def _run_module(tmp_path: Path, payload: dict) -> dict:
    env = dict(os.environ, LORE_HOME=str(tmp_path), PYTHONIOENCODING="utf-8")
    r = subprocess.run([sys.executable, "-m", "lore.recall"], cwd=LORE_DIR, input=json.dumps(payload),
                       capture_output=True, text=True, encoding="utf-8", env=env, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout.strip().splitlines()[-1])


def test_missing_database_is_an_error_not_silence(tmp_path):
    out = _run_module(tmp_path / "nothing-here", {"prompt": "tytul oferty ebay limit znakow", "budget": 450})
    assert out["status"] == "error" and "lore.db" in out["reason"] and out["block"] == ""


# ---------------------------------------------------------------- the hook itself (node)

node = shutil.which("node")
needs_node = pytest.mark.skipif(node is None, reason="no node on this machine")


def _hook(tmp_path: Path, payload, **env) -> tuple[str, dict]:
    reminder = tmp_path / "reminder.json"
    reminder.write_text(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                           "additionalContext": RULES}}), encoding="utf-8")
    state = tmp_path / "state.json"
    full_env = dict(os.environ, MR_ARCHIWUM_STAN=str(state), MR_LORE_PYTHON=sys.executable, LORE_HOME=str(tmp_path))
    full_env.update(env)
    r = subprocess.run([node, str(HOOK), str(reminder), str(tmp_path / "no-progress")],
                       input=payload if isinstance(payload, str) else json.dumps(payload),
                       capture_output=True, text=True, encoding="utf-8", env=full_env, timeout=30)
    assert r.returncode == 0, r.stderr
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    return ctx, json.loads(state.read_text(encoding="utf-8"))


@needs_node
def test_hook_glues_the_hit_after_the_rules(archive, tmp_path):
    cid = add(archive, "Tytuly ofert na eBayu maja limit 80 znakow, najmocniejsza fraza z zakupami idzie na poczatek.")
    ctx, state = _hook(tmp_path, {"session_id": "s1", "prompt": "ustaw tytul oferty na ebayu, limit znakow"})
    assert ctx.startswith(RULES)
    assert f"#{cid}" in ctx and recall.HEADER in ctx
    assert state["wynik"] == "hits" and state["sesje"]["s1"]["ids"] == [cid]
    # the same conversation asks again: the fragment is already in its history
    ctx2, state2 = _hook(tmp_path, {"session_id": "s1", "prompt": "ustaw tytul oferty na ebayu, limit znakow"})
    assert f"#{cid}" not in ctx2


@needs_node
@pytest.mark.parametrize("case, payload, env", [
    ("no database", {"session_id": "s", "prompt": "tytul oferty ebay limit znakow"}, {"LORE_HOME": "__missing__"}),
    ("no python", {"session_id": "s", "prompt": "tytul oferty ebay limit znakow"}, {"MR_LORE_PYTHON": "__missing__"}),
    ("empty input", "", {}),
    ("input without prompt", {"session_id": "s"}, {}),
])
def test_hook_keeps_the_rules_whole_and_leaves_a_trace(archive, tmp_path, case, payload, env):
    env = {k: (str(tmp_path / "missing" / "x") if v == "__missing__" else v) for k, v in env.items()}
    ctx, state = _hook(tmp_path, payload, **env)
    assert RULES in ctx, case
    assert ctx.startswith("UWAGA: podpowiedz z archiwum (Lore) nie dziala"), case
    assert state["wynik"] == "awaria" and state["awaria"]["ile"] == 1, case
    # the same failure again: still in the state, but not shouted at every message
    ctx2, state2 = _hook(tmp_path, payload, **env)
    assert ctx2 == RULES and state2["awaria"]["ile"] == 2, case
