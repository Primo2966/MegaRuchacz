// Globalny rejestr pracy workerow dla Claude Code - wariant dla instalacji
// globalnej. Dopisuje START/KONIEC workera do `<projekt>/.megaruchacz/worklog.md`,
// czyli tam, gdzie pisze go Codex i opencode - jedno miejsce dla wszystkich trzech.
//
// Rozni sie od `<projekt>/.claude/mr-log.js` tylko miejscem zapisu: tamten jest
// czescia wdrozenia per projekt i pisze do `.claude/worklog.md`. Gdy dziala
// instalacja globalna, per-projektowe hooki rejestru powinny byc wylaczone,
// zeby ten sam worker nie trafil do rejestru dwa razy.
//
// Wolany przez hooki SubagentStart / SubagentStop z ~/.claude/settings.json.
// Katalog projektu bierze z $CLAUDE_PROJECT_DIR.

const fs = require("fs");
const path = require("path");

let wej = "";
process.stdin.on("data", (c) => (wej += c));
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(wej || "{}"); } catch { /* pusty payload tez jest ok */ }

  const katalog = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const koniec = process.argv[2] === "stop";

  const kto = d.agent_type || d.subagent_type || d.agent || d.name || "worker";
  const co =
    d.description || d.task || d.summary ||
    (typeof d.prompt === "string" ? d.prompt.split("\n")[0].slice(0, 90) : "") || "";
  const czas = new Date().toLocaleTimeString("pl-PL", { hour12: false });

  try {
    const dir = path.join(katalog, ".megaruchacz");
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const plik = path.join(dir, "worklog.md");
    if (!fs.existsSync(plik)) fs.writeFileSync(plik, "# Rejestr pracy\n\n");
    fs.appendFileSync(plik, "- " + czas + "  " + (koniec ? "KONIEC " : "START  ") + kto + (co ? " | " + co : "") + "\n");
  } catch { /* rejestr to wygoda, nie moze wywrocic sesji */ }

  // Wspolny rejestr okien dla panelu nadzoru (rozszerzenie/extension.js czyta
  // ~/.claude/mr-okna). Do 2026-09-24 robil to osobny ~/.claude/mr/mr-log.js,
  // wolany DRUGIM hookiem obok tego - dwa hooki na jednego workera. Straznik
  // zdejmuje tamten jako duplikat, wiec jego robota przeszla tutaj, 1:1.
  try {
    const nazwa = path.basename(katalog);
    const kopia = nazwa.toLowerCase().indexOf("wt-") === 0;
    const dom = process.env.USERPROFILE || process.env.HOME || path.dirname(katalog);
    const dir = path.join(dom, ".claude", "mr-okna");
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const id = katalog.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^-+|-+$/g, "");
    const plik = path.join(dir, id + ".json");

    let stan = {};
    if (fs.existsSync(plik)) { try { stan = JSON.parse(fs.readFileSync(plik, "utf8")); } catch { stan = {}; } }

    stan.id = id;
    stan.galaz = kopia ? nazwa.slice(3) : null;
    stan.nazwa = kopia ? nazwa.slice(3) : "GLOWNE";
    stan.kopia = kopia;
    stan.folder = katalog;
    stan.aktywni = Math.max(0, (stan.aktywni || 0) + (koniec ? -1 : 1));
    stan.lacznie = (stan.lacznie || 0) + (koniec ? 0 : 1);
    stan.ostatni = kto + (co ? " | " + co : "");
    stan.ostatnia_zmiana = Date.now();
    if (!koniec) stan.puls = Date.now();

    fs.writeFileSync(plik, JSON.stringify(stan, null, 2));
  } catch { /* panel to wygoda, nie moze wywrocic sesji */ }

  process.stdout.write(JSON.stringify({ suppressOutput: true }));
});
