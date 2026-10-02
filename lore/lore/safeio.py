"""Writing the memory files so that a power cut cannot leave them full of zero bytes.

2026-10-02 08:03 the morning cycle wrote CLAUDE.md and eleven files in wiedza/, and some thirty
seconds later the machine went down without a clean shutdown (Kernel-Power 41). NTFS had already
journaled the new sizes, but not the data: after the restart every one of those files had its full
length and nothing but 0x00 inside. The guard then took the zeroed CLAUDE.md for the user's own
text, appended its blocks to it and made a "backup" of the zeros.

Two rules come out of that:

- a memory file is written to a temporary file in the same directory, flushed and fsync'ed, and
  only then moved over the old one — a cut at any moment leaves either the old file or the new
  one, never a zeroed hybrid. An append (the trail, the waiting room) is fsync'ed after writing.
- nothing builds on a file that has zero bytes in it. No text file of ours ever holds 0x00, so one
  zero byte is proof of a broken write, not a matter of taste: the run stops, says which file, and
  points at the last healthy copy.
"""
from __future__ import annotations

import os
import time
from pathlib import Path

from .db import CLAUDE_HOME, log

# The daily copies kept by narzedzia\kopie-dzienne.ps1 (rotated once a day, before the cycle):
# the same layout as the home directory under each of these two.
DAILY_DIR = CLAUDE_HOME / "mr" / "kopie-dzienne"
DAILY_SLOTS = ("wczoraj", "przedwczoraj")
# The one command that puts the zeroed files back from the newest healthy daily copy.
RESTORE_HINT = r"powershell -ExecutionPolicy Bypass -File <repo>\narzedzia\kopie-dzienne.ps1 -Przywroc"

# os.replace over a file another process holds open (the guard reading CLAUDE.md, an editor) is
# refused on Windows. A few short tries cover such a moment; ~2 s in total.
REPLACE_TRIES = 20
REPLACE_PAUSE_S = 0.1

# Which files in wiedza\ are ours and textual — only those are checked for zeros, so that a binary
# file the user drops there one day cannot raise a false alarm.
TEXT_SUFFIXES = {".md", ".txt", ".tsv", ".json", ".jsonl", ""}


class ZeroedMemory(RuntimeError):
    """A memory file with zero bytes inside — nothing may be built on it."""

    def __init__(self, found: list[tuple[Path, int, int]]):
        self.found = found
        super().__init__(describe_zeroed(found))


def _fsync_dir(directory: Path) -> None:
    """The rename itself made durable where the OS allows it (POSIX); Windows has no such handle."""
    if os.name == "nt":
        return
    try:
        fd = os.open(directory, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass  # a directory that cannot be synced still has the file synced inside it
    finally:
        os.close(fd)


def write_text(path: Path | str, text: str, newline: str | None = "\n",
               encoding: str = "utf-8") -> None:
    """The whole file anew: temp file in the same directory, flush, fsync, then the swap.

    `newline` works as in open(): "\\n" keeps the text as it is, "" too, None translates to the
    platform's line ending (what Path.write_text did by default).
    """
    path = Path(path)
    if "\0" in text:
        raise ValueError(f"refusing to write zero bytes into {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        with open(tmp, "w", encoding=encoding, newline=newline) as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        for attempt in range(REPLACE_TRIES):
            try:
                os.replace(tmp, path)
                break
            except PermissionError:
                if attempt == REPLACE_TRIES - 1:
                    raise
                time.sleep(REPLACE_PAUSE_S)
    except BaseException:
        try:
            tmp.unlink(missing_ok=True)
        except OSError as e:
            log(f"UWAGA: the temporary file {tmp} stays behind: {e}")
        raise
    _fsync_dir(path.parent)


def write_bytes(path: Path | str, data: bytes) -> None:
    """write_text for a copy taken byte for byte."""
    path = Path(path)
    if b"\0" in data:
        raise ValueError(f"refusing to write zero bytes into {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        with open(tmp, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        for attempt in range(REPLACE_TRIES):
            try:
                os.replace(tmp, path)
                break
            except PermissionError:
                if attempt == REPLACE_TRIES - 1:
                    raise
                time.sleep(REPLACE_PAUSE_S)
    except BaseException:
        try:
            tmp.unlink(missing_ok=True)
        except OSError as e:
            log(f"UWAGA: the temporary file {tmp} stays behind: {e}")
        raise
    _fsync_dir(path.parent)


def append_text(path: Path | str, text: str, header: str = "", newline: str | None = "\n",
                encoding: str = "utf-8") -> None:
    """One more piece at the end of an append-only file, on the disk before this returns.

    `header` goes first when the file does not exist yet. An append that is cut short loses at
    most its own tail — what was there before had its fsync already.
    """
    path = Path(path)
    if "\0" in text or "\0" in header:
        raise ValueError(f"refusing to write zero bytes into {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    first_time = not path.exists()
    with open(path, "a", encoding=encoding, newline=newline) as f:
        f.write((header if first_time else "") + text)
        f.flush()
        os.fsync(f.fileno())


def copy_file(source: Path | str, target: Path | str) -> None:
    """A backup copy that is really on the disk — and never a copy of zeros."""
    source, target = Path(source), Path(target)
    data = source.read_bytes()
    if b"\0" in data:
        raise ZeroedMemory([(source, data.count(0), len(data))])
    write_bytes(target, data)
    try:
        os.utime(target, (source.stat().st_atime, source.stat().st_mtime))
    except OSError:
        pass  # the date in the name says when; the mtime is a courtesy


# ---------------------------------------------------------------- zero bytes

def zero_count(path: Path | str) -> tuple[int, int]:
    """(zero bytes, size) of one file; (0, 0) when it is not there or cannot be read."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return 0, 0
    return data.count(0), len(data)


def memory_files(knowledge_dir: Path, instruction_paths) -> list[Path]:
    """What the cycle reads and writes: the instruction files and the text files of wiedza\\."""
    out = [Path(p) for p in instruction_paths if Path(p).is_file()]
    if knowledge_dir.is_dir():
        for p in sorted(knowledge_dir.iterdir()):
            if not p.is_file() or ".tmp-" in p.name:
                continue
            if p.suffix.lower() in TEXT_SUFFIXES or p.name.startswith("."):
                out.append(p)
    return out


def find_zeroed(paths) -> list[tuple[Path, int, int]]:
    """Every file with at least one zero byte: (path, zero bytes, size)."""
    found = []
    for p in paths:
        zeros, size = zero_count(p)
        if zeros:
            found.append((Path(p), zeros, size))
    return found


def healthy_copy(path: Path) -> Path | None:
    """The newest copy of `path` without a single zero byte — the daily copies first, then the
    backups taken next to the file and in wiedza\\kopie. None when there is none."""
    path = Path(path)
    candidates: list[Path] = []
    home = CLAUDE_HOME.parent
    try:
        rel = path.resolve().relative_to(home.resolve())
    except (ValueError, OSError):
        rel = None
    if rel is not None:
        candidates += [DAILY_DIR / slot / rel for slot in DAILY_SLOTS]
    siblings = list(path.parent.glob(f"{path.name}.bak-*")) + list(path.parent.glob(f"{path.name}.przed-*"))
    kopie = CLAUDE_HOME / "wiedza" / "kopie"
    if kopie.is_dir():
        siblings += list(kopie.glob(f"{path.stem}-*{path.suffix}"))
    siblings.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    for c in candidates + siblings:
        zeros, size = zero_count(c)
        if size and not zeros:
            return c
    return None


def describe_zeroed(found: list[tuple[Path, int, int]]) -> str:
    parts = []
    for p, zeros, size in found:
        copy = healthy_copy(p)
        where = f"ostatnia zdrowa kopia: {copy}" if copy else "zdrowej kopii nie znalazlem"
        parts.append(f"{p} ({zeros} z {size} bajtow to zera; {where})")
    return ("ALARM: wyzerowane pliki pamieci - " + "; ".join(parts) +
            f". Nic na nich nie buduje i nie robie z nich kopii. Przywrocenie: {RESTORE_HINT}")


def guard(paths) -> None:
    """Stops the run when any of the memory files has zero bytes in it — loudly."""
    found = find_zeroed(paths)
    if found:
        raise ZeroedMemory(found)
