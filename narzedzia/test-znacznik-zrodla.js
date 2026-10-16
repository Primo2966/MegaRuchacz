// Proba hooka znacznika zrodla (narzedzia\znacznik-zrodla.js) na sztucznych transkryptach:
// tura z Lore, z jfwiedza, z doklejka, u workera, bez niczego (proba negatywna - takze
// wiadomosc cytujaca naglowek doklejki i definicje narzedzi w transkrypcie), tura dluzsza niz
// pierwszy kawalek czytania, uszkodzony i brakujacy transkrypt, zepsuty plik stanu.
// Wszystko w %TEMP%, prawdziwy stan (~\.claude\mr) nietkniety; hook bez okna (windowsHide).
//
// Uzycie:  node narzedzia\test-znacznik-zrodla.js [--zostaw]
// Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const HOOK = path.join(__dirname, "znacznik-zrodla.js");
const T = fs.mkdtempSync(path.join(os.tmpdir(), "mr-test-znacznika-"));
const STAN = path.join(T, "stan.json");
let zle = 0;

function sprawdz(co, ok, szczegol) {
  console.log((ok ? "OK    " : "BLAD  ") + co + (!ok && szczegol !== undefined ? " -- " + szczegol : ""));
  if (!ok) zle++;
}

function uruchom(wejscie, env) {
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [HOOK], {
    input: wejscie === null ? "" : (typeof wejscie === "string" ? wejscie : JSON.stringify(wejscie)),
    encoding: "utf8",
    windowsHide: true,
    timeout: 10000,
    env: Object.assign({}, process.env, { MR_ZNACZNIK_STAN: STAN }, env || {}),
  });
  let msg = "";
  let jsonOk = true;
  if ((r.stdout || "").trim()) {
    try { msg = JSON.parse(r.stdout).systemMessage || ""; } catch (e) { jsonOk = false; }
  }
  return { kod: r.status, stdout: r.stdout || "", stderr: r.stderr || "", msg, jsonOk, ms: Date.now() - t0 };
}

function stan() { return JSON.parse(fs.readFileSync(STAN, "utf8")); }

// --- budowanie transkryptow w ukladzie Claude Code 2.1.x
let licz = 0;
const baza = Date.parse("2026-10-16T10:00:00Z");
function czas(s) { return new Date(baza + s * 1000).toISOString(); }
function uzytkownik(tekst, s, extra) {
  return Object.assign({ type: "user", isSidechain: false, uuid: "u" + (++licz), timestamp: czas(s),
    origin: { kind: "human" }, message: { role: "user", content: tekst } }, extra || {});
}
function wynikNarzedzia(id, tekst, s) {
  return { type: "user", isSidechain: false, uuid: "r" + (++licz), timestamp: czas(s),
    message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: tekst }] } };
}
function narzedzie(nazwa, s, extra) {
  const id = "toolu_" + (++licz);
  return Object.assign({ type: "assistant", isSidechain: false, uuid: "a" + licz, timestamp: czas(s),
    message: { role: "assistant", content: [{ type: "tool_use", id, name: nazwa, input: { query: "x" } }] } }, extra || {});
}
function odpowiedz(tekst, s) {
  return { type: "assistant", isSidechain: false, uuid: "a" + (++licz), timestamp: czas(s),
    message: { role: "assistant", content: [{ type: "text", text: tekst }] } };
}
function doklejka(tekst, s) {
  return { type: "attachment", isSidechain: false, uuid: "h" + (++licz), timestamp: czas(s),
    attachment: { type: "hook_additional_context", content: [tekst], hookName: "UserPromptSubmit", hookEvent: "UserPromptSubmit" } };
}
// Definicje narzedzi w transkrypcie (jak api-request-blob) - nazwy mcp__lore__ NIE sa wywolaniami.
function definicje(s) {
  return { type: "api-request-blob", timestamp: czas(s), message: { role: "system", content: [
    { type: "text", text: "tools" }, { name: "mcp__lore__lore_search", server: "lore" }, { name: "mcp__jfwiedza__szukaj_wiedzy" }] } };
}
function zapisz(nazwa, wpisy, surowe) {
  const p = path.join(T, nazwa + ".jsonl");
  fs.writeFileSync(p, surowe !== undefined ? surowe : wpisy.map((w) => JSON.stringify(w)).join("\n") + "\n", "utf8");
  return p;
}
function stop(p, sesja) { return { session_id: sesja || path.basename(p, ".jsonl"), transcript_path: p, hook_event_name: "Stop", stop_hook_active: false }; }

const LORE = "\u{1F7E3} Lore";
const JFW = "\u{1F7E0} jfwiedza";
const X = "×";

try {
  // 1. Lore: lore_search + lore_context w biezacej turze
  {
    const t1 = narzedzie("mcp__lore__lore_search", 2);
    const t2 = narzedzie("mcp__lore__lore_context", 4);
    const p = zapisz("lore", [definicje(0), uzytkownik("co ustalilismy o robocie?", 1), t1,
      wynikNarzedzia(t1.message.content[0].id, "wyniki", 3), t2, wynikNarzedzia(t2.message.content[0].id, "kontekst", 5), odpowiedz("Ustalono X.", 6)]);
    const r = uruchom(stop(p));
    sprawdz("lore: kod 0 i poprawny JSON", r.kod === 0 && r.jsonOk, r.stdout + r.stderr);
    sprawdz("lore: linia '" + LORE + ": wyszukano 1" + X + ", kontekst 1" + X + "'", r.msg === LORE + ": wyszukano 1" + X + ", kontekst 1" + X, r.msg);
    sprawdz("lore: bez 'decision' (tura nie jest blokowana)", !/decision/.test(r.stdout), r.stdout);
    sprawdz("lore: stan 'pokazano' z czasem przebiegu", stan().wynik === "pokazano" && !!stan().czas, JSON.stringify(stan()));
    sprawdz("lore: hook szybki (< 2 s z uruchomieniem node)", r.ms < 2000, r.ms + " ms");
  }

  // 2. jfwiedza: 2x szukaj_wiedzy + tematy; poprzednia tura z Lore NIE liczy sie
  {
    const stara = narzedzie("mcp__lore__lore_search", 2);
    const a = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 11);
    const b = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 12);
    const c = narzedzie("mcp__jfwiedza__tematy", 13);
    const p = zapisz("jfwiedza", [uzytkownik("stara tura", 1), stara, wynikNarzedzia(stara.message.content[0].id, "x", 3), odpowiedz("ok", 4),
      uzytkownik("co wiemy o kadzidelkach?", 10), a, b, c, odpowiedz("Wiemy Y.", 14)]);
    const r = uruchom(stop(p));
    sprawdz("jfwiedza: linia '" + JFW + ": wyszukano 2" + X + ", tematy 1" + X + "' (bez Lore z poprzedniej tury)",
      r.msg === JFW + ": wyszukano 2" + X + ", tematy 1" + X, r.msg);
  }

  // 3. doklejki obu hookow (Lore i wiedza firmy) bez wywolan + oba serwery naraz
  {
    const a = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 3);
    const p = zapisz("doklejka", [uzytkownik("pytanie", 1),
      doklejka("TRYB MEGARUCHACZA ...\n\nZ ARCHIWUM (Lore, automat) - trop, nie dowod.\n- #1 ...", 1),
      doklejka("Z WIEDZY FIRMY (jfwiedza, automat) - ...", 1), a, odpowiedz("ok", 4)]);
    const r = uruchom(stop(p));
    sprawdz("doklejka: '" + LORE + ": doklejono z archiwum · " + JFW + ": wyszukano 1" + X + ", doklejono z wiedzy firmy'",
      r.msg === LORE + ": doklejono z archiwum · " + JFW + ": wyszukano 1" + X + ", doklejono z wiedzy firmy", r.msg);
  }

  // 4. PROBA NEGATYWNA: nic z Lore/jfwiedza - wiadomosc cytuje naglowki doklejek, w transkrypcie
  //    leza definicje narzedzi mcp__lore__, sa inne narzedzia MCP, doklejka bez naglowka, meta-skill
  {
    const bash = narzedzie("Bash", 3);
    const inne = narzedzie("mcp__ecommerce-helper__spapi_get", 4);
    const p = zapisz("nic", [definicje(0),
      uzytkownik("rozpoznawaj 'Z ARCHIWUM (Lore' i 'Z WIEDZY FIRMY (jfwiedza' oraz mcp__lore__lore_search", 1),
      doklejka("TRYB MEGARUCHACZA - same zasady", 1),
      uzytkownik("Base directory for this skill: mcp__lore__lore_search", 2, { isMeta: true, origin: undefined }),
      bash, wynikNarzedzia(bash.message.content[0].id, "Z ARCHIWUM (Lore w wyniku narzedzia", 3),
      inne, odpowiedz("Zrobione.", 5)]);
    const r = uruchom(stop(p));
    sprawdz("nic: kod 0 i pusty wypis (zadnej linii)", r.kod === 0 && r.stdout.trim() === "", r.stdout);
    sprawdz("nic: stan 'nic' (slad, ze hook byl)", stan().wynik === "nic", JSON.stringify(stan()));
  }

  // 5. worker: wywolanie Lore w pliku subagents\agent-*.jsonl w trakcie tury; drugi Stop tej
  //    samej rozmowy nie liczy go drugi raz
  {
    const sesja = "sesja-workera";
    const teraz = Date.now();
    const iso = (ms) => new Date(ms).toISOString();
    const ag = { type: "tool_use", id: "toolu_ag", name: "Agent", input: {} };
    const p = zapisz(sesja, [
      Object.assign(uzytkownik("rozdaj", 0), { timestamp: iso(teraz - 60000) }),
      { type: "assistant", isSidechain: false, timestamp: iso(teraz - 59000), message: { role: "assistant", content: [ag] } },
      Object.assign(wynikNarzedzia("toolu_ag", "worker ruszyl", 0), { timestamp: iso(teraz - 58000) }),
      Object.assign(odpowiedz("Rozdane.", 0), { timestamp: iso(teraz - 57000) })]);
    const kat = path.join(T, sesja, "subagents");
    fs.mkdirSync(kat, { recursive: true });
    const w = narzedzie("mcp__lore__lore_search", 0, { isSidechain: true, agentId: "abc" });
    w.timestamp = iso(teraz - 50000);
    const stary = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 0, { isSidechain: true, agentId: "abc" });
    stary.timestamp = iso(teraz - 3600000);   // przed poczatkiem tury - nie liczy sie
    fs.writeFileSync(path.join(kat, "agent-abc.jsonl"), [stary, w].map((x) => JSON.stringify(x)).join("\n") + "\n", "utf8");
    const r = uruchom(stop(p, sesja));
    sprawdz("worker: '" + LORE + ": wyszukano 1" + X + " (w tym workerzy 1" + X + ")'",
      r.msg === LORE + ": wyszukano 1" + X + " (w tym workerzy 1" + X + ")", r.msg);
    const r2 = uruchom(stop(p, sesja));
    sprawdz("worker: drugi Stop tej rozmowy nie liczy tego samego wywolania", r2.stdout.trim() === "", r2.stdout);
  }

  // 6. tura dluzsza niz pierwszy kawalek czytania (1 MB) + linia zepsuta w srodku tury
  {
    const t1 = narzedzie("mcp__lore__lore_search", 3);
    const wpisy = [uzytkownik("stara", 0), narzedzie("mcp__jfwiedza__szukaj_wiedzy", 0.5), uzytkownik("dluga tura", 1), t1,
      wynikNarzedzia(t1.message.content[0].id, "z".repeat(3 * 1024 * 1024), 4), odpowiedz("ok", 5)];
    const linie = wpisy.map((x) => JSON.stringify(x));
    linie.splice(4, 0, "{to nie jest json");
    const p = zapisz("dluga", null, linie.join("\n") + "\n");
    const r = uruchom(stop(p));
    sprawdz("dluga tura: Lore znalezione mimo 3 MB w srodku tury", r.msg === LORE + ": wyszukano 1" + X, r.msg);
    sprawdz("dluga tura: zepsuta linia policzona w stanie, bez awarii", stan().zepsute_linie === 1 && stan().wynik === "pokazano", JSON.stringify(stan()));
  }

  // 7. PROBA NEGATYWNA: uszkodzony transkrypt - kod 0, alarm raz, slad w stanie
  {
    fs.writeFileSync(STAN, "{}", "utf8");
    const p = zapisz("smieci", null, "\u0000\u0000smieci\nnie json\n{\"type\":\"assistant\"\n");
    const r = uruchom(stop(p));
    sprawdz("uszkodzony: kod 0 (tura sie nie wywraca)", r.kod === 0, r.stderr);
    sprawdz("uszkodzony: linia UWAGA dla uzytkownika", /^UWAGA: znacznik Lore\/jfwiedza nie dziala/.test(r.msg), r.msg);
    const s = stan();
    sprawdz("uszkodzony: stan 'awaria' z powodem", s.wynik === "awaria" && /nie ma wiadomosci uzytkownika/.test(s.powod) && s.awaria && s.awaria.ile === 1, JSON.stringify(s));
    const r2 = uruchom(stop(p));
    sprawdz("uszkodzony: ten sam alarm nie wraca przy kazdej odpowiedzi", r2.kod === 0 && r2.stdout.trim() === "", r2.stdout);
    sprawdz("uszkodzony: licznik awarii rosnie mimo ciszy", stan().awaria.ile === 2, JSON.stringify(stan()));
    // zdrowa tura sprzata awarie
    const ok = uruchom(stop(path.join(T, "lore.jsonl")));
    sprawdz("po awarii: zdrowa tura znakuje i sprzata awarie", ok.msg.startsWith(LORE) && !stan().awaria, JSON.stringify(stan()));
  }

  // 8. PROBA NEGATYWNA: brak pliku transkryptu, brak transcript_path, wejscie nie-JSON, puste wejscie
  {
    fs.writeFileSync(STAN, "{}", "utf8");
    const r = uruchom(stop(path.join(T, "nie-ma-takiego.jsonl")));
    sprawdz("brak transkryptu: kod 0 i UWAGA z powodem", r.kod === 0 && /brak pliku transkryptu/.test(r.msg), r.msg + r.stderr);
    const r2 = uruchom({ session_id: "x", hook_event_name: "Stop" });
    sprawdz("brak transcript_path: kod 0 i UWAGA (inna przyczyna = nowy alarm)", r2.kod === 0 && /bez transcript_path/.test(r2.msg), r2.msg);
    const r3 = uruchom("to nie json");
    sprawdz("wejscie nie-JSON: kod 0, slad w stanie", r3.kod === 0 && /nie JSON/.test(stan().powod), JSON.stringify(stan()));
    const r4 = uruchom(null);
    sprawdz("puste wejscie: kod 0, slad w stanie", r4.kod === 0 && /nic na wejsciu/.test(stan().powod), JSON.stringify(stan()));
  }

  // 9. zepsuty plik stanu nie blokuje znacznika
  {
    fs.writeFileSync(STAN, "{zepsuty", "utf8");
    const r = uruchom(stop(path.join(T, "lore.jsonl")));
    sprawdz("zepsuty stan: znacznik dalej wychodzi, stan zapisany od nowa", r.msg.startsWith(LORE) && stan().zepsuty_stan, r.msg + " / " + fs.readFileSync(STAN, "utf8").slice(0, 200));
  }
} catch (e) {
  sprawdz("test bez wywrotki", false, e && e.stack || e);
}

if (process.argv.includes("--zostaw")) console.log("pliki testu: " + T);
else fs.rmSync(T, { recursive: true, force: true });
console.log(zle === 0 ? "WYNIK: wszystkie proby przeszly" : "WYNIK: nieudanych prob: " + zle);
process.exit(zle === 0 ? 0 : 1);
