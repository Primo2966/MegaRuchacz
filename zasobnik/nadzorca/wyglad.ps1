# zasobnik\nadzorca\wyglad.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Stan okna - wszystkie zmienne $script: okna ustawione na start
# (kontrolki, dane, stan liczenia w tle) - oraz wyglad: kolory, czcionki,
# szerokosci liczone z ekranu, typ MegaRuchacz.Pulpit (ShowWindow) i
# Wymus-Pokazanie.
# Skad wolane: wszystkie pozostale moduly okna czytaja te zmienne; Wymus-Pokazanie
# wola okno.ps1. Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii, jako
# PIERWSZY modul okna - tu kod wykonuje sie przy wczytaniu (tak samo, jak dawniej
# w tym miejscu nadzorca.ps1).

# --- stan okna ---------------------------------------------------------------
$script:Okno           = $null
$script:Ikona          = $null
$script:Naglowek       = $null   # pasek u gory: tytul, podtytul, przelacznik widokow
$script:LPodtytul      = $null
$script:BPrzeglad      = $null   # przelacznik [Przeglad | Szczegoly]
$script:BSzczegoly     = $null
$script:WidokPrzeglad  = $null   # karty - przewijane tylko wtedy, gdy ekran jest za niski
$script:WidokSzczegoly = $null   # karty sekcji szczegolow, przewijane
$script:Root           = $null
$script:PanelProblemy  = $null
$script:PanelLiczby    = $null
$script:PanelStan      = $null
$script:ListaSzczegolow = $null  # karty sekcji w zakladce Szczegoly (od 25.09.2026 zamiast jednego pola tekstu)
$script:KartaStart     = $null   # karta "Otwarcie sesji" na Przegladzie
$script:KartaWerdykt   = $null   # jedno zdanie na samej gorze: MegaRuchacz kosztuje malo / duzo / nie wiadomo (P15)
# Pomiar otwarcia sesji z transkryptow (Pomiar-Startu). Liczony przy otwarciu okna
# (gdy nie ma swiezego) i przy recznym przeliczeniu - nie w dozorze co kwadrans,
# bo nikt go wtedy nie oglada.
$script:Start          = $null
$script:UdzialStartu   = 0.0
# Dzienne zuzycie tokenow w rozmowach z Claude (Zuzycie-Dzienne, P17) - jedyne
# sensowne porownanie dla kosztu nauki. Liczone w osobnym procesie; gdy trwa,
# zegar co 3 s zaglada do pliku podrecznego i odmalowuje okno po wyniku.
$script:Zuzycie        = $null
$script:ZegarZuzycia   = $null
# Prawdziwy koszt dnia (Koszt-Dzis, P26): dzis rozmowy kontra workerzy, najdrozsi
# workerzy, najdluzsze rozmowy. Karta na Przegladzie i sekcja w Szczegolach.
$script:KosztDzis      = $null
$script:KartaKoszt     = $null
$script:PodgladInfo    = $null   # dwie kolumny nad trescia podgladu warstwy
$script:BWarstwy       = $null   # trzeci przycisk przelacznika
$script:WidokWarstwy   = $null   # warstwy pamieci: lista po lewej, podglad po prawej
$script:LWarstwy       = $null   # jedno zdanie podsumowania nad lista
$script:ListaWarstw    = $null
$script:PodgladWarstwy = $null
# Odpowiedz Warstwy-Pamieci - liczona dopiero przy wejsciu w zakladke, bo wola
# osobny proces, a przeglad ma sie otwierac bez czekania.
$script:DaneWarstw     = $null
# Zakladka "Skille" (P18): lista po lewej (wiersze-karty, bo opis ma sie zawinac,
# a nie uciac trzema kropkami), szczegoly i przyciski po prawej.
$script:BSkille        = $null   # czwarty przycisk przelacznika
$script:WidokSkille    = $null
$script:LSkille        = $null   # zdanie o bezpieczenstwie + podsumowanie
$script:BSkilleTeraz   = $null   # "Sprawdz teraz" - wszystkie skille
$script:ListaSkilli    = $null   # przewijany panel z wierszami
$script:SkilleInfo     = $null   # dwie kolumny o wybranym skillu
$script:SkillePrzyciski = $null
$script:BSkillInstaluj = $null
$script:BSkillAktualizuj = $null
$script:BSkillCofnij   = $null
$script:BSkillUsun     = $null   # "Usun u mnie" - tylko skill usuniety przez autora (P20)
$script:GrupySkilli    = @{}     # rozwiniete grupy (id zrodla -> $true), do zamkniecia okna
$script:NaglowkiGrup   = @{}     # id -> naglowek grupy (przewijanie do niego po kliknieciu)
$script:ZnacznikiGrup  = @{}     # id -> kolor paska z lewej naglowka albo $null
$script:SkillePodglad  = $null   # co sie zmienilo / wynik operacji
$script:DaneSkilli     = $null   # odpowiedz Stan-Skilli
$script:SkillWybrany   = ""
$script:WierszeSkilli  = @{}
$script:ZegarSkilli    = $null
$script:SkilleOperacjaOd = $null
$script:SkilleOperacjaOpis = ""
$script:Pasek          = $null
$script:BAktualizuj    = $null
$script:LAktualizuj    = $null
$script:BCykl          = $null
$script:LCykl          = $null
$script:PanelZmian     = $null   # linie zmian w pamieci, schowane pod "pokaz zmiany"
$script:LinkZmian      = $null
# Rozwiniecie listy zmian przezywa przeliczenie okna - inaczej lista zwijalaby
# sie sama co kwadrans, w trakcie czytania.
$script:ZmianyRozwiniete = $false
$script:Widok          = "przeglad"
# Dane, z ktorych rysuje sie wykres w zdarzeniu Paint - procedura obslugi siega
# wylacznie po $script:, wiec odkladamy je tutaj przy kazdym zlozeniu wykresu
# (od P35 karta w Szczegolach, Panel-Wykresu).
$script:StatWykresu    = $null
# Jednostka osi wykresu (Ustaw-Miare-Wykresu): od P17 zawsze tysiace tokenow.
$script:WykresDz       = 1000.0
$script:WykresProc     = $false
# Wywrotka rysowania meldowana RAZ, a nie przy kazdym odmalowaniu - Paint
# przychodzi dziesiatki razy na minute i zasypalby dziennik.
$script:RysowanieZawiodlo = $false
$script:RamkaZawiodla     = $false

# Bufor: ostatnio zebrane liczby i GODZINA, z ktorej pochodza. Ta godzina jest
# pokazywana zawsze - okno, ktore pokazuje stare liczby jako biezace, klamie.
$script:Dane      = $null
$script:DaneCzas  = $null
$script:DaneBlad  = $null
$script:Rozbicie  = $null   # rozbicie rachunku liczymy dopiero, gdy ktos otworzy szczegoly
$script:Wywrotki  = @()
$script:Licze     = $false
$script:Problemy  = @()
# Gdy widok szczegolow pokazuje cudzy tekst (odpowiedz straznika po pobraniu
# nowszej wersji), przeliczenie danych NIE ma go podmieniac - uzytkownik
# czytalby wtedy co innego, niz przed chwila kliknal.
$script:SzczegolyZajete = $false
# Liczenie w tle i ekran ladowania (P21) - opis przy Rusz-Krok.
$script:StanKawalkow   = @{}     # UWAGA: nie "$script:Kawalki" - PowerShell nie rozroznia wielkosci liter, to bylby $KAWALKI. id kawalka danych -> Czas, Nieudany, Krok (trwajacy), Ostatni
$script:KolejkaKrokow  = New-Object System.Collections.ArrayList   # czekaja na wolne miejsce
$script:KrokiAktywne   = New-Object System.Collections.ArrayList   # otwieraja watek albo licza
$script:WolniRobotnicy = New-Object System.Collections.ArrayList   # otwarte watki bez pracy
$script:Zombie         = New-Object System.Collections.ArrayList   # przerwane po limicie, do sprzatniecia
$script:ZegarKrokow    = $null
$script:KrokDozoru     = $null
$script:CzasyKrokow    = @{}     # id -> ile trwal ostatnio (s), do paska postepu
$script:BladZegaraKrokow = ""
$script:Ladowanie      = $null   # ekran ladowania na wierzchu: widok, kawalki, kroki, od, BladOd
$script:WidokLadowania = $null
$script:ListaKrokow    = $null
$script:WierszeKrokow  = @{}
$script:PasekLadowania = $null
$script:PostepLadowania = 0.0
$script:LLadowanieTytul = $null
$script:LLadowanieOpis = $null
$script:LLadowanieStopka = $null
$script:BPokazTeraz    = $null
$script:TykKrokow      = 0
$script:DoOdmalowania  = @{ przeglad = $true; szczegoly = $true; warstwy = $true; skille = $true }
$script:SkillePoOperacji = $null
$script:PolozenieOkna  = $null   # gdzie uzytkownik zostawil okno - nastepne otwarcie stanie tam samo
$script:PrzydzialPoPokazaniu = $false   # w trakcie budowy okna kroki tylko staja w kolejce (P21)

# --- wyglad ------------------------------------------------------------------
# KOLOR TYLKO TAM, GDZIE NIESIE ZNACZENIE. Czerwony wylacznie przy sprawie,
# ktora wymaga dzialania, zolty przy "czegos nie wiem" i przy informacji,
# zielony przy jednym zdaniu "wszystko gra", bursztyn na slupku dnia
# nadrabiania (ten sam ton, co zolta informacja o nim). Cala reszta jest szara
# albo granatowo-szara. Tecza w oknie uczy ignorowania kolorow.
$script:KolTekst  = [System.Drawing.Color]::FromArgb(28, 28, 30)
$script:KolSzary  = [System.Drawing.Color]::FromArgb(106, 108, 112)
$script:KolPilne  = [System.Drawing.Color]::FromArgb(176, 32, 32)
$script:KolUwaga  = [System.Drawing.Color]::FromArgb(146, 98, 0)
$script:KolDobrze = [System.Drawing.Color]::FromArgb(24, 104, 56)
$script:TloPilne  = [System.Drawing.Color]::FromArgb(253, 236, 236)
$script:TloUwaga  = [System.Drawing.Color]::FromArgb(255, 248, 227)
$script:TloPaska  = [System.Drawing.Color]::FromArgb(250, 250, 251)
$script:TloOkna   = [System.Drawing.Color]::FromArgb(243, 244, 246)
$script:TloKarty  = [System.Drawing.Color]::White
$script:TloPrzel  = [System.Drawing.Color]::FromArgb(228, 230, 234)
$script:TloZnacz  = [System.Drawing.Color]::FromArgb(238, 240, 243)
$script:KolRamki  = [System.Drawing.Color]::FromArgb(224, 226, 230)
$script:KolSiatki = [System.Drawing.Color]::FromArgb(236, 237, 240)
$script:KolOsi    = [System.Drawing.Color]::FromArgb(200, 203, 208)
$script:KolSlupek = [System.Drawing.Color]::FromArgb(92, 108, 130)
$script:KolNadrab = [System.Drawing.Color]::FromArgb(214, 160, 52)
$script:KolNiezn  = [System.Drawing.Color]::FromArgb(176, 182, 190)
# Pasek otwarcia sesji: MegaRuchacz spokojnym niebieskim (to jedyny akcent
# w oknie, ktory nie jest sygnalem ostrzezenia), Claude Code jasnoszarym tlem.
$script:KolMr     = [System.Drawing.Color]::FromArgb(47, 95, 168)
$script:KolCc     = [System.Drawing.Color]::FromArgb(214, 218, 224)
$script:PioroRamki = New-Object System.Drawing.Pen($script:KolRamki)

# Hierarchia robi sie krojem i wielkoscia, nie kolorem. Czcionki sa WSPOLNE dla
# wszystkich etykiet - tworzone przy kazdym odmalowaniu wyciekalyby uchwytami GDI.
# "Segoe UI Semibold" jest w kazdym Windows 10/11; gdyby go nie bylo, Windows
# podstawia zwykly kroj - okno dalej dziala, tylko ciensze.
$script:CzDuza        = New-Object System.Drawing.Font("Segoe UI Semibold", 20)
$script:CzTytul       = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$script:CzGruba       = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
$script:CzSrednia     = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$script:CzZwykla      = New-Object System.Drawing.Font("Segoe UI", 9.75)
$script:CzZwyklaGruba = New-Object System.Drawing.Font("Segoe UI Semibold", 9.75)
$script:CzMala        = New-Object System.Drawing.Font("Segoe UI", 8.75)
$script:CzMalaGruba   = New-Object System.Drawing.Font("Segoe UI Semibold", 8.75)
$script:CzStala       = New-Object System.Drawing.Font("Consolas", 9.5)
$script:CzStalaMala   = New-Object System.Drawing.Font("Consolas", 9)

# Szerokosci - od 25.09.2026 liczone z ekranu, a nie na sztywno. Uzytkownik:
# "wez cale te okna szersze zrob, bardziej czytelne". Okno ma do 1240 px wnetrza
# (na 1920 i 2560 px szerokosci - tyle; na malym ekranie mniej, ale nigdy
# szerzej niz obszar roboczy minus 80 px i nigdy wezej niz 900). Tresc to okno
# minus marginesy po 28 px i 20 px na pionowy suwak, gdy ekran jest za niski -
# suwak poziomy nie ma prawa sie pojawic, a tekst wyjezdzajacy poza krawedz
# bylby ucieciem po cichu.
$script:ObszarEkranu = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:SzerOkna    = [int][math]::Max(900, [math]::Min(1240, $script:ObszarEkranu.Width - 80))
$script:Margines    = 28
$script:SzerTresc   = $script:SzerOkna - 2 * $script:Margines - 20
$script:SzerKarty   = $script:SzerTresc
$script:Odstep      = 16
$script:SzerEtykiety = 220   # lewa kolumna w karcie stanu i w szczegolach

# ZLAPANE 24.09.2026 NA PROBIE Z PRAWDZIWYM OKNEM, i to jest dokladnie ten rodzaj
# usterki, dla ktorego istnieje zasada "cisza jest zakazana": proces startowany
# z ukryta konsola (-WindowStyle Hidden, a tak wlasnie robi to zadanie
# w Harmonogramie) przekazuje SW_HIDE ze STARTUPINFO pierwszemu oknu, jakie
# stworzy. Form.Show() konczy sie wtedy bez bledu, okno POWSTAJE - i jest
# niewidzialne. Uzytkownik klikalby ikone i nie dzialoby sie NIC, bez sladu
# w dzienniku. Dlatego po kazdym Show() wymuszamy pokazanie wprost.
Add-Type -Namespace MegaRuchacz -Name Pulpit -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr uchwyt, int jak);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr uchwyt);
'@
$SW_POKAZ = 5   # SW_SHOW

function Wymus-Pokazanie($formularz) {
  try {
    [MegaRuchacz.Pulpit]::ShowWindow($formularz.Handle, $SW_POKAZ) | Out-Null
    [MegaRuchacz.Pulpit]::SetForegroundWindow($formularz.Handle) | Out-Null
  } catch { Zanotuj-Wywrotke "wymuszenie pokazania okna" $_ }
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["wyglad"] = $true
