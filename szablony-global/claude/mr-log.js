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

  process.stdout.write(JSON.stringify({ suppressOutput: true }));
});
