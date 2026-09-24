// Przypomnienie doklejane do KAZDEJ wiadomosci uzytkownika (hook UserPromptSubmit) -
// stala tresc z pliku ladunku PLUS jedna linia o cyklu wiedzy, gdy ten akurat pracuje
// albo wlasnie skonczyl.
//
// Dlaczego skrypt, a nie samo "cat" pliku (tak bylo do 2026-09-17):
//   - hook chodzi przy KAZDYM enterze, wiec nie wolno mu nic liczyc; gotowa linie
//     stanu pisze sam cykl (narzedzia\cykl-dzienny.ps1) do pliku .cykl-postep,
//     a tutaj jest juz tylko odczyt jednego malego pliku i sklejenie JSON-a,
//   - zmiana POLECENIA hooka Codeksa uniewaznia zatwierdzenie z /hooks, wiec
//     polecenie ma wskazywac na ten skrypt raz na zawsze; kazda kolejna poprawka
//     dzieje sie w srodku, bez ruszania .codex\hooks.json.
//
// Uzycie (hook):
//   node narzedzia\przypomnienie.js <plik-ladunku.json> [plik-postepu]
// Drugi argument sluzy do testow; w hooku go nie ma i stan czytany jest
// z ~\.claude\wiedza\.cykl-postep.
//
// Od 2026-09-24 skrypt dokleja tez NA KONCU 1-2 fragmenty z archiwum rozmow (Lore),
// dobrane do tresci wiadomosci, ktora hook dostaje na wejsciu (JSON: prompt, session_id).
// Model sam po lore_search nie siega (~co trzecia sesja), wiec szuka za niego automat.
// Szukanie robi lore\lore\recall.py (samo FTS5, bez modelu wektorowego - uzasadnienie
// z pomiarami jest tam). To DODATEK: kazda jego awaria konczy sie tym, ze przypomnienie
// wychodzi jak dotad, a problem laduje w pliku stanu i - raz na jakis czas - w jednej
// linii na poczatku (patrz alarmArchiwum).
// Zmienne do testow: MR_ARCHIWUM_STAN (plik stanu), MR_LORE_PYTHON (python Lore),
// LORE_HOME (katalog bazy - czyta go sam recall.py).

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// Sufit ladunku (additionalContextLimit) ucina KONIEC tresci i nie mowi o tym ani
// slowa - dlatego linia o cyklu idzie na POCZATEK, tak samo jak alarmy w straznik-zasad.ps1.
// Jej dlugosc jest ograniczona, zeby stala tresc przypomnienia nie wyjechala ponad sufit:
// przypomnienia maja dzis ~620 znakow przy suficie 1500 (.codex\hooks.json), wiec
// 620 + 300 = 920 i zapas zostaje. Podnoszac ten limit, sprawdz tamten.
const MAX_STAN = 300;
// Stan "pracuje" starszy niz tyle godzin znaczy, ze proces cyklu padl i nikt juz
// tego pliku nie domknie. Lepiej milczec niz w kolko meldowac prace, ktorej nie ma.
const GODZIN_WAZNOSCI = 3;

// --- archiwum (Lore) ---
// Sufit calego ladunku: additionalContextLimit hooka przypomnienia w szablony-codex\hooks.json.
// Claude Code ma sufit wyzszy, ale skrypt nie wie, kto go wola, wiec liczy pod nizszy.
// Fragmenty ida na KONIEC - jesli cokolwiek ma pasc ofiara ucinania, niech to bedzie
// podpowiedz, nie zasady - ale i tak sa przycinane tak, zeby calosc zmiescila sie pod sufitem.
const SUFIT_LADUNKU = 1500;
// Twardy limit doklejanego archiwum: 450 znakow ~ 130-150 tokenow (polski z ogonkami to
// ~3 znaki na token). Tak nisko, bo doklejony tekst NIE jest placony raz: zostaje w historii
// rozmowy i model czyta go ponownie przy kazdym kolejnym wywolaniu (~10 na jedna wiadomosc
// uzytkownika, z bufora, po ~10% ceny). Fragment doklejony na N wiadomosci przed koncem sesji
// kosztuje wiec mniej wiecej tyle, co 150 x N tokenow czytanych po pelnej cenie - w sesji
// na 50 wiadomosci srednio ~3-4 tys. na jedno doklejenie. Dlatego tez: prog trafnosci
// w recall.py (lepiej nic niz smiec) i zakaz powtarzania fragmentu w tej samej rozmowie.
const MAX_ARCHIWUM = 450;
// Budzet calego hooka to < 1 s. Node startuje ~50 ms, python z zapytaniem 70-150 ms
// (zmierzone 2026-09-24), wiec 650 ms na pythona to kilkukrotny zapas, a nie oczekiwanie.
const CZAS_PYTHONA_MS = 650;
// Hook podaje JSON na wejsciu od razu i zamyka je; to tylko bezpiecznik na wypadek
// wejscia, ktore nigdy sie nie zamknie (wtedy zasady i tak musza wyjsc na czas).
const CZAS_WEJSCIA_MS = 150;
// Jak czesto powtarzac linie o tej samej awarii. Kazda awaria jest zapisana w pliku stanu
// zawsze; na poczatek ladunku trafia przy pierwszym wystapieniu, przy zmianie przyczyny
// i potem co 6 godzin - na tyle rzadko, zeby nie uczyc ignorowania ostrzezen (jedna linia
// przy kazdej wiadomosci to szum), i na tyle czesto, zeby nie zniknela w dniu pracy.
const GODZIN_MIEDZY_ALARMAMI = 6;
// Pamiec "co juz doklejono w tej rozmowie" - fragment raz doklejony siedzi w historii,
// drugi raz to czysty koszt. Trzymamy ostatnie rozmowy, starsze wypadaja.
const PAMIETANYCH_SESJI = 40;

function czytaj(sciezka) {
  try {
    return fs.readFileSync(sciezka, "utf8").replace(/^﻿/, "");
  } catch (e) {
    return null;
  }
}

// Pliki stanu narzedzia trzymaja proste "klucz: wartosc" - tak samo czytaja je
// skrypty PowerShella (Klucze-Z-Tekstu). Wartosc moze zawierac dwukropek,
// wiec dzielimy na PIERWSZYM.
function klucze(tekst) {
  const out = {};
  if (!tekst) return out;
  for (const linia of tekst.split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*:\s*(.*?)\s*$/.exec(linia);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

// Zwraca linie do doklejenia albo "" - i sprzata po sobie, gdy meldunek koncowy
// zostal juz pokazany. Meldunek o koszcie ma sie pokazac RAZ, a nie przy kazdej
// kolejnej wiadomosci do konca dnia.
function liniaCyklu(plik) {
  const stan = klucze(czytaj(plik));
  if (!stan.stan || !stan.linia) return "";

  const czas = Date.parse((stan.czas || "").replace(" ", "T"));
  const stary = !isNaN(czas) && (Date.now() - czas) / 3600000 > GODZIN_WAZNOSCI;
  if (stan.stan === "pracuje" && stary) {
    usun(plik);
    return "";
  }
  if (stan.stan !== "pracuje" && stan.stan !== "koniec") return "";

  // Meldunek koncowy znika razem z plikiem - to jedyne, co pilnuje "tylko raz".
  if (stan.stan === "koniec") usun(plik);

  let linia = stan.linia;
  if (linia.length > MAX_STAN) linia = linia.slice(0, MAX_STAN - 3) + "...";
  return linia;
}

function usun(plik) {
  try { fs.unlinkSync(plik); } catch (e) { /* cudza rece albo brak pliku - nic tu nie ratujemy */ }
}

// ---------------------------------------------------------------- archiwum (Lore)

// Wejscie hooka (JSON z trescia wiadomosci). Czytane asynchronicznie z bezpiecznikiem
// czasu: readFileSync(0) na wejsciu, ktore sie nie zamyka, zawiesiloby caly hook,
// a razem z nim przypomnienie zasad. null = nic nie przyszlo; "tty" = reczne uruchomienie.
function czytajWejscie(ms) {
  return new Promise((gotowe) => {
    if (process.stdin.isTTY) return gotowe("tty");
    let dane = "";
    let koniec = false;
    const skoncz = (wynik) => {
      if (koniec) return;
      koniec = true;
      clearTimeout(zegar);
      try { process.stdin.destroy(); } catch (e) { /* i tak wychodzimy przez process.exit */ }
      gotowe(wynik);
    };
    const zegar = setTimeout(() => skoncz(dane || null), ms);
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (k) => { dane += k; });
    process.stdin.on("end", () => skoncz(dane || null));
    process.stdin.on("error", () => skoncz(dane || null));
  });
}

function pythonLore() {
  if (process.env.MR_LORE_PYTHON) return process.env.MR_LORE_PYTHON;
  const venv = path.join(__dirname, "..", "lore", ".venv");
  return process.platform === "win32"
    ? path.join(venv, "Scripts", "python.exe")
    : path.join(venv, "bin", "python");
}

// Czy Lore w ogole jest na tej maszynie - ta sama kolejnosc co db._data_home w Pythonie.
// Brak i srodowiska, i bazy to "nie zainstalowane", nie awaria: meldowanie tego co kilka
// godzin na maszynie bez Lore byloby falszywym alarmem.
function jestBazaLore() {
  const dom = process.env.LORE_HOME || process.env.CLAUDE_HISTORIA_HOME;
  const kandydaci = dom ? [dom] : [path.join(os.homedir(), ".claude"), path.join(os.homedir(), ".lore")];
  return kandydaci.some((k) => fs.existsSync(path.join(k, "lore.db")));
}

function czytajStan(plik) {
  const t = czytaj(plik);
  if (!t) return {};
  try {
    const s = JSON.parse(t);
    return s && typeof s === "object" ? s : {};
  } catch (e) {
    // Zepsuty plik stanu nie moze zablokowac podpowiedzi - zaczynamy od zera,
    // a slad zostaje w nowym stanie.
    return { zepsuty_stan: String(e.message).slice(0, 120) };
  }
}

// Sama podpowiedz. Zwraca { blok, alarm } i ZAWSZE zapisuje stan ("bylem tu" + wynik),
// takze wtedy, gdy nic nie doklejono - brak wpisu nie moze znaczyc "wszystko gra".
function archiwum(wejscie, budzet, plikStanu) {
  const start = Date.now();
  const stan = czytajStan(plikStanu);
  const sesje = stan.sesje && typeof stan.sesje === "object" ? stan.sesje : {};
  let wynik = { blok: "", alarm: "", status: "", powod: "", awaria: false };

  const awaria = (powod) => { wynik = { blok: "", alarm: "", status: "awaria", powod, awaria: true }; };
  let prosba = null;
  if (wejscie === "tty") {
    wynik.status = "pominiete";
    wynik.powod = "reczne uruchomienie - brak wiadomosci na wejsciu";
  } else if (!wejscie) {
    awaria("hook nie podal tresci wiadomosci na wejsciu");
  } else {
    try { prosba = JSON.parse(wejscie); } catch (e) { prosba = null; }
    const tresc = prosba && (prosba.prompt || prosba.user_prompt);
    if (typeof tresc !== "string") {
      awaria("wejscie hooka bez pola prompt");
      prosba = null;
    } else {
      prosba = { prompt: tresc, sesja: prosba.session_id || prosba.sessionId || null };
    }
  }

  if (prosba) {
    const py = pythonLore();
    if (!fs.existsSync(py) && !jestBazaLore()) {
      wynik.status = "brak-lore";
      wynik.powod = "Lore nie jest zainstalowane na tej maszynie";
    } else if (!fs.existsSync(py)) {
      awaria("brak srodowiska Lore (" + py + ") - uruchom narzedzia\\instaluj-lore.ps1");
    } else {
      const juz = (sesje[prosba.sesja] && Array.isArray(sesje[prosba.sesja].ids)) ? sesje[prosba.sesja].ids : [];
      const r = spawnSync(py, ["-m", "lore.recall"], {
        cwd: path.join(__dirname, "..", "lore"),
        input: JSON.stringify({ prompt: prosba.prompt, session: prosba.sesja, budget: budzet, exclude: juz }),
        encoding: "utf8",
        timeout: CZAS_PYTHONA_MS,
        windowsHide: true,
        env: Object.assign({}, process.env, { PYTHONIOENCODING: "utf-8", PYTHONUTF8: "1" }),
      });
      let odp = null;
      if (r.error && r.error.code === "ETIMEDOUT") {
        awaria("Lore nie odpowiedzialo w " + CZAS_PYTHONA_MS + " ms");
      } else if (r.error) {
        awaria("nie da sie uruchomic Lore: " + r.error.message);
      } else {
        try { odp = JSON.parse((r.stdout || "").trim().split(/\r?\n/).pop()); } catch (e) { odp = null; }
        if (!odp) {
          const blad = (r.stderr || "").trim().split(/\r?\n/).pop() || ("kod wyjscia " + r.status);
          awaria("Lore zwrocilo smieci: " + blad);
        } else if (odp.status === "error") {
          awaria(String(odp.reason || "nieznany blad"));
        } else {
          wynik.status = odp.status;
          wynik.powod = String(odp.reason || "");
          wynik.python_ms = odp.ms;
          const blok = typeof odp.block === "string" ? odp.block : "";
          // Druga linia obrony: recall.py liczy sie z budzetem sam, ale sufit ma tu
          // krzyczec, a nie ucinac - blok za dlugi po prostu nie idzie, a stan to mowi.
          if (blok.length > budzet) {
            wynik.status = "za-dlugi";
            wynik.powod = "blok " + blok.length + " znakow przy budzecie " + budzet + " - odrzucony";
          } else if (blok) {
            wynik.blok = blok;
            const ids = Array.isArray(odp.ids) ? odp.ids : [];
            if (prosba.sesja) {
              sesje[prosba.sesja] = { czas: new Date().toISOString(), ids: juz.concat(ids).slice(-100) };
            }
          }
        }
      }
    }
  }

  // Alarm: zawsze w stanie, w ladunku - przy nowej przyczynie albo co GODZIN_MIEDZY_ALARMAMI.
  const teraz = new Date();
  if (wynik.awaria) {
    const byla = stan.awaria && stan.awaria.powod === wynik.powod ? stan.awaria : null;
    stan.awaria = { powod: wynik.powod, od: byla ? byla.od : teraz.toISOString(), ile: (byla ? byla.ile : 0) + 1 };
    const ostatni = stan.alarm && Date.parse(stan.alarm.czas);
    const swiezy = stan.alarm && stan.alarm.powod === wynik.powod && !isNaN(ostatni) &&
      (teraz - ostatni) / 3600000 < GODZIN_MIEDZY_ALARMAMI;
    if (!swiezy) {
      stan.alarm = { powod: wynik.powod, czas: teraz.toISOString() };
      let l = "UWAGA: podpowiedz z archiwum (Lore) nie dziala - " + wynik.powod +
        ". Zasady ponizej sa kompletne. Szczegoly: " + plikStanu.replace(os.homedir(), "~");
      if (l.length > MAX_STAN) l = l.slice(0, MAX_STAN - 3) + "...";
      wynik.alarm = l;
    }
  } else {
    delete stan.awaria;
    delete stan.alarm;
  }

  // Najstarsze rozmowy wypadaja z pamieci powtorek.
  const klucze = Object.keys(sesje).sort((a, b) => String(sesje[b].czas).localeCompare(String(sesje[a].czas)));
  for (const k of klucze.slice(PAMIETANYCH_SESJI)) delete sesje[k];

  stan.czas = teraz.toISOString();
  stan.wynik = wynik.status;
  stan.powod = wynik.powod;
  stan.ms = Date.now() - start;
  if (wynik.python_ms !== undefined) stan.python_ms = wynik.python_ms; else delete stan.python_ms;
  stan.doklejono_znakow = wynik.blok.length;
  stan.sesje = sesje;
  try {
    fs.mkdirSync(path.dirname(plikStanu), { recursive: true });
    fs.writeFileSync(plikStanu, JSON.stringify(stan, null, 1), "utf8");
  } catch (e) {
    // Nie da sie zapisac stanu - jedyne, co zostaje, to stderr hooka. Podpowiedz nie
    // przepada, ale bez stanu nie bedzie pamieci powtorek ani licznika awarii.
    process.stderr.write("przypomnienie.js: nie zapisalem stanu archiwum: " + e.message + "\n");
  }
  return wynik;
}

// ---------------------------------------------------------------- calosc

function wypisz(tekst) {
  // Wyjscie przez process.exit dopiero po oproznieniu stdout: wejscie uciete bezpiecznikiem
  // moglo zostac otwarte i trzymaloby proces przy zyciu.
  process.stdout.write(tekst, () => process.exit(0));
}

async function glowna() {
  const plikLadunku = process.argv[2];
  const plikPostepu = process.argv[3] ||
    path.join(os.homedir(), ".claude", "wiedza", ".cykl-postep");
  const plikStanu = process.env.MR_ARCHIWUM_STAN ||
    path.join(os.homedir(), ".claude", "wiedza", ".archiwum-stan.json");

  const surowy = plikLadunku ? czytaj(plikLadunku) : null;
  if (!surowy) {
    // Brak ladunku to nie jest powod, zeby wywrocic wiadomosc uzytkownika -
    // po prostu nie ma czego doklejac.
    process.exit(0);
  }

  let ladunek = null;
  try { ladunek = JSON.parse(surowy); } catch (e) { ladunek = null; }
  if (!ladunek || !ladunek.hookSpecificOutput ||
      typeof ladunek.hookSpecificOutput.additionalContext !== "string") {
    // Plik jest, ale nie ma w nim ladunku, ktory umiemy uzupelnic - oddajemy go
    // slowo w slowo, dokladnie tak, jak robilo to wczesniejsze "cat".
    wypisz(surowy);
    return;
  }

  const kontekst = ladunek.hookSpecificOutput;
  let linia = "";
  try { linia = liniaCyklu(plikPostepu); } catch (e) { linia = ""; }
  if (linia) kontekst.additionalContext = linia + "\n" + kontekst.additionalContext;

  // Podpowiedz z archiwum. Cokolwiek tu padnie, przypomnienie wychodzi nizej bez zmian.
  const zasady = kontekst.additionalContext;
  try {
    const wejscie = await czytajWejscie(CZAS_WEJSCIA_MS);
    const budzet = Math.min(MAX_ARCHIWUM, SUFIT_LADUNKU - zasady.length - 2);
    const w = archiwum(wejscie, budzet, plikStanu);
    let calosc = zasady;
    if (w.alarm) calosc = w.alarm + "\n" + calosc;
    if (w.blok) calosc = calosc + "\n\n" + w.blok;
    kontekst.additionalContext = calosc;
  } catch (e) {
    kontekst.additionalContext = zasady;
    process.stderr.write("przypomnienie.js: podpowiedz z archiwum padla: " + (e && e.stack || e) + "\n");
  }
  wypisz(JSON.stringify(ladunek));
}

glowna().catch((e) => {
  // Ostatnia deska: blad poza podpowiedzia (nie powinien sie zdarzyc). Oddajemy ladunek
  // tak, jak lezy na dysku - dokladnie to, co robilo "cat" - i zostawiamy slad na stderr.
  process.stderr.write("przypomnienie.js: " + (e && e.stack || e) + "\n");
  const surowy = process.argv[2] ? czytaj(process.argv[2]) : null;
  if (surowy) wypisz(surowy); else process.exit(0);
});
