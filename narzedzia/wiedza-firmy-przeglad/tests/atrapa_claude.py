"""Atrapa `claude -p` dla testow przegladu - zero prawdziwych wywolan modelu.

Czyta stdin jak prawdziwy claude, oddaje koperte `--output-format json` z structured_output.
Paczka: kazda wypowiedz z "USTALENIE: <tresc>" daje jedno ustalenie (temat z "TEMAT=<id>",
poufnosc z "POZIOM=<poziom>"); "SEKRET" daje ustalenie z haslem (do proby negatywnej).
Konsolidacja: wpisy E o tej samej tresci sklejone w jeden.
Sterowanie srodowiskiem: ATRAPA_LOG (katalog - jeden pusty plik na kazde wywolanie),
ATRAPA_PADA_NA (tekst - gdy jest w materiale, atrapa konczy sie bledem), ATRAPA_POZIOM_KONS
(wymuszony poziom w odpowiedzi konsolidacji), ATRAPA_SMIECI=1 (odpowiedz, ktora nie jest JSON-em).
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
schemat = argv[argv.index("--json-schema") + 1]
assert "-p" in argv and argv[argv.index("--model") + 1] == "sonnet", argv
assert "--no-session-persistence" in argv and "--safe-mode" in argv, argv
material = wejscie.split("## Materiał\n", 1)[-1]
konsolidacja = '"wpisy"' in schemat

if os.environ.get("ATRAPA_LOG"):  # katalog, plik na wywolanie: rownolegle dopisywanie do jednego gubi linie
    os.makedirs(os.environ["ATRAPA_LOG"], exist_ok=True)
    etap = "konsolidacja" if konsolidacja else "paczka"
    with open(os.path.join(os.environ["ATRAPA_LOG"], f"{uuid.uuid4().hex}.{etap}"), "w", encoding="utf-8"):
        pass
pada = os.environ.get("ATRAPA_PADA_NA")
if pada and pada in material:
    print("atrapa: awaria na zyczenie", file=sys.stderr)
    sys.exit(3)
if os.environ.get("ATRAPA_SMIECI"):
    print("to nie jest json")
    sys.exit(0)

if not konsolidacja:
    ustalenia = []
    for m in re.finditer(r"^\[#(\d+) (\d{4}-\d{2}-\d{2}) [\d:]+ (?:Primo|AI)\] (.*)$", material, re.M):
        cid, data, tekst = int(m.group(1)), m.group(2), m.group(3)
        temat = (re.search(r"TEMAT=(\S+)", tekst) or [None, "temat-a"])[1]
        poziom = (re.search(r"POZIOM=(\S+)", tekst) or [None, "wewnetrzne"])[1]
        if "USTALENIE:" in tekst:
            tresc = tekst.split("USTALENIE:", 1)[1].split(" TEMAT=")[0].split(" POZIOM=")[0].strip()
            ustalenia.append({"tresc": tresc, "temat": temat, "poufnosc": poziom, "data_ustalenia": data,
                              "chunk_id": cid, "niepewne": "NIEPEWNE" in tekst,
                              "powod": "atrapa: niepewne" if "NIEPEWNE" in tekst else ""})
        if "SEKRET" in tekst:
            ustalenia.append({"tresc": "Hasło do panelu sklepu: Xk9pQ2zzR7 (zapisane w rozmowie).",
                              "temat": "temat-a", "poufnosc": "wrazliwe", "data_ustalenia": data,
                              "chunk_id": cid, "niepewne": False})
    dane = {"ustalenia": ustalenia, "pominiete_tajne": 0}
else:
    wpisy, po_tresci = [], {}
    for m in re.finditer(r"^E(\d+) \[(\S+)\] \[(\S+)\](?: \[niepewne: [^\]]*\])? (.*)$", material, re.M):
        e, data, poziom, tresc = m.group(1), m.group(2), m.group(3), m.group(4)
        if tresc in po_tresci:
            w = po_tresci[tresc]
            w["zrodla"].append(f"E{e}")
            w["data_ustalenia"] = max(w["data_ustalenia"], data)
            continue
        w = {"tresc": tresc, "poufnosc": os.environ.get("ATRAPA_POZIOM_KONS") or poziom,
             "data_ustalenia": data, "zrodla": [f"E{e}"], "niepewne": "NIEPEWNE" in tresc,
             "powod": "atrapa: niepewne" if "NIEPEWNE" in tresc else ""}
        po_tresci[tresc] = w
        wpisy.append(w)
    dane = {"wpisy": wpisy}

print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "",
                  "structured_output": dane, "total_cost_usd": 0.0125,
                  "usage": {"input_tokens": 100, "cache_creation_input_tokens": 10,
                            "cache_read_input_tokens": 50, "output_tokens": 20}}, ensure_ascii=False))
