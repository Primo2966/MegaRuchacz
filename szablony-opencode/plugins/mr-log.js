// Rejestr pracy workerow dla opencode - odpowiednik .claude/mr-log.js (Claude Code)
// i narzedzia/mr-log-codex.js (Codex CLI).
//
// W opencode nie ma hookow, ktore mozna zatwierdzic - jest wtyczka. Ta wtyczka
// robi trzy rzeczy:
//
//   1. slucha zdarzen sesji: kazdy podagent dostaje wlasna sesje z wypelnionym
//      "parentID", a jej start i koniec to dokladnie moment, w ktorym worker
//      zaczyna i konczy robote - z tego sklada sie rejestr;
//   2. odswieza znacznik .megaruchacz/.opencode-zyje przy kazdym starcie, zeby
//      milczenie rejestru bylo odroznialne od rejestru, ktory nie chodzi;
//   3. wola w tle straznika zasad (samoaktualizacja, pilnowanie blokow zasad) -
//      pod Claude Code i Codeksem robi to hook SessionStart, ktorego opencode
//      nie ma.
//
// Rejestr lezy w <projekt>/.megaruchacz/worklog.md - tym samym pliku i formacie
// co pod Codeksem, zeby mapa i rejestr byly wspolne dla obu narzedzi.
//
// Plik jest modulem ESM: opencode laduje go sam, a "export" to jedyny sposob,
// w jaki opencode rozpoznaje wtyczke. Nie wolno zamienic go na wymagajacy
// "module.exports" - przestalby byc wtyczka, a rejestr zaczalby milczec.

import fs from "node:fs"
import path from "node:path"
import os from "node:os"
import { spawn } from "node:child_process"

// Znacznik "bylem tu". Rejestr, ktory milczy, musi byc odroznialny od rejestru,
// ktory nie chodzi - a wtyczka, ktora sie nie zaladowala, sama o sobie nie powie.
// Lezy globalnie, w ~/.claude/.
const ZNACZNIK = ".megaruchacz-opencode-zyje"

function katalogProjektu(wejscie) {
  return wejscie.directory || wejscie.worktree || process.cwd()
}

function katalogMegaruchacza(wejscie) {
  return path.join(katalogProjektu(wejscie), ".megaruchacz")
}

function dopisz(katalog, tekst) {
  try {
    fs.mkdirSync(katalog, { recursive: true })
    const plik = path.join(katalog, "worklog.md")
    if (!fs.existsSync(plik)) fs.writeFileSync(plik, "# Rejestr pracy\n\n")
    fs.appendFileSync(plik, tekst + "\n")
  } catch {
    // Rejestr to wygoda - nie ma prawa wywrocic sesji.
  }
}

function stempluj() {
  // Znacznik lezy globalnie (~/.claude/), a nie w projekcie: instalacja globalna
  // dziala w kazdym projekcie, wiec nie ma powodu zostawiac sladu w kazdym z nich.
  try {
    const dir = path.join(os.homedir(), ".claude")
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(path.join(dir, ZNACZNIK), new Date().toISOString())
  } catch {
    // brak stempla zglasza straznik - tu nie ma czego ratowac
  }
}

// Straznik zasad pod Claude Code i Codeksem jest wolany hookiem SessionStart.
// opencode takiego hooka nie ma, wiec wolamy go stad: raz na proces, w tle,
// w trybie -Tlo (nic nie wypisuje, slad zostaje w dzienniku). Sciezke do repo
// bierzemy z .megaruchacz/wersja.txt ("zrodlo: ...") - wtyczka jest kopiowana
// doslownie, wiec nie moze miec jej wpisanej na sztywno.
let straznikOdpytywal = false

function odpalStraznika(katalogProjektu, katalogMegaruchacza) {
  if (straznikOdpytywal || process.platform !== "win32") return
  straznikOdpytywal = true
  try {
    // Skad repo narzedzia: najpierw znacznik wdrozenia per projekt, a gdy go nie
    // ma - znacznik instalacji globalnej. Ten sam klucz "zrodlo:".
    const kandydaci = [
      path.join(katalogMegaruchacza, "wersja.txt"),
      path.join(os.homedir(), ".claude", ".megaruchacz-global"),
    ]
    let zrodlo = null
    for (const p of kandydaci) {
      if (!fs.existsSync(p)) continue
      const trafienie = fs.readFileSync(p, "utf8").match(/^zrodlo:[ \t]*(.+)$/m)
      if (trafienie) { zrodlo = trafienie[1].trim(); break }
    }
    if (!zrodlo) return
    const skrypt = path.join(zrodlo, "narzedzia", "straznik-zasad.ps1")
    if (!fs.existsSync(skrypt)) return
    const proces = spawn(
      "powershell",
      ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
       "-File", skrypt, "-Tlo", "-Zrodlo", zrodlo, "-Projekt", katalogProjektu],
      // Bez "detached": na Windowsie detached razem z ukryciem okna potrafi
      // nie uruchomic procesu wcale (sprawdzone). Serwer opencode zyje dlugo,
      // wiec dziecko nie musi sie od niego odrywac.
      { stdio: "ignore", windowsHide: true }
    )
    proces.unref()
  } catch {
    // brak straznika to nie powod, zeby sesja sie nie otworzyla
  }
}

function godzina() {
  return new Date().toLocaleTimeString("pl-PL", { hour12: false })
}

export const MrLog = async (wejscie) => {
  wejscie = wejscie || {}
  const projekt = katalogProjektu(wejscie)
  const katalog = katalogMegaruchacza(wejscie)
  stempluj()
  odpalStraznika(projekt, katalog)

  // Sesje workerow, ktore juz zameldowaly start, a jeszcze nie koniec.
  const trwaja = new Map()

  const start = (id, opis) => {
    if (!id || trwaja.has(id)) return
    trwaja.set(id, true)
    dopisz(katalog, "- " + godzina() + "  START  worker" + (opis ? " | " + opis : ""))
  }

  const koniec = (id) => {
    if (!id || !trwaja.has(id)) return
    trwaja.delete(id)
    dopisz(katalog, "- " + godzina() + "  KONIEC")
  }

  return {
    // Gdy AGENTS.md jest sledzony w gicie albo go nie ma, instalator go nie
    // dotyka - a wtedy opencode nie mialby skad wziac zasad. Dokladamy je jako
    // plik instrukcji z .megaruchacz\, ale tylko wtedy, gdy w AGENTS.md ich nie
    // ma: inaczej to samo lecialoby do modelu dwa razy.
    config: async (cfg) => {
      try {
        const plikAgents = path.join(katalogProjektu(wejscie), "AGENTS.md")
        let wAgents = false
        if (fs.existsSync(plikAgents)) {
          wAgents = fs.readFileSync(plikAgents, "utf8").includes("<!-- MegaRuchacz:start -->")
        }
        if (wAgents) return
        const plikZasad = path.join(katalog, "zasady-kierownika.md")
        if (!fs.existsSync(plikZasad)) return
        cfg.instructions = cfg.instructions || []
        const jest = cfg.instructions.some((i) => String(i).replace(/\\/g, "/").includes(".megaruchacz/zasady-kierownika.md"))
        if (!jest) cfg.instructions.push(plikZasad.replace(/\\/g, "/"))
      } catch {
        // brak zasad nie moze wywrocic startu opencode
      }
    },
    event: async ({ event }) => {
      if (!event || !event.type) return
      const p = event.properties || {}
      if (event.type === "session.created") {
        const info = p.info || {}
        // Zwykla sesja nie ma rodzica - workerem jest tylko podagent.
        if (!info.parentID) return
        start(info.id, info.title || "")
      } else if (event.type === "session.idle") {
        koniec(p.sessionID)
      } else if (event.type === "session.deleted") {
        const info = p.info || {}
        koniec(info.id)
      }
    },
  }
}
