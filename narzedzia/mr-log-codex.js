// Dopisuje linie do .megaruchacz/worklog.md przy starcie i koncu kazdego workera.
// Wolany przez hooki Codeksa SubagentStart / SubagentStop - odpowiednik
// .claude/mr-log.js z Claude Code.
//
// Rejestr lezy w <projekt>/.megaruchacz/, a NIE w <projekt>/.codex/: piaskownica
// Codeksa trzyma .codex/ rekurencyjnie tylko do odczytu, wiec zapis tam nie ma
// prawa sie udac.
//
// Uzycie:  node mr-log-codex.js start|stop "<katalog projektu>"
// Na wejsciu zdarzenie Codeksa: agent_id, agent_type, permission_mode.
const fs = require("fs");
const path = require("path");

let wej = "";
process.stdin.on("data", (c) => (wej += c));
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(wej || "{}"); } catch { /* pusty payload tez jest ok */ }

  const koniec = process.argv[2] === "stop";
  const katalog = process.argv[3] || process.env.CODEX_PROJECT_DIR || process.cwd();

  const kto  = d.agent_type || d.agentType || "worker";
  const id   = d.agent_id || d.agentId || "";
  const tryb = d.permission_mode || d.permissionMode || "";
  const czas = new Date().toLocaleTimeString("pl-PL", { hour12: false });

  try {
    const dir = path.join(katalog, ".megaruchacz");
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const plik = path.join(dir, "worklog.md");
    if (!fs.existsSync(plik)) fs.writeFileSync(plik, "# Rejestr pracy\n\n");
    const ogon = [id ? "id " + id : "", tryb ? "tryb " + tryb : ""].filter(Boolean).join(" | ");
    fs.appendFileSync(plik, "- " + czas + "  " + (koniec ? "KONIEC " : "START  ") + kto + (ogon ? " | " + ogon : "") + "\n");
  } catch { /* rejestr to wygoda, nie moze wywrocic sesji */ }

  // Wyjscie SubagentStart trafia do podagenta jako dodatkowy kontekst - stad
  // cisza, zeby nie doklejac mu smieci do zlecenia. SubagentStop czyta JSON,
  // wiec mowimy wprost: workera nie przerywamy.
  if (koniec) process.stdout.write(JSON.stringify({ continue: true }));
});
