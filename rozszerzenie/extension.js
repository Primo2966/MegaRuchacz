const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const cp = require("child_process");
const os = require("os");

const PULS_MS = 10000;      // jak czesto okno melduje, ze zyje
const MARTWE_PO = 45000;    // po tylu ms bez pulsu okno uznajemy za zamkniete

function ust(k) { return vscode.workspace.getConfiguration("megaruchacz").get(k); }
// Pusta konfiguracja znaczy: bierz folder otwarty w VS Code.
function repo() {
  const zUstawien = String(ust("repo") || "").trim();
  if (zUstawien) return zUstawien.replace(/[\\/]+$/, "");
  const f = vscode.workspace.workspaceFolders;
  if (f && f.length > 0) return f[0].uri.fsPath.replace(/[\\/]+$/, "");
  return "";
}
// Gdy nie ma ani ustawienia, ani otwartego folderu - mowimy to wprost,
// zamiast puszczac dalej pusta sciezke do gita.
function repoLubKomunikat() {
  const r = repo();
  if (!r) {
    vscode.window.showInformationMessage(
      "MegaRuchacz: nie wiem, gdzie jest repozytorium. Otworz folder projektu albo ustaw 'megaruchacz.repo' w ustawieniach."
    );
    return null;
  }
  return r;
}
function rodzic() { return path.dirname(repo()); }
// Jeden rejestr dla wszystkich projektow - ten sam, do ktorego pisze hook.
function katalogRejestru() { return path.join(os.homedir(), ".claude", "mr-okna"); }

// Okno jest "kopia robocza", gdy jego folder nazywa sie wt-<galaz>.
function stanOkna() {
  const f = vscode.workspace.workspaceFolders;
  if (!f || f.length === 0) return { kopia: false, galaz: null, folder: null, id: null };
  const folder = f[0].uri.fsPath;
  const nazwa = path.basename(folder);
  const kopia = nazwa.toLowerCase().indexOf("wt-") === 0;
  return {
    kopia: kopia,
    galaz: kopia ? nazwa.slice(3) : null,
    folder: folder,
    nazwa: kopia ? nazwa.slice(3) : "GLOWNE",
    id: folder.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^-+|-+$/g, "")
  };
}

function plikOkna(id) { return path.join(katalogRejestru(), id + ".json"); }

function czytajOkno(id) {
  try { return JSON.parse(fs.readFileSync(plikOkna(id), "utf8")); } catch (e) { return null; }
}

function zapiszOkno(id, zmiany) {
  try {
    const dir = katalogRejestru();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const stan = czytajOkno(id) || {};
    Object.keys(zmiany).forEach(function (k) { stan[k] = zmiany[k]; });
    fs.writeFileSync(plikOkna(id), JSON.stringify(stan, null, 2));
    return stan;
  } catch (e) { return null; }
}

function wszystkieOkna() {
  const dir = katalogRejestru();
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(function (n) { return n.slice(-5) === ".json"; })
    .map(function (n) {
      try { return JSON.parse(fs.readFileSync(path.join(dir, n), "utf8")); } catch (e) { return null; }
    })
    .filter(function (o) { return !!o; })
    .sort(function (a, b) {
      if (a.kopia !== b.kopia) return a.kopia ? 1 : -1;
      return String(a.id).localeCompare(String(b.id));
    });
}

function zywe(o) { return Date.now() - (o.puls || 0) < MARTWE_PO; }

function wTerminalu(tytul, komenda) {
  const t = vscode.window.createTerminal({ name: tytul, shellPath: "powershell.exe" });
  t.show();
  t.sendText(komenda);
}

function git(args) {
  return new Promise(function (ok) {
    cp.execFile("git", ["-C", repo()].concat(args), { windowsHide: true }, function (err, out, errOut) {
      ok({ kod: err ? (err.code || 1) : 0, tekst: (out || "") + (errOut || "") });
    });
  });
}

// ---------------------------------------------------------------- drzewo

function DostawcaDrzewa() {
  this._zmiana = new vscode.EventEmitter();
  this.onDidChangeTreeData = this._zmiana.event;
}

DostawcaDrzewa.prototype.odswiez = function () { this._zmiana.fire(); };
DostawcaDrzewa.prototype.getTreeItem = function (e) { return e; };

DostawcaDrzewa.prototype.getChildren = function (wezelRodzic) {
  if (wezelRodzic) return wezelRodzic.dzieci || [];

  const okna = wszystkieOkna();
  if (okna.length === 0) {
    const pusty = new vscode.TreeItem("Brak zarejestrowanych okien");
    pusty.description = "kliknij + zeby zaczac zadanie";
    pusty.iconPath = new vscode.ThemeIcon("info");
    return [pusty];
  }

  return okna.map(function (o) {
    const czyZyje = zywe(o);
    const aktywni = czyZyje ? (o.aktywni || 0) : 0;

    const wezel = new vscode.TreeItem(
      o.nazwa || (o.kopia ? o.galaz : "GLOWNE"),
      vscode.TreeItemCollapsibleState.Collapsed
    );

    if (!czyZyje) {
      wezel.description = "zamkniete";
      wezel.iconPath = new vscode.ThemeIcon("circle-outline");
    } else if (aktywni > 0) {
      wezel.description = aktywni + (aktywni === 1 ? " worker" : " workerow");
      wezel.iconPath = new vscode.ThemeIcon("sync~spin");
    } else {
      wezel.description = o.kopia ? "bezczynne" : "okno glowne";
      wezel.iconPath = new vscode.ThemeIcon(o.kopia ? "check" : "home");
    }

    wezel.contextValue = (o.kopia && czyZyje) ? "kopia" : "inne";
    wezel.dane = o;
    wezel.tooltip = o.folder;

    const dzieci = [];
    function pozycja(tekst, ikona) {
      const p = new vscode.TreeItem(tekst);
      p.iconPath = new vscode.ThemeIcon(ikona);
      dzieci.push(p);
    }
    if (o.kopia) pozycja("galaz " + o.galaz, "git-branch");
    pozycja("workerow lacznie: " + (o.lacznie || 0), "history");
    if (o.ostatni) pozycja(String(o.ostatni).slice(0, 70), "person");
    if (o.ostatnia_zmiana) {
      pozycja("ostatnio: " + new Date(o.ostatnia_zmiana).toLocaleTimeString("pl-PL", { hour12: false }), "clock");
    }
    wezel.dzieci = dzieci;
    return wezel;
  });
};

// ---------------------------------------------------------------- start

function activate(kontekst) {
  const ja = stanOkna();
  const drzewo = new DostawcaDrzewa();
  const kanal = vscode.window.createOutputChannel("MegaRuchacz");

  vscode.window.registerTreeDataProvider("megaruchacz.okna", drzewo);

  // to okno melduje sie w rejestrze i bije pulsem
  if (ja.folder) {
    zapiszOkno(ja.id, {
      id: ja.id,
      kopia: ja.kopia,
      galaz: ja.galaz,
      nazwa: ja.nazwa,
      folder: ja.folder,
      puls: Date.now(),
      sygnal: null
    });
    const puls = setInterval(function () { zapiszOkno(ja.id, { puls: Date.now() }); }, PULS_MS);
    kontekst.subscriptions.push({ dispose: function () { clearInterval(puls); } });
  }

  function przycisk(kolejnosc, tekst, opis, komenda, ostrzegawczy) {
    const p = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, kolejnosc);
    p.text = tekst;
    p.tooltip = opis;
    if (komenda) p.command = komenda;
    if (ostrzegawczy) p.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
    p.show();
    kontekst.subscriptions.push(p);
    return p;
  }

  // Pasek stanu: trzy elementy w klamrze, zeby bylo widac, ze to jeden dodatek.
  // VS Code nie pozwala obramowac grupy, wiec klamre robimy znakami na koncach.
  const stan = przycisk(100, "▏ MegaRuchacz", "MegaRuchacz - klik otwiera panel okien", "megaruchacz.pokazPanel", ja.kopia);
  przycisk(98, "$(add)", "Nowe zadanie w izolowanej kopii projektu", "megaruchacz.noweZadanie", false);
  przycisk(97, "$(eye) ▕", "Podglad rejestru workerow tego okna na zywo", "megaruchacz.rejestr", false);

  function odswiezWszystko() {
    drzewo.odswiez();
    const okna = wszystkieOkna().filter(zywe);
    const workerow = okna.reduce(function (s, o) { return s + (o.aktywni || 0); }, 0);
    const kim = ja.kopia ? "$(git-branch) " + ja.galaz : "$(home) GLOWNE";
    stan.text = "▏ MegaRuchacz · " + kim + " · " +
      okna.length + (okna.length === 1 ? " okno" : " okna") + " · " + workerow + " work.";
    stan.tooltip = "To okno: " + (ja.kopia ? "kopia robocza na galezi " + ja.galaz : "glowne, tu scalasz") +
      "\n\nPracuja teraz:\n" + (okna.map(function (o) {
        return "  " + (o.nazwa || (o.kopia ? o.galaz : "GLOWNE")) + ": " + (o.aktywni || 0) + " workerow";
      }).join("\n") || "  brak") + "\n\nKlik otwiera panel okien.";
  }
  odswiezWszystko();

  const tyk = setInterval(odswiezWszystko, 3000);
  kontekst.subscriptions.push({ dispose: function () { clearInterval(tyk); } });

  // okno kopii slucha, czy kierownik kaze mu sie zamknac
  if (ja.kopia) {
    const wartownik = setInterval(function () {
      const moj = czytajOkno(ja.id);
      if (moj && moj.sygnal === "zamknij") {
        zapiszOkno(ja.id, { sygnal: null, puls: 0, zamkniete_at: Date.now() });
        vscode.commands.executeCommand("workbench.action.closeWindow");
      }
    }, 1500);
    kontekst.subscriptions.push({ dispose: function () { clearInterval(wartownik); } });
  }

  function zarejestruj(nazwa, fn) {
    kontekst.subscriptions.push(vscode.commands.registerCommand(nazwa, fn));
  }

  zarejestruj("megaruchacz.odswiez", odswiezWszystko);

  zarejestruj("megaruchacz.pokazPanel", function () {
    vscode.commands.executeCommand("workbench.view.extension.megaruchacz");
  });

  zarejestruj("megaruchacz.noweZadanie", async function () {
    const wPracy = wszystkieOkna().filter(function (o) { return zywe(o) && o.kopia; });
    if (wPracy.length > 0) {
      const lista = wPracy.map(function (o) {
        return "- " + o.galaz + " (" + (o.aktywni || 0) + " workerow)";
      }).join("\n");
      const dalej = await vscode.window.showInformationMessage(
        "W tej chwili pracuja juz inne okna:\n\n" + lista + "\n\nZakladac kolejne?",
        { modal: true },
        "Zakladaj"
      );
      if (dalej !== "Zakladaj") return;
    }
    const nazwa = await vscode.window.showInputBox({
      prompt: "Nazwa zadania (bedzie nazwa galezi i folderu)",
      placeHolder: "np. cytaty-whatsapp",
      validateInput: function (v) {
        return v && v.trim().length >= 2 ? null : "Podaj co najmniej 2 znaki";
      }
    });
    if (!nazwa) return;
    const gdzie = repoLubKomunikat();
    if (!gdzie) return;
    wTerminalu(
      "MegaRuchacz: nowe zadanie",
      'powershell -ExecutionPolicy Bypass -File "' + ust("skrypt") + '" "' + nazwa + '" -Repo "' + gdzie + '"'
    );
  });

  zarejestruj("megaruchacz.rejestr", function () {
    const st = stanOkna();
    if (!st.folder) {
      vscode.window.showInformationMessage("Najpierw otworz folder projektu.");
      return;
    }
    wTerminalu("Workerzy na zywo", 'Get-Content "' + path.join(st.folder, ".claude", "worklog.md") + '" -Wait -Tail 25');
  });

  zarejestruj("megaruchacz.otworz", function (wezel) {
    const o = wezel && wezel.dane;
    if (!o) return;
    if (!repoLubKomunikat()) return;
    const ws = path.join(rodzic(), "wt-" + o.galaz + ".code-workspace");
    const cel = fs.existsSync(ws) ? ws : o.folder;
    vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(cel), { forceNewWindow: true });
  });

  zarejestruj("megaruchacz.scalIZamknij", async function (wezel) {
    const o = wezel && wezel.dane;
    if (!o || !o.kopia) return;
    if (!repoLubKomunikat()) return;

    if ((o.aktywni || 0) > 0) {
      const mimo = await vscode.window.showWarningMessage(
        "W oknie '" + o.galaz + "' pracuje jeszcze " + o.aktywni + " workerow. Scalac mimo to?",
        { modal: true },
        "Scalaj"
      );
      if (mimo !== "Scalaj") return;
    } else {
      const ok = await vscode.window.showWarningMessage(
        "Scalic galaz '" + o.galaz + "' do glownej, zamknac jej okno i usunac kopie?",
        { modal: true },
        "Scal i zamknij"
      );
      if (ok !== "Scal i zamknij") return;
    }

    kanal.show(true);
    kanal.appendLine("=== " + o.galaz + " ===");

    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: "MegaRuchacz: " + o.galaz, cancellable: false },
      async function (postep) {
        postep.report({ message: "scalanie galezi..." });
        const scal = await git(["merge", "--no-ff", o.galaz, "-m", "Scalenie galezi " + o.galaz]);
        kanal.appendLine(scal.tekst.trim());
        if (scal.kod !== 0) {
          vscode.window.showErrorMessage(
            "Scalenie sie nie powiodlo - konflikty rozstrzygnij recznie. Szczegoly w panelu wyjscia MegaRuchacz."
          );
          return;
        }

        postep.report({ message: "zamykanie okna zadania..." });
        zapiszOkno(o.id, { sygnal: "zamknij" });
        for (let i = 0; i < 12; i++) {
          await new Promise(function (r) { setTimeout(r, 700); });
          const teraz = czytajOkno(o.id);
          if (!teraz || !zywe(teraz)) break;
        }

        postep.report({ message: "sprzatanie kopii..." });
        const usun = await git(["worktree", "remove", o.folder, "--force"]);
        kanal.appendLine(usun.tekst.trim());

        try { fs.unlinkSync(path.join(rodzic(), "wt-" + o.galaz + ".code-workspace")); } catch (e) {}
        try { fs.unlinkSync(plikOkna(o.id)); } catch (e) {}

        odswiezWszystko();
        vscode.window.showInformationMessage(
          "Galaz '" + o.galaz + "' scalona, okno zamkniete, kopia usunieta."
        );
      }
    );
  });

  zarejestruj("megaruchacz.scal", async function () {
    const st = stanOkna();
    if (!st.kopia) {
      vscode.window.showInformationMessage("To jest okno glowne - nie ma czego scalac.");
      return;
    }
    const ok = await vscode.window.showWarningMessage(
      "Scalic galaz '" + st.galaz + "' do glownej?", { modal: true }, "Scal"
    );
    if (ok !== "Scal") return;
    if (!repoLubKomunikat()) return;
    wTerminalu("MegaRuchacz: scalanie", 'git -C "' + repo() + '" merge ' + st.galaz);
  });

  zarejestruj("megaruchacz.usun", async function () {
    const st = stanOkna();
    if (!st.kopia) {
      vscode.window.showInformationMessage("To jest okno glowne - go nie usuwamy.");
      return;
    }
    const ok = await vscode.window.showWarningMessage(
      "Usunac kopie '" + st.galaz + "'? Niezscalone zmiany przepadna.", { modal: true }, "Usun"
    );
    if (ok !== "Usun") return;
    if (!repoLubKomunikat()) return;
    wTerminalu(
      "MegaRuchacz: usuwanie kopii",
      'git -C "' + repo() + '" worktree remove "' + st.folder + '" --force'
    );
  });
}

function deactivate() {}

module.exports = { activate: activate, deactivate: deactivate };
