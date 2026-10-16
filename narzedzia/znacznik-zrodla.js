// Znacznik zrodla - hook Stop Claude Code. Po kazdej odpowiedzi mowi uzytkownikowi, czy w tej
// turze Claude siegnal do pamieci rozmow (Lore) albo do wiedzy firmy (jfwiedza), np.
//   🟣 Lore: wyszukano 1× · 🟠 jfwiedza: wyszukano 2× (w tym workerzy 1×)
// Gdy nic z tego nie zaszlo - nie wypisuje nic (bez szumu).
//
// Dlaczego hook, a nie zasada dla modelu: do 0.34.0 znaczek 🟣 Lore / 🟠 jfwiedza mial stawiac
// sam model (zasady-lore.md, instrukcje serwerow MCP) - i w praktyce go nie stawial. Ten hook
// liczy mechanicznie, z transkryptu, niezaleznie od tego, co model napisal.
//
// Co liczy (transkrypt JSONL z pola transcript_path wejscia hooka):
//   - wywolania narzedzi mcp__lore__* i mcp__jfwiedza__* w biezacej turze - od ostatniej
//     wiadomosci uzytkownika (albo powiadomienia o workerze) do konca pliku,
//   - to samo u workerow: pliki <sesja>\subagents\agent-*.jsonl obok transkryptu, wpisy
//     z czasem od poprzedniego Stop tej rozmowy (pamietany w pliku stanu) - dzieki temu
//     wywolanie workera w tle, ktory pracowal miedzy turami, liczy sie raz, w najblizszej
//     odpowiedzi; rozmowa nieznana stanowi = od poczatku tury.
// Doklejki hookow do wiadomosci uzytkownika ("Z ARCHIWUM (Lore", "Z WIEDZY FIRMY (jfwiedza")
// NIE daja linii: to podpowiedz automatu, a nie dowod, ze odpowiedz sie na niej oparla -
// linia przy samej doklejce byla falszywym alarmem (16.10).
// Linia idzie w polu systemMessage ("Warning message shown to the user" w schemacie hookow
// Claude Code 2.1.x) - widzi ja uzytkownik, model nie. Bez "decision" - tura konczy sie zawsze.
//
// Cisza jest zakazana: kazdy przebieg zostawia slad w pliku stanu (czas, wynik, powod). Awaria
// (brak transkryptu, plik bez poczatku tury, wywrotka) - zapis w stanie zawsze, a linia UWAGA
// u uzytkownika przy pierwszym wystapieniu, przy zmianie przyczyny i potem co 6 h - ten sam
// rytm co alarm archiwum w przypomnienie.js. Kod wyjscia zawsze 0.
//
// Uzycie (hook Stop, uklada go straznik - Wzory-Hookow-Globalnych, rodzaj "znacznik"):
//   node narzedzia\znacznik-zrodla.js
// Zmienne do testow: MR_ZNACZNIK_STAN (plik stanu).

const fs = require("fs");
const os = require("os");
const path = require("path");

// Serwery MCP, ktore znakujemy. Nazwa serwera to czesc miedzy "mcp__" a nastepnym "__".
const ZRODLA = [
  { klucz: "lore", znaczek: "\u{1F7E3} Lore", serwer: "lore" },
  { klucz: "jfwiedza", znaczek: "\u{1F7E0} jfwiedza", serwer: "jfwiedza" },
];
const RAZY = "×";

// Czytamy transkrypt od konca kawalkami: rozmowa potrafi miec dziesiatki MB, a tura to ogon.
// 1 MB miesci zwykla ture; kazda kolejna proba czyta 4x wiecej. Sufit 64 MB: hook ma byc szybki,
// tura dluzsza niz tyle to awaria do stanu (glosno), nie czytanie w nieskonczonosc.
const KAWALEK = 1024 * 1024;
const MAX_CZYTANIA = 64 * 1024 * 1024;
// Hook podaje JSON na wejsciu od razu; to bezpiecznik na wejscie, ktore sie nie zamyka.
const CZAS_WEJSCIA_MS = 500;
// Rytm powtarzania linii o tej samej awarii - jak GODZIN_MIEDZY_ALARMAMI w przypomnienie.js:
// linia przy kazdej odpowiedzi uczy ja ignorowac, raz na dzien pracy to za malo.
const GODZIN_MIEDZY_ALARMAMI = 6;
// Ile rozmow pamietamy (czas ostatniego Stop) - starsze wypadaja; nieznana rozmowa liczy
// workerow od poczatku tury, wiec wypadniecie niczego nie psuje.
const PAMIETANYCH_SESJI = 40;

function plikStanu() {
  return process.env.MR_ZNACZNIK_STAN ||
    path.join(os.homedir(), ".claude", "mr", ".znacznik-zrodla-stan.json");
}

// ------------------------------------------------------------------ wejscie

function czytajWejscie(ms) {
  return new Promise((gotowe) => {
    if (process.stdin.isTTY) return gotowe(null);
    let dane = "";
    let koniec = false;
    const skoncz = () => {
      if (koniec) return;
      koniec = true;
      clearTimeout(zegar);
      try { process.stdin.destroy(); } catch (e) { /* i tak wychodzimy przez process.exit */ }
      gotowe(dane || null);
    };
    const zegar = setTimeout(skoncz, ms);
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (k) => { dane += k; });
    process.stdin.on("end", skoncz);
    process.stdin.on("error", skoncz);
  });
}

// ------------------------------------------------------------------ transkrypt

// Wpisy z konca pliku, poczawszy od ostatniego, dla ktorego stop(wpis) = true (wlacznie).
// Zwraca { wpisy, zepsute, znaleziono }. Pierwsza linia kawalka bywa ucieta w pol - pomijamy ja,
// chyba ze kawalek zaczyna sie na poczatku pliku. Linia, ktora nie jest JSON-em, to "zepsuta":
// liczona, nie przerywa (ostatnia linia potrafi byc w trakcie zapisu).
function wpisyOdKonca(plik, stop) {
  const fd = fs.openSync(plik, "r");
  try {
    const rozmiar = fs.fstatSync(fd).size;
    let ile = Math.min(rozmiar, KAWALEK);
    for (;;) {
      const buf = Buffer.alloc(ile);
      fs.readSync(fd, buf, 0, ile, rozmiar - ile);
      let linie = buf.toString("utf8").split("\n");
      if (ile < rozmiar) linie = linie.slice(1);
      const wpisy = [];
      let zepsute = 0;
      for (const l of linie) {
        const t = l.trim();
        if (!t) continue;
        try { wpisy.push(JSON.parse(t)); } catch (e) { zepsute++; }
      }
      for (let i = wpisy.length - 1; i >= 0; i--) {
        if (stop(wpisy[i])) return { wpisy: wpisy.slice(i), zepsute, znaleziono: true };
      }
      if (ile >= rozmiar) return { wpisy, zepsute, znaleziono: false };
      if (ile >= MAX_CZYTANIA) {
        throw new Error("nie znalazlem poczatku tury w ostatnich " + Math.round(MAX_CZYTANIA / 1048576) + " MB transkryptu");
      }
      ile = Math.min(rozmiar, ile * 4, MAX_CZYTANIA);
    }
  } finally {
    fs.closeSync(fd);
  }
}

// Poczatek tury: wiadomosc uzytkownika (albo powiadomienie o workerze - po nim tez jest
// odpowiedz) w glownym watku. Nie: wynik narzedzia, meta-wiadomosc (np. tresc skilla),
// streszczenie po /compact.
function poczatekTury(w) {
  if (!w || w.type !== "user" || w.isSidechain || w.isMeta || w.isCompactSummary) return false;
  const m = w.message;
  if (!m) return false;
  if (typeof m.content === "string") return true;
  if (!Array.isArray(m.content)) return false;
  if (m.content.some((c) => c && c.type === "tool_result")) return false;
  return m.content.some((c) => c && (c.type === "text" || c.type === "image"));
}

function serwerNarzedzia(nazwa) {
  const m = /^mcp__(.+?)__(.+)$/.exec(String(nazwa || ""));
  return m ? { serwer: m[1], narzedzie: m[2] } : null;
}

// Czynnosc po ludzku. Nieznane narzedzie idzie pod wlasna nazwa - lepiej surowa nazwa niz
// zgadywanie, co zrobilo.
function czynnosc(narzedzie) {
  const n = narzedzie.toLowerCase();
  if (/search|szukaj/.test(n)) return "wyszukano";
  if (/context|kontekst/.test(n)) return "kontekst";
  if (/dodaj|add|zapisz|save/.test(n)) return "zapisano";
  return narzedzie;
}

function noweLiczniki() {
  const l = {};
  for (const z of ZRODLA) l[z.klucz] = { czynnosci: {}, workerzy: 0, wszystkich: 0 };
  return l;
}

function policzWywolanie(liczniki, nazwa, odWorkera) {
  const s = serwerNarzedzia(nazwa);
  if (!s) return;
  const z = ZRODLA.find((x) => x.serwer === s.serwer);
  if (!z) return;
  const l = liczniki[z.klucz];
  const c = czynnosc(s.narzedzie);
  l.czynnosci[c] = (l.czynnosci[c] || 0) + 1;
  l.wszystkich++;
  if (odWorkera) l.workerzy++;
}

function wywolaniaWe(wpis) {
  if (!wpis || wpis.type !== "assistant" || !wpis.message || !Array.isArray(wpis.message.content)) return [];
  return wpis.message.content.filter((c) => c && c.type === "tool_use" && typeof c.name === "string");
}

function czasWpisu(w) {
  const t = w && Date.parse(w.timestamp);
  return isNaN(t) ? null : t;
}

// Wywolania workerow od chwili "od" (ms). Pliki zmienione przed "od" pomijamy bez czytania.
// Zwraca liczbe plikow, ktorych nie dalo sie przeczytac (do stanu - nie przerywa).
function policzWorkerow(transkrypt, od, liczniki, widziane) {
  const kat = path.join(path.dirname(transkrypt), path.basename(transkrypt, ".jsonl"), "subagents");
  let pliki;
  try { pliki = fs.readdirSync(kat); }
  catch (e) {
    if (e && e.code === "ENOENT") return { bledy: [] };   // rozmowa bez workerow
    return { bledy: ["katalog workerow: " + e.message] };
  }
  const bledy = [];
  for (const f of pliki) {
    if (!/^agent-.*\.jsonl$/.test(f)) continue;
    const p = path.join(kat, f);
    try {
      if (fs.statSync(p).mtimeMs <= od) continue;
      const r = wpisyOdKonca(p, (w) => { const t = czasWpisu(w); return t !== null && t <= od; });
      for (const w of r.wpisy) {
        const t = czasWpisu(w);
        if (t === null || t <= od) continue;
        for (const c of wywolaniaWe(w)) {
          if (c.id && widziane.has(c.id)) continue;
          if (c.id) widziane.add(c.id);
          policzWywolanie(liczniki, c.name, true);
        }
      }
    } catch (e) {
      bledy.push(f + ": " + e.message);
    }
  }
  return { bledy };
}

function linia(liczniki) {
  const czesci = [];
  for (const z of ZRODLA) {
    const l = liczniki[z.klucz];
    const elementy = Object.keys(l.czynnosci).map((k) => k + " " + l.czynnosci[k] + RAZY);
    if (!elementy.length) continue;
    let t = z.znaczek + ": " + elementy.join(", ");
    if (l.workerzy) t += " (w tym workerzy " + l.workerzy + RAZY + ")";
    czesci.push(t);
  }
  return czesci.join(" · ");
}

// ------------------------------------------------------------------ stan

function czytajStan(plik) {
  let t;
  try { t = fs.readFileSync(plik, "utf8").replace(/^﻿/, ""); }
  catch (e) {
    if (e && e.code === "ENOENT") return {};
    return { zepsuty_stan: { powod: "odczyt: " + String(e.message).slice(0, 120), czas: new Date().toISOString() } };
  }
  try {
    const s = JSON.parse(t);
    return s && typeof s === "object" ? s : {};
  } catch (e) {
    // Zepsuty stan nie moze zablokowac znacznika - od zera, a slad (z czasem, zeby bylo widac,
    // ze to historia, a nie stan biezacy) zostaje w nowym stanie.
    return { zepsuty_stan: { powod: String(e.message).slice(0, 120), czas: new Date().toISOString() } };
  }
}

function zapiszStan(plik, stan) {
  const tekst = JSON.stringify(stan, null, 1);
  try {
    fs.mkdirSync(path.dirname(plik), { recursive: true });
    const tmp = plik + ".tmp" + process.pid;
    fs.writeFileSync(tmp, tekst, "utf8");
    try { fs.renameSync(tmp, plik); }
    catch (e) {
      fs.writeFileSync(plik, tekst, "utf8");
      try { fs.unlinkSync(tmp); } catch (e2) { process.stderr.write("znacznik-zrodla.js: zostal plik tymczasowy " + tmp + ": " + e2.message + "\n"); }
    }
  } catch (e) {
    // Jedyny slad, jaki zostaje bez pliku stanu: stderr hooka (Claude Code pokazuje go w trybie
    // szczegolowym). Znacznik dla uzytkownika i tak wychodzi.
    process.stderr.write("znacznik-zrodla.js: nie zapisalem stanu " + plik + ": " + e.message + "\n");
  }
}

// ------------------------------------------------------------------ calosc

// Robota wlasciwa. Zwraca { linia, wynik, powod, zepsute } albo rzuca - awarie lapie glowna().
function zbadaj(prosba, stan) {
  const transkrypt = prosba && (prosba.transcript_path || prosba.transcriptPath);
  if (!transkrypt) throw new Error("wejscie hooka bez transcript_path");
  if (!fs.existsSync(transkrypt)) throw new Error("brak pliku transkryptu " + transkrypt);
  const sesja = String(prosba.session_id || prosba.sessionId || path.basename(transkrypt, ".jsonl"));

  const r = wpisyOdKonca(transkrypt, poczatekTury);
  if (!r.znaleziono) {
    throw new Error("w transkrypcie nie ma wiadomosci uzytkownika (" + r.wpisy.length + " wpisow, " + r.zepsute + " zepsutych linii)");
  }
  const liczniki = noweLiczniki();
  const widziane = new Set();
  for (const w of r.wpisy) {
    for (const c of wywolaniaWe(w)) {
      if (c.id && widziane.has(c.id)) continue;
      if (c.id) widziane.add(c.id);
      policzWywolanie(liczniki, c.name, Boolean(w.isSidechain));
    }
  }

  // Workerzy: od poprzedniego Stop tej rozmowy, a gdy go nie znamy - od poczatku tury.
  const sesje = stan.sesje && typeof stan.sesje === "object" ? stan.sesje : {};
  const poprzedni = sesje[sesja] ? Date.parse(sesje[sesja].ostatni) : NaN;
  const od = !isNaN(poprzedni) ? poprzedni : czasWpisu(r.wpisy[0]);
  let bledyWorkerow = [];
  if (od !== null) bledyWorkerow = policzWorkerow(transkrypt, od, liczniki, widziane).bledy;
  else bledyWorkerow = ["poczatek tury bez czasu - workerow nie policzylem"];

  sesje[sesja] = { ostatni: new Date().toISOString() };
  const klucze = Object.keys(sesje).sort((a, b) => String(sesje[b].ostatni).localeCompare(String(sesje[a].ostatni)));
  for (const k of klucze.slice(PAMIETANYCH_SESJI)) delete sesje[k];
  stan.sesje = sesje;

  const l = linia(liczniki);
  return { linia: l, wynik: l ? "pokazano" : "nic", zepsute: r.zepsute, bledyWorkerow };
}

function wypisz(obiekt) {
  if (!obiekt) process.exit(0);
  process.stdout.write(JSON.stringify(obiekt), () => process.exit(0));
}

async function glowna() {
  const start = Date.now();
  const plik = plikStanu();
  const stan = czytajStan(plik);
  let wynik;
  let prosba = null;
  try {
    const wejscie = await czytajWejscie(CZAS_WEJSCIA_MS);
    if (!wejscie) throw new Error("hook nie podal nic na wejsciu");
    try { prosba = JSON.parse(wejscie); } catch (e) { throw new Error("wejscie hooka to nie JSON: " + e.message); }
    wynik = zbadaj(prosba, stan);
  } catch (e) {
    wynik = { linia: "", wynik: "awaria", powod: String(e && e.message || e), zepsute: 0, bledyWorkerow: [] };
  }

  const teraz = new Date();
  let alarm = "";
  if (wynik.wynik === "awaria") {
    const byla = stan.awaria && stan.awaria.powod === wynik.powod ? stan.awaria : null;
    stan.awaria = { powod: wynik.powod, od: byla ? byla.od : teraz.toISOString(), ile: (byla ? byla.ile : 0) + 1 };
    const ostatni = stan.alarm && Date.parse(stan.alarm.czas);
    const swiezy = stan.alarm && stan.alarm.powod === wynik.powod && !isNaN(ostatni) &&
      (teraz - ostatni) / 3600000 < GODZIN_MIEDZY_ALARMAMI;
    if (!swiezy) {
      stan.alarm = { powod: wynik.powod, czas: teraz.toISOString() };
      alarm = "UWAGA: znacznik Lore/jfwiedza nie dziala - " + wynik.powod +
        ". Nie wiem, czy ta odpowiedz korzystala z pamieci. Szczegoly: " + plik.replace(os.homedir(), "~");
    }
  } else {
    delete stan.awaria;
    delete stan.alarm;
  }

  stan.czas = teraz.toISOString();
  stan.wynik = wynik.wynik;
  stan.powod = wynik.powod || "";
  stan.linia = wynik.linia;
  stan.ms = Date.now() - start;
  stan.zepsute_linie = wynik.zepsute;
  if (wynik.bledyWorkerow.length) stan.bledy_workerow = wynik.bledyWorkerow.slice(0, 10); else delete stan.bledy_workerow;
  zapiszStan(plik, stan);

  const tekst = alarm ? (wynik.linia ? alarm + "\n" + wynik.linia : alarm) : wynik.linia;
  wypisz(tekst ? { systemMessage: tekst } : null);
}

glowna().catch((e) => {
  // Ostatnia deska (blad poza zbadaj(), np. przy zapisie stanu): slad na stderr, tura konczy sie normalnie.
  process.stderr.write("znacznik-zrodla.js: " + (e && e.stack || e) + "\n");
  process.exit(0);
});
