"""Maskowanie sekretów przed zapisem do indeksu."""

from __future__ import annotations

import re

MASKA = "[MASKED]"

_KLUCZE = (
    r"api[_\-]?key|apikey|access[_\-]?token|refresh[_\-]?token|id[_\-]?token|auth[_\-]?token|"
    r"client[_\-]?secret|secret[_\-]?key|secret|token|password|passwd|pwd|authorization|"
    r"private[_\-]?key|x-api-key"
)

_WZORCE: list[tuple[re.Pattern, str]] = [
    # Bearer <token>
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9\-._~+/=]{8,}"), f"Bearer {MASKA}"),
    # klucz: wartość / klucz=wartość / "klucz": "wartość"
    # (bez \b z przodu — POSTGRES_PASSWORD=, WA_API_KEY= też mają być maskowane)
    (
        re.compile(
            rf'(?i)({_KLUCZE})\b(\s*["\']?\s*[:=]\s*["\']?)([^\s"\',;}}\]]{{6,}})'
        ),
        rf"\1\2{MASKA}",
    ),
    # znane prefiksy kluczy
    (re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9_\-]{10,}"), MASKA),
    (re.compile(r"\bctx7sk-[A-Za-z0-9\-]{8,}"), MASKA),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), MASKA),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), MASKA),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), MASKA),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}"), MASKA),
    (re.compile(r"\bAIza[0-9A-Za-z\-_]{30,}"), MASKA),
    # JWT
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"), MASKA),
]

# hex >= 32 znaków (bez otaczających znaków alfanumerycznych)
_HEX = re.compile(r"(?<![A-Za-z0-9])[0-9a-fA-F]{32,}(?![A-Za-z0-9])")
# base64 >= 32 znaków
_B64 = re.compile(r"(?<![A-Za-z0-9+/=_\-])[A-Za-z0-9+/]{32,}={0,2}(?![A-Za-z0-9+/=])")


def _b64_podejrzany(m: re.Match) -> str:
    s = m.group(0)
    # zwykłe słowa/ścieżki nie mają jednocześnie cyfr, małych i wielkich liter
    if any(c.isdigit() for c in s) and any(c.islower() for c in s) and any(c.isupper() for c in s):
        return MASKA
    return s


def maskuj(tekst: str) -> str:
    if not tekst:
        return tekst
    for wz, zam in _WZORCE:
        tekst = wz.sub(zam, tekst)
    tekst = _HEX.sub(MASKA, tekst)
    tekst = _B64.sub(_b64_podejrzany, tekst)
    return tekst
