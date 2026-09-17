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

const fs = require("fs");
const os = require("os");
const path = require("path");

// Sufit ladunku (additionalContextLimit) ucina KONIEC tresci i nie mowi o tym ani
// slowa - dlatego linia o cyklu idzie na POCZATEK, tak samo jak alarmy w straznik-zasad.ps1.
// Jej dlugosc jest ograniczona, zeby stala tresc przypomnienia nie wyjechala ponad sufit:
// przypomnienia maja dzis ~620 znakow przy suficie 1500 (.codex\hooks.json), wiec
// 620 + 300 = 920 i zapas zostaje. Podnoszac ten limit, sprawdz tamten.
const MAX_STAN = 300;
// Stan "pracuje" starszy niz tyle godzin znaczy, ze proces cyklu padl i nikt juz
// tego pliku nie domknie. Lepiej milczec niz w kolko meldowac prace, ktorej nie ma.
const GODZIN_WAZNOSCI = 3;

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

const plikLadunku = process.argv[2];
const plikPostepu = process.argv[3] ||
  path.join(os.homedir(), ".claude", "wiedza", ".cykl-postep");

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
  process.stdout.write(surowy);
  process.exit(0);
}

let linia = "";
try { linia = liniaCyklu(plikPostepu); } catch (e) { linia = ""; }
if (linia) {
  ladunek.hookSpecificOutput.additionalContext =
    linia + "\n" + ladunek.hookSpecificOutput.additionalContext;
}
process.stdout.write(JSON.stringify(ladunek));
