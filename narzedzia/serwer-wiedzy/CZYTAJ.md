# Serwer „Wiedza firmy” na Pakowanie2 — wdrożenie krok po kroku

Dla kierownika. Wszystko z biurowego PC przez SSH; na Pakowanie2 nie ma gita ani uv,
jest Python 3.12 systemowy (`C:\Program Files\Python312\python.exe`) i pip.

Układ na Pakowanie2:

| Co | Gdzie |
|---|---|
| program (venv, kod, skrypty) | `C:\dev\wiedza-firmy\` |
| kod serwera (podmienia go samoaktualizacja) | `C:\dev\wiedza-firmy\kod\` (`wiedza_firmy\` + `lore\lore\`) |
| skrypty wdrożenia | `C:\dev\wiedza-firmy\narzedzia\` |
| model mmlw (przypięty, ~500 MB) | `%APPDATA%\wiedza-firmy\modele\` (`wiedza_firmy.sciezki`; poza kopią zapasową) |
| `LORE_HOME` (izolacja: lore nic nie zakłada w profilu) | `C:\dev\wiedza-firmy\lore-dane\` |
| znaczniki i dzienniki | `C:\dev\wiedza-firmy\stan\` (`straznik.json/.log`, `serwer.log`, `aktualizacja.json/.log`, `kopia.json/.log`, `pip.log`) |
| kopie zapasowe (14 dni) | `C:\dev\wiedza-firmy\kopie\RRRR-MM-DD_HHMMSS\` |
| konfiguracja | `C:\dev\wiedza-firmy\serwer-wiedzy.json` (port, moduł, argumenty, dane, drugi cel kopii) |
| **dane** (baza, tematy, osoby, `serwer-zyje.json`) | `%APPDATA%\wiedza-firmy\` — aktualizacja ani instalator tego nie ruszają |
| zadanie Harmonogramu | `WiedzaFirmyHttp` (BootTrigger 30 s, S4U, restart co 1 min) |
| zapora | `WiedzaFirmyHttp-TCP` (TCP 8766, tylko 192.168.0.0/24, 100.64.0.0/10, 127.0.0.1) |

Skrót do SSH (PowerShell na biurowym PC):

```powershell
$S = @('-F','C:/dev/.ssh/config','-o','IdentityFile=C:/dev/.ssh/id_ed25519','-o','UserKnownHostsFile=C:/dev/.ssh/known_hosts')
function P2([string]$polecenie) {   # dluzsze polecenia: zakodowane, bez klopotow z cudzyslowami
  $b = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($polecenie))
  ssh @S pakowanie2 "powershell -NoProfile -EncodedCommand $b" 2>&1 | Where-Object { "$_" -notmatch 'post-quantum|store now, decrypt later|upgraded|openssh.com/pq|CLIXML|<Objs' }
}
```

## 1. Zanim zaczniesz

- Kod `wiedza_firmy/` (z `pyproject.toml`) musi być w gałęzi `main` na GitHubie —
  instalator i samoaktualizacja biorą go z publicznego zipballa `Primo2966/MegaRuchacz`.
  Nie ma go jeszcze w `main`? Zbuduj archiwum lokalnie i podaj `-ZrodloKodu` (krok 3b).
- Sprawdź, jak moduł serwera się nazywa i jakie bierze argumenty. Domyślnie:
  `python -m wiedza_firmy.serwer --host 0.0.0.0 --port 8766`. Inna nazwa → `-Modul`;
  inne argumenty → popraw `argumenty` w `serwer-wiedzy.json` po instalacji
  (strażnik czyta go przy każdym starcie).
- Port 8766 musi być wolny: `P2 'Get-NetTCPConnection -LocalPort 8766 -State Listen'` (pusto = OK).
  **Nie** 8765 — tam stoi ecommerce-helper, a strażnik zamyka każdego pythona na swoim porcie.

## 2. Przegraj skrypty

```powershell
P2 'New-Item -ItemType Directory -Force C:\dev\wiedza-firmy-instalator | Out-Null'
scp @S C:\dev\claude-worker\narzedzia\serwer-wiedzy\* pakowanie2:C:/dev/wiedza-firmy-instalator/
```

## 3. Próba, potem instalacja

```powershell
# a) plan bez zmian
P2 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\wiedza-firmy-instalator\instaluj-serwer-wiedzy.ps1 -Proba'
# b) instalacja (konto użytkownik, sesja SSH ma uprawnienia administratora)
P2 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\wiedza-firmy-instalator\instaluj-serwer-wiedzy.ps1'
```

Instalacja pobiera model (~500 MB, `python -m wiedza_firmy.model`: przypięty commit,
sumy SHA-256, próbne załadowanie) — kilka minut. Każdy krok kończy się `[OK]` albo
`[BLAD] <co i gdzie szukać>`; po błędzie wystarczy poprawić przyczynę i uruchomić
instalator jeszcze raz (drugie uruchomienie niczego nie psuje, venv i model zostają).

Kod spoza GitHuba (3b): na biurowym PC

```powershell
git -C C:\dev\claude-worker archive --prefix=Primo2966-MegaRuchacz-lokalny/ -o C:\dev\wf.zip HEAD wiedza_firmy lore/lore lore/pyproject.toml
scp @S C:\dev\wf.zip pakowanie2:C:/dev/wiedza-firmy-instalator/
P2 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\wiedza-firmy-instalator\instaluj-serwer-wiedzy.ps1 -ZrodloKodu C:\dev\wiedza-firmy-instalator\wf.zip'
```

Potem samoaktualizacja co godzinę i tak sięga do GitHuba; dopóki w `main` nie ma
`wiedza_firmy/`, zostaje stary kod, a w `stan\aktualizacja.json` stoi błąd (widoczny,
nie cichy).

Ponowne wgranie skryptów (np. nowy strażnik) do działającej instalacji:
skopiuj pliki jak w kroku 2 i uruchom instalator z `-Restartuj`. Samoaktualizacja
podmienia **tylko** `kod\` — skrypty w `narzedzia\` zmieniają się wyłącznie przez instalator.

## 4. Pierwsza osoba (token wypisywany RAZ)

```powershell
P2 '& C:\dev\wiedza-firmy\venv\Scripts\python.exe C:\dev\wiedza-firmy\narzedzia\uruchom.py wiedza_firmy.osoby nowa primo --admin'
P2 '& C:\dev\wiedza-firmy\venv\Scripts\python.exe C:\dev\wiedza-firmy\narzedzia\uruchom.py wiedza_firmy.osoby nowa ela'
```

`uruchom.py` ustawia ścieżki do kodu (`kod\`) — samo `python -m wiedza_firmy.osoby` nie
zadziała, bo kod nie jest instalowany pip-em. Token zapisz od razu w bezpiecznym
miejscu (Menedżer poświadczeń na komputerze tej osoby), nie w repo i nie w czacie.
Tematy: `... uruchom.py wiedza_firmy.tematy wczytaj <plik.json>`; wsad:
`... uruchom.py wiedza_firmy.importuj <plik.md>`.

## 5. Sprawdzenie

```powershell
P2 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\wiedza-firmy\narzedzia\stan-serwera-wiedzy.ps1'
```

`[OK]`/`[UWAGA]`/`[ALARM]` + koniec `straznik.log`; kod wyjścia 1 = jest ALARM. Progi
(z uzasadnieniem w nagłówku skryptu): strażnik milczy > 5 min, port głuchy > 3 min od
startu serwera, serwer bez znaku życia (`serwer-zyje.json`) > 5 min, model w stanie BLAD,
problem z `osoby.json`, aktualizacja bez sukcesu > 24 h, kopia z błędem albo bez sukcesu > 26 h.
Zaraz po instalacji kopii jeszcze nie ma (robi się raz dziennie od 3:00, pierwsza przy
najbliższej okazji po 3:00) — ALARM „kopia nigdy nie przebiegła” jest wtedy prawdziwy.
Kopię na żądanie: `P2 '& C:\dev\wiedza-firmy\venv\Scripts\python.exe C:\dev\wiedza-firmy\narzedzia\kopia.py --kat C:\dev\wiedza-firmy'`.

Z biurowego PC: `http://<IP-LAN-Pakowanie2>:8766/mcp` (LAN) albo `http://<IP-Tailscale-Pakowanie2>:8766/mcp`
(Tailscale), nagłówek `Authorization: Bearer <token>`; bez tokenu ma być 401.

## 6. Zatrzymanie, restart, odinstalowanie

- `Stop-ScheduledTask WiedzaFirmyHttp` zatrzymuje **tylko strażnika** — python serwera
  dalej słucha. Restart: Stop + Start (nowy strażnik sam zamknie starego pythona na 8766)
  albo instalator z `-Restartuj`.
- Odinstalowanie (zadanie, zapora, procesy; dane, kopie i program zostają):
  `P2 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\wiedza-firmy\narzedzia\odinstaluj-serwer-wiedzy.ps1'`

## Pułapki

- Zadanie S4U nie dostaje zmiennych użytkownika — strażnik dociąga `WIEDZA_FIRMY_*`
  z `HKCU\Environment`. Inne zmienne trzeba nazwać z tym przedrostkiem.
- Strażnik ustawia procesowi serwera `WIEDZA_FIRMY_HOME` (= `dane` z `serwer-wiedzy.json`),
  `WIEDZA_FIRMY_PORT` i `LORE_HOME`. `uruchom.py` robi to samo dla poleceń przez SSH, więc
  `osoby`, `tematy`, `importuj` i `model` widzą te same dane co serwer.
- Ochrona przed DNS rebinding w serwerze włącza się zmienną `WIEDZA_FIRMY_HOSTY`
  (np. `<IP-LAN-Pakowanie2>,<IP-Tailscale-Pakowanie2>`). Ustaw ją jako zmienną użytkownika (HKCU) — strażnik
  ją dociągnie; bez niej serwer nie sprawdza nagłówka Host (token i tak jest wymagany).
- Dysku Google na Pakowanie2 nie ma (sprawdzone 14.10.2026: tylko C: i napęd D: CD,
  brak GoogleDriveFS). Gdyby doszedł: `-DrugiCelKopii <katalog>` przy instalacji — ale dysk
  G: montowany w sesji zalogowanego użytkownika może być niewidoczny dla zadania S4U;
  wtedy kopia ma status „częściowo” i ALARM w stanie, nie cichą dziurę.
- Wolny RAM na Pakowanie2 to ~2,4 GB (Chrome robota Alibaby); model mmlw w pamięci to
  kilkaset MB.
