// Znacznik zrodla - hook Stop Claude Code. Po kazdej odpowiedzi mowi uzytkownikowi, czy TRESC
// tej odpowiedzi opiera sie na danych z pamieci rozmow (Lore) albo z wiedzy firmy (jfwiedza):
//   🟣 Lore  /  🟠 jfwiedza  /  🟣 Lore · 🟠 jfwiedza
// Gdy odpowiedz z nich nie korzysta - nie wypisuje nic (bez szumu), takze gdy Claude szukal.
//
// Dlaczego hook, a nie zasada dla modelu: do 0.34.0 znaczek 🟣 Lore / 🟠 jfwiedza mial stawiac
// sam model (zasady-lore.md, instrukcje serwerow MCP) - i w praktyce go nie stawial. Ten hook
// ocenia mechanicznie, z transkryptu, niezaleznie od tego, co model napisal.
//
// Dlaczego "wykorzystanie", a nie "wywolanie" (16.10): linia przy kazdym wyszukaniu albo przy
// samej doklejce byla falszywym alarmem - np. odpowiedz o kluczu Empik opierala sie na swiezym
// sprawdzeniu (Bash), a pod nia stalo "Lore", bo automat dokleil archiwum, z ktorego nic nie
// wzieto. Teraz linia jest tylko wtedy, gdy w odpowiedzi stoi tresc przyniesiona przez Lore/
// jfwiedza, ktorej model nie mial skad indziej. Zasady i progi: sekcja "wykorzystanie" nizej.
//
// Skad fragmenty (transkrypt JSONL z pola transcript_path wejscia hooka), w biezacej turze - od
// ostatniej wiadomosci uzytkownika (albo powiadomienia o workerze) do konca pliku:
//   - wyniki narzedzi mcp__lore__lore_search / lore_context i mcp__jfwiedza__szukaj_wiedzy -
//     kazdy wpis wyniku (pole id + text/tresc) osobno,
//   - doklejki hookow ("Z ARCHIWUM (Lore, automat)", "Z WIEDZY FIRMY (jfwiedza, automat)") -
//     kazda linia "- #ID ..." / "- [autor, data, #ID] ..." osobno,
//   - to samo u workerow: pliki <sesja>\subagents\agent-*.jsonl obok transkryptu, wpisy z czasem
//     od poprzedniego Stop tej rozmowy (pamietany w pliku stanu) - wynik workera w tle, ktory
//     pracowal miedzy turami, liczy sie raz, w najblizszej odpowiedzi; rozmowa nieznana stanowi
//     = od poczatku tury.
// Numery wykorzystanych wpisow i dowody (wspolne cechy) ida do pliku stanu - do sprawdzenia;
// w linii sa tylko znaczki (decyzja uzytkownika 16.10: linia maksymalnie krotka).
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
// Zmienne do testow: MR_ZNACZNIK_STAN (plik stanu), MR_ZNACZNIK_INSTRUKCJE (pliki instrukcji
// rozdzielone ";" zamiast ~\.claude\CLAUDE.md, <cwd>\CLAUDE.md i MEMORY.md projektu; "" = zadne).

const fs = require("fs");
const os = require("os");
const path = require("path");

// Serwery MCP, ktore znakujemy. Nazwa serwera to czesc miedzy "mcp__" a nastepnym "__".
// "dane" - narzedzia, ktorych wynik to tresc z pamieci (fragmenty); reszta (np. dodaj_wpis,
// tematy) to nie dane do odpowiedzi. "naglowek" - poczatek doklejki hooka tego zrodla.
const ZRODLA = [
  { klucz: "lore", znaczek: "\u{1F7E3} Lore", serwer: "lore", dane: ["lore_search", "lore_context"],
    naglowek: "Z ARCHIWUM (Lore" },
  { klucz: "jfwiedza", znaczek: "\u{1F7E0} jfwiedza", serwer: "jfwiedza", dane: ["szukaj_wiedzy"],
    naglowek: "Z WIEDZY FIRMY (jfwiedza" },
];

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
// Ile dowodow (wspolnych cech) na wpis zapisujemy w stanie - do sprawdzenia, nie do liczenia.
const DOWODOW_NA_WPIS = 6;

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
// Zwraca { wpisy, przed, zepsute, znaleziono } - "przed()" daje wpisy przeczytanego kawalka sprzed
// tego miejsca (wczesniejsza czesc rozmowy); parsujemy je dopiero na zadanie, bo potrzebne sa
// rzadko, a JSON.parse megabajta to kilkadziesiat ms przy kazdej odpowiedzi. Linie parsujemy od
// konca do poczatku tury. Pierwsza linia kawalka bywa ucieta w pol - pomijamy ja, chyba ze
// kawalek zaczyna sie na poczatku pliku. Linia, ktora nie jest JSON-em, to "zepsuta": liczona
// (w turze), nie przerywa (ostatnia linia potrafi byc w trakcie zapisu).
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
      for (let i = linie.length - 1; i >= 0; i--) {
        const t = linie[i].trim();
        if (!t) continue;
        let w;
        try { w = JSON.parse(t); } catch (e) { zepsute++; continue; }
        wpisy.push(w);
        if (stop(w)) {
          const reszta = linie.slice(0, i);
          return { wpisy: wpisy.reverse(), przed: () => parsujLinie(reszta), zepsute, znaleziono: true };
        }
      }
      if (ile >= rozmiar) return { wpisy: wpisy.reverse(), przed: () => [], zepsute, znaleziono: false };
      if (ile >= MAX_CZYTANIA) {
        throw new Error("nie znalazlem poczatku tury w ostatnich " + Math.round(MAX_CZYTANIA / 1048576) + " MB transkryptu");
      }
      ile = Math.min(rozmiar, ile * 4, MAX_CZYTANIA);
    }
  } finally {
    fs.closeSync(fd);
  }
}

function parsujLinie(linie) {
  const wpisy = [];
  for (const l of linie) {
    const t = l.trim();
    if (!t) continue;
    try { wpisy.push(JSON.parse(t)); } catch (e) { /* ucieta linia historii - historia to tylko tlo; zepsute linie liczymy w turze */ }
  }
  return wpisy;
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

// Zrodlo, z ktorego narzedzie przynosi dane z pamieci (klucz z ZRODLA), albo null.
function zrodloDanych(nazwa) {
  const s = serwerNarzedzia(nazwa);
  if (!s) return null;
  const z = ZRODLA.find((x) => x.serwer === s.serwer);
  return z && z.dane.includes(s.narzedzie) ? z.klucz : null;
}

function czasWpisu(w) {
  const t = w && Date.parse(w.timestamp);
  return isNaN(t) ? null : t;
}

// Tekst z tresci wyniku narzedzia albo wiadomosci: napis albo lista blokow {type:"text"}.
function tekstTresci(c) {
  if (typeof c === "string") return c;
  if (!Array.isArray(c)) return "";
  return c.map((b) => (b && typeof b.text === "string" ? b.text : (typeof b === "string" ? b : ""))).join("\n");
}

// Wszystkie napisy z dowolnej struktury (tresc doklejek innych niz Lore/jfwiedza, zalaczniki).
function napisyZ(x, wynik) {
  if (typeof x === "string") wynik.push(x);
  else if (Array.isArray(x)) for (const e of x) napisyZ(e, wynik);
  else if (x && typeof x === "object") for (const k of Object.keys(x)) napisyZ(x[k], wynik);
  return wynik;
}

// ------------------------------------------------------------------ fragmenty z pamieci

// Wpisy wyniku narzedzia Lore/jfwiedza. Wynik to JSON: lore_search {result:[{id,text}]},
// lore_context {turns:[{id,text}]}, szukaj_wiedzy {wyniki:[{id,tresc}]} - bierzemy kazdy obiekt
// z liczbowym id i tekstem, bez zgadywania ukladu. Nie-JSON (np. komunikat o bledzie) to jeden
// fragment bez numeru.
function fragmentyWyniku(klucz, tekst) {
  let dane;
  try { dane = JSON.parse(tekst); } catch (e) { return tekst.trim() ? [{ klucz, id: "?", tekst }] : []; }
  const wynik = [];
  const idz = (x) => {
    if (Array.isArray(x)) { for (const e of x) idz(e); return; }
    if (!x || typeof x !== "object") return;
    const t = typeof x.text === "string" ? x.text : (typeof x.tresc === "string" ? x.tresc : null);
    if (t !== null && (typeof x.id === "number" || /^\d+$/.test(String(x.id)))) {
      wynik.push({ klucz, id: String(x.id), tekst: t });
      return;
    }
    for (const k of Object.keys(x)) idz(x[k]);
  };
  idz(dane);
  return wynik;
}

// Linie doklejki hooka: po naglowku zrodla kolejne linie "- ..." to wpisy.
//   Lore:     "- #ID RRRR-MM-DD (sprzed N dni) projekt, rola: tresc"
//   jfwiedza: "- [autor, RRRR-MM-DD, #ID] tresc"
// Metryka (numer, data wpisu, wiek, projekt, autor) nie jest trescia - odcinamy ja, inaczej data
// wpisu w odpowiedzi ("dzis 16.10") liczylaby sie jako cytat. Zwraca { fragmenty, reszta } -
// reszta (np. zasady trybu doklejone w tym samym bloku) to zwykla wiedza, nie pamiec.
function fragmentyDoklejki(tekst) {
  const fragmenty = [];
  const reszta = [];
  let zrodlo = null;
  for (const l of String(tekst).split(/\r?\n/)) {
    const z = ZRODLA.find((x) => l.startsWith(x.naglowek));
    if (z) { zrodlo = z.klucz; continue; }
    if (zrodlo && l.startsWith("- ")) {
      let m = /^- #(\d+) \S+ \([^)]*\) [^,]*, [^:]*: ?(.*)$/.exec(l) || /^- #(\d+) (.*)$/.exec(l);
      if (!m) m = /^- \[[^\]]*#(\d+)\] ?(.*)$/.exec(l);
      if (m) { fragmenty.push({ klucz: zrodlo, id: m[1], tekst: m[2] }); continue; }
    }
    zrodlo = null;
    reszta.push(l);
  }
  return { fragmenty, reszta: reszta.join("\n") };
}

// ------------------------------------------------------------------ wykorzystanie
//
// Fragment jest WYKORZYSTANY, gdy odpowiedz zawiera z niego charakterystyczna tresc, ktorej nie
// bylo nigdzie indziej, skad model mogl ja wziac ("znane"): w wiadomosciach uzytkownika, w wynikach
// innych narzedzi (Bash, Read, Agent... - swieze dane, nie pamiec), we wczesniejszej czesci rozmowy
// (przeczytany kawalek transkryptu, takze poprzednie odpowiedzi) i w plikach instrukcji (CLAUDE.md,
// MEMORY.md - model ma je w kazdej turze). Bez modelu AI i bez sieci.
//
// Cechy (tekst po zlozeniu: male litery, bez polskich ogonkow, bez spacji tysiecy):
//   identyfikator - ciag z literami i cyframi od 4 znakow (ASIN, SKU, PT02, plik z data) albo
//                   numer wersji; czesci jednego SKU to jeden dowod
//   liczba        - od 3 cyfr (kwota 1 272,70, numer sprawy); krotsze i rok 19xx/20xx pomijane
//                   (padaja w co drugiej odpowiedzi)
//   dwucyfrowa liczba z jednostka ("30 szt", "40 g")
//   data          - RRRR-MM-DD, DD.MM.RRRR i DD.MM sprowadzone do MM-DD
//   fraza         - trzy kolejne slowa tresciowe (4+ liter, bez pospolitych), kazde przyciete do
//                   6 liter, zeby odmiana nie psula zgodnosci ("kadzidelka"/"kadzidelek")
// Dowod = cecha wspolna odpowiedzi i fragmentowi, ktorej nie ma w "znanych". Wpis jest
// wykorzystany, gdy ma >= MIN_DOWODOW dowodow, a gdy to SAME frazy - >= MIN_FRAZ trojek slow (np.
// wspolny ciag pieciu slow tresciowych albo trzy osobne frazy); albo gdy odpowiedz cytuje jego
// numer ("#64869"), ktorego nie bylo w znanych.
//
// Progi z kalibracji 16.10 na prawdziwych transkryptach z 12 dni (138 rozmow, 2780 tur, w tym
// 450 z fragmentami Lore/jfwiedza); tury z linia przejrzane recznie:
//   - 1 dowod (tez jedna fraza):   44 tury z linia; dodatkowe to w wiekszosci przypadek - jedna
//     fraza wspolna z tematem ("todo postep amazon", "dziala cala strone", "brutto netto netto"),
//   - 2 dowody, frazy tez od 2:    25 tur; 7 ponad wybrany prog to same dwie frazy - czesc
//     trafna ("Z rozmow z 08.10 wynika"), ale czesc przypadkowa ("wiadomosci z poprzedniego
//     dnia", "twojej osobistej pamieci": temat rozmowy jest ten sam co w Lore, wiec i slowa),
//   - 2 dowody, same frazy od 3 (WYBRANE): 18 tur, wszystkie trafne,
//   - 3 dowody:                     15 tur; odpadaja trafne ("Lore mowi, ze 10 wrzesnia...
//     wazny 547 dni" - liczba + fraza).
// Pojedynczy identyfikator nie wystarcza: trafil sie raz (SKU, trafnie), ale tak samo wyglada
// nazwa modelu czy sciezka wspolna wielu rozmowom (np. "claude-opus-5" w wycinku #15812).
// Przypadek zgloszony przez uzytkownika (klucz Empik: odpowiedz ze swiezego sprawdzenia, obok
// doklejki Lore i jfwiedza bez zwiazku z trescia) - brak linii przy kazdym z tych progow.
// Lepiej przeoczyc slabe uzycie (sama parafraza, jeden konkret) niz dac linie bez pokrycia -
// falszywy alarm uczy ignorowac.
const MIN_DOWODOW = 2;
const MIN_FRAZ = 3;
// Slowa pospolite (po zlozeniu) - nie tworza fraz. Do tego slowa krotsze niz 4 litery.
// Spojniki, zaimki, czasowniki posilkowe PL/DE/EN i slowa ram transkryptu Lore (user, tool, result).
const POSPOLITE = new Set((
  "jest jestem jestes sa byc bedzie beda byl byla bylo byli moze mozna musi trzeba nalezy ktory ktora ktore ktorej " +
  "ktorych ktorym tego temu tych tymi tutaj teraz jeszcze tylko takze tez oraz albo czyli wiec jednak potem przed " +
  "przez przy pod nad bez dla gdzie kiedy jesli jezeli zeby aby bardzo wszystko wszystkie wszystkich kazdy kazda " +
  "kazde inny inna inne innych swoj swoja swoje mnie tobie ciebie jego jej ich nas was nasz nasza nasze twoj twoja " +
  "twoje sobie siebie mamy masz macie maja mial miala mialo zrobic zrobione zrobilem sprawdz sprawdzic sprawdzilem " +
  "sprawdzone jakie jaki jaka jako jak tak nie juz czy lub ani albo dzis wczoraj jutro okolo pliku plik plikow " +
  "tylko wiecej mniej bylo dalej razem osobno potrzebne gotowe dziala dzialac jednym jedna jeden dwie dwa trzy " +
  "user tool result assistant uzytkownik asystent rozmowa conversation streszczenie text " +
  "this that with from have will would should could there their they them what when which while into also only " +
  "then than been were your about just more some such each other these those does done make made " +
  "nicht eine einen einer eines oder auch noch sind wird werden wurde haben fuer ueber unter nach mit dass " +
  "dies diese dieser dieses kann sein"
).split(/\s+/));
// Identyfikatory techniczne z literami i cyframi, ktore padaja wszedzie - nie sa niczyim cytatem.
const POSPOLITE_ID = new Set("utf-8 utf8 win32 win64 x64 x86 sha256 sha1 md5 base64 ipv4 ipv6 oauth2 http2 mp3 mp4 h264 iso8601 es2020 es2022 1x 2x 3x 4x 5x 10x".split(" "));
const JEDNOSTKI = "ml|kg|mg|g|szt|cm|mm|gb|mb|kb|ms|min|godz|h|dni|zl|pln|eur|usd|gbp|%";

function zloz(t) {
  return String(t).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\u0142/g, "l").replace(/\u00df/g, "ss");
}

function dzienMiesiac(d, m) {
  const dd = +d, mm = +m;
  if (dd < 1 || dd > 31 || mm < 1 || mm > 12) return null;
  return "d:" + String(mm).padStart(2, "0") + "-" + String(dd).padStart(2, "0");
}

// Mapa cecha -> ciag, z ktorego pochodzi (grupa). Jeden SKU daje kilka cech (calosc,
// "set3-health", "010407"), ale to jeden dowod - przy liczeniu dowodow grupa liczy sie raz.
// "filtr" (Set cech) - liczymy tylko te cechy: tekst "znanych" bywa megabajtem, a potrzeba z niego
// jedynie cech wspolnych odpowiedzi i fragmentom (kilkadziesiat).
function cechy(tekst, filtr) {
  const c = new Map();
  const dodaj = (k, grupa) => {
    if ((filtr && !filtr.has(k)) || c.has(k)) return;
    c.set(k, grupa || k);
  };
  // Separator tysiecy (spacja) znika: "1 272,70" i "1272.70" z wyniku narzedzia to ta sama liczba.
  let t = zloz(tekst);
  for (let i = 0; i < 2; i++) t = t.replace(/(?<![\d.,])(\d{1,3})[ \u00a0\u202f](\d{3})(?![\d])/g, "$1$2");
  let m;
  // Liczba jest cecha od 3 cyfr: krotsze ("1,5 h", "2 dni", "5%") pada wszedzie.
  const liczbaCecha = (cyfry) => cyfry.length >= 3;
  // liczby dwucyfrowe z jednostka ("30 szt", "40 g") - od trzech cyfr liczba jest cecha sama
  // w sobie (nizej), jednostka nie dodaje drugiego dowodu
  const reJedn = new RegExp("(?<![\\w.,])(\\d{2}) ?(" + JEDNOSTKI + ")(?![a-z0-9])", "g");
  while ((m = reJedn.exec(t))) dodaj("u:" + m[1] + m[2]);
  // daty
  const reIso = /(?<![\d.])(?:19|20)\d\d-(\d\d)-(\d\d)(?!\d)/g;
  while ((m = reIso.exec(t))) { const k = dzienMiesiac(m[2], m[1]); if (k) dodaj(k); }
  const rePl = /(?<![\d.,])(\d{1,2})\.(\d{2})(?:\.(?:19|20)\d\d)?(?![\d]|\.\d)/g;
  while ((m = rePl.exec(t))) { const k = dzienMiesiac(m[1], m[2]); if (k) dodaj(k); }
  // ulamki: przecinek zawsze, kropka gdy to nie data i nie numer wersji; potem znikaja z tekstu,
  // zeby czesc calkowita ("272" z "272,70") nie liczyla sie drugi raz jako osobny numer
  t = t.replace(/(?<![\d.,])(\d+)([.,])(\d+)(?![\d]|[.,]\d)/g, (cale, a, z, b) => {
    if (z === "." && dzienMiesiac(a, b) && b.length === 2) return cale;
    if (liczbaCecha(a + b)) dodaj("n:" + a + "." + b);
    return " ";
  });
  // identyfikatory i numery - tylko ciagi z cyfra (bez cyfry nie ma ani identyfikatora, ani
  // numeru; to tez oszczednosc czasu przy megabajtowych "znanych")
  const reCiag = /[a-z0-9_\-\/\[\]#.]+/g;
  const szukacCiagow = !filtr || [...filtr].some((k) => !k.startsWith("w:"));
  while (szukacCiagow && (m = reCiag.exec(t))) {
    if (!/\d/.test(m[0])) continue;
    const tok = m[0].replace(/^[.\-\/#_\[]+|[.\-\/#_]+$/g, "");
    if (!tok) continue;
    const czesci = [tok].concat(tok.split(/[\/\[\]#]+/).filter((p) => p && p !== tok));
    const grupa = "g:" + tok;
    for (const p0 of czesci) {
      const p = p0.replace(/^[.\-_]+|[.\-_]+$/g, "");
      if (!p) continue;
      if (/^\d{1,3}(\.\d+){2,}$/.test(p)) { dodaj("i:" + p, grupa); continue; }          // numer wersji
      const litery = /[a-z]/.test(p), cyfry = /\d/.test(p);
      if (litery && cyfry && p.length >= 4 && !POSPOLITE_ID.has(p)) { dodaj("i:" + p, grupa); continue; }
      if (/^\d+$/.test(p) && liczbaCecha(p) && !/^(19|20)\d\d$/.test(p)) dodaj("n:" + p, grupa);
    }
  }
  // frazy: trzy kolejne slowa tresciowe
  const slowa = [];
  const reSlowo = /[a-z]+/g;
  const szukacFraz = !filtr || [...filtr].some((k) => k.startsWith("w:"));
  while (szukacFraz && (m = reSlowo.exec(t))) {
    const s = m[0];
    if (s.length < 4 || POSPOLITE.has(s)) continue;
    slowa.push(s.slice(0, 6));
  }
  let pierwsze = null;
  if (filtr) {
    pierwsze = new Set();
    for (const k of filtr) if (k.startsWith("w:")) pierwsze.add(k.slice(2, k.indexOf(" ")));
  }
  for (let i = 0; i + 2 < slowa.length; i++) {
    if (pierwsze && !pierwsze.has(slowa[i])) continue;
    dodaj("w:" + slowa[i] + " " + slowa[i + 1] + " " + slowa[i + 2]);
  }
  return c;
}

// Ocena fragmentow wzgledem odpowiedzi. "znaneDla(f, filtr)" zwraca { tekst, cechy } tego, co
// model mial skad indziej (liczone leniwie - tylko gdy cokolwiek z odpowiedzi pasuje do fragmentu).
// Zwraca liste { klucz, id, dowodow, dowody } wykorzystanych fragmentow.
function ocen(fragmenty, odpowiedz, znaneDla) {
  if (!fragmenty.length || !odpowiedz.trim()) return [];
  const cOdp = cechy(odpowiedz);
  const zOdp = zloz(odpowiedz);
  const wynik = [];
  // Najpierw cechy wspolne odpowiedzi i fragmentom; tylko je sprawdzamy potem w znanych.
  const kandydaci = [];
  const filtr = new Set();
  for (const f of fragmenty) {
    const wspolne = [];
    for (const k of cechy(f.tekst).keys()) if (cOdp.has(k)) { wspolne.push(k); filtr.add(k); }
    const cytat = f.id !== "?" && new RegExp("#" + f.id + "(?!\\d)").test(zOdp);
    if (wspolne.length || cytat) kandydaci.push({ f, wspolne, cytat });
  }
  for (const { f, wspolne, cytat } of kandydaci) {
    const znane = znaneDla(f, filtr);
    const grupy = new Set();
    const dowody = [];
    let frazy = true;
    for (const k of wspolne) {
      if (znane.cechy.has(k)) continue;
      grupy.add(cOdp.get(k));
      dowody.push(k);
      if (!k.startsWith("w:")) frazy = false;
    }
    const cytatNowy = cytat && !new RegExp("#" + f.id + "(?!\\d)").test(znane.tekst);
    if (cytatNowy) dowody.unshift("#" + f.id);
    if (!cytatNowy && grupy.size < (frazy ? MIN_FRAZ : MIN_DOWODOW)) continue;
    // Ten sam wpis z dwoch zrodel (lore_search i lore_context, doklejka i wyszukanie) - raz.
    const byl = wynik.find((x) => x.klucz === f.klucz && x.id === f.id);
    if (byl && byl.dowodow >= grupy.size) continue;
    if (byl) wynik.splice(wynik.indexOf(byl), 1);
    wynik.push({ klucz: f.klucz, id: f.id, dowodow: grupy.size, dowody: dowody.slice(0, DOWODOW_NA_WPIS) });
  }
  return wynik;
}

// ------------------------------------------------------------------ zbieranie z transkryptu

// Narzedzia, ktorych wynik to raport workera (posrednik), a nie swieze dane: dla fragmentow
// znalezionych przez workera ich wynik NIE jest "znany" - to ta sama pamiec, podana dalej.
const POSREDNICY = new Set(["Agent", "Task", "SendMessage", "TaskOutput"]);

function nowyZbior() {
  return { fragmenty: [], znane: [], posrednie: [], odpowiedz: [], wywolania: {}, wywolaniaWorkerow: 0 };
}

// Przechodzi wpisy jednego watku. "tura" = czy to biezaca tura (wtedy fragmenty i odpowiedz
// sie licza); poza tura (wczesniejsza czesc rozmowy) wszystko oprocz pamieci idzie do znanych.
// "nazwy" - mapa id wywolania -> nazwa narzedzia (wywolania poprzedzaja wyniki).
function przejdz(wpisy, zbior, opcje) {
  const { tura, worker, nazwy, widziane } = opcje;
  for (const w of wpisy) {
    if (!w || typeof w !== "object") continue;
    if (w.type === "assistant" && w.message && Array.isArray(w.message.content)) {
      for (const c of w.message.content) {
        if (!c) continue;
        if (c.type === "tool_use" && typeof c.name === "string") {
          if (c.id) nazwy.set(c.id, c.name);
          if (tura && serwerNarzedzia(c.name) && ZRODLA.some((z) => z.serwer === serwerNarzedzia(c.name).serwer)) {
            if (c.id && widziane.has(c.id)) continue;
            if (c.id) widziane.add(c.id);
            const k = serwerNarzedzia(c.name).serwer;
            zbior.wywolania[k] = (zbior.wywolania[k] || 0) + 1;
            if (worker || w.isSidechain) zbior.wywolaniaWorkerow++;
          }
        } else if (c.type === "text" && typeof c.text === "string") {
          // Odpowiedz to tekst glownego watku w tej turze; wczesniejsze odpowiedzi to rzeczy juz
          // znane. Tekst workera to jego raport - posrednik (niesie jego pamiec dalej).
          if (worker || w.isSidechain) zbior.posrednie.push(c.text);
          else if (tura) zbior.odpowiedz.push(c.text);
          else zbior.znane.push(c.text);
        }
      }
      continue;
    }
    if (w.type === "user" && w.message) {
      const tresc = w.message.content;
      if (Array.isArray(tresc) && tresc.some((c) => c && c.type === "tool_result")) {
        for (const c of tresc) {
          if (!c || c.type !== "tool_result") continue;
          const nazwa = nazwy.get(c.tool_use_id) || "";
          const tekst = tekstTresci(c.content);
          const klucz = zrodloDanych(nazwa);
          if (klucz) {
            if (tura) zbior.fragmenty.push(...fragmentyWyniku(klucz, tekst).map((f) => Object.assign(f, { worker: Boolean(worker || w.isSidechain) })));
            // poza tura: stare wyniki pamieci nie sa ani fragmentem tej odpowiedzi, ani "swiezymi danymi"
          } else if (POSREDNICY.has(nazwa)) zbior.posrednie.push(tekst);
          else zbior.znane.push(tekst);
        }
      } else {
        const tekst = tekstTresci(tresc);
        // Powiadomienie o workerze niesie jego raport - posrednik, jak wynik Agent.
        if (/^\s*<task-notification>/.test(tekst)) zbior.posrednie.push(tekst);
        else zbior.znane.push(tekst);
      }
      continue;
    }
    if (w.type === "attachment" && w.attachment) {
      const a = w.attachment;
      const napisy = napisyZ(a.content !== undefined ? a.content : a, []).join("\n");
      if (a.type === "hook_additional_context" && ZRODLA.some((z) => napisy.includes(z.naglowek))) {
        const d = fragmentyDoklejki(napisy);
        if (tura && !worker) zbior.fragmenty.push(...d.fragmenty);
        zbior.znane.push(d.reszta);
      } else if (a.type !== "prompt_snapshot") {
        // Zalaczniki (tresc pliku, kontekst innych hookow) - model je widzi, wiec to rzeczy znane.
        // prompt_snapshot to zasady systemowe Claude Code (kilkanascie KB), bez danych firmy.
        zbior.znane.push(napisy);
      }
    }
  }
}

// Pliki instrukcji, ktore model ma w kazdej turze - tresc z nich to nie pamiec.
function plikiInstrukcji(prosba, transkrypt) {
  const z = process.env.MR_ZNACZNIK_INSTRUKCJE;
  if (z !== undefined) return z.split(";").filter(Boolean);
  const pliki = [path.join(os.homedir(), ".claude", "CLAUDE.md"),
    path.join(path.dirname(transkrypt), "memory", "MEMORY.md")];
  const cwd = prosba && prosba.cwd;
  if (cwd) pliki.push(path.join(cwd, "CLAUDE.md"));
  return pliki;
}

function czytajInstrukcje(pliki, bledy) {
  const teksty = [];
  for (const p of pliki) {
    try { teksty.push(fs.readFileSync(p, "utf8")); }
    catch (e) { if (!e || e.code !== "ENOENT") bledy.push("instrukcje " + p + ": " + e.message); }
  }
  return teksty;
}

// Workerzy od chwili "od" (ms): fragmenty pamieci z ich wynikow i ich wlasne swieze dane.
// Pliki zmienione przed "od" pomijamy bez czytania. Bledy do stanu - nie przerywaja.
function zbierzWorkerow(transkrypt, od, widziane) {
  const kat = path.join(path.dirname(transkrypt), path.basename(transkrypt, ".jsonl"), "subagents");
  const workerzy = [];
  let pliki;
  try { pliki = fs.readdirSync(kat); }
  catch (e) {
    if (e && e.code === "ENOENT") return { workerzy, bledy: [] };   // rozmowa bez workerow
    return { workerzy, bledy: ["katalog workerow: " + e.message] };
  }
  const bledy = [];
  for (const f of pliki) {
    if (!/^agent-.*\.jsonl$/.test(f)) continue;
    const p = path.join(kat, f);
    try {
      if (fs.statSync(p).mtimeMs <= od) continue;
      const r = wpisyOdKonca(p, (w) => { const t = czasWpisu(w); return t !== null && t <= od; });
      const zbior = nowyZbior();
      const nazwy = new Map();
      // Wpisy sprzed "od" tylko po nazwy wywolan i znane dane (wynik moze przyjsc po "od").
      przejdz(r.wpisy.filter((w) => { const t = czasWpisu(w); return t === null || t <= od; }), zbior,
        { tura: false, worker: true, nazwy, widziane: new Set() });
      przejdz(r.wpisy.filter((w) => { const t = czasWpisu(w); return t !== null && t > od; }), zbior,
        { tura: true, worker: true, nazwy, widziane });
      workerzy.push(zbior);
    } catch (e) {
      bledy.push(f + ": " + e.message);
    }
  }
  return { workerzy, bledy };
}

function linia(wykorzystane) {
  return ZRODLA.filter((z) => wykorzystane.some((x) => x.klucz === z.klucz)).map((z) => z.znaczek).join(" \u00b7 ");
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

// Ocena tury z gotowych wpisow (bez plikow) - wspolna dla hooka i kalibracji.
//   tura      - wpisy glownego watku od poczatku tury,
//   przed     - wczesniejsza czesc rozmowy: lista albo funkcja, ktora ja da (wolana tylko, gdy
//               cokolwiek z odpowiedzi pasuje do fragmentu),
//   workerzy  - zbiory z zbierzWorkerow, instrukcje - teksty plikow instrukcji.
// Zwraca { wykorzystane, fragmentow, wywolania, wywolaniaWorkerow }.
function ocenTure(tura, przed, workerzy, instrukcje, widziane) {
  const glowny = nowyZbior();
  przejdz(tura, glowny, { tura: true, worker: false, nazwy: new Map(), widziane: widziane || new Set() });
  const odpowiedz = glowny.odpowiedz.join("\n");
  let historia = null;
  const zHistorii = () => {
    if (!historia) {
      historia = nowyZbior();
      przejdz(typeof przed === "function" ? przed() : (przed || []), historia,
        { tura: false, worker: false, nazwy: new Map(), widziane: new Set() });
    }
    return historia;
  };

  // Znane liczymy leniwie i raz: glowny watek + instrukcje (+ posrednicy dla fragmentow glownego
  // watku; dla fragmentow workera raport workera to ta sama pamiec, wiec bez niego, za to z jego
  // wlasnymi swiezymi danymi).
  const pamiec = new Map();
  const zbuduj = (klucz, teksty, filtr) => {
    if (!pamiec.has(klucz)) {
      const tekst = zloz(teksty.join("\n"));
      pamiec.set(klucz, { tekst, cechy: cechy(tekst, filtr) });
    }
    return pamiec.get(klucz);
  };
  const baza = () => zHistorii().znane.concat(glowny.znane, instrukcje);
  const wszystkie = glowny.fragmenty.map((f) => ({ f, znane: (filtr) =>
    zbuduj("glowny", baza().concat(zHistorii().posrednie, glowny.posrednie), filtr) }));
  workerzy.forEach((wz, i) => {
    for (const f of wz.fragmenty) wszystkie.push({ f, znane: (filtr) => zbuduj("worker" + i, baza().concat(wz.znane), filtr) });
  });
  const znaneDla = new Map(wszystkie.map((x) => [x.f, x.znane]));
  const wykorzystane = ocen(wszystkie.map((x) => x.f), odpowiedz, (f, filtr) => znaneDla.get(f)(filtr));

  const wywolania = Object.assign({}, glowny.wywolania);
  let wywolaniaWorkerow = glowny.wywolaniaWorkerow;
  for (const wz of workerzy) {
    for (const k of Object.keys(wz.wywolania)) wywolania[k] = (wywolania[k] || 0) + wz.wywolania[k];
    wywolaniaWorkerow += wz.wywolaniaWorkerow;
  }
  const fragmentow = {};
  for (const x of wszystkie) fragmentow[x.f.klucz] = (fragmentow[x.f.klucz] || 0) + 1;
  return { wykorzystane, fragmentow, wywolania, wywolaniaWorkerow };
}

// Robota wlasciwa. Zwraca { linia, wynik, ... } albo rzuca - awarie lapie glowna().
function zbadaj(prosba, stan) {
  const transkrypt = prosba && (prosba.transcript_path || prosba.transcriptPath);
  if (!transkrypt) throw new Error("wejscie hooka bez transcript_path");
  if (!fs.existsSync(transkrypt)) throw new Error("brak pliku transkryptu " + transkrypt);
  const sesja = String(prosba.session_id || prosba.sessionId || path.basename(transkrypt, ".jsonl"));

  const r = wpisyOdKonca(transkrypt, poczatekTury);
  if (!r.znaleziono) {
    throw new Error("w transkrypcie nie ma wiadomosci uzytkownika (" + r.wpisy.length + " wpisow, " + r.zepsute + " zepsutych linii)");
  }

  // Workerzy: od poprzedniego Stop tej rozmowy, a gdy go nie znamy - od poczatku tury.
  const sesje = stan.sesje && typeof stan.sesje === "object" ? stan.sesje : {};
  const poprzedni = sesje[sesja] ? Date.parse(sesje[sesja].ostatni) : NaN;
  const od = !isNaN(poprzedni) ? poprzedni : czasWpisu(r.wpisy[0]);
  const widziane = new Set();
  let workerzy = [];
  let bledy = [];
  if (od !== null) ({ workerzy, bledy } = zbierzWorkerow(transkrypt, od, widziane));
  else bledy = ["poczatek tury bez czasu - workerow nie policzylem"];
  const instrukcje = czytajInstrukcje(plikiInstrukcji(prosba, transkrypt), bledy);

  const o = ocenTure(r.wpisy, r.przed, workerzy, instrukcje, widziane);

  sesje[sesja] = { ostatni: new Date().toISOString() };
  const klucze = Object.keys(sesje).sort((a, b) => String(sesje[b].ostatni).localeCompare(String(sesje[a].ostatni)));
  for (const k of klucze.slice(PAMIETANYCH_SESJI)) delete sesje[k];
  stan.sesje = sesje;

  const l = linia(o.wykorzystane);
  const wykorzystane = {};
  for (const x of o.wykorzystane) (wykorzystane[x.klucz] = wykorzystane[x.klucz] || []).push({ id: x.id, dowodow: x.dowodow, dowody: x.dowody });
  const szukano = Object.keys(o.wywolania).length || Object.keys(o.fragmentow).length;
  return { linia: l, wynik: l ? "pokazano" : (szukano ? "bez wykorzystania" : "nic"), zepsute: r.zepsute, bledyWorkerow: bledy,
    wykorzystane, fragmentow: o.fragmentow, wywolania: o.wywolania, wywolaniaWorkerow: o.wywolaniaWorkerow };
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
  // Do sprawdzenia przez czlowieka: ktore wpisy uznano za wykorzystane i po czym; ile fragmentow
  // pamieci bylo w turze i ile wywolan (wyszukanie bez wykorzystania = wynik "bez wykorzystania").
  stan.wykorzystane = wynik.wykorzystane || {};
  stan.fragmentow = wynik.fragmentow || {};
  stan.wywolania = wynik.wywolania || {};
  stan.wywolania_workerow = wynik.wywolaniaWorkerow || 0;
  if (wynik.bledyWorkerow.length) stan.bledy_workerow = wynik.bledyWorkerow.slice(0, 10); else delete stan.bledy_workerow;
  zapiszStan(plik, stan);

  const tekst = alarm ? (wynik.linia ? alarm + "\n" + wynik.linia : alarm) : wynik.linia;
  wypisz(tekst ? { systemMessage: tekst } : null);
}

module.exports = { ocenTure, cechy, fragmentyDoklejki, fragmentyWyniku, zbierzWorkerow, wpisyOdKonca, poczatekTury, MIN_DOWODOW, MIN_FRAZ };

if (require.main === module) {
  glowna().catch((e) => {
    // Ostatnia deska (blad poza zbadaj(), np. przy zapisie stanu): slad na stderr, tura konczy sie normalnie.
    process.stderr.write("znacznik-zrodla.js: " + (e && e.stack || e) + "\n");
    process.exit(0);
  });
}
