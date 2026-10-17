"""Helpers for the tests that start the recall server (lore/lore/recall_serwer.py) — directly or through
the hook. Nothing a test starts may stay running (rule of the repo), so every server is stopped by its
token and, if it does not go, killed; `procesy` finds stragglers by their --dom in the command line.
Every process a test starts is windowless (pythonw, CREATE_NO_WINDOW)."""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

LORE_DIR = Path(__file__).resolve().parents[1]
SERWER = LORE_DIR / "lore" / "recall_serwer.py"
ADRES = "lore-podpowiedz.json"
STAN = "lore-podpowiedz-stan.json"
BEZ_OKNA = 0x08000000 if os.name == "nt" else 0   # CREATE_NO_WINDOW


def base_python(windowed: bool = True) -> str:
    """The interpreter the venv was made from (the hook calls it the same way, without the launcher)."""
    base = Path(getattr(sys, "_base_executable", sys.executable))
    if os.name == "nt" and windowed and base.with_name("pythonw.exe").exists():
        return str(base.with_name("pythonw.exe"))
    return str(base)


def czytaj(p: Path) -> dict | None:
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def adres(dom: Path) -> dict | None:
    return czytaj(Path(dom) / ADRES)


def stan(dom: Path) -> dict | None:
    return czytaj(Path(dom) / STAN)


def zyje(pid: int | None) -> bool:
    if not pid:
        return False
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x1000, False, int(pid))   # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        try:
            code = ctypes.c_ulong()
            k.GetExitCodeProcess(h, ctypes.byref(code))
            return code.value == 259                  # STILL_ACTIVE
        finally:
            k.CloseHandle(h)
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def czekaj(warunek, sekund: float = 6.0, krok: float = 0.05):
    koniec = time.monotonic() + sekund
    while time.monotonic() < koniec:
        w = warunek()
        if w:
            return w
        time.sleep(krok)
    return warunek()


def uruchom(dom: Path, **env) -> subprocess.Popen:
    """A server the way the hook starts it (real pythonw, -I, script path, --dom), windowless."""
    full = dict(os.environ, **{k: str(v) for k, v in env.items()})
    full.setdefault("MR_LORE_SERWER_BEZCZYNNOSC_S", "60")   # safety net should a test forget to stop it
    return subprocess.Popen([base_python(), "-I", "-X", "utf8", str(SERWER), "--dom", str(dom)],
                            cwd=str(dom), env=full, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, creationflags=BEZ_OKNA)


def gotowy(dom: Path, pid: int | None = None, sekund: float = 6.0) -> dict:
    def ok():
        a = adres(dom)
        if a and zyje(a.get("pid")) and (pid is None or a["pid"] == pid):
            return a
        return None
    a = czekaj(ok, sekund)
    assert a, f"serwer w {dom} nie wstal; stan: {stan(dom)}"
    return a


def wyslij(port: int, linia: bytes, czas: float = 5.0) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=czas) as s:
        s.sendall(linia)
        dane = b""
        while b"\n" not in dane:
            k = s.recv(65536)
            if not k:
                break
            dane += k
        return dane


def zapytaj(dom: Path, **req) -> dict:
    a = adres(dom)
    assert a, f"brak pliku adresu w {dom}"
    req.setdefault("token", a["token"])
    req.setdefault("wersja", a["wersja"])
    odp = wyslij(a["port"], (json.dumps(req, ensure_ascii=False) + "\n").encode("utf-8"))
    return json.loads(odp.split(b"\n", 1)[0].decode("utf-8"))


def procesy(fragment: str) -> list[int]:
    """PIDs of recall servers whose command line contains `fragment` (here: the test's --dom)."""
    if os.name != "nt":
        r = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True, text=True, timeout=30)
        return [int(l.split(None, 1)[0]) for l in r.stdout.splitlines()
                if "recall_serwer" in l and fragment in l]
    polecenie = ("Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" | "
                 "Where-Object { $_.CommandLine -like '*recall_serwer*' } | "
                 "ForEach-Object { '' + $_.ProcessId + '|' + $_.CommandLine }")
    r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", polecenie],
                       capture_output=True, text=True, timeout=60, creationflags=BEZ_OKNA)
    return [int(l.split("|", 1)[0]) for l in r.stdout.splitlines()
            if "|" in l and fragment.lower() in l.lower()]


def zabij(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)   # TerminateProcess on Windows
    except OSError:
        pass  # already gone between the check and the kill - that is what we wanted
    czekaj(lambda: not zyje(pid), 5)


def sprzatnij(dom: Path, *pidy: int | None, szukaj: bool = False) -> list[int]:
    """Stops every server of `dom`: by token, then by force. Returns the PIDs that had to be killed."""
    dom = Path(dom)
    kandydaci = {p for p in pidy if p}
    a = adres(dom)
    if a:
        kandydaci.add(a["pid"])
        if zyje(a["pid"]):
            try:
                zapytaj(dom, cmd="stop")
            except (OSError, ValueError):
                pass  # it did not take the stop - it gets killed below
    if szukaj:
        kandydaci.update(procesy(str(dom)))
    zabite = []
    for pid in kandydaci:
        if czekaj(lambda: not zyje(pid), 4):
            continue
        zabite.append(pid)
        zabij(pid)
    return zabite


def stan_hooka_pidy(plik: Path) -> list[int]:
    s = czytaj(plik) or {}
    serw = s.get("serwer") or {}
    return [p for p in (serw.get("pid_startu"), serw.get("pid")) if p]
