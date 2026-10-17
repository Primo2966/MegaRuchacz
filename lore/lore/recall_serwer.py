"""A long-lived process answering the "Z ARCHIWUM" hint (narzedzia/przypomnienie.js) — the very same
recall.recall(), minus a Python start on every message.

Why: measured 2026-10-17, the hook spent most of its Lore time starting Python, not searching. The
venv python.exe is a launcher that starts the real interpreter as a second process (~83 ms + ~55 ms
+ ~35 ms of imports), the warm query itself takes 12-65 ms. Under load (other hooks starting
PowerShell at the same moment) 8 of 101 runs went over the hook's 650 ms limit and the message
lost its hint. Here Python is already running and the database already open: the hook sends one
line of JSON over 127.0.0.1 and gets one line back.

The second half of the story is the disk cache. On the office machine (24 GB, ~3 GB free) the OS
drops the pages of lore.db within minutes: a fresh connection took 625-1487 ms for a query that ran
in 40-90 ms a minute earlier, while a connection holding the pages in its OWN cache stayed at
7-45 ms through the same disturbance (2026-10-17). So the server keeps one connection with a large
page cache (CACHE_MB) and fills it in quiet moments (the warm-up, see ROZGRZEWKA_*). SQLite empties
that cache whenever another connection commits (the indexer, every ~10 min — verified), so the
warm-up runs again after every change of PRAGMA data_version.

How it lives (no installer, no scheduled task, no supervisor — so it works the same after a reboot,
on the second machine and on Ela's): the hook starts it lazily. When it does not answer, the hook
answers this one message the old way (spawnSync of recall.py) and at the same time starts this
server in the background, detached, windowless (pythonw.exe, DETACHED_PROCESS). The server leaves
by itself after BEZCZYNNOSC_S without a question; the next message starts it again.

One at a time: an exclusive lock on ZAMEK (released by the OS when the process dies, however it
dies). Discovery: ADRES holds port, token, pid and the code version. The token keeps a stray
process on a reused port from being taken for us; the version makes an old server step down after
a MegaRuchacz update — the hook sends the version of the code it sees on disk; on a mismatch the old
server still answers that one question (marked "stary_kod": its cache is warm, while a fresh Python
after an update met cold pages and missed the 650 ms limit three times out of three on 2026-10-17)
and leaves; the hook starts the new code. If an update ever changes what the hook needs in the
answer, the hook must not take such a marked answer from an old server.

The database is opened read-only (recall.open_readonly, WAL — the indexer and the knowledge cycle
write undisturbed; no transaction stays open between questions) and reopened whenever the file
changes identity on disk (replaced, rebuilt, checkpointed) or a query fails with a database error.
While the server lives it holds lore.db open, like the MCP server "lore" of every open window does;
Windows refuses to delete or replace such a file — after BEZCZYNNOSC_S the server is gone.

Single-threaded on purpose: one connection, one cache, questions answered one by one between
slices of the warm-up (a question waits at most one slice). A warm query takes tens of ms.

"I was here": STAN — start, pid, version, memory, number of questions, the last 50 query times, the
last error, the warm-ups, and why it ended. Nothing here fails silently: an error that does not stop
the server lands in STAN and in the next answer ("uwaga"), which the hook stores in its own state.

Run: <real python>[w] -I -X utf8 lore/lore/recall_serwer.py --dom <Lore data dir>
(or python -m lore.recall_serwer in tests). Stdlib only, like recall.py.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import secrets
import select
import socket
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

if not __package__:
    # started as a script with -I (the hook does that: no venv launcher, no cwd on sys.path)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lore import recall  # noqa: E402

if os.name == "nt":
    import msvcrt
else:
    import fcntl

ADRES = "lore-podpowiedz.json"
STAN = "lore-podpowiedz-stan.json"
ZAMEK = "lore-podpowiedz.lock"


def _env_seconds(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


# Leave after this long without a question. Two hours cover the breaks of a working day (lunch, a
# meeting): the first message after them stays fast. Longer would keep CACHE_MB of memory and the
# open lore.db for nothing — after a longer break the first message goes the old way once (exactly as
# before the server existed) and starts it again.
BEZCZYNNOSC_S = _env_seconds("MR_LORE_SERWER_BEZCZYNNOSC_S", 2 * 3600)
# Upper bound of the page cache. What the search touches is chunks (~73 MB with the texts),
# chunks_fts_data (~19 MB) and chunks_fts_docsize (~1 MB) — ~93 MB on 2026-10-17 (68 099 chunks); the
# cache grows only as far as pages are read. The bound leaves room for a year of growth and keeps a
# much bigger archive from taking the memory of a machine that has little to spare.
CACHE_MB = 160
# Fill the cache (read the tables above, through the server's own connection) after this long without
# a question. Not at once: the hook that started the server is still asking its own Python at that
# moment (the old way, at most 650 ms) — a warm-up started together with the server (2026-10-17, in a
# thread) read cold pages for 2.8 s, that Python took 684 ms and lost the hint, and the questions
# meanwhile took 506-821 ms. One second after the last question that hook is done. The warm-up goes
# in slices of ROZGRZEWKA_PLASTER rows; a question that comes meanwhile goes first, before the next slice.
ROZGRZEWKA_PO_CISZY_S = 1.0
ROZGRZEWKA_PLASTER = 2000      # rows per slice (~2 MB of chunks, ~10-60 ms)
# ...again after every commit of someone else (the cache was emptied), and at the latest every this
# many seconds even without one — rereading pages already in the cache costs ~50 ms of CPU, and it
# brings back whatever the OS paged out. 0 = no warm-up at all.
ROZGRZEWKA_CO_S = _env_seconds("MR_LORE_SERWER_ROZGRZEWKA_S", 15 * 60)
# A server replacing an old one (after "stale") waits this long for the old one to release the lock.
CZEKAJ_NA_ZAMEK_S = 3.0
# The hook writes its line right after connecting; a client that sends nothing for this long is not
# the hook and must not hold the (single-threaded) server any longer.
CZAS_KLIENTA_S = 0.5
# A prompt can be a long paste; anything bigger than this is not a hook's question.
MAX_ZADANIA = 4 * 1024 * 1024
HISTORIA = 50
TIK_S = 5.0


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def code_version() -> str:
    """Hash of the code that answers (recall.py + this file) — the hook computes the same from disk.

    MR_LORE_WERSJA_KODU overrides it on both sides; only the tests use it (an "update" without
    touching the repository)."""
    forced = os.environ.get("MR_LORE_WERSJA_KODU")
    if forced:
        return forced
    h = hashlib.sha1()
    for p in (Path(recall.__file__), Path(__file__)):
        h.update(p.read_bytes())
        h.update(b"\0")
    return h.hexdigest()[:16]


def write_json(path: Path, data: dict) -> None:
    """Temp file + swap: the hook reading ADRES never sees half of it. os.replace over a file someone
    holds open is refused on Windows for a moment — a few short tries."""
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    for attempt in range(10):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            if attempt == 9:
                tmp.unlink(missing_ok=True)
                raise
            time.sleep(0.02)


def take_lock(path: Path, wait_s: float):
    """The open lock file (held = we are THE server) or None when another live server holds it."""
    f = open(path, "a+b")
    deadline = time.monotonic() + wait_s
    while True:
        try:
            if os.name == "nt":
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return f
        except OSError:
            if time.monotonic() >= deadline:
                f.close()
                return None
            time.sleep(0.05)


def _has_console() -> bool | None:
    """Proof of windowlessness from the inside (the tests read it from STAN)."""
    if os.name != "nt":
        return None
    import ctypes
    return bool(ctypes.windll.kernel32.GetConsoleWindow())


def _memory_mb() -> dict | None:
    """What the cache costs, in the user's unit: megabytes of this process (Windows only)."""
    if os.name != "nt":
        return None
    import ctypes
    from ctypes import wintypes

    class Counters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]

    c = Counters()
    c.cb = ctypes.sizeof(c)
    psapi = ctypes.WinDLL("psapi")
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    if not psapi.GetProcessMemoryInfo(ctypes.windll.kernel32.GetCurrentProcess(), ctypes.byref(c), c.cb):
        return None
    return {"robocza": round(c.WorkingSetSize / 2 ** 20), "prywatna": round(c.PagefileUsage / 2 ** 20)}


# What the warm-up reads, in this order: the small FTS tables first (every query counts terms in them).
# length() of TEXT reads the whole value; substr() of a BLOB loads it (length() of a BLOB alone is
# answered from the record header and would not touch the pages). Keyset slices: FTS5 data ids are
# sparse, a range of ids would be mostly empty.
TABELE_ROZGRZEWKI = (("chunks_fts_docsize", "length(substr(sz, -1))"),
                     ("chunks_fts_data", "length(substr(block, -1))"),
                     ("chunks", "length(text)"))


class Server:
    def __init__(self, home: Path, version: str) -> None:
        self.home = home
        self.db = home / recall.DB_NAME
        self.version = version
        self.token = secrets.token_hex(16)
        self.conn: sqlite3.Connection | None = None
        self.identity: tuple | None = None
        self.last = time.monotonic()          # last question (or the start)
        self.warm = None                      # the warm-up in progress (a generator of slices)
        self.warm_started = 0.0
        self.warm_done_at = 0.0               # monotonic time of the last finished warm-up
        self.warm_data_version = None         # PRAGMA data_version the cache was filled at
        self.warm_failed = False              # the last warm-up failed: next try only after ROZGRZEWKA_CO_S
        self.history: collections.deque = collections.deque(maxlen=HISTORIA)
        self.note = ""                        # a problem worth passing to the hook with the next answer
        self.sock: socket.socket | None = None
        self.state = {"pid": os.getpid(), "start": now_iso(), "wersja": self.version, "dziala": True,
                      "baza": str(self.db), "python": sys.executable, "konsola": _has_console(),
                      "zapytan": 0, "bledow": 0, "otwarcia_bazy": 0, "zamkniecia_bazy": {},
                      "zle_zadania": 0, "po_limicie": 0, "rozgrzewek": 0}

    # ------------------------------------------------------------ state

    def problem(self, what: str, counter: str = "bledow") -> None:
        self.state[counter] = self.state.get(counter, 0) + 1
        self.state["ostatni_blad"] = {"czas": now_iso(), "opis": what[:300]}
        self.note = what[:200]

    def save_state(self) -> None:
        self.state["czas"] = now_iso()
        self.state["historia"] = list(self.history)
        self.state["pamiec_mb"] = _memory_mb()
        try:
            write_json(self.home / STAN, self.state)
        except OSError as e:
            # no file to say it in — the next answer says it to the hook, which keeps it in its state
            self.note = f"nie zapisalem stanu serwera: {e}"[:200]

    def publish_address(self) -> None:
        write_json(self.home / ADRES, {"pid": os.getpid(), "port": self.sock.getsockname()[1],
                                       "token": self.token, "wersja": self.version, "start": self.state["start"]})

    def address_is_ours(self) -> bool:
        try:
            return json.loads((self.home / ADRES).read_text(encoding="utf-8")).get("token") == self.token
        except (OSError, ValueError):
            return False

    # ------------------------------------------------------------ database

    def connect(self) -> sqlite3.Connection:
        try:
            st = os.stat(self.db)
        except FileNotFoundError:
            self.disconnect("baza zniknela z dysku")
            raise FileNotFoundError(f"brak bazy {self.db}") from None
        identity = (st.st_ino, st.st_dev, st.st_size, st.st_mtime_ns)
        if self.conn is not None and identity != self.identity:
            self.disconnect("baza zmienila sie na dysku")
        if self.conn is None:
            self.conn = recall.open_readonly(self.db)
            self.conn.execute(f"PRAGMA cache_size=-{CACHE_MB * 1024}")
            self.identity = identity
            self.warm_data_version = None     # a new connection starts with an empty cache
            self.state["otwarcia_bazy"] += 1
        return self.conn

    def disconnect(self, why: str) -> None:
        self.warm = None
        if self.conn is None:
            return
        try:
            self.conn.close()
        except sqlite3.Error as e:
            self.problem(f"zamkniecie bazy ({why}): {e}")
        self.conn = None
        counts = self.state["zamkniecia_bazy"]
        counts[why] = counts.get(why, 0) + 1

    def search(self, req: dict) -> dict:
        prompt = str(req.get("prompt") or "")
        session = req.get("session")
        budget = int(req.get("budget") or 0)
        exclude = [int(x) for x in req.get("exclude") or []]
        for attempt in (1, 2):
            conn = self.connect()
            try:
                return recall.recall(prompt, session, budget, conn, exclude=exclude)
            except sqlite3.Error as e:
                # a rebuilt or overwritten file shows up here (malformed, no such table, schema
                # changed): one retry on a fresh connection. A lock does not go away by reopening —
                # waiting longer only makes the hook give up.
                self.disconnect(f"blad bazy: {type(e).__name__}")
                text = str(e).lower()
                if attempt == 2 or "locked" in text or "busy" in text:
                    raise
        raise AssertionError("unreachable")

    # ------------------------------------------------------------ warm-up

    def warm_due(self) -> bool:
        if ROZGRZEWKA_CO_S <= 0 or self.warm is not None:
            return False
        if time.monotonic() - self.last < ROZGRZEWKA_PO_CISZY_S:
            return False
        since = time.monotonic() - self.warm_done_at
        if since >= ROZGRZEWKA_CO_S:
            return True
        if self.warm_failed:
            return False                      # a failure is not retried every tick (it is in STAN)
        if self.warm_data_version is None:
            return True
        try:
            # someone else committed: SQLite emptied our cache at the next read
            return self.connect().execute("PRAGMA data_version").fetchone()[0] != self.warm_data_version
        except (OSError, sqlite3.Error) as e:
            self.problem(f"rozgrzewka (sprawdzenie zmian): {type(e).__name__}: {e}")
            return False

    def slices(self):
        conn = self.connect()
        version = conn.execute("PRAGMA data_version").fetchone()[0]
        n = 0
        for table, value in TABELE_ROZGRZEWKI:
            last = -(2 ** 63)
            while True:
                rows = conn.execute(f"SELECT id, {value} FROM {table} WHERE id > ? ORDER BY id LIMIT ?",
                                    (last, ROZGRZEWKA_PLASTER)).fetchall()
                n += 1
                if not rows:
                    break
                last = rows[-1][0]
                yield
        self.warm_data_version = version
        self.state["rozgrzewka"] = {"czas": now_iso(), "ms": round((time.perf_counter() - self.warm_started) * 1000),
                                    "plastrow": n}

    def warm_step(self) -> None:
        """One slice of the warm-up; the end and every failure land in STAN."""
        try:
            next(self.warm)
            return
        except StopIteration:
            self.state["rozgrzewek"] += 1
            self.warm_failed = False
        except Exception as e:  # recorded, and the server goes on — a cold cache is slow, not broken
            self.problem(f"rozgrzewka: {type(e).__name__}: {e}")
            self.state["rozgrzewka"] = {"czas": now_iso(), "blad": f"{type(e).__name__}: {e}"[:200]}
            self.warm_failed = True
        self.warm = None
        self.warm_done_at = time.monotonic()
        self.save_state()

    # ------------------------------------------------------------ one client

    def handle(self, client: socket.socket) -> str | None:
        """Answers one connection. Returns why the server should leave, or None."""
        client.settimeout(CZAS_KLIENTA_S)
        data = b""
        try:
            while b"\n" not in data:
                chunk = client.recv(65536)
                if not chunk:
                    break
                data += chunk
                if len(data) > MAX_ZADANIA:
                    raise ValueError(f"zadanie dluzsze niz {MAX_ZADANIA} bajtow")
            req = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
            if not isinstance(req, dict):
                raise ValueError("zadanie to nie obiekt JSON")
        except (OSError, ValueError) as e:  # socket.timeout is an OSError
            self.problem(f"zle zadanie od klienta: {type(e).__name__}: {e}", "zle_zadania")
            return None

        leave = None
        if req.get("token") != self.token:
            out = {"status": "obcy", "reason": "zly token - to nie jest zadanie od hooka tego serwera"}
            self.problem("zadanie ze zlym tokenem", "zle_zadania")
        elif req.get("cmd") == "stop":
            out, leave = {"status": "stop", "reason": "zatrzymuje sie"}, "polecenie stop"
        else:
            started = time.perf_counter()
            try:
                out = self.search(req)
            except Exception as e:  # the same as recall.main: reported to the hook, not swallowed
                out = recall._nothing("error", f"{type(e).__name__}: {e}"[:200])
                self.problem(out["reason"])
            self.last = time.monotonic()
            out["ms"] = round((time.perf_counter() - started) * 1000)
            self.state["zapytan"] += 1
            self.state["ostatnie_zapytanie"] = now_iso()
            # the hook says how long it waits; an answer later than that reached nobody (sendall to a
            # socket the hook already closed does not fail, so this is the only way to count them)
            limit = req.get("limit_ms")
            if isinstance(limit, int) and out["ms"] > limit:
                self.state["po_limicie"] += 1
            self.history.append([now_iso(), out["ms"], out["status"]])
            if req.get("wersja") != self.version:
                out["stary_kod"] = True
                leave = f"stara wersja kodu (serwer {self.version}, hook {req.get('wersja')})"
        out["pid"] = os.getpid()
        out["wersja"] = self.version
        if self.note:
            out["uwaga"], self.note = self.note, ""
        try:
            client.sendall((json.dumps(out, ensure_ascii=False) + "\n").encode("utf-8"))
        except OSError as e:
            self.problem(f"nie oddalem odpowiedzi ({out.get('ms')} ms): {e}")
        self.save_state()
        return leave

    # ------------------------------------------------------------ the loop

    def tick(self) -> str | None:
        """Nothing came for a while. Returns why the server should leave, or None."""
        if time.monotonic() - self.last > BEZCZYNNOSC_S:
            return "bezczynnosc"
        if not self.address_is_ours():
            # deleted or overwritten by hand: the lock says we are the server, so say it again
            self.problem("plik adresu zniknal albo nie jest nasz - zapisuje go od nowa")
            self.publish_address()
            self.save_state()
        if self.warm_due():
            self.warm_started = time.perf_counter()
            self.warm = self.slices()         # runs slice by slice in run(); failures in warm_step
        return None

    def run(self) -> str:
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if os.name == "nt":
            # nobody else may bind our port while we hold it (port hijacking on Windows)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(16)
        self.state["port"] = self.sock.getsockname()[1]
        self.publish_address()
        self.save_state()
        wait = min(TIK_S, max(0.2, BEZCZYNNOSC_S / 4), max(0.5, ROZGRZEWKA_PO_CISZY_S))
        failures = 0
        while True:
            ready, _, _ = select.select([self.sock], [], [], 0 if self.warm is not None else wait)
            if not ready:
                if self.warm is not None:
                    self.warm_step()
                    continue
                leave = self.tick()
                if leave:
                    return leave
                continue
            try:
                client, _ = self.sock.accept()
                failures = 0
            except OSError as e:
                # a single broken incoming connection is not the end; a socket that keeps failing is -
                # leaving lets the hook start a fresh server
                failures += 1
                self.problem(f"accept: {type(e).__name__}: {e}")
                if failures >= 20:
                    return f"gniazdo nie dziala ({e})"
                time.sleep(0.1)
                continue
            try:
                leave = self.handle(client)
            finally:
                client.close()
            if leave:
                return leave

    def close(self, why: str) -> None:
        """Address first (nobody new comes), then the socket, the database; the lock goes last (main)."""
        if self.address_is_ours():
            try:
                (self.home / ADRES).unlink()
            except OSError as e:
                self.problem(f"nie usunalem pliku adresu: {e}")
        if self.sock is not None:
            self.sock.close()
        self.disconnect("koniec serwera")
        self.state["dziala"] = False
        self.state["koniec"] = {"czas": now_iso(), "powod": why}
        self.save_state()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dom", help="katalog danych Lore (domyslnie jak recall.data_home)")
    args = parser.parse_args(argv)
    home = Path(args.dom) if args.dom else recall.data_home()
    if not home.is_dir():
        return 2  # no Lore data here (the hook starts us only next to an existing lore.db)
    # nothing of the repository stays held by this process (a directory in use cannot be deleted)
    os.chdir(home)
    version = code_version()
    try:
        lock = take_lock(home / ZAMEK, CZEKAJ_NA_ZAMEK_S)
    except OSError:
        # cannot even open the lock file - no state can be written safely without the lock; the
        # hook counts starts that never answer and raises the alarm (przypomnienie.js, PROG_STARTOW)
        return 4
    if lock is None:
        return 3  # another live server holds the lock — that is the expected outcome, not an error
    server = Server(home, version)
    why = "?"
    try:
        why = server.run()
        return 0
    except BaseException as e:  # written down for whoever reads STAN; pythonw has no stderr
        why = f"blad: {type(e).__name__}: {e}"[:300]
        server.problem(why)
        return 1
    finally:
        server.close(why)
        lock.close()


if __name__ == "__main__":
    sys.exit(main())
