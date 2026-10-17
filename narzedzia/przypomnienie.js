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
//
// Od 2026-09-30 (P26): gdy "wiadomosc" to powiadomienie o koncu workera (<task-notification>),
// skrypt nie dokleja NIC - ani zasad, ani archiwum, ani linii o cyklu (P22: 19 z 76 doklejek
// w rozmowie kierownika szlo do powiadomien, czyli do nikogo). Slad pominietych powiadomien:
// ~\.claude\wiedza\.powiadomienia-stan.json (do testow: MR_POWIADOMIENIA_STAN).
// Ostrzezenie o dlugiej rozmowie (tez P26) usuniete 2026-10-01 (P43) decyzja uzytkownika:
// linia przychodzila dopiero po wyslaniu wiadomosci, kiedy koszt juz poszedl.
//
// Od P59a (instalator z wyborem modulow) kazda czesc idzie tylko przy swoim module z rejestru
// instalacji ~\.claude\mr\instalacja.json (umowa: narzedzia\instalacja\stan.ps1): ladunek
// z pliku - kierownik, linia o cyklu - wiedza, "Z ARCHIWUM" - lore. Brak rejestru = jak dotad
// (wszystko); rejestr nieczytelny = jak dotad plus jedna linia alarmu na poczatku (w rytmie
// alarmu archiwum). Bez ladunku kierownika linia cyklu i archiwum ida dalej - do P59a brak pliku
// ladunku konczyl skrypt na wejsciu i zabieral je ze soba. Gdy nie ma nic do doklejenia, skrypt
// nie wypisuje nic. Zmienne do testow: MR_INSTALACJA (plik rejestru), MR_INSTALACJA_ALARM (stan
// alarmu o nieczytelnym rejestrze).
//
// Od 2026-10-16 za archiwum idzie tez "Z WIEDZY FIRMY" - wpisy ze wspolnej wiedzy firmy (serwer
// jfwiedza), przy module wiedzafirmy. Szczegoly i uzasadnienia progow: sekcja "wiedza firmy" nizej.

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

// ---------------------------------------------------------------- wiedza firmy (jfwiedza)

// Od 2026-10-16 obok archiwum idzie tez podpowiedz ze wspolnej wiedzy firmy (serwer MCP jfwiedza,
// kod w wiedza_firmy\ tego repo): to samo szukaj_wiedzy, ktore Claude ma jako narzedzie, ale wolane
// przez automat - jak przy Lore, model sam po nie nie siega. Na serwerze to FTS5 + lokalny model
// wektorow (mmlw przez fastembed/ONNX, wiedza_firmy\wiedza_firmy\wektory.py) - zadnego platnego API.
// Jedno zadanie HTTP (serwer jest bezstanowy: tools/call bez initialize) z tymi samymi naglowkami,
// ktorych uzywa klient MCP Claude Code (~\.claude.json, mcpServers.jfwiedza) - token nie lezy ani
// w repo, ani w pliku stanu, ani w zadnym komunikacie.
// Rownolegle z Lore: zadanie najpierw wychodzi, potem Lore (spawnSync blokuje petle, ale odpowiedz
// serwera czeka w buforze gniazda), na koncu odbior - czasy sie nie sumuja.
// Wlaczone tylko przy wiedzafirmy === true w rejestrze instalacji (trzeci stan, stan.ps1: brak
// klucza = nie zaproponowano; rejestr nieczytelny = jak przed ta zmiana, czyli bez) i przy wpisie
// jfwiedza w konfiguracji. Bez wpisu - cisza i "brak-konfiguracji" w stanie: komputer bez wiedzy
// firmy to nie awaria.
// Zmienne do testow: MR_JFWIEDZA_KONFIG (plik w ukladzie ~\.claude.json), MR_JFWIEDZA_STAN.

const NAGLOWEK_WIEDZY = "Z WIEDZY FIRMY (jfwiedza, automat) - trop, nie dowod; moze byc nieaktualne. Calosc: szukaj_wiedzy.";
const SERWER_WIEDZY = "jfwiedza";
// Ten sam sufit i to samo uzasadnienie kosztu co MAX_ARCHIWUM (doklejka zostaje w historii rozmowy).
const MAX_WIEDZY = 450;
const POZYCJI_WIEDZY = 3;
// Pozycja z mniej niz tyloma znakami tresci to urwane zdanie bez sensu - wtedy mniej pozycji.
const MIN_TRESCI = 100;
// Limit od wyslania do odpowiedzi - jak CZAS_PYTHONA_MS. Zmierzone 2026-10-16 w sieci biura:
// 155-180 ms przy cieplym serwerze.
const CZAS_WIEDZY_MS = 650;
// Ile najwyzej czekac na wyslanie zadania, zanim ruszy Lore (polaczenie w LAN to kilka ms; host
// nieosiagalny nie moze wstrzymywac Lore).
const CZAS_WYSLANIA_MS = 100;
// Awaria sieci (limit czasu, odmowa polaczenia, HTTP 5xx) krzyczy dopiero za trzecim razem z rzedu.
// Pojedyncza jest spodziewana: serwer co 10 min odswieza w trakcie zadania liste tematow z JFTools
// (do 3 s - jftools.LIMIT_ZAPYTANIA_S; pierwsze zapytanie 2026-10-16 trwalo 4265 ms) i co godzine sam
// sie restartuje po aktualizacji. Trzech wiadomosci z rzedu to nie tlumaczy - odswiezenie konczy sie
// po stronie serwera, nawet gdy my juz nie czekamy. Bledy pewne (401 - zly token, smieci w odpowiedzi,
// zla konfiguracja) krzycza od razu.
const PROG_AWARII_SIECI = 3;
// Po progu nie pytamy przy kazdej wiadomosci, tylko co tyle minut: serwer poza zasiegiem (laptop
// poza biurem) kosztowalby inaczej do CZAS_WIEDZY_MS na kazdy enter.
const MINUT_PRZERWY_PO_AWARII = 5;
// Pytanie do serwera: poczatek wiadomosci wystarczy (to wyszukiwanie, nie rozmowa).
const MAX_PYTANIA = 400;

// Konfiguracja klienta MCP: { brak } = nie ma czego pytac (cisza), { blad } = jest, ale zepsuta (alarm).
function konfiguracjaWiedzy(plik) {
  let t;
  try { t = fs.readFileSync(plik, "utf8").replace(/^﻿/, ""); }
  catch (e) {
    if (e && e.code === "ENOENT") return { brak: "brak pliku " + plik.replace(os.homedir(), "~") };
    return { blad: "nie umiem odczytac " + plik.replace(os.homedir(), "~") + ": " + (e && e.message || e) };
  }
  let j;
  try { j = JSON.parse(t); } catch (e) { return { blad: plik.replace(os.homedir(), "~") + " nieczytelny: " + e.message }; }
  const s = j && j.mcpServers && j.mcpServers[SERWER_WIEDZY];
  if (!s) return { brak: "brak serwera " + SERWER_WIEDZY + " w " + plik.replace(os.homedir(), "~") };
  if (typeof s.url !== "string" || !s.url) return { blad: "wpis " + SERWER_WIEDZY + " bez adresu url" };
  const naglowki = {};
  if (s.headers && typeof s.headers === "object") {
    for (const k of Object.keys(s.headers)) if (typeof s.headers[k] === "string") naglowki[k] = s.headers[k];
  }
  return { url: s.url, naglowki };
}

// Kiedy w ogole nie pytac: za krotka wiadomosc ("b", "nook", "tak zrob tak") daje na serwerze same
// smieci tuz nad progiem trafnosci (wektory.py: jednowyrazowe 0,74-0,75) - i przypadkowy wpis w rozmowie.
// Regula jest PRZENIESIONA z lore\lore\recall.py (MIN_PROMPT_CHARS, MIN_MATCHED, STOP, fold, _terms),
// zeby archiwum i wiedza firmy pomijaly te same wiadomosci. Ma byc z nia ZGODNA co do znaku - pilnuje
// tego test_wiedza_firmy_hook.py (te same slowa pospolite, te same stale, te same slowa z przykladow);
// zmieniajac jedno, zmien drugie. Tylko czesc bez bazy: recall.py odsiewa potem jeszcze slowa, ktorych
// archiwum nie zna albo ma ich za duzo - tego serwer wiedzy firmy nie potrzebuje.
const MIN_ZNAKOW_PYTANIA = 12;   // recall.MIN_PROMPT_CHARS
const MIN_SLOW_PYTANIA = 2;      // recall.MIN_MATCHED
const SLOWA_POSPOLITE = new Set(`
ale albo ani aby bardzo bez bo byc byl byla bylo byly bedzie beda bez chce chcesz ci cie co czy
czyli dla do dobrze gdy gdzie go ich ile im iz ja jak jaki jakie jako je jego jej jest jestem jesli
juz ktora ktore ktory kto lub ma mam mamy masz mi mnie moge moze mozna my na nad nam nas nic nie niech
nim no o od oraz po pod potem przez przy sa sie sobie tak tam tego tej ten teraz to tu tutaj tych tylko
ty wiec wszystko wtedy z za ze zeby zrob zrobic prosze dzieki okej ok the and for with that this from
are was were you your have has not but can will what how why when which into then than also just
sprawdz dlaczego czemu dodaj napisz ustaw dziala mowi powiedz pokaz zobacz trzeba musi mozesz dalej
jeszcze nowy nowa nowe wszystkie kazdy kazda kazde zamiast chodzi robi jakis sprawa rzecz
`.split(/\s+/).filter(Boolean));   // recall.STOP

// recall.fold: male litery bez ogonkow, znak po znaku (dlugosc w znakach sie nie zmienia).
function zlozTekst(tekst) {
  let out = "";
  for (const ch of String(tekst).toLowerCase()) {
    if (ch === "ł") { out += "l"; continue; }   // l z kreska nie rozklada sie w NFKD
    const d = Array.from(ch.normalize("NFKD"));
    out += d.length ? d[0] : ch;
  }
  return out;
}

// recall._terms: slowa warte szukania (dluzsze jako rdzen z "*", jak w FTS).
function slowaDoSzukania(tekst) {
  const out = [];
  const bylo = new Set();
  for (const w of zlozTekst(tekst).match(/[\p{L}\p{N}_]+/gu) || []) {
    const z = Array.from(w);
    let term;
    if (/^\p{Nd}+$/u.test(w)) {
      if (z.length < 2) continue;
      term = w;
    } else {
      if (z.length < 3 || SLOWA_POSPOLITE.has(w) || w.indexOf("_") >= 0) continue;
      if (z.length >= 7) term = z.slice(0, -2).join("") + "*";
      else if (z.length >= 5) term = ("aeiouy".indexOf(z[z.length - 1]) >= 0 ? z.slice(0, -1).join("") : w) + "*";
      else term = w;
    }
    if (!bylo.has(term)) { bylo.add(term); out.push(term); }
  }
  return out;
}

// Powod pominiecia (te same slowa co recall.py) albo "" - wtedy pytamy.
function pominiecieWiedzy(tresc) {
  if (Array.from(String(tresc).trim()).length < MIN_ZNAKOW_PYTANIA) return "krotka wiadomosc";
  if (slowaDoSzukania(tresc).length < MIN_SLOW_PYTANIA) return "za malo slow do szukania";
  return "";
}

// Pytanie do serwera: poczatek wiadomosci (to wyszukiwanie, nie rozmowa).
function pytanieWiedzy(tresc) {
  return String(tresc).replace(/\s+/g, " ").trim().slice(0, MAX_PYTANIA);
}

function opisBleduSieci(e) {
  const kod = e && e.code ? e.code : "";
  if (kod === "ECONNREFUSED") return "serwer odmowil polaczenia (" + kod + ")";
  if (kod === "EHOSTUNREACH" || kod === "ENETUNREACH" || kod === "ENOTFOUND" || kod === "EAI_AGAIN") return "serwer poza zasiegiem (" + kod + ")";
  return "blad sieci: " + (kod ? kod + " " : "") + String(e && e.message || e).slice(0, 120);
}

// Wysyla zadanie i od razu wraca. wynik: { http, cialo } albo { siec: true, blad }.
function wyslijPytanie(konf, pytanie, limit) {
  let u;
  try { u = new URL(konf.url); } catch (e) { return { blad: "zly adres serwera " + SERWER_WIEDZY + ": " + konf.url }; }
  const modul = u.protocol === "https:" ? require("https") : (u.protocol === "http:" ? require("http") : null);
  if (!modul) return { blad: "nieobslugiwany adres serwera " + SERWER_WIEDZY + ": " + konf.url };
  const cialo = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call",
    params: { name: "szukaj_wiedzy", arguments: { pytanie, limit } } });
  const naglowki = Object.assign({}, konf.naglowki, { "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream", "Content-Length": Buffer.byteLength(cialo) });
  const h = { req: null, wynik: null, wyslane: null };
  h.wynik = new Promise((gotowe) => {
    h.req = modul.request(u, { method: "POST", headers: naglowki, agent: false }, (odp) => {
      let dane = "";
      odp.setEncoding("utf8");
      odp.on("data", (k) => { dane += k; });
      odp.on("end", () => gotowe({ http: odp.statusCode, cialo: dane }));
      odp.on("error", (e) => gotowe({ siec: true, blad: "przerwana odpowiedz: " + e.message }));
    });
    h.req.on("error", (e) => gotowe({ siec: true, blad: opisBleduSieci(e) }));
  });
  h.wyslane = new Promise((gotowe) => { h.req.on("finish", gotowe); });
  h.req.end(cialo);
  return h;
}

// Odpowiedz serwera -> { dane } albo { blad, siec }. Odpowiedz bywa JSON-em albo SSE (data: ...).
function rozbierzOdpowiedz(w) {
  if (w.siec) return { blad: w.blad, siec: true };
  if (w.http === 401 || w.http === 403) {
    return { blad: "serwer odrzucil token (HTTP " + w.http + ") - zly albo wycofany token jfwiedza w ~\\.claude.json" };
  }
  if (w.http >= 500) return { blad: "serwer zwrocil HTTP " + w.http, siec: true };
  if (w.http !== 200) return { blad: "serwer zwrocil HTTP " + w.http };
  let tekst = String(w.cialo || "").trim();
  if (/^(event|data|id):/m.test(tekst) && !tekst.startsWith("{")) {
    const linie = tekst.split(/\r?\n/).filter((l) => l.startsWith("data:"));
    tekst = linie.length ? linie[linie.length - 1].slice(5).trim() : "";
  }
  let j;
  try { j = JSON.parse(tekst); } catch (e) { return { blad: "odpowiedz to nie JSON: " + tekst.slice(0, 80) }; }
  if (j && j.error) return { blad: "blad serwera: " + String(j.error.message || JSON.stringify(j.error)).slice(0, 150) };
  const r = j && j.result;
  const pierwszy = r && Array.isArray(r.content) && r.content[0] && typeof r.content[0].text === "string" ? r.content[0].text : null;
  if (r && r.isError) return { blad: "szukaj_wiedzy zwrocilo blad: " + String(pierwszy || "").slice(0, 150) };
  let dane = null;
  if (pierwszy !== null) { try { dane = JSON.parse(pierwszy); } catch (e) { dane = null; } }
  if (!dane && r && r.structuredContent && typeof r.structuredContent === "object") dane = r.structuredContent;
  if (!dane || !Array.isArray(dane.wyniki)) return { blad: "odpowiedz szukaj_wiedzy bez listy wynikow" };
  return { dane };
}

// Linia wpisu najwyzej `max` znakow albo null, gdy na tresc zostaloby mniej niz MIN_TRESCI.
function pozycjaWiedzy(w, max) {
  const glowa = "- [" + (w.autor || "?") + ", " + (w.data || "?") + ", #" + w.id + "] ";
  let t = String(w.tresc).replace(/\s+/g, " ").trim();
  const miejsce = max - glowa.length;
  if (t.length > miejsce) {
    if (miejsce - 3 < MIN_TRESCI) return null;
    t = t.slice(0, miejsce - 3);
    const spacja = t.lastIndexOf(" ");
    if (spacja > MIN_TRESCI) t = t.slice(0, spacja);
    t = t.replace(/[\s,;:.\-]+$/, "") + "...";
  }
  return glowa + t;
}

// Blok do doklejenia: najwyzej POZYCJI_WIEDZY wpisow jeszcze niedoklejonych w tej rozmowie. Krotkie
// wpisy ida w calosci, dlugie dziela reszte miejsca po rowno; za malo miejsca na sensowna tresc =
// o jeden wpis mniej. Blok nigdy nie przekracza budzetu - przyciete sa tresci wpisow (z "..."), nie blok.
function blokWiedzy(wyniki, budzet, juz) {
  const nowe = wyniki.filter((w) => w && typeof w.tresc === "string" && w.id !== undefined && juz.indexOf(w.id) < 0);
  for (let k = Math.min(POZYCJI_WIEDZY, nowe.length); k >= 1; k--) {
    const wybrane = nowe.slice(0, k);
    let zostalo = budzet - NAGLOWEK_WIEDZY.length - k;   // k znakow nowej linii
    const linie = new Array(k);
    const kolejnosc = wybrane.map((w, i) => i)
      .sort((a, b) => String(wybrane[a].tresc).length - String(wybrane[b].tresc).length);
    let ok = true;
    kolejnosc.forEach((i, n) => {
      if (!ok) return;
      const l = pozycjaWiedzy(wybrane[i], Math.floor(zostalo / (k - n)));
      if (l === null) { ok = false; return; }
      linie[i] = l;
      zostalo -= l.length;
    });
    if (ok) return { blok: [NAGLOWEK_WIEDZY].concat(linie).join("\n"), ids: wybrane.map((w) => w.id) };
  }
  return { blok: "", ids: [] };
}

// Krok 1 (przed Lore): decyzja, czy pytac, i wyslanie. Nic tu nie czeka na odpowiedz.
function zacznijWiedze(tresc, sesja, plikKonfigu, plikStanu) {
  const u = { start: Date.now(), plikStanu, sesja, stan: czytajStan(plikStanu), h: null, gotowy: null };
  u.sesje = u.stan.sesje && typeof u.stan.sesje === "object" ? u.stan.sesje : {};
  u.juz = (sesja && u.sesje[sesja] && Array.isArray(u.sesje[sesja].ids)) ? u.sesje[sesja].ids : [];
  const aw = u.stan.awaria;
  const konf = typeof tresc === "string" ? konfiguracjaWiedzy(plikKonfigu) : null;
  const pomin = typeof tresc === "string" ? pominiecieWiedzy(tresc) : "";
  if (!konf) {
    // brak tresci wiadomosci melduje juz archiwum (alarm Lore) - tu tylko slad
    u.gotowy = { status: "pominiete", powod: "brak tresci wiadomosci na wejsciu" };
  } else if (konf.brak) {
    u.gotowy = { status: "brak-konfiguracji", powod: konf.brak };
  } else if (konf.blad) {
    u.gotowy = { awaria: true, siec: false, powod: konf.blad };
  } else if (pomin) {
    // bez zapytania i bez linii - tylko slad w stanie (ta sama regula co w recall.py)
    u.gotowy = { status: "pominieto-krotka", powod: pomin };
  } else if (aw && aw.siec && aw.ile >= PROG_AWARII_SIECI && !isNaN(Date.parse(aw.proba)) &&
             (u.start - Date.parse(aw.proba)) / 60000 < MINUT_PRZERWY_PO_AWARII) {
    u.gotowy = { status: "przerwa", powod: "po " + aw.ile + " awariach sieci z rzedu pytam co " + MINUT_PRZERWY_PO_AWARII + " min", przerwa: true };
  } else {
    const h = wyslijPytanie(konf, pytanieWiedzy(tresc), Math.min(10, POZYCJI_WIEDZY + u.juz.length));
    if (h.blad) u.gotowy = { awaria: true, siec: false, powod: h.blad };
    else u.h = h;
  }
  return u;
}

// Czeka, az zadanie wyjdzie do gniazda (najwyzej CZAS_WYSLANIA_MS) - dopiero potem moze ruszyc Lore.
function wyslanaWiedza(u) {
  if (!u.h) return Promise.resolve();
  let zegar;
  return Promise.race([u.h.wyslane, u.h.wynik, new Promise((g) => { zegar = setTimeout(g, CZAS_WYSLANIA_MS); })])
    .then(() => clearTimeout(zegar));
}

// Krok 2 (po Lore): odbior, blok, alarm i stan. dlugoscReszty = ile znakow ma juz ladunek bez nas.
// Zwraca { blok, alarm }; stan zapisuje ZAWSZE (takze przy braku konfiguracji - "bylem tu").
async function skonczWiedze(u, dlugoscReszty) {
  let w = u.gotowy;
  if (!w) {
    // Najmniej 5 ms: po dlugim Lore termin minal, a odpowiedz moze juz czekac w buforze gniazda -
    // zegar ustawiony na 0 odpalilby sie przed jej odczytem.
    const zostalo = Math.max(u.start + CZAS_WIEDZY_MS - Date.now(), 5);
    let zegar;
    const odp = await Promise.race([u.h.wynik, new Promise((g) => {
      zegar = setTimeout(() => g({ siec: true, blad: "jfwiedza nie odpowiedziala w " + CZAS_WIEDZY_MS + " ms" }), zostalo);
    })]);
    clearTimeout(zegar);
    u.h.req.destroy();
    const r = rozbierzOdpowiedz(odp);
    if (r.blad) {
      w = { awaria: true, siec: !!r.siec, powod: r.blad };
    } else {
      const d = r.dane;
      w = { status: d.wyniki.length ? "trafienia" : "brak-trafien",
            powod: d.wyniki.length ? "" : String(d.komunikat || ""), wyniki: d.wyniki,
            uwagi: Array.isArray(d.uwagi) ? d.uwagi.map((x) => String(x).slice(0, 200)) : null };
    }
  }

  const stan = u.stan;
  const teraz = new Date();
  let alarm = "";
  if (w.awaria) {
    const ile = (stan.awaria ? Number(stan.awaria.ile) || 0 : 0) + 1;
    const ta_sama = stan.awaria && stan.awaria.powod === w.powod;
    stan.awaria = { powod: w.powod, siec: w.siec, od: ta_sama ? stan.awaria.od : teraz.toISOString(),
                    ile, proba: teraz.toISOString() };
    // Awarie sieci liczymy jako jeden rodzaj: limit czasu i odmowa polaczenia na zmiane to wciaz ta sama awaria.
    const rodzaj = w.siec ? "siec" : w.powod;
    const ostatni = stan.alarm && Date.parse(stan.alarm.czas);
    const swiezy = stan.alarm && stan.alarm.rodzaj === rodzaj && !isNaN(ostatni) &&
      (teraz - ostatni) / 3600000 < GODZIN_MIEDZY_ALARMAMI;
    if ((!w.siec || ile >= PROG_AWARII_SIECI) && !swiezy) {
      stan.alarm = { rodzaj, powod: w.powod, czas: teraz.toISOString() };
      alarm = "UWAGA: podpowiedz z wiedzy firmy (jfwiedza) nie dziala - " + w.powod +
        (w.siec ? " (" + ile + " razy z rzedu)" : "") + ". Szczegoly: " + u.plikStanu.replace(os.homedir(), "~");
      if (alarm.length > MAX_STAN) alarm = alarm.slice(0, MAX_STAN - 3) + "...";
    }
  } else if (!w.przerwa) {
    delete stan.awaria;
    delete stan.alarm;
  }

  let blok = "";
  let status = w.awaria ? "awaria" : w.status;
  let powod = w.powod;
  if (w.wyniki && w.wyniki.length) {
    const budzet = Math.min(MAX_WIEDZY, SUFIT_LADUNKU - dlugoscReszty - (alarm ? alarm.length + 1 : 0) - 2);
    const b = blokWiedzy(w.wyniki, budzet, u.juz);
    if (b.blok.length > budzet) {
      // nie powinno sie zdarzyc (blokWiedzy liczy sie z budzetem) - ale sufit krzyczy, nie ucina
      status = "za-dlugi";
      powod = "blok " + b.blok.length + " znakow przy budzecie " + budzet + " - odrzucony";
    } else if (b.blok) {
      blok = b.blok;
      if (u.sesja) u.sesje[u.sesja] = { czas: teraz.toISOString(), ids: u.juz.concat(b.ids).slice(-100) };
    } else if (w.wyniki.some((x) => x && u.juz.indexOf(x.id) < 0)) {
      status = "brak-miejsca";
      powod = "trafienia sa, ale budzet " + budzet + " znakow nie miesci zadnej pozycji";
    } else {
      status = "juz-doklejone";
      powod = "wszystkie trafienia sa juz w tej rozmowie";
    }
  }

  const klucze = Object.keys(u.sesje).sort((a, b) => String(u.sesje[b].czas).localeCompare(String(u.sesje[a].czas)));
  for (const k of klucze.slice(PAMIETANYCH_SESJI)) delete u.sesje[k];
  stan.czas = teraz.toISOString();
  stan.wynik = status;
  stan.powod = powod;
  stan.ms = Date.now() - u.start;
  if (w.uwagi && w.uwagi.length) stan.uwagi_serwera = w.uwagi; else delete stan.uwagi_serwera;
  stan.doklejono_znakow = blok.length;
  stan.sesje = u.sesje;
  zapiszStan(u.plikStanu, stan);
  return { blok, alarm };
}

// ---------------------------------------------------------------- powiadomienia (P26)

// Powiadomienie o koncu workera (albo innego zadania w tle) to nie wiadomosc uzytkownika.
// Sprawdzone w transkryptach 30.09.2026: Claude Code wola ten hook takze dla nich - prompt
// zaczyna sie wtedy od "<task-notification>" (i tak laduje w transkrypcie jako tresc wiadomosci).
// "[SYSTEM NOTIFICATION - NOT USER INPUT]" (w <system-reminder>) to ta sama rzecz w postaci,
// w jakiej Claude Code pokazuje ja modelowi przy powiadomieniu w trakcie pracy - lapiemy obie,
// ale tylko NA POCZATKU promptu: wiadomosc uzytkownika, ktora cytuje powiadomienie, dostaje
// zasady jak kazda inna.
function czyPowiadomienie(tresc) {
  if (typeof tresc !== "string") return false;
  const p = tresc.replace(/^\s+/, "");
  if (p.startsWith("<task-notification>")) return true;
  return /^(<system-reminder>\s*)?\[SYSTEM NOTIFICATION - NOT USER INPUT\]/.test(p);
}

// Zapis stanu przez plik tymczasowy i podmiane - dwa okna rozmowy naraz nie zostawia
// polowy pliku. Gdy podmiana nie wyjdzie (plik trzymany przez kogos), zapis wprost.
function zapiszStan(plik, stan) {
  const tekst = JSON.stringify(stan, null, 1);
  try {
    fs.mkdirSync(path.dirname(plik), { recursive: true });
    const tmp = plik + ".tmp" + process.pid;
    fs.writeFileSync(tmp, tekst, "utf8");
    try { fs.renameSync(tmp, plik); }
    catch (e) { fs.writeFileSync(plik, tekst, "utf8"); usun(tmp); }
  } catch (e) {
    process.stderr.write("przypomnienie.js: nie zapisalem stanu " + plik + ": " + e.message + "\n");
  }
}

// Slad po pominietym powiadomieniu - dowod, ze hook je rozpoznal, a nie ze milczy z awarii.
function odnotujPowiadomienie(plikStanu, tresc) {
  const stan = czytajStan(plikStanu);
  const p = stan.powiadomienia && typeof stan.powiadomienia === "object" ? stan.powiadomienia : {};
  p.pominiete = (Number(p.pominiete) || 0) + 1;
  p.ostatnie = new Date().toISOString();
  p.poczatek = String(tresc).replace(/\s+/g, " ").slice(0, 60);
  stan.powiadomienia = p;
  zapiszStan(plikStanu, stan);
}

// ---------------------------------------------------------------- rejestr instalacji (P59a)

// Moduly, od ktorych zalezy, co ten hook dokleja.
const MODULY_PRZYPOMNIENIA = ["kierownik", "wiedza", "lore"];

// Rejestr wybranych modulow - te same zasady odczytu co Czytaj-Instalacje w stan.ps1: brak pliku =
// wszystko wlaczone; pusty, z bajtem 0x00, zly JSON albo bez "moduly" = wszystko wlaczone + blad;
// brak klucza modulu (albo null) = wlaczony. Jeden maly odczyt pliku na wiadomosc.
// wiedzafirmy ma TRZECI STAN (stan.ps1): wlaczony tylko przy jawnym true. Brak rejestru, brak klucza
// i rejestr nieczytelny = bez podpowiedzi z wiedzy firmy, czyli dokladnie jak przed nia.
function rejestrInstalacji(plik) {
  const wszystko = { wiedzafirmy: false };
  for (const n of MODULY_PRZYPOMNIENIA) wszystko[n] = true;
  const zly = (powod) => ({ moduly: wszystko, blad: "nie umiem odczytac rejestru instalacji " +
    plik.replace(os.homedir(), "~") + ": " + powod });
  let b;
  try { b = fs.readFileSync(plik); }
  catch (e) {
    if (e && e.code === "ENOENT") return { moduly: wszystko, blad: null };
    return zly(String(e && e.message || e));
  }
  if (b.length === 0) return zly("plik jest pusty");
  if (b.indexOf(0) >= 0) return zly("plik zawiera bajty 0x00 (uszkodzony, np. po zaniku zasilania)");
  let j = null;
  try { j = JSON.parse(b.toString("utf8").replace(/^﻿/, "")); } catch (e) { return zly(String(e.message)); }
  if (j === null || typeof j !== "object" || j.moduly === undefined || j.moduly === null) return zly('brak pola "moduly"');
  const moduly = {};
  for (const n of MODULY_PRZYPOMNIENIA) {
    const v = j.moduly[n];
    moduly[n] = (v === undefined || v === null) ? true : Boolean(v);
  }
  moduly.wiedzafirmy = j.moduly.wiedzafirmy === true;
  return { moduly, blad: null };
}

// Linia alarmu o nieczytelnym rejestrze: przy pierwszym wystapieniu, przy zmianie przyczyny i potem
// co GODZIN_MIEDZY_ALARMAMI - ten sam rytm co alarm archiwum (linia przy kazdej wiadomosci uczy ja
// ignorowac). Stan w malym pliku obok rejestru; zdrowy rejestr go sprzata. "" = nic do pokazania.
function alarmRejestru(blad, plikAlarmu) {
  if (!blad) {
    if (fs.existsSync(plikAlarmu)) usun(plikAlarmu);
    return "";
  }
  const stan = czytajStan(plikAlarmu);
  const teraz = new Date();
  const ostatni = Date.parse(stan.czas);
  if (stan.powod === blad && !isNaN(ostatni) && (teraz - ostatni) / 3600000 < GODZIN_MIEDZY_ALARMAMI) return "";
  zapiszStan(plikAlarmu, { powod: blad, czas: teraz.toISOString() });
  let l = "UWAGA: " + blad + " - doklejam wszystko jak przed rejestrem; zapisze go od nowa instalator (instaluj.bat).";
  if (l.length > MAX_STAN) l = l.slice(0, MAX_STAN - 3) + "...";
  return l;
}

// Czy wolno oddac surowy ladunek w ostatniej desce ratunku (glowna().catch) - nie przy module
// kierownik wylaczonym w rejestrze: ladunek to jego tresc.
let kierownikWlaczony = true;

// ---------------------------------------------------------------- calosc

function wypisz(tekst) {
  // Wyjscie przez process.exit dopiero po oproznieniu stdout: wejscie uciete bezpiecznikiem
  // moglo zostac otwarte i trzymaloby proces przy zyciu.
  process.stdout.write(tekst, () => process.exit(0));
}

// Powiadomienie ma dostac zero doklejki takze wtedy, gdy cos po drodze sie wywroci -
// ostatnia deska na dole oddaje wtedy ladunek, a tego dla powiadomienia robic nie wolno.
let jestPowiadomienie = false;

async function glowna() {
  const plikLadunku = process.argv[2];
  const plikPostepu = process.argv[3] ||
    path.join(os.homedir(), ".claude", "wiedza", ".cykl-postep");
  const plikStanu = process.env.MR_ARCHIWUM_STAN ||
    path.join(os.homedir(), ".claude", "wiedza", ".archiwum-stan.json");
  const plikPowiadomien = process.env.MR_POWIADOMIENIA_STAN ||
    path.join(os.homedir(), ".claude", "wiedza", ".powiadomienia-stan.json");
  const plikRejestru = process.env.MR_INSTALACJA ||
    path.join(os.homedir(), ".claude", "mr", "instalacja.json");
  const plikAlarmuRejestru = process.env.MR_INSTALACJA_ALARM ||
    path.join(os.homedir(), ".claude", "mr", ".instalacja-alarm.json");
  const plikKonfiguWiedzy = process.env.MR_JFWIEDZA_KONFIG || path.join(os.homedir(), ".claude.json");
  const plikStanuWiedzy = process.env.MR_JFWIEDZA_STAN ||
    path.join(os.homedir(), ".claude", "wiedza", ".wiedza-firmy-stan.json");

  // Wejscie hooka NAJPIERW: o tym, ze to powiadomienie, trzeba wiedziec, zanim linia cyklu
  // zniknie z dysku (meldunek koncowy pokazuje sie tylko raz - nie moze pojsc do powiadomienia).
  let wejscie = null;
  try { wejscie = await czytajWejscie(CZAS_WEJSCIA_MS); }
  catch (e) { process.stderr.write("przypomnienie.js: nie odczytalem wejscia: " + (e && e.message || e) + "\n"); }
  let prosba = null;
  if (wejscie && wejscie !== "tty") { try { prosba = JSON.parse(wejscie); } catch (e) { prosba = null; } }
  const tresc = prosba && (typeof prosba.prompt === "string" ? prosba.prompt : prosba.user_prompt);
  if (czyPowiadomienie(tresc)) {
    jestPowiadomienie = true;
    try { odnotujPowiadomienie(plikPowiadomien, tresc); }
    catch (e) { process.stderr.write("przypomnienie.js: slad powiadomienia: " + (e && e.message || e) + "\n"); }
    process.exit(0);
  }

  // Ktore czesci w ogole doklejamy - rejestr instalacji (P59a).
  const rejestr = rejestrInstalacji(plikRejestru);
  const mod = rejestr.moduly;
  kierownikWlaczony = mod.kierownik;
  let alarm = "";
  try { alarm = alarmRejestru(rejestr.blad, plikAlarmuRejestru); }
  catch (e) { process.stderr.write("przypomnienie.js: alarm o rejestrze: " + (e && e.message || e) + "\n"); }

  // Plik ladunku daje tez "koperte" odpowiedzi (np. suppressOutput Claude Code) - bierzemy ja
  // takze przy wylaczonym kierowniku, ale wtedy bez jego tresci.
  const surowy = plikLadunku ? czytaj(plikLadunku) : null;
  let ladunek = null;
  if (surowy) { try { ladunek = JSON.parse(surowy); } catch (e) { ladunek = null; } }
  const umiemy = ladunek && ladunek.hookSpecificOutput &&
    typeof ladunek.hookSpecificOutput.additionalContext === "string";
  if (surowy && !umiemy && mod.kierownik) {
    // Plik jest, ale nie ma w nim ladunku, ktory umiemy uzupelnic - oddajemy go
    // slowo w slowo, dokladnie tak, jak robilo to wczesniejsze "cat".
    wypisz(surowy);
    return;
  }
  // Bez pliku ladunku (albo bez kierownika i z nieczytelnym plikiem) - pusta koperta. Brak
  // ladunku nie jest powodem, zeby zabrac linie cyklu i podpowiedz z archiwum.
  if (!umiemy) ladunek = { hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: "" } };
  const kontekst = ladunek.hookSpecificOutput;
  if (!mod.kierownik) kontekst.additionalContext = "";

  let linia = "";
  if (mod.wiedza) { try { linia = liniaCyklu(plikPostepu); } catch (e) { linia = ""; } }
  if (linia) kontekst.additionalContext = linia + (kontekst.additionalContext ? "\n" + kontekst.additionalContext : "");

  // Wiedza firmy rusza PRZED archiwum, zeby oba czekania szly naraz (opis przy zacznijWiedze).
  let wiedza = null;
  if (mod.wiedzafirmy) {
    try {
      const sesja = prosba ? (prosba.session_id || prosba.sessionId || null) : null;
      wiedza = zacznijWiedze(tresc, sesja, plikKonfiguWiedzy, plikStanuWiedzy);
      await wyslanaWiedza(wiedza);
    } catch (e) {
      wiedza = null;
      process.stderr.write("przypomnienie.js: podpowiedz z wiedzy firmy padla przy wysylce: " + (e && e.stack || e) + "\n");
    }
  }

  // Podpowiedz z archiwum. Cokolwiek tu padnie, przypomnienie wychodzi nizej bez zmian.
  const zasady = kontekst.additionalContext;
  if (mod.lore) {
    try {
      const budzet = Math.min(MAX_ARCHIWUM, SUFIT_LADUNKU - zasady.length - 2);
      const w = archiwum(wejscie, budzet, plikStanu);
      let calosc = zasady;
      if (w.alarm) calosc = w.alarm + (calosc ? "\n" + calosc : "");
      if (w.blok) calosc = calosc ? calosc + "\n\n" + w.blok : w.blok;
      kontekst.additionalContext = calosc;
    } catch (e) {
      kontekst.additionalContext = zasady;
      process.stderr.write("przypomnienie.js: podpowiedz z archiwum padla: " + (e && e.stack || e) + "\n");
    }
  }
  // Podpowiedz z wiedzy firmy - na koniec, za archiwum; alarm na poczatek. Awaria nie rusza reszty.
  if (wiedza) {
    const przed = kontekst.additionalContext;
    try {
      const w = await skonczWiedze(wiedza, przed.length);
      let calosc = przed;
      if (w.blok) calosc = calosc ? calosc + "\n\n" + w.blok : w.blok;
      if (w.alarm) calosc = w.alarm + (calosc ? "\n" + calosc : "");
      kontekst.additionalContext = calosc;
    } catch (e) {
      kontekst.additionalContext = przed;
      process.stderr.write("przypomnienie.js: podpowiedz z wiedzy firmy padla: " + (e && e.stack || e) + "\n");
    }
  }
  // Alarm o rejestrze na samym poczatku - sufit ucina koniec, poczatek przezywa zawsze.
  if (alarm) kontekst.additionalContext = alarm + (kontekst.additionalContext ? "\n" + kontekst.additionalContext : "");
  // Nic do doklejenia (np. same moduly bez tresci w tym hooku) - zadnego wyjscia.
  if (!kontekst.additionalContext) process.exit(0);
  wypisz(JSON.stringify(ladunek));
}

// Wczytany przez require (testy zgodnosci reguly z recall.py) - nic nie uruchamia, tylko oddaje funkcje.
if (require.main !== module) {
  module.exports = { SLOWA_POSPOLITE, MIN_ZNAKOW_PYTANIA, MIN_SLOW_PYTANIA, zlozTekst, slowaDoSzukania, pominiecieWiedzy };
} else {
  glowna().catch((e) => {
    // Ostatnia deska: blad poza podpowiedzia (nie powinien sie zdarzyc). Oddajemy ladunek
    // tak, jak lezy na dysku - dokladnie to, co robilo "cat" - i zostawiamy slad na stderr.
    // Przy kierowniku wylaczonym w rejestrze nie oddajemy nic: ladunek to jego tresc.
    process.stderr.write("przypomnienie.js: " + (e && e.stack || e) + "\n");
    if (jestPowiadomienie || !kierownikWlaczony) process.exit(0);
    const surowy = process.argv[2] ? czytaj(process.argv[2]) : null;
    if (surowy) wypisz(surowy); else process.exit(0);
  });
}
