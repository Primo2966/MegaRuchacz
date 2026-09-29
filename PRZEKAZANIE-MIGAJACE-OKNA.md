# Przekazanie: migające okna konsoli w Orce

## Problem

Przy delegowaniu z Orki pojawiały się migające okna konsoli. Hooki MegaRuchacza są potrzebne, ponieważ zapisują zdarzenia `START` i `STOP` workerów do `.megaruchacz/worklog.md`; nie należało ich wyłączać tylko po to, aby ukryć okna.

## Stan wyjściowy

- Repozytorium przed tą pracą: MegaRuchacz `0.21.3`, `origin/main` na commicie `45fcda65ab8376d8a16fd178f4bc39d4d10d63a5`.
- Ustalenie diagnostyczne: przyczyną był sposób uruchamiania Codexa przez Orkę z zarządzanym daemonem, a nie zadania Lore ani sama logika hooków.

## Wdrożona zmiana lokalna

Praca została wykonana na **maszynie domowej**. W aktywnym profilu Orki ustawiono `settings.agentDefaultArgs.codex` na:

```text
--dangerously-bypass-approvals-and-sandbox --no-daemon
```

Obok bazy profilu utworzono kopię zapasową. Ta konfiguracja Orki leży poza repozytorium: ten commit dokumentuje jej stan, ale nie ustawia jej automatycznie na innej maszynie.

Nie patchowano binariów Codexa i nie wyłączano hooków. Hooki `START`/`STOP` nadal zapisują rejestr pracy.

## Dowód

Wykonano rzeczywisty test Codexa `0.158` z opcjami `--no-daemon --no-alt-screen --dangerously-bypass-hook-trust`. Delegacja utworzyła wpisy `START` i `STOP` w worklogu, a 45-sekundowy monitor nie wykrył widocznych okien konsoli.

## Co zrobić teraz

1. Zamknąć i ponownie otworzyć Orkę, aby wczytała zmianę profilu.
2. Wykonać kilka normalnych delegacji.
3. Sprawdzić, czy nie ma migających okien oraz czy `.megaruchacz/worklog.md` dostaje pary wpisów `START` i `STOP`.

## Dla kolejnego AI

Najpierw potwierdź wersję Codexa, argumenty aktywnego profilu Orki i zachowanie po restarcie aplikacji. Potem przetestuj delegację oraz wpisy worklogu. Jeśli problem wróci, nie wyłączaj hooków i nie modyfikuj binariów Codexa; porównaj tryb uruchamiania z `--no-daemon` i sprawdź konfigurację Orki poza repozytorium.
