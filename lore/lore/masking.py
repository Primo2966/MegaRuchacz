"""Masking of secrets before they reach the index."""

from __future__ import annotations

import re

MASK = "[MASKED]"

_KEYS = (
    r"api[_\-]?key|apikey|access[_\-]?token|refresh[_\-]?token|id[_\-]?token|auth[_\-]?token|"
    r"client[_\-]?secret|secret[_\-]?key|secret|token|password|passwd|pwd|authorization|"
    r"private[_\-]?key|x-api-key"
)

_PATTERNS: list[tuple[re.Pattern, str]] = [
    # Bearer <token>
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9\-._~+/=]{8,}"), f"Bearer {MASK}"),
    # key: value / key=value / "key": "value"
    # (no leading \b — POSTGRES_PASSWORD=, WA_API_KEY= have to be masked too)
    (
        re.compile(
            rf'(?i)({_KEYS})\b(\s*["\']?\s*[:=]\s*["\']?)([^\s"\',;}}\]]{{6,}})'
        ),
        rf"\1\2{MASK}",
    ),
    # known key prefixes
    (re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9_\-]{10,}"), MASK),
    (re.compile(r"\bctx7sk-[A-Za-z0-9\-]{8,}"), MASK),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), MASK),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), MASK),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), MASK),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}"), MASK),
    (re.compile(r"\bAIza[0-9A-Za-z\-_]{30,}"), MASK),
    # JWT
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"), MASK),
]

# hex >= 32 characters (without surrounding alphanumerics)
_HEX = re.compile(r"(?<![A-Za-z0-9])[0-9a-fA-F]{32,}(?![A-Za-z0-9])")
# base64 >= 32 characters
_B64 = re.compile(r"(?<![A-Za-z0-9+/=_\-])[A-Za-z0-9+/]{32,}={0,2}(?![A-Za-z0-9+/=])")


def _b64_suspicious(m: re.Match) -> str:
    s = m.group(0)
    # ordinary words/paths do not mix digits, lower and upper case at once
    if any(c.isdigit() for c in s) and any(c.islower() for c in s) and any(c.isupper() for c in s):
        return MASK
    return s


def mask(text: str) -> str:
    if not text:
        return text
    for pattern, repl in _PATTERNS:
        text = pattern.sub(repl, text)
    text = _HEX.sub(MASK, text)
    text = _B64.sub(_b64_suspicious, text)
    return text
