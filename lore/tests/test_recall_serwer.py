"""The recall server (lore/lore/recall_serwer.py) and the way the hook (narzedzia/przypomnienie.js) uses
it: same answers as recall.recall, one server at a time, self-replacement after an update, and the
negative cases — killed server, foreign process on the port, damaged answers, locked / replaced /
missing database, two hooks starting it at once. Own database in tmp_path; the real ~/.claude and the
real server are never touched, and no test server outlives its test (`sprzatacz`)."""

from __future__ import annotations

import json
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from lore import recall
from pomoc_serwera import (BEZ_OKNA, LORE_DIR, adres, base_python, czekaj, gotowy, procesy, sprzatnij, stan,
                           stan_hooka_pidy, uruchom, wyslij, zabij, zapytaj, zyje)
from test_recall import FILLER, add

HOOK = LORE_DIR.parent / "narzedzia" / "przypomnienie.js"
RULES = "ZASADY: odpowiadaj w sekundach, rozdawaj w tle."
ALARM = "UWAGA: podpowiedz z archiwum (Lore) nie dziala"
PROMPT = "ustaw tytul oferty na ebayu, limit znakow"
FACT = "Tytuly ofert na eBayu maja limit 80 znakow, najmocniejsza fraza z zakupami idzie na poczatek."

node = shutil.which("node")
needs_node = pytest.mark.skipif(node is None, reason="no node on this machine")


@pytest.fixture
def archive(environment):
    for i, t in enumerate(FILLER * 5):
        add(environment, t, session=f"filler-{i}")
    environment.fact = add(environment, FACT)
    environment.conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    return environment


@pytest.fixture
def sprzatacz(tmp_path):
    """After the test: every server of tmp_path stopped or killed, and proof that none is left."""
    pidy: list[int] = []
    yield pidy
    sprzatnij(tmp_path, *pidy, *stan_hooka_pidy(tmp_path / "state.json"), szukaj=True)
    assert procesy(str(tmp_path)) == [], "testowy serwer zostal w procesach"


def _hook(tmp_path: Path, prompt: str = PROMPT, session: str = "s1", state_name: str = "state.json",
          **env) -> tuple[str, dict, float]:
    reminder = tmp_path / "reminder.json"
    if not reminder.exists():
        reminder.write_text(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                               "additionalContext": RULES}}), encoding="utf-8")
    state = tmp_path / state_name
    full = dict(os.environ, MR_ARCHIWUM_STAN=str(state), MR_LORE_PYTHON=sys.executable, LORE_HOME=str(tmp_path),
                MR_INSTALACJA=str(tmp_path / "no-registry.json"), MR_INSTALACJA_ALARM=str(tmp_path / "reg-alarm.json"),
                MR_LORE_SERWER_BEZCZYNNOSC_S="60")
    full.update(env)
    t0 = time.monotonic()
    r = subprocess.run([node, str(HOOK), str(reminder), str(tmp_path / "no-progress")],
                       input=json.dumps({"session_id": session, "prompt": prompt}),
                       capture_output=True, text=True, encoding="utf-8", env=full, timeout=30)
    took = time.monotonic() - t0
    assert r.returncode == 0, r.stderr
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    return ctx, json.loads(state.read_text(encoding="utf-8")), took


def stan_gdy(dom: Path, warunek) -> dict:
    """The server writes its state right AFTER answering - wait for the write the test is about."""
    s = czekaj(lambda: (lambda x: x if x and warunek(x) else None)(stan(dom)), 5)
    assert s, f"stan serwera nie doszedl do oczekiwanego: {stan(dom)}"
    return s


def _hook_state(tmp_path: Path) -> dict:
    return json.loads((tmp_path / "state.json").read_text(encoding="utf-8"))


def _allow_new_start(tmp_path: Path) -> None:
    """Pretends the hook's last server start was long ago (the hook starts at most one per minute)."""
    s = _hook_state(tmp_path)
    s.setdefault("serwer", {})["start"] = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()
    (tmp_path / "state.json").write_text(json.dumps(s), encoding="utf-8")


class Obcy:
    """Something else listening on a port: `tryb` = what it does with a connection."""

    def __init__(self, tryb: str):
        self.tryb = tryb
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(8)
        self.port = self.sock.getsockname()[1]
        self.polaczen = 0
        self.zywy = True
        threading.Thread(target=self._petla, daemon=True).start()

    def _petla(self):
        while self.zywy:
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            self.polaczen += 1
            try:
                c.settimeout(2)
                try:
                    c.recv(65536)
                except OSError:
                    pass  # some modes do not care what came
                if self.tryb == "smieci":
                    c.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n\n")
                elif self.tryb == "json-bez-statusu":
                    c.sendall(b'{"block": "nic"}\n')
                elif self.tryb == "bez-konca-linii":
                    c.sendall(b"x" * (1024 * 1024 + 10))
                elif self.tryb == "milczy":
                    time.sleep(1.5)
                # "zamyka": close at once, without a word
            except OSError:
                pass  # the hook gave up first - expected in "milczy"
            finally:
                c.close()

    def zamknij(self):
        self.zywy = False
        self.sock.close()


def _fake_address(tmp_path: Path, port: int) -> None:
    # a live PID (this test process), so the hook really connects instead of skipping a dead one
    (tmp_path / "lore-podpowiedz.json").write_text(json.dumps(
        {"pid": os.getpid(), "port": port, "token": "x" * 32, "wersja": "?"}), encoding="utf-8")


# ---------------------------------------------------------------- the server itself


def test_server_gives_the_same_answer_as_recall(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    odp = zapytaj(tmp_path, prompt=PROMPT, session="s1", budget=450, exclude=[])
    conn = recall.open_readonly(tmp_path / "lore.db")
    try:
        direct = recall.recall(PROMPT, "s1", 450, conn, exclude=[])
    finally:
        conn.close()
    assert odp["status"] == "hits" and odp["block"] == direct["block"] and odp["ids"] == [archive.fact]
    assert odp["pid"] == p.pid and isinstance(odp["ms"], int)
    st = stan_gdy(tmp_path, lambda s: s["zapytan"] == 1)
    assert st["dziala"] is True and st["zapytan"] == 1 and st["historia"][-1][2] == "hits"
    assert st["konsola"] in (False, None)


def test_history_keeps_the_last_query_times(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    for i in range(3):
        zapytaj(tmp_path, prompt=PROMPT, session=f"s{i}", budget=450, exclude=[])
    zapytaj(tmp_path, prompt="b", session="s9", budget=450, exclude=[])
    st = stan_gdy(tmp_path, lambda s: s["zapytan"] == 4)
    assert st["zapytan"] == 4 and [h[2] for h in st["historia"]] == ["hits", "hits", "hits", "skipped"]
    assert all(isinstance(h[1], int) for h in st["historia"])


def test_only_one_server_at_a_time(archive, tmp_path, sprzatacz):
    a, b = uruchom(tmp_path), uruchom(tmp_path)
    sprzatacz.extend([a.pid, b.pid])
    # the loser leaves by itself after waiting for the lock (3 s); exit code 3 = "another one is alive"
    przegrany = czekaj(lambda: next((x for x in (a, b) if x.poll() is not None), None), 8)
    assert przegrany is not None and przegrany.returncode == 3
    zwyciezca = b if przegrany is a else a
    assert zwyciezca.poll() is None and gotowy(tmp_path, zwyciezca.pid)["pid"] == zwyciezca.pid


def test_old_code_steps_down_when_the_hook_has_new_code(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    # the old server still answers this one question (its cache is warm), marks it and leaves
    odp = zapytaj(tmp_path, wersja="nowsza", prompt=PROMPT, session="s", budget=450, exclude=[])
    assert odp["status"] == "hits" and odp["stary_kod"] is True and odp["ids"] == [archive.fact]
    assert p.wait(timeout=5) == 0
    assert adres(tmp_path) is None
    st = stan(tmp_path)
    assert st["dziala"] is False and "stara wersja kodu" in st["koniec"]["powod"]


def test_wrong_token_is_refused_and_the_server_goes_on(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    assert zapytaj(tmp_path, token="zly", prompt=PROMPT, session="s", budget=450, exclude=[])["status"] == "obcy"
    assert zapytaj(tmp_path, prompt=PROMPT, session="s", budget=450, exclude=[])["status"] == "hits"
    assert stan_gdy(tmp_path, lambda s: s["zapytan"] == 1)["zle_zadania"] == 1


def test_garbage_and_silent_clients_do_not_kill_the_server(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    a = gotowy(tmp_path, p.pid)
    assert wyslij(a["port"], b"to nie json\n") == b""
    assert wyslij(a["port"], b"[1, 2]\n") == b""
    with socket.create_connection(("127.0.0.1", a["port"])) as s:   # says nothing: the server moves on
        time.sleep(0.8)
    assert zapytaj(tmp_path, prompt=PROMPT, session="s", budget=450, exclude=[])["status"] == "hits"
    st = stan_gdy(tmp_path, lambda s: s["zapytan"] == 1)
    assert st["zle_zadania"] == 3 and "zle zadanie" in st["ostatni_blad"]["opis"]


def test_idle_server_leaves_and_cleans_up(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path, MR_LORE_SERWER_BEZCZYNNOSC_S="1.5")
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    assert p.wait(timeout=10) == 0
    assert adres(tmp_path) is None
    st = stan(tmp_path)
    assert st["dziala"] is False and st["koniec"]["powod"] == "bezczynnosc"


def test_database_changed_on_disk_is_reopened(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    zapytaj(tmp_path, prompt=PROMPT, session="a", budget=450, exclude=[])
    db = tmp_path / "lore.db"
    st0 = db.stat()
    os.utime(db, ns=(st0.st_atime_ns, st0.st_mtime_ns + 5_000_000_000))
    assert zapytaj(tmp_path, prompt=PROMPT, session="b", budget=450, exclude=[])["status"] == "hits"
    st = stan_gdy(tmp_path, lambda s: s["zapytan"] == 2)
    assert st["otwarcia_bazy"] == 2 and st["zamkniecia_bazy"].get("baza zmienila sie na dysku") == 1


def test_database_is_free_once_the_server_left_and_a_rebuilt_one_is_read(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path, MR_LORE_SERWER_BEZCZYNNOSC_S="1.5")
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    assert zapytaj(tmp_path, prompt=PROMPT, session="a", budget=450, exclude=[])["status"] == "hits"
    archive.conn.close()
    if os.name == "nt":
        # while the server lives it holds lore.db, like the MCP server of every open window does
        with pytest.raises(PermissionError):
            (tmp_path / "lore.db").unlink()
    assert p.wait(timeout=10) == 0
    (tmp_path / "lore.db").unlink()           # gone with the server - nothing holds it any more
    for suffix in ("-wal", "-shm"):
        (tmp_path / f"lore.db{suffix}").unlink(missing_ok=True)
    # a rebuilt database at the same path, with other content (the fixture patched db.DB_PATH to it)
    from lore import db as lore_db
    archive.conn = lore_db.connect()
    cid = add(archive, "Kadzidelka backflow biala szalwia numer 31 maja zdjecia na dysku G w folderze marki.",
              session="nowa")
    for i, t in enumerate(FILLER * 5):
        add(archive, t, session=f"f-{i}")
    p2 = uruchom(tmp_path)
    sprzatacz.append(p2.pid)
    gotowy(tmp_path, p2.pid)
    odp = zapytaj(tmp_path, prompt="kadzidelka backflow biala szalwia zdjecia", session="x", budget=450, exclude=[])
    assert odp["status"] == "hits" and odp["ids"] == [cid]


def test_locked_database_is_an_error_and_the_server_recovers(archive, tmp_path, sprzatacz):
    dom = tmp_path / "zablokowana"
    dom.mkdir()
    archive.conn.execute("VACUUM INTO ?", [str(dom / "lore.db")])
    blok = sqlite3.connect(dom / "lore.db", isolation_level=None)
    blok.execute("PRAGMA journal_mode=DELETE")
    p = uruchom(dom, MR_LORE_SERWER_ROZGRZEWKA_S="0")
    sprzatacz.append(p.pid)
    gotowy(dom, p.pid)
    try:
        assert zapytaj(dom, prompt=PROMPT, session="a", budget=450, exclude=[])["status"] == "hits"
        blok.execute("BEGIN EXCLUSIVE")
        odp = zapytaj(dom, prompt=PROMPT, session="b", budget=450, exclude=[])
        assert odp["status"] == "error" and "locked" in odp["reason"]
        blok.execute("ROLLBACK")
        assert zapytaj(dom, prompt=PROMPT, session="c", budget=450, exclude=[])["status"] == "hits"
        assert "locked" in stan_gdy(dom, lambda s: s["zapytan"] == 3)["ostatni_blad"]["opis"]
    finally:
        blok.close()
        sprzatnij(dom, p.pid)


def test_warm_up_fills_the_cache_in_a_quiet_moment_and_again_after_a_commit(archive, tmp_path, sprzatacz):
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    st = stan_gdy(tmp_path, lambda s: s["rozgrzewek"] == 1)
    assert st["rozgrzewka"]["plastrow"] >= 3          # docsize, fts data, chunks - each to the end
    assert st["zapytan"] == 0                          # nobody asked: it waited for the quiet moment itself
    # someone else commits (the indexer): SQLite empties the cache, the server fills it again
    add(archive, "Nowy fragment z indeksowania, ktory zmienia data_version bazy.", session="indeks")
    stan_gdy(tmp_path, lambda s: s["rozgrzewek"] == 2)
    assert zapytaj(tmp_path, prompt=PROMPT, session="a", budget=450, exclude=[])["status"] == "hits"


def test_failed_warm_up_is_recorded_and_not_retried_every_moment(tmp_path, sprzatacz):
    # a database without the search tables: the warm-up cannot read them and must say so
    sqlite3.connect(tmp_path / "lore.db").executescript("CREATE TABLE cos(x); INSERT INTO cos VALUES (1);").close()
    p = uruchom(tmp_path)
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    st = stan_gdy(tmp_path, lambda s: "blad" in s.get("rozgrzewka", {}))
    assert "no such table" in st["rozgrzewka"]["blad"] and "rozgrzewka" in st["ostatni_blad"]["opis"]
    time.sleep(4)
    assert stan(tmp_path)["bledow"] == 1 and zyje(p.pid)
    odp = zapytaj(tmp_path, prompt=PROMPT, session="a", budget=450, exclude=[])
    assert odp["status"] == "error" and "no such table" in odp["reason"]


def test_missing_database_is_an_error_not_silence(tmp_path, sprzatacz):
    p = uruchom(tmp_path, MR_LORE_SERWER_ROZGRZEWKA_S="0")
    sprzatacz.append(p.pid)
    gotowy(tmp_path, p.pid)
    odp = zapytaj(tmp_path, prompt=PROMPT, session="b", budget=450, exclude=[])
    assert odp["status"] == "error" and "brak bazy" in odp["reason"]
    assert zyje(p.pid)


# ---------------------------------------------------------------- through the hook


@needs_node
def test_hook_starts_the_server_unseen_and_the_next_message_uses_it(archive, tmp_path, sprzatacz):
    ctx, st, took = _hook(tmp_path)
    assert ctx.startswith(RULES) and f"#{archive.fact}" in ctx
    assert st["droga"] == "zapasowa" and st["wynik"] == "hits"
    # the hook did not wait for the server it started (no inherited pipes, detached)
    assert took < 3, took
    a = gotowy(tmp_path)
    assert a["pid"] == st["serwer"]["pid_startu"]
    ctx2, st2, _ = _hook(tmp_path, session="s2")
    assert st2["droga"] == "serwer" and st2["wynik"] == "hits" and f"#{archive.fact}" in ctx2
    assert st2["serwer"]["pid"] == a["pid"] and st2["serwer"]["starty_bez_odpowiedzi"] == 0
    # windowless: no console from the inside, no visible window from the outside
    s = stan(tmp_path)
    assert s["konsola"] in (False, None)
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        widoczne = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def kazde(hwnd, _):
            pid = wintypes.DWORD()
            ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if pid.value == a["pid"] and ctypes.windll.user32.IsWindowVisible(hwnd):
                widoczne.append(hwnd)
            return True

        ctypes.windll.user32.EnumWindows(kazde, 0)
        assert widoczne == []


@needs_node
def test_killed_server_costs_no_hint_and_is_replaced(archive, tmp_path, sprzatacz):
    _hook(tmp_path)
    stary = gotowy(tmp_path)["pid"]
    sprzatacz.append(stary)
    zabij(stary)
    ctx, st, _ = _hook(tmp_path, session="s2")
    assert f"#{archive.fact}" in ctx and st["droga"] == "zapasowa" and "nie zyje" in st["serwer"]["problem"]
    assert "awaria" not in st
    _allow_new_start(tmp_path)
    _hook(tmp_path, session="s3")
    nowy = czekaj(lambda: (adres(tmp_path) or {}).get("pid") not in (None, stary) and adres(tmp_path)["pid"])
    sprzatacz.append(nowy)
    assert nowy and zyje(nowy)
    _, st4, _ = _hook(tmp_path, session="s4")
    assert st4["droga"] == "serwer" and st4["serwer"]["pid"] == nowy


@needs_node
@pytest.mark.parametrize("tryb", ["smieci", "json-bez-statusu", "zamyka", "bez-konca-linii"])
def test_foreign_or_broken_answer_falls_back_and_a_real_server_takes_over(archive, tmp_path, sprzatacz, tryb):
    obcy = Obcy(tryb)
    try:
        _fake_address(tmp_path, obcy.port)
        ctx, st, _ = _hook(tmp_path)
        assert obcy.polaczen == 1
        assert f"#{archive.fact}" in ctx and st["droga"] == "zapasowa" and st["wynik"] == "hits"
        assert "awaria" not in st
        # the lock is free (the "server" in the address file is not ours): the one the hook started takes over
        a = czekaj(lambda: (adres(tmp_path) or {}).get("port") not in (None, obcy.port) and adres(tmp_path))
        assert a and zyje(a["pid"])
        _, st2, _ = _hook(tmp_path, session="s2")
        assert st2["droga"] == "serwer"
    finally:
        obcy.zamknij()


@needs_node
def test_silent_server_is_a_failure_like_before_not_a_long_wait(archive, tmp_path, sprzatacz):
    obcy = Obcy("milczy")
    try:
        _fake_address(tmp_path, obcy.port)
        ctx, st, took = _hook(tmp_path)
        assert ctx.startswith(ALARM) and "300 ms" in ctx.splitlines()[0] and RULES in ctx
        assert st["wynik"] == "awaria" and st["droga"] == "serwer"
        assert took < 1.4, took          # 300 ms of waiting, not the 1.5 s of the silent process
        # the hook still started a real server (the lock was free) - the next message is served
        a = czekaj(lambda: (adres(tmp_path) or {}).get("port") not in (None, obcy.port) and adres(tmp_path))
        assert a
        ctx2, st2, _ = _hook(tmp_path, session="s2")
        assert st2["droga"] == "serwer" and st2["wynik"] == "hits" and "awaria" not in st2
    finally:
        obcy.zamknij()


@needs_node
def test_two_hooks_at_once_leave_exactly_one_server(archive, tmp_path, sprzatacz):
    wyniki = []

    def jeden(i):
        # own state file each: two hooks writing one file at the same moment is not what is tested here
        wyniki.append(_hook(tmp_path, session=f"rownolegle-{i}", state_name=f"state-{i}.json"))

    watki = [threading.Thread(target=jeden, args=(i,)) for i in range(2)]
    for w in watki:
        w.start()
    for w in watki:
        w.join(30)
    assert len(wyniki) == 2 and all(f"#{archive.fact}" in ctx for ctx, _, _ in wyniki)
    gotowy(tmp_path)
    time.sleep(3.5)                      # the loser waits up to 3 s for the lock, then leaves
    zywe = procesy(str(tmp_path))
    assert len(zywe) == 1 and zywe[0] == adres(tmp_path)["pid"], zywe


@needs_node
def test_server_with_old_code_is_replaced_after_an_update(archive, tmp_path, sprzatacz):
    _hook(tmp_path)
    stary = gotowy(tmp_path)["pid"]
    sprzatacz.append(stary)
    # "update": the hook now sees other code on disk (the override acts on the hook and the new server)
    ctx, st, _ = _hook(tmp_path, session="s2", MR_LORE_WERSJA_KODU="po-aktualizacji")
    # answered by the old (warm) server one last time - no cold fallback right after an update
    assert f"#{archive.fact}" in ctx and st["droga"] == "serwer" and st["serwer"]["pid"] == stary
    assert "stary kod" in st["serwer"]["problem"] and "awaria" not in st
    assert czekaj(lambda: not zyje(stary), 5)
    nowy = czekaj(lambda: (adres(tmp_path) or {}).get("wersja") == "po-aktualizacji" and adres(tmp_path)["pid"], 8)
    sprzatacz.append(nowy)
    assert nowy and nowy != stary
    _, st3, _ = _hook(tmp_path, session="s3", MR_LORE_WERSJA_KODU="po-aktualizacji")
    assert st3["droga"] == "serwer" and st3["serwer"]["pid"] == nowy


@needs_node
def test_server_that_never_comes_up_raises_the_alarm_after_three_starts(archive, tmp_path, sprzatacz):
    (tmp_path / "lore-podpowiedz.lock").mkdir()      # the server cannot even open its lock file
    for i in range(3):
        if i:
            _allow_new_start(tmp_path)
        ctx, st, _ = _hook(tmp_path, session=f"s{i}")
        assert f"#{archive.fact}" in ctx and not ctx.startswith("UWAGA"), i   # the hint still comes
        assert st["serwer"]["starty_bez_odpowiedzi"] == i + 1
        time.sleep(0.5)
    ctx, st, _ = _hook(tmp_path, session="s3")
    assert ctx.startswith("UWAGA: serwer podpowiedzi Lore nie wstaje (3 startow") and RULES in ctx
    assert f"#{archive.fact}" in ctx and len(ctx) <= 1500
    # the same story again: in the state, but not shouted at every message
    ctx2, _, _ = _hook(tmp_path, session="s4")
    assert not ctx2.startswith("UWAGA")


@needs_node
def test_switch_off_goes_the_old_way_and_starts_nothing(archive, tmp_path, sprzatacz):
    ctx, st, _ = _hook(tmp_path, MR_LORE_SERWER="0")
    assert f"#{archive.fact}" in ctx and st["droga"] == "zapasowa" and "pid_startu" not in st.get("serwer", {})
    time.sleep(0.5)
    assert adres(tmp_path) is None
