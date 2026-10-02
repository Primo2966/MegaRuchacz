
## 2026-10-01 — do zrobienia po wlaczeniu domowego PC

- [x] Nowe zdanie o awansie faktu (0.24.1) wgrac do zasad na komputerze DOMOWYM: `narzedzia\wpisz-zasady.ps1` (biuro zrobione 01.10 10:09, "Co wiem" nietkniete). DOM: wgral sam straznik 01.10 17:05 przy aktualizacji (Claude Code i Codex), "Co wiem" w AGENTS.md identyczne z kopia .bak-20261001-170504.
- [x] Dom (`D:\OrcaSpace\MegaRuchacz`, SSH przez Tailscale — `~\.claude\wiedza\polaczenia-ssh.md`): sprawdzic, czy straznik SAM pobral nowa wersje (0.24.1, test naprawy P36: brudny rejestr nie blokuje juz aktualizacji). Porownac `git log -1` domu z GitHubem; jesli w tyle — opisac dlaczego, nie aktualizowac recznie git. Potem restart nadzorcy w domu (zadanie `MegaRuchaczNadzorca`). WYNIK 01.10: dom = 6d2a733 (0.25.1) = GitHub; pobral przycisk w nadzorcy 17:05 (0.23.1 -> 0.25.1, mimo niesledzonych raportow), nie straznik przy starcie; nadzorca zrestartowany 17:10, dozor OK; Defender bez nowych wykryc.
- Kolejka z poprzedniej rundy: P37 (przycisk aktualizacji pokazuje powod, petla w Rachunek-Rozbicie, zawieszanie przy nieistniejacym -KatalogDomowy), P28b (podzial straznika na moduly) — szczegoly w `.megaruchacz/raporty/PRZEKAZANIE-2026-09-30.md`.

## 2026-10-02 - dom po przepisaniu historii na GitHubie (P67)

- [ ] Dom (D:\OrcaSpace\MegaRuchacz): historia na GitHubie zostala przepisana (usuniete prywatne dane). Straznik w domu zobaczy 'historie rozjechana' i nie pobierze nowej wersji. Naprawa przez SSH: kopia calego .megaruchacz\ (przed 02.10 raporty byly sledzone - reset by je skasowal), potem git fetch i git reset --hard origin/main, przywrocenie plikow z kopii, restart nadzorcy. Szczegoly: raport P67 na komputerze biurowym.

