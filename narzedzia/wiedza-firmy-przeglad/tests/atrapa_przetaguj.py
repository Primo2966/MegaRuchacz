"""Atrapa `claude -p` dla testow przetaguj.py - zero prawdziwych wywolan modelu.

Czyta stdin jak prawdziwy claude, oddaje koperte `--output-format json` z structured_output.
Wpis "W<n> [temat] tresc": temat glowny bez zmian, dodatkowe z "TAG=a,b" w tresci, przeniesienie
z "PRZENIES=x". Sterowanie srodowiskiem: ATRAPA_LOG (katalog - plik na kazde wywolanie),
ATRAPA_PADA_NA (tekst w materiale -> blad procesu), ATRAPA_ZMIEN_TRESC=1 (poczatek pierwszego wpisu
zmieniony), ATRAPA_GUB=1 (bez ostatniego wpisu), ATRAPA_NIEZNANY=1 (pierwszy wpis z nieznanym tematem).
"""

import json
import os
import re
import sys
import uuid

sys.stdout.reconfigure(encoding="utf-8")
sys.stdin.reconfigure(encoding="utf-8")
argv = sys.argv[1:]
wejscie = sys.stdin.read()
schemat = json.loads(argv[argv.index("--json-schema") + 1])
assert "-p" in argv and argv[argv.index("--model") + 1] == "sonnet", argv
assert "--no-session-persistence" in argv and "--safe-mode" in argv, argv
assert "dodatkowe" in schemat["properties"]["wpisy"]["items"]["properties"]
material = wejscie.split("## Materiał\n", 1)[-1]

if os.environ.get("ATRAPA_LOG"):
    os.makedirs(os.environ["ATRAPA_LOG"], exist_ok=True)
    with open(os.path.join(os.environ["ATRAPA_LOG"], f"{uuid.uuid4().hex}.tagi"), "w", encoding="utf-8"):
        pass
pada = os.environ.get("ATRAPA_PADA_NA")
if pada and pada in material:
    print("atrapa: awaria na zyczenie", file=sys.stderr)
    sys.exit(3)

wpisy = []
for m in re.finditer(r"^W(\d+) \[(\S+)\] (.*)$", material, re.M):
    n, temat, tresc = m.group(1), m.group(2), m.group(3)
    dod = (re.search(r"TAG=(\S+)", tresc) or [None, ""])[1]
    przen = re.search(r"PRZENIES=(\S+)", tresc)
    wpisy.append({"id": f"W{n}", "poczatek": " ".join(tresc.split()[:3]),
                  "temat": przen.group(1) if przen else temat,
                  "dodatkowe": [t for t in dod.split(",") if t],
                  **({"powod": "atrapa: zly temat"} if przen else {})})
if os.environ.get("ATRAPA_ZMIEN_TRESC") and wpisy:
    wpisy[0]["poczatek"] = "Zupelnie inne slowa"
if os.environ.get("ATRAPA_GUB") and wpisy:
    wpisy.pop()
if os.environ.get("ATRAPA_NIEZNANY") and wpisy:
    wpisy[0]["dodatkowe"] = ["nie-ma-takiego"]

print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "",
                  "structured_output": {"wpisy": wpisy}, "total_cost_usd": 0.004,
                  "usage": {"input_tokens": 100, "cache_creation_input_tokens": 10,
                            "cache_read_input_tokens": 50, "output_tokens": 20}}, ensure_ascii=False))
