// Przypomnienia z terminem ("za 2 dni sprawdz logi X i ustaw prog") - jeden plik
// markdown na maszyne, poza repo: ~\.claude\mr\przypomnienia.md. AI zaklada je samo,
// gdy obiecuje cos sprawdzic pozniej (zasada w bloku MegaRuchacz:wiedza, zrodlo
// zasady-wiedza.md). Do 2026-10-05 takie sprawy lezaly w plikach pamieci jako
// "sprawdz na starcie sesji" i ginely - nikt tam nie zagladal w dniu terminu.
//
// Dwa tryby (decyzja uzytkownika 2026-10-05, "jak w Hermesie"):
//   sam        (domyslny) - w dniu terminu zasobnik\terminy.ps1 (wolany przez nadzorce przy
//              starcie i co godzine 8-20) SAM otwiera widoczne okno Claude Code w katalogu
//              projektu z zadaniem jako pierwszym poleceniem; status "w toku". Najwyzej JEDNO
//              samoczynne uruchomienie na przypomnienie. Nie odhaczone do nastepnego dnia ->
//              okno z przyciskami i adnotacja, ze automat nie dokonczyl.
//   przypomnij - tylko okno z przyciskami "Zrob teraz / Jutro / Zrobione" (potrzebny czlowiek).
// Do tego hook SessionStart Claude Code ("start") - na starcie KAZDEGO okna mowi AI, co jest
// zalegle; brak zaleglych = brak wyjscia. Hook uklada straznik (Wzory-Hookow-Globalnych,
// rodzaj "terminy").
//
// UMOWA PLIKU (czyta ja tez zasobnik\terminy.ps1 - przez "zalegle --json", nie wlasnym parserem):
//   - [ ] #<id> <RRRR-MM-DD> | <projekt> | <tresc> | sprawdz: <jak> | tryb: sam | dodane <RRRR-MM-DD>
//   - [~] #<id> ... | w toku <RRRR-MM-DD HH:MM>            (uruchomione, czeka na odhaczenie)
//   - [x] #<id> ... | zrobione <RRRR-MM-DD>
// Pola dzielone " | " (w tresci zamieniane na " / "); "sprawdz:" i "tryb:" opcjonalne (brak trybu
// = sam). Linia zaczynajaca sie od "- [", ktora nie pasuje do ukladu, to linia NIECZYTELNA -
// glosno, nigdy po cichu pominieta. Reszta pliku (naglowek, wlasne notatki) zostaje nietknieta:
// zmiany ida podmiana jednej linii, nie przepisaniem calosci z obiektow.
//
// Uzycie:
//   node narzedzia\terminy.js dodaj <kiedy> <projekt> "<tresc>" ["<jak sprawdzic>"] [--tylko-przypomnij]
//       kiedy: RRRR-MM-DD | DD.MM.RRRR | dzis | jutro | pojutrze | +N | "za N dni" |
//              "za tydzien" | "za N tygodni";  projekt: sciezka albo nazwa, "." = biezacy katalog
//       --tryb sam|przypomnij (--tylko-przypomnij = --tryb przypomnij)
//   node narzedzia\terminy.js lista [--wszystkie]
//   node narzedzia\terminy.js zrobione <id> [<id>...]          (tez: odhacz)
//   node narzedzia\terminy.js przesun <id> <kiedy>             (wraca do "otwarte")
//   node narzedzia\terminy.js w-toku <id>                      (wola zasobnik\terminy.ps1)
//   node narzedzia\terminy.js usun <id>                        (kasuje linie - pomylki, testy)
//   node narzedzia\terminy.js zalegle --json                   (dla zasobnik\terminy.ps1, ASCII)
//   node narzedzia\terminy.js start                            (hook SessionStart)
// Opcje (do testow): --dzis RRRR-MM-DD (udawana data), --plik <sciezka>, --dom <katalog domowy>;
// zmienne MR_DZIS, MR_PRZYPOMNIENIA. Kody: 0 ok, 1 blad, 2 zle wywolanie; "start" zawsze 0.

const fs = require("fs");
const os = require("os");
const path = require("path");

// Sufit tego, co hook "start" wstrzykuje do rozmowy. Claude Code przyjmuje z hooka do
// 10 000 znakow, ale tekst zostaje w historii i model czyta go przy kazdym wywolaniu -
// 2500 znakow to ~10 przypomnien po ~200 znakow, wiecej na starcie okna nikt nie ogarnie.
// Sufit nie ucina po cichu: co sie nie miesci, zapowiada PIERWSZA linia z liczba i komenda.
const SUFIT_STARTU = 2500;
// Zamek pliku przy zapisie (dwa okna moga dodawac naraz). Zamek starszy niz tyle
// sekund to pozostalosc po procesie, ktory padl - zdejmujemy go.
const ZAMEK_STARY_S = 30;
const ZAMEK_CZEKAJ_MS = 3000;
const TRYBY = ["sam", "przypomnij"];

const NAGLOWEK = [
  "# Przypomnienia MegaRuchacza",
  "",
  "Plik tej maszyny. Prowadzi go `narzedzia/terminy.js` (dodaj, lista, zrobione, przesun).",
  "Jedna linia = jedno przypomnienie: `- [ ] #id termin | projekt | treść | sprawdź: jak | tryb: sam | dodane data`.",
  "`[ ]` czeka, `[~]` w toku (uruchomione, czeka na odhaczenie), `[x]` zrobione. Tryb `sam` = w dniu terminu",
  "MegaRuchacz sam otwiera Claude Code z tym zadaniem; `przypomnij` = tylko okno z przyciskami.",
  "Można poprawiać ręcznie, byle zachować układ linii.",
  "",
];

// ------------------------------------------------------------------ argumenty

class BladWywolania extends Error {}

function argumenty(argv) {
  const pozycyjne = [];
  const opcje = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--wszystkie" || a === "--json") { opcje[a.slice(2)] = true; continue; }
    if (a === "--tylko-przypomnij") { opcje.tryb = "przypomnij"; continue; }
    if (a === "--dzis" || a === "--plik" || a === "--dom" || a === "--tryb") {
      if (i + 1 >= argv.length) throw new BladWywolania(`${a} wymaga wartosci`);
      opcje[a.slice(2)] = argv[++i];
      continue;
    }
    pozycyjne.push(a);
  }
  return { pozycyjne, opcje };
}

function numer(t) {
  const id = parseInt(String(t).replace(/^#/, ""), 10);
  if (!(id > 0)) throw new BladWywolania(`"${t}" to nie numer przypomnienia`);
  return id;
}

// ------------------------------------------------------------------ daty

function dwie(n) { return String(n).padStart(2, "0"); }
function naTekst(d) { return `${d.getFullYear()}-${dwie(d.getMonth() + 1)}-${dwie(d.getDate())}`; }
function teraz() { const d = new Date(); return `${naTekst(d)} ${dwie(d.getHours())}:${dwie(d.getMinutes())}`; }

// Data z "RRRR-MM-DD" - tylko prawdziwa (2026-02-30 to blad, nie 2 marca).
function zTekstu(t) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(t || "");
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  if (d.getFullYear() !== +m[1] || d.getMonth() !== +m[2] - 1 || d.getDate() !== +m[3]) return null;
  return d;
}

function dzis(opcje) {
  const udawana = opcje.dzis || process.env.MR_DZIS;
  if (udawana) {
    const d = zTekstu(udawana);
    if (!d) throw new BladWywolania(`--dzis: "${udawana}" to nie data RRRR-MM-DD`);
    return d;
  }
  const t = new Date();
  return new Date(t.getFullYear(), t.getMonth(), t.getDate());
}

function plusDni(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
function dniMiedzy(od, doo) { return Math.round((doo - od) / 86400000); }

// Termin z tego, co poda AI albo czlowiek. Nieznany zapis = blad, nigdy zgadywanie.
function termin(tekst, odDnia) {
  const t = String(tekst || "").trim().toLowerCase();
  let m;
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return zTekstu(t);
  if ((m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(t))) return zTekstu(`${m[3]}-${dwie(m[2])}-${dwie(m[1])}`);
  if (t === "dzis" || t === "dziś") return odDnia;
  if (t === "jutro") return plusDni(odDnia, 1);
  if (t === "pojutrze") return plusDni(odDnia, 2);
  if ((m = /^\+(\d{1,4})$/.exec(t))) return plusDni(odDnia, +m[1]);
  if ((m = /^(?:za\s+)?(\d{1,4})\s+(?:dzień|dzien|dni)$/.exec(t))) return plusDni(odDnia, +m[1]);
  if (t === "za tydzien" || t === "za tydzień") return plusDni(odDnia, 7);
  if ((m = /^(?:za\s+)?(\d{1,3})\s+(?:tygodnie|tygodni|tydzien|tydzień)$/.exec(t))) return plusDni(odDnia, 7 * +m[1]);
  return null;
}

function opisTerminu(d, odDnia) {
  const n = dniMiedzy(odDnia, d);
  if (n === 0) return "dziś";
  if (n === 1) return "jutro";
  if (n === -1) return "zaległe 1 dzień";
  if (n < 0) return `zaległe ${-n} dni`;
  return `za ${n} dni`;
}

// ------------------------------------------------------------------ plik

function sciezki(opcje) {
  const dom = opcje.dom || os.homedir();
  const plik = opcje.plik || process.env.MR_PRZYPOMNIENIA || path.join(dom, ".claude", "mr", "przypomnienia.md");
  return { dom, plik, stan: path.join(path.dirname(plik), "przypomnienia-stan.txt") };
}

const WZOR_LINII = /^- \[([ xX~])\] #(\d+) (\d{4}-\d{2}-\d{2}) \| (.*)$/;

// Czyta plik: linie surowe (do podmiany jednej) i przypomnienia z numerem linii.
// Brak pliku = pusta lista, nie blad.
function wczytaj(plik) {
  let tekst = "";
  if (fs.existsSync(plik)) tekst = fs.readFileSync(plik, "utf8").replace(/^﻿/, "");
  const nl = tekst.includes("\r\n") ? "\r\n" : (tekst ? "\n" : "\r\n");
  const linie = tekst ? tekst.split(/\r?\n/) : [];
  const pozycje = [];
  const nieczytelne = [];
  linie.forEach((l, i) => {
    if (!l.startsWith("- [")) return;
    const p = rozbierz(l);
    if (p) { p.nr = i; pozycje.push(p); }
    else nieczytelne.push({ nr: i + 1, linia: l });
  });
  return { tekst, nl, linie, pozycje, nieczytelne };
}

function rozbierz(l) {
  const m = WZOR_LINII.exec(l);
  if (!m || !zTekstu(m[3])) return null;
  const pola = m[4].split(" | ");
  if (pola.length < 2) return null;
  const znak = m[1].toLowerCase();
  const p = { status: znak === "x" ? "zrobione" : (znak === "~" ? "w toku" : "otwarte"), id: +m[2], termin: m[3],
              projekt: pola[0].trim(), tresc: pola[1].trim(), sprawdz: "", tryb: "sam", dodane: "", wTokuOd: "", dataZrobienia: "" };
  for (const pole of pola.slice(2)) {
    let r;
    if ((r = /^sprawd[zź]:\s*(.*)$/.exec(pole))) p.sprawdz = r[1].trim();
    else if ((r = /^tryb:\s*(sam|przypomnij)$/.exec(pole))) p.tryb = r[1];
    else if ((r = /^dodane (\d{4}-\d{2}-\d{2})$/.exec(pole))) p.dodane = r[1];
    else if ((r = /^w toku (\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)$/.exec(pole))) p.wTokuOd = r[1];
    else if ((r = /^zrobione (\d{4}-\d{2}-\d{2})$/.exec(pole))) p.dataZrobienia = r[1];
    else p.tresc += " / " + pole.trim();    // reczna edycja z " | " w tresci - nic nie ginie
  }
  return p;
}

// Zapis odporny na zanik pradu: plik tymczasowy obok, fsync, podmiana (ta sama zasada
// co Zapisz-Trwale w zapis-trwaly.ps1). Odmawia zapisu pustego tekstu - pusty plik
// przypomnien to zawsze blad, nigdy zamiar.
function zapisz(plik, tekst) {
  if (!tekst || !tekst.trim()) throw new Error(`odmawiam zapisu pustego pliku ${plik}`);
  fs.mkdirSync(path.dirname(plik), { recursive: true });
  const tmp = `${plik}.tmp-${process.pid}`;
  const fd = fs.openSync(tmp, "w");
  try {
    fs.writeSync(fd, tekst, null, "utf8");
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, plik);
}

function podZamkiem(plik, robota) {
  fs.mkdirSync(path.dirname(plik), { recursive: true });
  const zamek = plik + ".zamek";
  const koniec = Date.now() + ZAMEK_CZEKAJ_MS;
  for (;;) {
    try {
      fs.closeSync(fs.openSync(zamek, "wx"));
      break;
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
      try {
        if ((Date.now() - fs.statSync(zamek).mtimeMs) / 1000 > ZAMEK_STARY_S) { fs.unlinkSync(zamek); continue; }
      } catch (e2) { continue; }   // zamek zniknal miedzy sprawdzeniami - probujemy od nowa
      if (Date.now() > koniec) throw new Error(`plik przypomnien zajety (${zamek}) - inny proces go zapisuje; sprobuj za chwile`);
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
  }
  try { return robota(); }
  finally { try { fs.unlinkSync(zamek); } catch (e) { console.error(`UWAGA: nie zdjalem zamka ${zamek}: ${e.message}`); } }
}

function bezKreski(t) { return String(t).replace(/\s*\|\s*/g, " / ").replace(/[\r\n]+/g, " ").trim(); }

function linia(p) {
  let l = `- [ ] #${p.id} ${p.termin} | ${p.projekt} | ${p.tresc}`;
  if (p.sprawdz) l += ` | sprawdź: ${p.sprawdz}`;
  l += ` | tryb: ${p.tryb} | dodane ${p.dodane}`;
  return l;
}

// Zmiana jednej linii pod zamkiem. zmiana(p, stara) zwraca nowa linie albo null = usun linie.
function zmienLinie(opcje, id, zmiana) {
  const { plik } = sciezki(opcje);
  return podZamkiem(plik, () => {
    const w = wczytaj(plik);
    const p = w.pozycje.find((x) => x.id === id);
    if (!p) return null;
    const stara = w.linie[p.nr];
    const nowa = zmiana(p, stara);
    if (nowa !== stara) {
      const linie = w.linie.slice();
      if (nowa === null) linie.splice(p.nr, 1); else linie[p.nr] = nowa;
      zapisz(plik, linie.join(w.nl));
    }
    return { p, nowa };
  });
}

// Zdejmuje z linii pole "w toku ..." i wraca do "[ ]" - po przesunieciu sprawa znow czeka.
function otworz(stara) {
  return stara.replace(/^- \[~\]/, "- [ ]").replace(/ \| w toku \d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?(?= \||$)/, "");
}

// ------------------------------------------------------------------ polecenia

function dodaj(poz, opcje) {
  if (poz.length < 3) throw new BladWywolania('dodaj <kiedy> <projekt> "<tresc>" ["<jak sprawdzic>"] [--tylko-przypomnij]');
  const odDnia = dzis(opcje);
  const d = termin(poz[0], odDnia);
  if (!d) throw new BladWywolania(`nie rozumiem terminu "${poz[0]}" - podaj RRRR-MM-DD, +N albo "za N dni"`);
  const tryb = (opcje.tryb || "sam").toLowerCase();
  if (!TRYBY.includes(tryb)) throw new BladWywolania(`tryb "${opcje.tryb}" - dozwolone: ${TRYBY.join(", ")}`);
  let projekt = poz[1];
  if (projekt === ".") projekt = process.cwd();
  projekt = bezKreski(projekt);
  const tresc = bezKreski(poz[2]);
  if (!projekt || !tresc) throw new BladWywolania("projekt i tresc nie moga byc puste");
  const { plik } = sciezki(opcje);
  return podZamkiem(plik, () => {
    const w = wczytaj(plik);
    const id = w.pozycje.reduce((m, p) => Math.max(m, p.id), 0) + 1;
    const p = { id, termin: naTekst(d), projekt, tresc, sprawdz: bezKreski(poz[3] || ""), tryb, dodane: naTekst(odDnia) };
    let linie = w.linie.slice();
    while (linie.length && linie[linie.length - 1] === "") linie.pop();
    if (!linie.length) linie = NAGLOWEK.slice();   // nowy plik: naglowek z pusta linia pod spodem
    linie.push(linia(p), "");
    zapisz(plik, linie.join(w.nl));
    const jak = tryb === "sam" ? "MegaRuchacz sam otworzy Claude Code z tym zadaniem" : "tylko okno z przypomnieniem";
    console.log(`Dodane przypomnienie #${id} na ${p.termin} (${opisTerminu(d, odDnia)}, tryb ${tryb}: ${jak}): ${projekt} - ${tresc}`);
    console.log(`Plik: ${plik}`);
    ostrzezNieczytelne(w);
    return 0;
  });
}

function lista(poz, opcje) {
  const odDnia = dzis(opcje);
  const { plik } = sciezki(opcje);
  const w = wczytaj(plik);
  const wybrane = w.pozycje.filter((p) => opcje.wszystkie || p.status !== "zrobione")
    .sort((a, b) => a.termin.localeCompare(b.termin) || a.id - b.id);
  if (!wybrane.length) {
    console.log(opcje.wszystkie ? `Brak przypomnien (plik: ${plik}).` : `Brak otwartych przypomnien (plik: ${plik}).`);
  } else {
    console.log(`Przypomnienia (plik: ${plik}):`);
    for (const p of wybrane) {
      let kiedy = opisTerminu(zTekstu(p.termin), odDnia);
      if (p.status === "zrobione") kiedy = `zrobione ${p.dataZrobienia || "?"}`;
      if (p.status === "w toku") kiedy += `, w toku od ${p.wTokuOd || "?"}`;
      let l = `#${p.id}  ${p.termin} (${kiedy}, tryb ${p.tryb})  ${p.projekt}  -  ${p.tresc}`;
      if (p.sprawdz) l += `  [sprawdź: ${p.sprawdz}]`;
      console.log(l);
    }
  }
  ostrzezNieczytelne(w);
  return 0;
}

function zrobione(poz, opcje) {
  if (!poz.length) throw new BladWywolania("zrobione <id> [<id>...]");
  const dzien = naTekst(dzis(opcje));
  let kod = 0;
  for (const t of poz) {
    const id = numer(t);
    let juz = false;
    const w = zmienLinie(opcje, id, (p, stara) => {
      if (p.status === "zrobione") { juz = true; return stara; }
      return otworz(stara).replace(/^- \[ \]/, "- [x]") + ` | zrobione ${dzien}`;
    });
    if (!w) { console.error(`Nie ma przypomnienia #${id}.`); kod = 1; continue; }
    console.log(juz ? `#${id} bylo juz odhaczone.` : `Odhaczone #${id}: ${w.p.tresc}`);
  }
  return kod;
}

function przesun(poz, opcje) {
  if (poz.length < 2) throw new BladWywolania("przesun <id> <kiedy>");
  const id = numer(poz[0]);
  const odDnia = dzis(opcje);
  const d = termin(poz[1], odDnia);
  if (!d) throw new BladWywolania(`nie rozumiem terminu "${poz[1]}" - podaj RRRR-MM-DD, +N albo "za N dni"`);
  const nowy = naTekst(d);
  let zrobioneJuz = false;
  const w = zmienLinie(opcje, id, (p, stara) => {
    if (p.status === "zrobione") { zrobioneJuz = true; return stara; }
    return otworz(stara).replace(/^(- \[ \] #\d+ )\d{4}-\d{2}-\d{2}/, `$1${nowy}`);
  });
  if (!w) { console.error(`Nie ma przypomnienia #${id}.`); return 1; }
  if (zrobioneJuz) { console.error(`#${id} jest juz odhaczone - nie przesuwam.`); return 1; }
  console.log(`#${id} przesuniete na ${nowy} (${opisTerminu(d, odDnia)}): ${w.p.tresc}`);
  return 0;
}

// "Uruchomione, czeka na odhaczenie" - ustawia zasobnik\terminy.ps1 PRZED otwarciem okna
// Claude Code: wywrotka po starcie okna nie moze skonczyc sie drugim uruchomieniem.
// --ponownie: sprawa juz "w toku" (automat nie dokonczyl), a czlowiek kliknal "Zrob teraz" -
// odswiezamy sama godzine. Bez tej flagi "w toku" odmawia: tak pilnujemy jednego uruchomienia.
function wToku(poz, opcje) {
  if (!poz.length) throw new BladWywolania("w-toku <id> [--ponownie]");
  const id = numer(poz[0]);
  const ponownie = poz.slice(1).includes("--ponownie");
  let blad = "";
  const w = zmienLinie(opcje, id, (p, stara) => {
    if (p.status === "otwarte") return stara.replace(/^- \[ \]/, "- [~]") + ` | w toku ${teraz()}`;
    if (p.status === "w toku" && ponownie) return otworz(stara).replace(/^- \[ \]/, "- [~]") + ` | w toku ${teraz()}`;
    blad = `#${id} ma status "${p.status}" - nie oznaczam`;
    return stara;
  });
  if (!w) { console.error(`Nie ma przypomnienia #${id}.`); return 1; }
  if (blad) { console.error(blad); return 1; }
  console.log(`#${id} w toku: ${w.p.tresc}`);
  return 0;
}

function usun(poz, opcje) {
  if (!poz.length) throw new BladWywolania("usun <id>");
  const id = numer(poz[0]);
  const w = zmienLinie(opcje, id, () => null);
  if (!w) { console.error(`Nie ma przypomnienia #${id}.`); return 1; }
  console.log(`Usuniete #${id}: ${w.p.tresc}`);
  return 0;
}

// Wszystkie nieodhaczone z terminem dzis albo wczesniej - dla zasobnik\terminy.ps1, ktory
// sam decyduje, co uruchomic, a co pokazac w oknie. JSON wylacznie w ASCII (\uXXXX):
// PowerShell 5.1 czyta wyjscie programu w stronie kodowej konsoli i psulby polskie litery.
function zalegle(poz, opcje) {
  const odDnia = dzis(opcje);
  const { plik } = sciezki(opcje);
  const w = wczytaj(plik);
  const lista = w.pozycje.filter((p) => p.status !== "zrobione" && zTekstu(p.termin) <= odDnia)
    .sort((a, b) => a.termin.localeCompare(b.termin) || a.id - b.id)
    .map((p) => ({ id: p.id, termin: p.termin, projekt: p.projekt, tresc: p.tresc, sprawdz: p.sprawdz, tryb: p.tryb,
                   status: p.status, wTokuOd: p.wTokuOd, opis: opisTerminu(zTekstu(p.termin), odDnia) }));
  const wynik = { dzis: naTekst(odDnia), plik, skrypt: __filename, zalegle: lista,
                  nieczytelne: w.nieczytelne.map((n) => `linia ${n.nr}: ${n.linia.slice(0, 200)}`) };
  if (!opcje.json) throw new BladWywolania("zalegle tylko z --json (dla ludzi jest: lista)");
  process.stdout.write(JSON.stringify(wynik).replace(/[\u0080-￿]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0")) + "\n");
  return 0;
}

function ostrzezNieczytelne(w) {
  for (const n of w.nieczytelne) console.log(`UWAGA: linia ${n.nr} pliku przypomnien ma zly uklad i jest pomijana: ${n.linia}`);
}

// Hook SessionStart: zalegle przypomnienia z poleceniem dla AI. Pomija te, ktore wlasnie
// chodza (w toku od dzis) - inaczej okno otwarte przez automat dostaloby swoje zadanie dwa
// razy. Tryb "sam" jeszcze nieuruchomiony: AI ma o nim powiedziec, ale NIE robic go tutaj,
// bo za chwile uruchomi go automat. Nic do pokazania = zero wyjscia (slad "bylem tu" zostaje
// w przypomnienia-stan.txt). Wywrotka nie jest cisza: jedna linia z powodem.
function start(poz, opcje) {
  const { plik, stan } = sciezki(opcje);
  const odDnia = dzis(opcje);
  const dzisTekst = naTekst(odDnia);
  const w = wczytaj(plik);
  const zal = w.pozycje.filter((p) => p.status !== "zrobione" && zTekstu(p.termin) <= odDnia &&
    !(p.status === "w toku" && (p.wTokuOd || "").slice(0, 10) >= dzisTekst))
    .sort((a, b) => a.termin.localeCompare(b.termin) || a.id - b.id);
  // Uwagi (linie nieczytelne, brak sladu) ida NAD przypomnieniami i licza sie do sufitu.
  // Najwyzej trzy linie - dalsze tylko liczba, bo zepsuty plik nie moze zjesc calego startu.
  const uwagi = [];
  for (const n of w.nieczytelne.slice(0, 3)) uwagi.push(`MegaRuchacz: linia ${n.nr} w ${plik} ma zly uklad i nie jest czytana jako przypomnienie - popraw ja: ${n.linia.slice(0, 200)}`);
  if (w.nieczytelne.length > 3) uwagi.push(`MegaRuchacz: i jeszcze ${w.nieczytelne.length - 3} takich linii w ${plik}.`);
  try {
    fs.mkdirSync(path.dirname(stan), { recursive: true });
    fs.writeFileSync(stan, `hook: ${new Date().toISOString()}\r\nzalegle: ${zal.length}\r\nnieczytelne: ${w.nieczytelne.length}\r\n`, "utf8");
  } catch (e) {
    uwagi.push(`MegaRuchacz: przypomnienia - nie zapisalem sladu ${stan}: ${e.message}`);
  }
  const wyjscie = [];
  if (zal.length) {
    const skrypt = __filename.replace(/\\/g, "/");
    const stopka = `Powiedz o nich użytkownikowi na samym początku pierwszej odpowiedzi, jednym-dwoma zdaniami. ` +
      `Pozycje „uruchomi się samo” zrobi automat w osobnym oknie - nie wykonuj ich tutaj bez prośby użytkownika. ` +
      `Gdy sprawa jest załatwiona, odhacz: node "${skrypt}" zrobione <id>; nowy termin: node "${skrypt}" przesun <id> <kiedy>.`;
    const pozycje = zal.map((p) => {
      let stanP = opisTerminu(zTekstu(p.termin), odDnia);
      if (p.status === "w toku") stanP += p.tryb === "sam" ? `, automat uruchomił je ${p.wTokuOd} i nie dokończył` : `, uruchomione ${p.wTokuOd}, nie odhaczone`;
      else if (p.tryb === "sam") stanP += ", uruchomi się samo";
      let l = `- #${p.id} [${p.termin}, ${stanP}] ${p.projekt}: ${p.tresc}`;
      if (p.sprawdz) l += ` (sprawdź: ${p.sprawdz})`;
      return l;
    });
    const glowa = `MegaRuchacz - przypomnienia z terminem na dziś lub zaległe (${zal.length}):`;
    const ostrzezenie = (n) => n < pozycje.length
      ? `UWAGA: zaległych przypomnień jest ${pozycje.length}, zmieściło się ${n} (sufit ${SUFIT_STARTU} znaków) - pełna lista: node "${skrypt}" lista`
      : "";
    const calosc = (n) => [ostrzezenie(n), ...uwagi, glowa, ...pozycje.slice(0, n), stopka].filter(Boolean);
    let zmiesci = pozycje.length;
    while (zmiesci > 0 && calosc(zmiesci).join("\n").length > SUFIT_STARTU) zmiesci--;
    wyjscie.push(...calosc(zmiesci));
  } else {
    wyjscie.push(...uwagi);
  }
  if (wyjscie.length) process.stdout.write(wyjscie.join("\n") + "\n");
  return 0;
}

// ------------------------------------------------------------------ wejscie

function main(argv) {
  const polecenie = (argv[0] || "").toLowerCase();
  try {
    const a = argumenty(argv.slice(1));
    switch (polecenie) {
      case "dodaj": return dodaj(a.pozycyjne, a.opcje);
      case "lista": return lista(a.pozycyjne, a.opcje);
      case "zrobione": case "odhacz": return zrobione(a.pozycyjne, a.opcje);
      case "przesun": case "przesuń": return przesun(a.pozycyjne, a.opcje);
      case "w-toku": return wToku(a.pozycyjne, a.opcje);
      case "usun": case "usuń": return usun(a.pozycyjne, a.opcje);
      case "zalegle": return zalegle(a.pozycyjne, a.opcje);
      case "start": return start(a.pozycyjne, a.opcje);
      default:
        console.error("Uzycie: node terminy.js dodaj <kiedy> <projekt> \"<tresc>\" [\"<jak sprawdzic>\"] [--tylko-przypomnij] | " +
          "lista [--wszystkie] | zrobione <id> | przesun <id> <kiedy> | w-toku <id> | usun <id> | zalegle --json | start");
        return 2;
    }
  } catch (e) {
    if (polecenie === "start") {
      // Hook nie ma prawa zablokowac startu okna, ale tez nie milczy o awarii.
      process.stdout.write(`MegaRuchacz: przypomnienia z terminem nie dzialaja - ${e.message}\n`);
      return 0;
    }
    console.error(`Blad: ${e.message}`);
    return e instanceof BladWywolania ? 2 : 1;
  }
}

process.exitCode = main(process.argv.slice(2));
