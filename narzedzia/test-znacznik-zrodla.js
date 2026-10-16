// Proba hooka znacznika zrodla (narzedzia\znacznik-zrodla.js). Linia ma byc tylko wtedy, gdy TRESC
// odpowiedzi opiera sie na danych z Lore / wiedzy firmy - nie przy samym wyszukaniu ani doklejce.
//   - sztuczne transkrypty: wykorzystanie z Lore, z jfwiedza, z obu, z doklejki, cytat numeru, u workera;
//     proby negatywne: wyszukanie bez wykorzystania, doklejka bez wykorzystania, dane z doklejki
//     obecne tez w wyniku Bash (swieze dane), w pliku instrukcji, we wczesniejszej czesci rozmowy,
//     przypadkowa wspolna fraza, definicje narzedzi i meta-wiadomosci;
//   - awarie: tura dluzsza niz pierwszy kawalek czytania, uszkodzony i brakujacy transkrypt,
//     zepsuty plik stanu;
//   - fikstury z prawdziwych tur (narzedzia\fikstury-znacznik-zrodla\, zanonimizowane: bez kluczy,
//     danych firmy i nazw kontrahentow, kwoty zmienione z zachowaniem ukladu):
//       empik-klucz, empik-sprawdz     - zgloszony falszywy alarm 16.10 (C--dev-ecommerce-helper,
//                                        rozmowa 194719aa, tury od linii 78 i 122): brak linii,
//       lore-robot-konkurencji         - rozmowa 7ab54377, tura od linii 78: Lore (#64869),
//       lore-sprzedaz-fr               - rozmowa a95422ac, tura od linii 7: Lore (#58629),
//       jfwiedza-karton                - rozmowa f96b4dce, tura od linii 164: jfwiedza (#130).
// Wszystko w %TEMP%, prawdziwy stan (~\.claude\mr) nietkniety, pliki instrukcji wylaczone
// (MR_ZNACZNIK_INSTRUKCJE=""), hook bez okna (windowsHide).
//
// Uzycie:  node narzedzia\test-znacznik-zrodla.js [--zostaw]
// Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const HOOK = path.join(__dirname, "znacznik-zrodla.js");
const FIKSTURY = path.join(__dirname, "fikstury-znacznik-zrodla");
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
    env: Object.assign({}, process.env, { MR_ZNACZNIK_STAN: STAN, MR_ZNACZNIK_INSTRUKCJE: "" }, env || {}),
  });
  let msg = "";
  let jsonOk = true;
  if ((r.stdout || "").trim()) {
    try { msg = JSON.parse(r.stdout).systemMessage || ""; } catch (e) { jsonOk = false; }
  }
  return { kod: r.status, stdout: r.stdout || "", stderr: r.stderr || "", msg, jsonOk, ms: Date.now() - t0 };
}

function stan() { return JSON.parse(fs.readFileSync(STAN, "utf8")); }
function idWykorzystanych(klucz) { return ((stan().wykorzystane || {})[klucz] || []).map((x) => x.id).sort(); }

// --- budowanie transkryptow w ukladzie Claude Code 2.1.x
let licz = 0;
const baza = Date.parse("2026-10-16T10:00:00Z");
function czas(s) { return new Date(baza + s * 1000).toISOString(); }
function uzytkownik(tekst, s, extra) {
  return Object.assign({ type: "user", isSidechain: false, uuid: "u" + (++licz), timestamp: czas(s),
    origin: { kind: "human" }, message: { role: "user", content: tekst } }, extra || {});
}
function wynikNarzedzia(id, tekst, s, extra) {
  return Object.assign({ type: "user", isSidechain: false, uuid: "r" + (++licz), timestamp: czas(s),
    message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: tekst }] } }, extra || {});
}
function narzedzie(nazwa, s, extra) {
  const id = "toolu_" + (++licz);
  return Object.assign({ type: "assistant", isSidechain: false, uuid: "a" + licz, timestamp: czas(s),
    message: { role: "assistant", content: [{ type: "tool_use", id, name: nazwa, input: { query: "x" } }] } }, extra || {});
}
function idNarz(w) { return w.message.content[0].id; }
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
// Wyniki narzedzi w ukladzie serwerow: lore_search {result:[{id,text}]}, szukaj_wiedzy {wyniki:[{id,tresc}]}.
function wynikLore(wpisy) { return JSON.stringify({ result: wpisy.map(([id, text]) => ({ id, date: "2026-09-10 08:06", project: "C--dev-test", role: "assistant", text })) }); }
function wynikWiedzy(wpisy) { return [{ type: "text", text: JSON.stringify({ wyniki: wpisy.map(([id, tresc]) => ({ id, naglowek: "ustalenie", tresc, temat: "test" })) }, null, 2) }]; }
const NAGL_L = "Z ARCHIWUM (Lore, automat) - trop, nie dowod; moze byc nieaktualne. Calosc: lore_context(id).";
const NAGL_W = "Z WIEDZY FIRMY (jfwiedza, automat) - trop, nie dowod; moze byc nieaktualne. Calosc: szukaj_wiedzy.";
function zapisz(nazwa, wpisy, surowe) {
  const p = path.join(T, nazwa + ".jsonl");
  fs.writeFileSync(p, surowe !== undefined ? surowe : wpisy.map((w) => JSON.stringify(w)).join("\n") + "\n", "utf8");
  return p;
}
function stop(p, sesja) { return { session_id: sesja || path.basename(p, ".jsonl"), transcript_path: p, hook_event_name: "Stop", stop_hook_active: false }; }

const LORE = "\u{1F7E3} Lore";
const JFW = "\u{1F7E0} jfwiedza";
const OBA = LORE + " · " + JFW;

// Tresci testowe (zmyslone): wpis o zamowieniu z konkretami i wpis bez zwiazku z odpowiedzia.
const ZAMOWIENIE = "Zamowienie testowe ZT-4711 na 120 sztuk dyfuzorow, sprawa w urzedzie 99887766, termin dostawy 23.11.2026, dostawca Kwiatowa Hurtownia.";
const OBCY = "Konfiguracja drukarki etykiet w magazynie wymaga sterownika w wersji 3.2.1 i papieru 50x30.";
const ODP_ZAMOWIENIE = "Z tego, co ustalono: zamowienie ZT-4711 to 120 sztuk dyfuzorow, sprawa ma numer 99887766, a termin dostawy to 23.11.";

try {
  // 1. Lore: lore_search + lore_context, odpowiedz cytuje konkrety z wyniku wyszukania
  {
    const t1 = narzedzie("mcp__lore__lore_search", 2);
    const t2 = narzedzie("mcp__lore__lore_context", 4);
    const p = zapisz("lore", [definicje(0), uzytkownik("co ustalilismy o zamowieniu?", 1), t1,
      wynikNarzedzia(idNarz(t1), wynikLore([[5001, ZAMOWIENIE], [5002, OBCY]]), 3), t2,
      wynikNarzedzia(idNarz(t2), JSON.stringify({ project: "x", turns: [{ id: 5003, text: OBCY }] }), 5),
      odpowiedz(ODP_ZAMOWIENIE, 6)]);
    const r = uruchom(stop(p));
    sprawdz("lore: kod 0 i poprawny JSON", r.kod === 0 && r.jsonOk, r.stdout + r.stderr);
    sprawdz("lore: linia dokladnie '" + LORE + "' (bez liczb i numerow)", r.msg === LORE, r.msg);
    sprawdz("lore: bez 'decision' (tura nie jest blokowana)", !/decision/.test(r.stdout), r.stdout);
    const s = stan();
    sprawdz("lore: stan 'pokazano', wykorzystany tylko #5001 (z dowodami)", s.wynik === "pokazano" &&
      idWykorzystanych("lore").join() === "5001" && s.wykorzystane.lore[0].dowody.length >= 2, JSON.stringify(s));
    sprawdz("lore: stan liczy fragmenty i wywolania", (s.fragmentow || {}).lore === 3 && (s.wywolania || {}).lore === 2, JSON.stringify(s));
    sprawdz("lore: hook szybki (< 2 s z uruchomieniem node, < 200 ms w srodku)", r.ms < 2000 && s.ms < 200, r.ms + " ms / " + s.ms + " ms");
  }

  // 2. jfwiedza: szukaj_wiedzy wykorzystany; poprzednia tura z Lore (tez wykorzystanym) NIE liczy sie
  {
    const stara = narzedzie("mcp__lore__lore_search", 2);
    const a = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 11);
    const c = narzedzie("mcp__jfwiedza__tematy", 13);
    const p = zapisz("jfwiedza", [uzytkownik("stara tura", 1), stara, wynikNarzedzia(idNarz(stara), wynikLore([[6001, OBCY]]), 3),
      odpowiedz("Drukarka potrzebuje sterownika 3.2.1 i papieru 50x30.", 4),
      uzytkownik("co wiemy o zamowieniu?", 10), a, wynikNarzedzia(idNarz(a), wynikWiedzy([[1084, ZAMOWIENIE]]), 12),
      c, wynikNarzedzia(idNarz(c), "magazyn, oferty", 13), odpowiedz(ODP_ZAMOWIENIE, 14)]);
    const r = uruchom(stop(p));
    sprawdz("jfwiedza: linia '" + JFW + "' (bez Lore z poprzedniej tury)", r.msg === JFW, r.msg);
    sprawdz("jfwiedza: w stanie wpis #1084", idWykorzystanych("jfwiedza").join() === "1084", JSON.stringify(stan()));
  }

  // 3. PROBA NEGATYWNA (pada na kodzie sprzed 16.10): wyszukanie Lore i jfwiedza bez wykorzystania -
  //    odpowiedz opiera sie na swiezym wyniku Bash
  {
    const l = narzedzie("mcp__lore__lore_search", 2);
    const w = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 3);
    const b = narzedzie("Bash", 4);
    const p = zapisz("wyszukanie-bez-uzycia", [uzytkownik("czy klucz dziala?", 1),
      l, wynikNarzedzia(idNarz(l), wynikLore([[7001, ZAMOWIENIE], [7002, OBCY]]), 2),
      w, wynikNarzedzia(idNarz(w), wynikWiedzy([[1200, OBCY]]), 3),
      b, wynikNarzedzia(idNarz(b), "{\"shop_name\":\"Firma Testowa\",\"currency\":\"PLN\"}\nHTTP 200", 5),
      odpowiedz("Klucz dziala. Sprawdzilem go jednym odczytem: sklep odpowiada i widzi konto Firma Testowa, waluta PLN.", 6)]);
    const r = uruchom(stop(p));
    sprawdz("wyszukanie bez wykorzystania: kod 0 i pusty wypis (zadnej linii)", r.kod === 0 && r.stdout.trim() === "", r.stdout);
    sprawdz("wyszukanie bez wykorzystania: stan 'bez wykorzystania', wywolania policzone",
      stan().wynik === "bez wykorzystania" && (stan().wywolania || {}).lore === 1 && (stan().wywolania || {}).jfwiedza === 1, JSON.stringify(stan()));
  }

  // 4. PROBA NEGATYWNA: same doklejki obu hookow, odpowiedz z nich nie korzysta
  {
    const p = zapisz("doklejka", [uzytkownik("pytanie o drukarke", 1),
      doklejka("TRYB MEGARUCHACZA ...\n\n" + NAGL_L + "\n- #8001 2026-09-10 (sprzed 36 dni) dev-test, asystent: " + ZAMOWIENIE, 1),
      doklejka(NAGL_W + "\n- [Primo, 2026-09-16, #875] " + ZAMOWIENIE, 1), odpowiedz("Drukarka dziala, sprawdzilem wydruk probny.", 4)]);
    const r = uruchom(stop(p));
    sprawdz("doklejka bez wykorzystania: kod 0 i pusty wypis", r.kod === 0 && r.stdout.trim() === "", r.stdout);
    sprawdz("doklejka bez wykorzystania: stan 'bez wykorzystania', 2 fragmenty", stan().wynik === "bez wykorzystania" &&
      (stan().fragmentow || {}).lore === 1 && (stan().fragmentow || {}).jfwiedza === 1, JSON.stringify(stan()));
  }

  // 5. doklejka wykorzystana (Lore) i doklejka + wyszukanie (oba zrodla)
  {
    const tura = (z, extra) => [uzytkownik("co z zamowieniem?", 1),
      doklejka("TRYB MEGARUCHACZA ...\n\n" + NAGL_L + "\n- #8001 2026-09-10 (sprzed 36 dni) dev-test, asystent: " + ZAMOWIENIE +
        "\n- #8002 2026-09-11 (sprzed 35 dni) dev-test, rozmowa: " + OBCY, 1)].concat(extra || [], [odpowiedz(ODP_ZAMOWIENIE, 6)]);
    const r = uruchom(stop(zapisz("doklejka-uzyta", tura())));
    sprawdz("doklejka wykorzystana: '" + LORE + "', w stanie #8001", r.msg === LORE && idWykorzystanych("lore").join() === "8001", r.msg + " " + JSON.stringify(stan().wykorzystane));
    const w = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 3);
    const r2 = uruchom(stop(zapisz("doklejka-i-wiedza", tura(null, [w, wynikNarzedzia(idNarz(w), wynikWiedzy([[1300, "Dostawca Kwiatowa Hurtownia dowozi tylko we wtorki, minimum 120 sztuk, sprawa 99887766 zamknieta."]]), 4)]))));
    sprawdz("doklejka Lore + szukaj_wiedzy, oba wykorzystane: '" + OBA + "'", r2.msg === OBA, r2.msg);
  }

  // 6. PROBA NEGATYWNA: dane z doklejki sa tez w swiezym wyniku Bash - to swieze dane, nie pamiec
  //    (kontrola: ta sama tura bez Bash daje linie - test 5)
  {
    const b = narzedzie("Bash", 3);
    const p = zapisz("doklejka-i-bash", [uzytkownik("co z zamowieniem?", 1),
      doklejka(NAGL_L + "\n- #8001 2026-09-10 (sprzed 36 dni) dev-test, asystent: " + ZAMOWIENIE, 1),
      b, wynikNarzedzia(idNarz(b), "zamowienia.csv: ZT-4711;120;99887766;2026-11-23", 4), odpowiedz(ODP_ZAMOWIENIE, 6)]);
    const r = uruchom(stop(p));
    sprawdz("dane z doklejki tez w wyniku Bash: pusty wypis", r.kod === 0 && r.stdout.trim() === "", r.stdout);
  }

  // 7. PROBA NEGATYWNA: dane z wyszukania sa w pliku instrukcji (CLAUDE.md) - model je zna i bez Lore;
  //    kontrola: bez pliku instrukcji ta sama tura daje linie
  {
    const l = narzedzie("mcp__lore__lore_search", 2);
    const p = zapisz("instrukcje", [uzytkownik("co z zamowieniem?", 1), l, wynikNarzedzia(idNarz(l), wynikLore([[9001, ZAMOWIENIE]]), 3), odpowiedz(ODP_ZAMOWIENIE, 6)]);
    const plik = path.join(T, "CLAUDE.md");
    fs.writeFileSync(plik, "# Ustalenia\n- " + ZAMOWIENIE + "\n", "utf8");
    const r = uruchom(stop(p), { MR_ZNACZNIK_INSTRUKCJE: plik });
    sprawdz("dane w pliku instrukcji: pusty wypis", r.kod === 0 && r.stdout.trim() === "", r.stdout);
    const r2 = uruchom(stop(p));
    sprawdz("kontrola bez pliku instrukcji: '" + LORE + "'", r2.msg === LORE, r2.msg);
  }

  // 8. PROBA NEGATYWNA: te same dane padly wczesniej w rozmowie (wynik Read w poprzedniej turze)
  {
    const rd = narzedzie("Read", 2);
    const l = narzedzie("mcp__lore__lore_search", 11);
    const p = zapisz("historia", [uzytkownik("przeczytaj plik zamowien", 1), rd, wynikNarzedzia(idNarz(rd), ZAMOWIENIE, 3), odpowiedz("Przeczytane.", 4),
      uzytkownik("co z zamowieniem?", 10), l, wynikNarzedzia(idNarz(l), wynikLore([[9101, ZAMOWIENIE]]), 12), odpowiedz(ODP_ZAMOWIENIE, 14)]);
    const r = uruchom(stop(p));
    sprawdz("dane z wczesniejszej czesci rozmowy: pusty wypis", r.kod === 0 && r.stdout.trim() === "", r.stdout);
  }

  // 9. PROBA NEGATYWNA: przypadkowa wspolna fraza (jedna trojka slow) i jeden konkret - za malo;
  //    cytat numeru wpisu ("#9201") wystarcza sam
  {
    const l = narzedzie("mcp__lore__lore_search", 2);
    const frag = "Raport sprzedazy tygodniowej wysylamy mailem w poniedzialek rano, razem z plikiem ZT-4711.";
    const p = zapisz("fraza", [uzytkownik("jak wysylamy raporty?", 1), l, wynikNarzedzia(idNarz(l), wynikLore([[9201, frag]]), 3),
      odpowiedz("Raport sprzedazy tygodniowej przygotuje teraz od nowa z danych Amazona.", 6)]);
    sprawdz("jedna wspolna fraza: pusty wypis", uruchom(stop(p)).stdout.trim() === "", stan().wykorzystane && JSON.stringify(stan().wykorzystane));
    const p2 = zapisz("jeden-konkret", [uzytkownik("co z plikiem?", 1), l, wynikNarzedzia(idNarz(l), wynikLore([[9201, frag]]), 3),
      odpowiedz("Plik ZT-4711 jest na dysku.", 6)]);
    sprawdz("jeden identyfikator: pusty wypis", uruchom(stop(p2)).stdout.trim() === "", JSON.stringify(stan().wykorzystane));
    const p3 = zapisz("cytat", [uzytkownik("skad to wiesz?", 1), l, wynikNarzedzia(idNarz(l), wynikLore([[9201, frag]]), 3),
      odpowiedz("To z wpisu #9201 w pamieci rozmow.", 6)]);
    const r3 = uruchom(stop(p3));
    sprawdz("cytat numeru wpisu: '" + LORE + "'", r3.msg === LORE && idWykorzystanych("lore").join() === "9201", r3.msg);
  }

  // 10. PROBA NEGATYWNA: nic z Lore/jfwiedza - wiadomosc cytuje naglowki doklejek, w transkrypcie
  //     leza definicje narzedzi mcp__lore__, sa inne narzedzia MCP, doklejka bez naglowka, meta-skill
  {
    const bash = narzedzie("Bash", 3);
    const inne = narzedzie("mcp__ecommerce-helper__spapi_get", 4);
    const p = zapisz("nic", [definicje(0),
      uzytkownik("rozpoznawaj 'Z ARCHIWUM (Lore' i 'Z WIEDZY FIRMY (jfwiedza' oraz mcp__lore__lore_search", 1),
      doklejka("TRYB MEGARUCHACZA - same zasady", 1),
      uzytkownik("Base directory for this skill: mcp__lore__lore_search", 2, { isMeta: true, origin: undefined }),
      bash, wynikNarzedzia(idNarz(bash), "Z ARCHIWUM (Lore w wyniku narzedzia\n- #1 2026-01-01 (x) a, b: " + ZAMOWIENIE, 3),
      inne, odpowiedz(ODP_ZAMOWIENIE, 5)]);
    const r = uruchom(stop(p));
    sprawdz("nic: kod 0 i pusty wypis (zadnej linii)", r.kod === 0 && r.stdout.trim() === "", r.stdout);
    sprawdz("nic: stan 'nic' (slad, ze hook byl)", stan().wynik === "nic", JSON.stringify(stan()));
  }

  // 11. worker: jego lore_search przyniosl dane, raport workera (wynik Agent) je powtarza, odpowiedz
  //     glownego watku je cytuje -> linia (raport to posrednik, nie swieze dane); drugi Stop tej samej
  //     rozmowy nie liczy tego drugi raz; worker, ktory szukal bez wykorzystania - brak linii
  {
    const teraz = Date.now();
    const iso = (ms) => new Date(ms).toISOString();
    const rozmowa = (sesja, tekstOdp, wynikWorkera) => {
      const ag = { type: "tool_use", id: "toolu_ag_" + sesja, name: "Agent", input: {} };
      const p = zapisz(sesja, [
        Object.assign(uzytkownik("sprawdz zamowienie", 0), { timestamp: iso(teraz - 60000) }),
        { type: "assistant", isSidechain: false, timestamp: iso(teraz - 59000), message: { role: "assistant", content: [ag] } },
        Object.assign(wynikNarzedzia(ag.id, "Raport: " + ODP_ZAMOWIENIE, 0), { timestamp: iso(teraz - 40000) }),
        Object.assign(odpowiedz(tekstOdp, 0), { timestamp: iso(teraz - 39000) })]);
      const kat = path.join(T, sesja, "subagents");
      fs.mkdirSync(kat, { recursive: true });
      const w = narzedzie("mcp__lore__lore_search", 0, { isSidechain: true, agentId: "abc" });
      w.timestamp = iso(teraz - 50000);
      const wr = wynikNarzedzia(idNarz(w), wynikLore([[9301, wynikWorkera]]), 0, { isSidechain: true, agentId: "abc" });
      wr.timestamp = iso(teraz - 49000);
      const stary = narzedzie("mcp__jfwiedza__szukaj_wiedzy", 0, { isSidechain: true, agentId: "abc" });
      stary.timestamp = iso(teraz - 3600000);   // przed poczatkiem tury - nie liczy sie
      fs.writeFileSync(path.join(kat, "agent-abc.jsonl"), [stary, w, wr].map((x) => JSON.stringify(x)).join("\n") + "\n", "utf8");
      return p;
    };
    const p = rozmowa("sesja-workera", ODP_ZAMOWIENIE, ZAMOWIENIE);
    const r = uruchom(stop(p, "sesja-workera"));
    sprawdz("worker: '" + LORE + "', w stanie #9301 i wywolanie workera", r.msg === LORE && idWykorzystanych("lore").join() === "9301" &&
      stan().wywolania_workerow === 1, r.msg + " " + JSON.stringify(stan()));
    const r2 = uruchom(stop(p, "sesja-workera"));
    sprawdz("worker: drugi Stop tej rozmowy nie liczy tego samego wyniku", r2.stdout.trim() === "", r2.stdout);
    const pn = rozmowa("sesja-workera-bez", "Worker skonczyl, zamowienie jeszcze nie przyszlo.", OBCY);
    sprawdz("worker szukal bez wykorzystania: pusty wypis", uruchom(stop(pn, "sesja-workera-bez")).stdout.trim() === "", JSON.stringify(stan()));
  }

  // 12. tura dluzsza niz pierwszy kawalek czytania (1 MB) + linia zepsuta w srodku tury
  {
    const t1 = narzedzie("mcp__lore__lore_search", 3);
    const wpisy = [uzytkownik("stara", 0), narzedzie("mcp__jfwiedza__szukaj_wiedzy", 0.5), uzytkownik("dluga tura", 1), t1,
      wynikNarzedzia(idNarz(t1), wynikLore([[9401, ZAMOWIENIE + " " + "z".repeat(3 * 1024 * 1024)]]), 4), odpowiedz(ODP_ZAMOWIENIE, 5)];
    const linie = wpisy.map((x) => JSON.stringify(x));
    linie.splice(4, 0, "{to nie jest json");
    const p = zapisz("dluga", null, linie.join("\n") + "\n");
    const r = uruchom(stop(p));
    sprawdz("dluga tura: Lore znalezione mimo 3 MB w srodku tury", r.msg === LORE, r.msg);
    sprawdz("dluga tura: zepsuta linia policzona w stanie, bez awarii", stan().zepsute_linie === 1 && stan().wynik === "pokazano", JSON.stringify(stan()).slice(0, 300));
  }

  // 13. PROBA NEGATYWNA: uszkodzony transkrypt - kod 0, alarm raz, slad w stanie
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
    sprawdz("po awarii: zdrowa tura znakuje i sprzata awarie", ok.msg === LORE && !stan().awaria, JSON.stringify(stan()));
  }

  // 14. PROBA NEGATYWNA: brak pliku transkryptu, brak transcript_path, wejscie nie-JSON, puste wejscie
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

  // 15. zepsuty plik stanu nie blokuje znacznika
  {
    fs.writeFileSync(STAN, "{zepsuty", "utf8");
    const r = uruchom(stop(path.join(T, "lore.jsonl")));
    sprawdz("zepsuty stan: znacznik dalej wychodzi, stan zapisany od nowa", r.msg === LORE && stan().zepsuty_stan, r.msg + " / " + fs.readFileSync(STAN, "utf8").slice(0, 200));
  }

  // 16. fikstury z prawdziwych tur (opis na gorze pliku)
  {
    const oczekiwane = [
      ["empik-klucz", "", null],
      ["empik-sprawdz", "", null],
      ["lore-robot-konkurencji", LORE, ["lore", "64869"]],
      ["lore-sprzedaz-fr", LORE, ["lore", "58629"]],
      ["jfwiedza-karton", JFW, ["jfwiedza", "130"]],
    ];
    for (const [nazwa, linia, wpis] of oczekiwane) {
      const p = path.join(FIKSTURY, nazwa + ".jsonl");
      const r = uruchom(stop(p, "fikstura-" + nazwa));
      const s = stan();
      sprawdz("fikstura " + nazwa + ": " + (linia ? "'" + linia + "'" : "brak linii") + (wpis ? ", w stanie #" + wpis[1] : ""),
        r.kod === 0 && r.msg === linia && (linia || r.stdout.trim() === "") && (!wpis || idWykorzystanych(wpis[0]).includes(wpis[1])) &&
        s.ms < 200, r.stdout + " " + JSON.stringify(s.wykorzystane) + " " + s.ms + " ms");
    }
  }
} catch (e) {
  sprawdz("test bez wywrotki", false, e && e.stack || e);
}

if (process.argv.includes("--zostaw")) console.log("pliki testu: " + T);
else fs.rmSync(T, { recursive: true, force: true });
console.log(zle === 0 ? "WYNIK: wszystkie proby przeszly" : "WYNIK: nieudanych prob: " + zle);
process.exit(zle === 0 ? 0 : 1);
