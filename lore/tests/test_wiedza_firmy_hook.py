"""Hook przypomnienie.js: podpowiedz "Z WIEDZY FIRMY" (jfwiedza). Atrapa serwera na 127.0.0.1, wlasny
rejestr, konfiguracja i stan w tmp_path - prawdziwy ~/.claude.json ani serwer jfwiedza nie sa ruszane.
Lore jest w tych probach wylaczone w rejestrze, wiec liczy sie tylko nowa czesc."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

HOOK = Path(__file__).resolve().parents[2] / "narzedzia" / "przypomnienie.js"
RULES = "ZASADY: odpowiadaj w sekundach, rozdawaj w tle."
TOKEN = "Bearer sekret-testowy-123"
HEADER = "Z WIEDZY FIRMY (jfwiedza, automat)"
ALARM = "UWAGA: podpowiedz z wiedzy firmy (jfwiedza) nie dziala"
PROMPT = "mentol FBA - czy potrzebna oferta na PL?"

node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="no node on this machine")


def wpis(i: int, tresc: str, autor: str = "Primo", data: str = "2026-10-14") -> dict:
    return {"id": i, "tresc": tresc, "autor": autor, "data": data, "temat": "oferty", "poufnosc": "jawne"}


def rpc(dane: dict) -> str:
    return json.dumps({"jsonrpc": "2.0", "id": 1, "result": {
        "content": [{"type": "text", "text": json.dumps(dane, ensure_ascii=False)}], "isError": False}})


class Atrapa:
    """Serwer jfwiedza na niby: odpowiedz ustawiana w tescie, kazde zadanie zapisane."""

    def __init__(self):
        self.status = 200
        self.cialo = rpc({"wyniki": []})
        self.zwloka = 0.0
        self.zadania: list[dict] = []
        atrapa = self

        class Obsluga(BaseHTTPRequestHandler):
            def do_POST(self):
                dl = int(self.headers.get("Content-Length") or 0)
                atrapa.zadania.append({"naglowki": dict(self.headers),
                                       "cialo": json.loads(self.rfile.read(dl).decode("utf-8"))})
                if atrapa.zwloka:
                    time.sleep(atrapa.zwloka)
                b = atrapa.cialo.encode("utf-8")
                try:
                    self.send_response(atrapa.status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(b)))
                    self.end_headers()
                    self.wfile.write(b)
                except (ConnectionError, OSError):
                    pass  # klient juz odszedl (proba limitu czasu) - to jest wynik oczekiwany

            def log_message(self, *a):
                pass

        self.serwer = ThreadingHTTPServer(("127.0.0.1", 0), Obsluga)
        self.serwer.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.serwer.server_address[1]}/mcp"
        threading.Thread(target=self.serwer.serve_forever, daemon=True).start()

    def wyniki(self, *wpisy, **reszta):
        self.cialo = rpc({"wyniki": list(wpisy), "uwaga": "ustalenia ludzi", **reszta})


@pytest.fixture
def atrapa():
    a = Atrapa()
    yield a
    a.serwer.shutdown()
    a.serwer.server_close()


def konfig(tmp_path: Path, url: str, token: str = TOKEN) -> Path:
    p = tmp_path / "claude.json"
    p.write_text(json.dumps({"mcpServers": {"jfwiedza": {"type": "http", "url": url,
                                                         "headers": {"Authorization": token}}}}), encoding="utf-8")
    return p


def rejestr(tmp_path: Path, wiedzafirmy=True) -> Path:
    moduly = {"kierownik": True, "wiedza": False, "lore": False}
    if wiedzafirmy is not None:
        moduly["wiedzafirmy"] = wiedzafirmy
    p = tmp_path / "instalacja.json"
    p.write_text(json.dumps({"wersja": 1, "moduly": moduly}), encoding="utf-8")
    return p


def hook(tmp_path: Path, prompt: str = PROMPT, sesja: str = "s1", rules: str = RULES, **env) -> tuple[str, float]:
    reminder = tmp_path / "reminder.json"
    reminder.write_text(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                           "additionalContext": rules}}), encoding="utf-8")
    full = dict(os.environ, MR_ARCHIWUM_STAN=str(tmp_path / "arch.json"), LORE_HOME=str(tmp_path / "bez-lore"),
                MR_LORE_PYTHON=str(tmp_path / "bez-pythona.exe"), MR_INSTALACJA=str(tmp_path / "instalacja.json"),
                MR_INSTALACJA_ALARM=str(tmp_path / "rej-alarm.json"), MR_JFWIEDZA_STAN=str(tmp_path / "wf.json"),
                MR_JFWIEDZA_KONFIG=str(tmp_path / "claude.json"))
    full.update(env)
    t0 = time.monotonic()
    r = subprocess.run([node, str(HOOK), str(reminder), str(tmp_path / "bez-postepu")],
                       input=json.dumps({"session_id": sesja, "prompt": prompt}),
                       capture_output=True, text=True, encoding="utf-8", env=full, timeout=30)
    czas = time.monotonic() - t0
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"], czas


def stan(tmp_path: Path) -> dict:
    return json.loads((tmp_path / "wf.json").read_text(encoding="utf-8"))


# ---------------------------------------------------------------- trafienie

def test_hit_is_glued_after_the_rules_with_author_and_date(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.wyniki(wpis(273, "Kazdy towar na FBA musi miec oferte na Amazon PL z tym samym SKU i ASIN-em."),
                  wpis(681, "Zdjecie glowne mentolu na eBayu to wariant 40 g.", autor="Gosia", data="2026-09-16"))
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(RULES)
    blok = ctx[len(RULES):].strip()
    assert blok.startswith(HEADER)
    assert "- [Primo, 2026-10-14, #273] Kazdy towar na FBA" in blok
    assert "- [Gosia, 2026-09-16, #681] Zdjecie glowne" in blok
    s = stan(tmp_path)
    assert s["wynik"] == "trafienia" and s["sesje"]["s1"]["ids"] == [273, 681]
    # klient autoryzuje sie jak klient MCP: naglowek z konfiguracji, jedno bezstanowe tools/call
    z = atrapa.zadania[0]
    assert z["naglowki"]["Authorization"] == TOKEN
    assert z["cialo"]["method"] == "tools/call" and z["cialo"]["params"]["name"] == "szukaj_wiedzy"
    assert z["cialo"]["params"]["arguments"]["pytanie"] == PROMPT
    # token nie wycieka do stanu
    assert "sekret-testowy" not in (tmp_path / "wf.json").read_text(encoding="utf-8")


def test_what_was_glued_is_not_repeated_in_the_same_conversation(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.wyniki(wpis(1, "Pierwsze ustalenie o mentolu i FBA na rynku PL."))
    hook(tmp_path)
    ctx, _ = hook(tmp_path)
    assert ctx == RULES and stan(tmp_path)["wynik"] == "juz-doklejone"
    ctx3, _ = hook(tmp_path, sesja="inna-rozmowa")
    assert "#1]" in ctx3


def test_block_never_exceeds_its_budget(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    dlugi = "Bardzo dlugie ustalenie o wysylkach FBA i ofertach na rynku PL, powtarzane w kolko. " * 15
    atrapa.wyniki(wpis(1, dlugi), wpis(2, dlugi), wpis(3, dlugi))
    ctx, _ = hook(tmp_path)
    blok = ctx[len(RULES):].strip()
    assert blok.startswith(HEADER) and len(blok) <= 450
    assert all(l.endswith("...") for l in blok.splitlines()[1:])
    # duzy ladunek zasad: blok sie kurczy, calosc dalej pod sufitem 1500 (albo blok nie idzie wcale)
    duze = "Z" * 1150
    ctx2, _ = hook(tmp_path, rules=duze, sesja="s2")
    assert ctx2.startswith(duze) and len(ctx2) <= 1500


def test_no_hits_means_nothing_glued(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.wyniki(komunikat="Brak ustaleń na ten temat.")
    ctx, _ = hook(tmp_path)
    assert ctx == RULES and stan(tmp_path)["wynik"] == "brak-trafien"


def test_short_message_is_not_asked(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    ctx, _ = hook(tmp_path, prompt="ok")
    assert ctx == RULES and atrapa.zadania == [] and stan(tmp_path)["wynik"] == "pominiete"


# ---------------------------------------------------------------- kiedy w ogole nie pytac (cisza)

@pytest.mark.parametrize("wiedzafirmy", [False, None, "brak rejestru"])
def test_module_not_chosen_means_no_request(atrapa, tmp_path, wiedzafirmy):
    if wiedzafirmy == "brak rejestru":
        moduly = None
    else:
        rejestr(tmp_path, wiedzafirmy)
        moduly = wiedzafirmy
    konfig(tmp_path, atrapa.url)
    atrapa.wyniki(wpis(1, "Ustalenie, ktore nie moze sie pojawic bez modulu wiedzy firmy."))
    ctx, _ = hook(tmp_path)
    assert ctx == RULES and atrapa.zadania == [], moduly
    assert not (tmp_path / "wf.json").exists()


@pytest.mark.parametrize("zawartosc", [None, {"mcpServers": {"lore": {"type": "stdio"}}}, {}])
def test_machine_without_jfwiedza_stays_silent(tmp_path, zawartosc):
    rejestr(tmp_path)
    if zawartosc is not None:
        (tmp_path / "claude.json").write_text(json.dumps(zawartosc), encoding="utf-8")
    for _ in range(2):
        ctx, _ = hook(tmp_path)
        assert ctx == RULES
    s = stan(tmp_path)
    assert s["wynik"] == "brak-konfiguracji" and "awaria" not in s


# ---------------------------------------------------------------- proby negatywne

def test_bad_token_alarms_at_once_then_keeps_quiet(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url, token="Bearer zly")
    atrapa.status, atrapa.cialo = 401, json.dumps({"error": "unauthorized"})
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(ALARM) and "HTTP 401" in ctx.splitlines()[0] and RULES in ctx
    ctx2, _ = hook(tmp_path)
    assert ctx2 == RULES
    s = stan(tmp_path)
    assert s["wynik"] == "awaria" and s["awaria"]["ile"] == 2
    assert "Bearer zly" not in (tmp_path / "wf.json").read_text(encoding="utf-8")


@pytest.mark.parametrize("status, cialo, slowo", [
    (200, "<html>proxy</html>", "nie JSON"),
    (200, json.dumps({"jsonrpc": "2.0", "id": 1, "error": {"code": -32602, "message": "Unknown tool"}}), "Unknown tool"),
    (200, json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"content": [{"type": "text", "text": "padlo"}],
                                                             "isError": True}}), "padlo"),
    (200, rpc({"cos": "innego"}), "bez listy wynikow"),
    (404, "nie ma", "HTTP 404"),
])
def test_garbage_from_the_server_alarms_at_once(atrapa, tmp_path, status, cialo, slowo):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.status, atrapa.cialo = status, cialo
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(ALARM) and slowo in ctx.splitlines()[0] and RULES in ctx


def test_broken_config_alarms_at_once(tmp_path):
    rejestr(tmp_path)
    (tmp_path / "claude.json").write_text("{ zepsuty", encoding="utf-8")
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(ALARM) and "nieczytelny" in ctx and RULES in ctx


def test_slow_server_does_not_hold_the_message_and_alarms_on_the_third_time(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.zwloka = 3.0
    atrapa.wyniki(wpis(1, "Ustalenie, ktore przyszloby za pozno i nie moze sie pojawic."))
    for i in (1, 2):
        ctx, czas = hook(tmp_path)
        assert ctx == RULES, i            # pojedyncza awaria sieci jest spodziewana - bez krzyku
        assert czas < 2.5, czas           # 650 ms limitu + start node, a nie 3 s serwera
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(ALARM) and "650 ms" in ctx and "3 razy z rzedu" in ctx
    # po progu przerwa: nastepna wiadomosc w ogole nie pyta serwera
    n = len(atrapa.zadania)
    ctx4, _ = hook(tmp_path)
    assert ctx4 == RULES and len(atrapa.zadania) == n and stan(tmp_path)["wynik"] == "przerwa"


def test_server_down_counts_as_network_failure(tmp_path):
    rejestr(tmp_path)
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()                             # port, na ktorym nikt nie slucha
    konfig(tmp_path, f"http://127.0.0.1:{port}/mcp")
    ctx, _ = hook(tmp_path)
    assert ctx == RULES
    st = stan(tmp_path)
    assert st["wynik"] == "awaria" and st["awaria"]["siec"] is True and st["awaria"]["ile"] == 1


def test_recovery_clears_the_failure(atrapa, tmp_path):
    rejestr(tmp_path)
    konfig(tmp_path, atrapa.url)
    atrapa.status, atrapa.cialo = 401, "{}"
    hook(tmp_path)
    atrapa.status = 200
    atrapa.wyniki(wpis(5, "Ustalenie po naprawie tokenu, juz widoczne w rozmowie."))
    ctx, _ = hook(tmp_path)
    assert ctx.startswith(RULES) and "#5]" in ctx
    st = stan(tmp_path)
    assert "awaria" not in st and "alarm" not in st
