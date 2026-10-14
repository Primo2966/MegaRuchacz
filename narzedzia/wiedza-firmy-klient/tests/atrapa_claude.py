"""Atrapa polecenia `claude` (tylko `mcp get|add|remove`) - prawdziwa konfiguracja Claude Code nietknieta.

Stan serwerow MCP w pliku z ATRAPA_CLAUDE_STAN (JSON {"serwery": {...}, "wywolania": [...]}); bez tej
zmiennej atrapa odmawia pracy. Wyjscie `mcp get` jak w Claude Code 2.1 (URL i naglowki).
"""

import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")
sciezka = os.environ.get("ATRAPA_CLAUDE_STAN")
if not sciezka:
    print("atrapa claude: brak ATRAPA_CLAUDE_STAN", file=sys.stderr)
    sys.exit(99)
stan = json.load(open(sciezka, encoding="utf-8")) if os.path.exists(sciezka) else {"serwery": {}, "wywolania": []}
a = sys.argv[1:]
stan.setdefault("wywolania", []).append(a[:2] + ([a[2]] if len(a) > 2 else []))
serwery = stan.setdefault("serwery", {})
kod = 0
if a[:2] == ["mcp", "get"]:
    s = serwery.get(a[2])
    if s:
        print(f"{a[2]}:\n  Scope: User config (available in all your projects)\n  Status: x Failed to connect\n"
              f"  Type: http\n  URL: {s['url']}\n  Headers:")
        for h in s["headers"]:
            print(f"    {h}")
    else:
        print(f'No MCP server named "{a[2]}".', file=sys.stderr)
        kod = 1
elif a[:2] == ["mcp", "add"]:
    assert a[2:6] == ["--transport", "http", "--scope", "user"], a
    nazwa, url = a[6], a[7]
    assert a[8] == "--header", a
    if nazwa in serwery:
        print(f"MCP server {nazwa} already exists in user config", file=sys.stderr)
        kod = 1
    else:
        serwery[nazwa] = {"url": url, "headers": [a[9]]}
        print(f"Added HTTP MCP server {nazwa} with URL: {url} to user config")
elif a[:2] == ["mcp", "remove"]:
    assert a[3:5] == ["-s", "user"], a
    if serwery.pop(a[2], None) is None:
        print(f"No user-scoped MCP server found with name: {a[2]}", file=sys.stderr)
        kod = 1
else:
    print(f"atrapa claude: nieznane polecenie {a}", file=sys.stderr)
    kod = 98
json.dump(stan, open(sciezka, "w", encoding="utf-8"))
sys.exit(kod)
