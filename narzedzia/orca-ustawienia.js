#!/usr/bin/env node
// Przenoszenie ustawien Orki miedzy komputerami.
//
// Orca trzyma wszystko w jednym pliku orca-data.json, a w nim mieszaja sie
// dwie rzeczy: ustawienia (przenosne) i stan tej maszyny - projekty, kopie
// robocze, sesje, cele SSH. Skopiowanie calego pliku zepsulo by druga maszyne,
// bo wskazywalby na sciezki, ktorych tam nie ma.
//
// Ten skrypt przenosi WYLACZNIE sekcje "settings" i "ui".
//
// Uzycie:
//   node orca-ustawienia.js eksport ustawienia-orki.json
//   node orca-ustawienia.js import  ustawienia-orki.json
//
// WAZNE: przy imporcie Orca musi byc ZAMKNIETA - przy zamykaniu zapisuje
// swoj plik i nadpisalaby zmiane.

const fs = require("fs");
const path = require("path");
const os = require("os");

const PRZENOSZONE = ["settings", "ui"];

// Sprawdzone 2026-09-16: obie przenoszone sekcje zawieraja rzeczy zwiazane
// z konkretna maszyna - identyfikatory repozytoriow i kopii roboczych, sciezki,
// filtry po projektach. Wgranie ich na drugi komputer pokazaloby tam projekty,
// ktorych nie ma, i schowalo te, ktore sa. Wyglad i preferencje przenosza sie,
// stan tej maszyny zostaje.
const POMIJANE = {
  settings: ["workspaceDir", "workspaceDirHistory"],
  ui: [
    "lastActiveRepoId",
    "lastActiveWorktreeId",
    "filterRepoIds",
    "manualRepoOrder",
    "visibleWorkspaceHostIds",
    "workspaceHostOrder",
    "agentsVisibleHostIds",
    "automationHostFilter",
  ],
};

function bezStanuMaszyny(klucz, sekcja) {
  const pomin = POMIJANE[klucz] || [];
  const wynik = {};
  for (const [k, v] of Object.entries(sekcja)) {
    if (!pomin.includes(k)) wynik[k] = v;
  }
  return { wynik, pominiete: pomin.filter((k) => k in sekcja) };
}

function plikOrki() {
  const baza = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
  return path.join(baza, "orca", "profiles", "local-default", "orca-data.json");
}

function czytajJson(sciezka) {
  return JSON.parse(fs.readFileSync(sciezka, "utf8"));
}

function stempel() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function eksport(cel) {
  const zrodlo = plikOrki();
  if (!fs.existsSync(zrodlo)) {
    console.error(`BLAD  nie znalazlem pliku Orki: ${zrodlo}`);
    process.exit(1);
  }
  const dane = czytajJson(zrodlo);
  const wynik = {};
  const brakujace = [];
  const pominieteRazem = [];
  for (const klucz of PRZENOSZONE) {
    if (!(klucz in dane)) {
      brakujace.push(klucz);
      continue;
    }
    const { wynik: czyste, pominiete } = bezStanuMaszyny(klucz, dane[klucz]);
    wynik[klucz] = czyste;
    pominiete.forEach((k) => pominieteRazem.push(`${klucz}.${k}`));
  }
  if (Object.keys(wynik).length === 0) {
    console.error("BLAD  w pliku Orki nie ma zadnej z przenoszonych sekcji - nic do zapisania.");
    process.exit(1);
  }
  fs.writeFileSync(cel, JSON.stringify(wynik, null, 2), "utf8");
  const kb = (fs.statSync(cel).size / 1024).toFixed(1);
  console.log(`OK    zapisane: ${cel}  (${kb} KB)`);
  console.log(`      sekcje: ${Object.keys(wynik).join(", ")}`);
  if (pominieteRazem.length) {
    console.log(`      pominiete (stan tej maszyny): ${pominieteRazem.join(", ")}`);
  }
  if (brakujace.length) console.log(`      nie bylo w zrodle: ${brakujace.join(", ")}`);
  console.log("");
  console.log("Przenies ten plik na druga maszyne i tam uruchom:");
  console.log(`  node orca-ustawienia.js import ${path.basename(cel)}`);
}

function importuj(zrodloUstawien) {
  if (!fs.existsSync(zrodloUstawien)) {
    console.error(`BLAD  nie ma pliku: ${zrodloUstawien}`);
    process.exit(1);
  }
  const cel = plikOrki();
  if (!fs.existsSync(cel)) {
    console.error(`BLAD  nie znalazlem pliku Orki: ${cel}`);
    console.error("      Uruchom Orke chocby raz na tej maszynie, zeby powstal.");
    process.exit(1);
  }

  const nowe = czytajJson(zrodloUstawien);
  const dane = czytajJson(cel);

  const kopia = `${cel}.bak-${stempel()}`;
  fs.copyFileSync(cel, kopia);

  // Scalamy klucz po kluczu, nie podmieniamy calej sekcji. Podmiana skasowalaby
  // na maszynie docelowej to, czego celowo nie przenosimy - jej wlasne sciezki
  // i identyfikatory projektow.
  const wgrane = [];
  let ileKluczy = 0;
  for (const klucz of PRZENOSZONE) {
    if (!(klucz in nowe)) continue;
    if (typeof dane[klucz] !== "object" || dane[klucz] === null) dane[klucz] = {};
    const pomin = POMIJANE[klucz] || [];
    for (const [k, v] of Object.entries(nowe[klucz])) {
      if (pomin.includes(k)) continue; // ochrona, gdyby plik pochodzil ze starszej wersji
      dane[klucz][k] = v;
      ileKluczy++;
    }
    wgrane.push(klucz);
  }
  if (wgrane.length === 0) {
    console.error("BLAD  plik nie zawiera zadnej z przenoszonych sekcji - nic nie zmieniam.");
    fs.unlinkSync(kopia);
    process.exit(1);
  }

  fs.writeFileSync(cel, JSON.stringify(dane, null, 2), "utf8");
  console.log(`OK    wgrane sekcje: ${wgrane.join(", ")} (${ileKluczy} ustawien)`);
  console.log(`      kopia przed zmiana: ${kopia}`);
  console.log("");
  console.log("Reszta - projekty, kopie robocze, sesje, cele SSH - zostala nietknieta,");
  console.log("bo wskazuje na sciezki tej maszyny.");
  console.log("");
  console.log("Uruchom Orke na nowo, zeby zobaczyc zmiany.");
}

const [tryb, plik] = process.argv.slice(2);

if (tryb === "eksport" && plik) {
  eksport(plik);
} else if (tryb === "import" && plik) {
  importuj(plik);
} else {
  console.log("Przenoszenie ustawien Orki miedzy komputerami.");
  console.log("");
  console.log("  node orca-ustawienia.js eksport <plik>   zapisuje ustawienia z tej maszyny");
  console.log("  node orca-ustawienia.js import  <plik>   wgrywa je na tej maszynie");
  console.log("");
  console.log("Przenoszone sa tylko sekcje: " + PRZENOSZONE.join(", "));
  console.log("Projekty, kopie robocze, sesje i cele SSH zostaja nietkniete.");
  console.log("");
  console.log("Przy imporcie Orca musi byc ZAMKNIETA - inaczej nadpisze zmiane przy wyjsciu.");
  process.exit(tryb ? 1 : 0);
}
