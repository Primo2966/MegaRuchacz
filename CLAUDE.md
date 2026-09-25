# MegaRuchacz — repozytorium narzędzia

Zasady kierownika są globalne: blok `MegaRuchacz:kierownik` w `~/.claude/CLAUDE.md`.
Ich źródło to `szablony-global/claude/zasady-kierownika.md` — zmienia się je tam
i wgrywa przez `narzedzia\instaluj-globalnie.ps1`, nigdy ręcznie. Tu stoi wyłącznie
to, co dotyczy budowania samego MegaRuchacza.

## Cisza jest zakazana

Ustalone 2026-09-17, po tym jak jednego dnia złamaliśmy tę zasadę w trzech
niezależnych miejscach. Dotyczy wszystkiego, co budujemy w tym projekcie.

**Nic nie ma prawa zawieść bez śladu.** Konkretnie:

- **Sufit nie ucina — sufit krzyczy.** Gdy tekst nie mieści się w limicie, na jego
  POCZĄTKU ma stanąć ostrzeżenie (początek przeżywa ucięcie zawsze), a narzędzie,
  które ten tekst składa, ma odmówić zapisu zamiast zapisać kadłubek i zameldować
  sukces.
- **Brak wiadomości nie może znaczyć „wszystko gra".** Każdy mechanizm chodzący
  w tle zostawia znacznik „byłem tu"; jego nieświeżość sama w sobie jest alarmem.
- **Puste `catch { }` jest zabronione.** Wolno nie przerywać pracy, nie wolno
  milczeć: błąd idzie do stanu i jest meldowany przy następnej okazji.
- **Liczba bez jednostki użytkownika to kłamstwo.** „Na wiadomość" i „na sesję" to
  różne pieniądze; mnożenie przez zmyśloną stałą („sesji na dobę") zaciemnia
  zamiast wyjaśniać.
- **Fałszywy alarm jest gorszy niż brak alarmu** — uczy ignorować ostrzeżenia.
  Alarm ma mieć próg z uzasadnieniem zapisanym obok, a nie liczbę z powietrza.

**Każde zabezpieczenie wymaga próby negatywnej.** Zabezpieczenie, którego nikt nie
próbował złamać, było 2026-09-17 martwe w trzech przypadkach na trzy — zawsze
wyglądało na działające. Dopóki nie widziałeś, jak reaguje na złamanie, nie liczy
się za zrobione.
