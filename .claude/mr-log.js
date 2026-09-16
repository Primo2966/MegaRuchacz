// Dopisuje linie do .claude/worklog.md przy starcie i koncu kazdego workera
// ORAZ aktualizuje wspolny rejestr okien, z ktorego korzysta panel nadzoru.
// Wolany przez hooki SubagentStart / SubagentStop.
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

  // --- 1. rejestr czytelny dla czlowieka ---
  try {
    const plik = path.join(katalog, ".claude", "worklog.md");
    if (!fs.existsSync(plik)) fs.writeFileSync(plik, "# Rejestr pracy\n\n");
    fs.appendFileSync(plik, "- " + czas + "  " + (koniec ? "KONIEC " : "START  ") + kto + (co ? " | " + co : "") + "\n");
  } catch { /* rejestr to wygoda, nie moze wywrocic sesji */ }

  // --- 2. wspolny rejestr okien, dla panelu nadzoru ---
  try {
    const nazwa = path.basename(katalog);
    const kopia = nazwa.toLowerCase().indexOf("wt-") === 0;
    const rodzic = path.dirname(katalog);
    const dir = path.join(rodzic, ".mr-okna");
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const id = kopia ? nazwa.slice(3) : "GLOWNE";
    const plik = path.join(dir, id + ".json");

    let stan = {};
    if (fs.existsSync(plik)) { try { stan = JSON.parse(fs.readFileSync(plik, "utf8")); } catch {} }

    stan.id = id;
    stan.galaz = kopia ? id : null;
    stan.kopia = kopia;
    stan.folder = katalog;
    stan.aktywni = Math.max(0, (stan.aktywni || 0) + (koniec ? -1 : 1));
    stan.lacznie = (stan.lacznie || 0) + (koniec ? 0 : 1);
    stan.ostatni = kto + (co ? " | " + co : "");
    stan.ostatnia_zmiana = Date.now();
    if (!koniec) stan.puls = Date.now();

    fs.writeFileSync(plik, JSON.stringify(stan, null, 2));
  } catch { /* nadzor tez nie moze wywrocic sesji */ }

  process.stdout.write(JSON.stringify({ suppressOutput: true }));
});
