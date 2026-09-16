#!/bin/sh
# Jednorazowe czyszczenie historii przed upublicznieniem repozytorium.
#
# Co robi:
#   1. podmienia adres e-mail autora we WSZYSTKICH commitach na adres
#      ukrywajacy tozsamosc, ktory GitHub i tak wiaze z kontem Primo2966
#      (autorstwo zostaje, znika tylko prywatny adres widoczny dla automatow),
#   2. usuwa z calej historii plik .claude/plan-repo.md - wewnetrzne notatki
#      z nazwa projektu firmowego,
#   3. wypycha przepisana historie na GitHuba.
#
# Uruchom w Git Bash:
#   sh /c/dev/claude-worker/wyczysc-historie.sh
#
# Po tym daj znac - przelacze repozytorium na publiczne.

set -e

cd /c/dev/claude-worker

NOWY="144699174+Primo2966@users.noreply.github.com"

echo "Przepisuje historie..."
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --env-filter "export GIT_AUTHOR_EMAIL='$NOWY'; export GIT_COMMITTER_EMAIL='$NOWY'" \
  --index-filter "git rm -q --cached --ignore-unmatch .claude/plan-repo.md" \
  -- --all

echo ""
echo "Adresy w historii po zmianie:"
git log --format='%ae' | sort -u

echo ""
echo "Czy plan-repo.md zniknal z historii (pusto = tak):"
git log --all --name-only --format= | sort -u | grep "plan-repo" || echo "  zniknal"

echo ""
echo "Wypycham..."
git push --force-with-lease origin main

echo ""
echo "GOTOWE. Powiedz MegaRuchaczowi, ze mozna publikowac."
