# zasobnik\nadzorca\stan-zuzycie.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Dzienne zuzycie tokenow w rozmowach z Claude:
# licznik w C# ($KOD_LICZNIKA_ZUZYCIA, Wczytaj-Licznik-Tokenow), ciezkie liczenie
# (Policz-Zuzycie) w osobnym procesie (Odpal-Liczenie-Zuzycia - wczytuje od nowa
# stan-nadzorcy.ps1 z $script:NadzTenPlik), tani odczyt dla okna (Zuzycie-Dzienne)
# i teksty (Tokeny-Okolo, Procent-Udzialu, Udzial-W-Dniu, Teksty-Nauki).
# Skad wolane: kroki w tle w w-tle.ps1, tryb -Raport w nadzorca.ps1, karty
# Przegladu, stan-koszt.ps1 (ten sam licznik). Wczytuje go stan-nadzorcy.ps1
# kropka - poza stalymi same definicje.

# ------------------------------------------- dzienne zuzycie tokenow w rozmowach
#
# P17 (28.09.2026). Uzytkownik o karcie nauki: "te 20%, to nie wiem czego. Moze
# nie ma sensu tego wyrazac procentem, bo nie wiem, z czym to zestawic". Mial
# racje - procent otwarcia okna rozmowy nie ma sensu przy koszcie DZIENNYM.
# Koszt nauki pokazujemy wiec w tokenach, a jedyne porownanie, jakie ma sens,
# to udzial w CALYM dziennym zuzyciu tokenow w rozmowach z Claude na tym
# komputerze.
#
# SKAD LICZBA. Transkrypty Claude Code (<dom>\.claude\projects\**\*.jsonl,
# z podagentami, ktorzy maja osobne pliki w ...\subagents\). Kazda odpowiedz
# modelu ma message.usage; sumujemy input_tokens + cache_creation_input_tokens
# + cache_read_input_tokens + output_tokens - te same cztery pola, z ktorych
# lore\lore\facts.py liczy koszt nauki (TOKEN_FIELDS), wiec obie liczby sa
# policzone tak samo i procent jest uczciwy. Claude Code zapisuje jedna
# odpowiedz w kilku liniach (po jednej na blok tresci) - liczymy kazde
# message.id raz. Wejscie i bufor sa w tych liniach takie same, ale output_tokens
# w pierwszej linii bywa czesciowy (np. 8 zamiast 224), wiec z linii tego samego
# id bierzemy NAJWIEKSZE wartosci (P26 - do 30.09.2026 brana byla pierwsza linia
# i odpowiedzi modelu wychodzily 3,8 raza za nisko). Czas z pola timestamp
# (UTC) -> dzien lokalny. Workerzy (podagenci) to pliki w ...\subagents\ -
# od P26 ich tokeny liczymy tez osobno.
# Ostatnie $DNI_ZUZYCIA PELNYCH dni (bez dzisiejszego, ktory jeszcze trwa),
# suma dzielona przez liczbe dni - takze tych, w ktorych rozmow nie bylo.
#
# BUFOR. cache_read_input_tokens to tekst, ktory model czyta ponownie z pamieci
# podrecznej - kosztuje ok. 1/10 ceny. Liczymy go do glownej liczby (tak jak
# w koszcie nauki), a drobnym drukiem mowimy, ile go jest i ile wychodzi bez niego.
#
# WYDAJNOSC. Pliki waza setki MB (28.09.2026: 150 plikow, ~330 MB w 7 dniach).
# Liczy je kawalek C# czytajacy strumieniowo, linia po linii, bez parsowania JSON
# (ok. 2 s). Wynik dnia idzie do pliku podrecznego; okno go tylko czyta, a gdy
# go brak - odpala liczenie w OSOBNYM procesie i odmalowuje sie, gdy wynik
# przyjdzie. Okno nie czeka.
#
# CISZA. Brak katalogu, brak rozmow, wywrotka - kazde zostawia Powod, a okno
# pisze "nie mam z czym porownac, bo ...". Nigdy zero i nigdy zgadnieta liczba.
# Zawieszone liczenie (slad "liczy_od" bez wyniku) po $MINUT_LICZENIA_ZUZYCIA
# minutach tez jest powodem, a nie wiecznym "licze".
$DNI_ZUZYCIA = 7
# Wersja 2 (P26, 30.09.2026): odpowiedzi modelu jako NAJWIEKSZA wartosc z linii tego
# samego message.id (wersja 1 brala pierwsza, czesciowa linie i zanizala je 3,8 raza:
# 1 909 596 zamiast 7 215 577 za 23-29.09) i podzial na rozmowy oraz workerow. Plik
# podreczny w starszej wersji liczy sie od nowa.
$WERSJA_ZUZYCIA = "2"
# Liczenie trwa ok. 2 s (pomiar 28.09.2026); 10 minut to zapas na wolny dysk
# i kilka razy wiecej transkryptow, a po nim wiadomo na pewno, ze proces zniknal.
$MINUT_LICZENIA_ZUZYCIA = 10
# Nieudane liczenie (np. brak katalogu) powtarzamy najwyzej co godzine - dosc
# czesto, zeby naprawa byla widac tego samego dnia, i dosc rzadko, zeby okno
# nie odpalalo procesu przy kazdym odmalowaniu.
$MINUT_PONOWIENIA_ZUZYCIA = 60
$script:NadzZuzycieOdpalone = $null

$KOD_LICZNIKA_ZUZYCIA = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace MegaRuchacz.Tokeny {
  // Nowe nazwy (P26), a nie poprawione stare: proces, ktory wczytal juz stary licznik
  // (MegaRuchacz.LicznikZuzycia), dostalby przy Add-Type blad "typ juz istnieje".
  public class Dzien {
    public long Wejscie, Tworzenie, Odczyt, Wyjscie, Odpowiedzi;
    // to samo, co wyzej, rozdzielone: glowne pliki rozmow i workerzy (pliki w ...\subagents\)
    public long Rozmowy, Workerzy, OdpowiedziRozmow, OdpowiedziWorkerow;
  }
  public class Plik {
    public string Sciezka;
    public bool Worker;
    public long Tokeny, Wywolania;                   // odpowiedzi z liczonego okresu
    public long Kontekst = -1;                       // ostatnie wywolanie: wejscie + zapis i odczyt bufora
    public DateTime Ostatnio = DateTime.MinValue;    // czas tego wywolania (UTC)
    public string Tytul = "";                        // custom-title albo ai-title (tylko rozmowy)
    public string Cwd = "";                          // katalog, w ktorym szla rozmowa
  }
  public class Wynik {
    public Dictionary<string, Dzien> Dni = new Dictionary<string, Dzien>();
    public List<Plik> PlikiZOdpowiedziami = new List<Plik>();
    public int Pliki, Nieczytelne, Duble;
    public long Bajty, Linie;
    public List<string> Bledy = new List<string>();
  }
  class Odpowiedz {
    public string Dzien;
    public int Plik;
    public long We, Tw, Od, Wy;
  }
  public static class Licznik {
    static long Liczba(string l, string klucz, int od) {
      int i = l.IndexOf(klucz, od, StringComparison.Ordinal);
      if (i < 0) return -1;
      i += klucz.Length;
      long v = 0; bool jest = false;
      while (i < l.Length && l[i] >= '0' && l[i] <= '9') { v = v * 10 + (l[i] - '0'); i++; jest = true; }
      return jest ? v : -1;
    }
    // Tekst po kluczu ("aiTitle":"...") do najblizszego cudzyslowu bez ukosnika,
    // z odkodowaniem \" \\ \/ \uXXXX; znaki konca linii jako spacja.
    static string Tekst(string l, string klucz) {
      int i = l.IndexOf(klucz, StringComparison.Ordinal);
      if (i < 0) return null;
      i += klucz.Length;
      var sb = new System.Text.StringBuilder();
      while (i < l.Length && sb.Length < 400) {
        char c = l[i];
        if (c == '"') break;
        if (c == '\\' && i + 1 < l.Length) {
          char n = l[i + 1];
          if (n == 'u' && i + 5 < l.Length) {
            int kod;
            if (int.TryParse(l.Substring(i + 2, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out kod)) sb.Append((char)kod);
            i += 6; continue;
          }
          if (n == 'n' || n == 'r' || n == 't') sb.Append(' '); else sb.Append(n);
          i += 2; continue;
        }
        sb.Append(c); i++;
      }
      return sb.ToString();
    }
    // Linia odpowiedzi modelu: "message":{ ... "role":"assistant" ... "usage":{ ...
    // W tekstach JSON cudzyslowy sa zapisane jako \" - wiec te wzorce trafiaja
    // tylko w prawdziwe klucze, nigdy w tresc rozmowy.
    // zPlikami: dodatkowo dla kazdego pliku suma z okresu, rozmiar ostatniego
    // wywolania, tytul rozmowy i katalog (prawdziwy koszt dnia, P26).
    public static Wynik Policz(string[] pliki, DateTime odDnia, DateTime doDniaWylacznie, bool zPlikami) {
      var w = new Wynik();
      var odp = new Dictionary<string, Odpowiedz>(StringComparer.Ordinal);
      var bezId = new List<Odpowiedz>();
      var info = new Plik[pliki.Length];
      for (int nr = 0; nr < pliki.Length; nr++) {
        string p = pliki[nr];
        var pl = new Plik();
        pl.Sciezka = p;
        pl.Worker = p.IndexOf("\\subagents\\", StringComparison.OrdinalIgnoreCase) >= 0;
        info[nr] = pl;
        string tytulAi = null, tytulWlasny = null;
        try {
          using (var s = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 1 << 16))
          using (var r = new StreamReader(s)) {
            w.Pliki++;
            w.Bajty += s.Length;
            string l;
            while ((l = r.ReadLine()) != null) {
              w.Linie++;
              int u = l.IndexOf("\"usage\":{", StringComparison.Ordinal);
              if (u < 0) {
                // Tytul rozmowy - krotkie linie typu ai-title / custom-title (wlasny ma pierwszenstwo).
                if (zPlikami && !pl.Worker && l.Length < 4096) {
                  if (l.IndexOf("\"type\":\"custom-title\"", StringComparison.Ordinal) >= 0) { string t = Tekst(l, "\"customTitle\":\""); if (!string.IsNullOrEmpty(t)) tytulWlasny = t; }
                  else if (l.IndexOf("\"type\":\"ai-title\"", StringComparison.Ordinal) >= 0) { string t = Tekst(l, "\"aiTitle\":\""); if (!string.IsNullOrEmpty(t)) tytulAi = t; }
                }
                continue;
              }
              int m = l.IndexOf("\"message\":{", StringComparison.Ordinal);
              if (m < 0 || m > u) continue;
              int rola = l.IndexOf("\"role\":\"assistant\"", m, StringComparison.Ordinal);
              if (rola < 0 || rola > u) continue;
              int t0 = l.LastIndexOf("\"timestamp\":\"", StringComparison.Ordinal);
              if (t0 < 0) { w.Nieczytelne++; continue; }
              t0 += 13;
              int k = l.IndexOf('"', t0);
              DateTime czas;
              if (k < 0 || !DateTime.TryParse(l.Substring(t0, k - t0), CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out czas)) { w.Nieczytelne++; continue; }
              long we = Liczba(l, "\"input_tokens\":", u);
              long tw = Liczba(l, "\"cache_creation_input_tokens\":", u);
              long od = Liczba(l, "\"cache_read_input_tokens\":", u);
              long wy = Liczba(l, "\"output_tokens\":", u);
              if (we < 0 && wy < 0) { w.Nieczytelne++; continue; }
              if (zPlikami) {
                // Rozmiar rozmowy w tej chwili = kontekst OSTATNIEGO wywolania (tyle czyta kazdy
                // nastepny krok). Odpowiedzi "<synthetic>" (komunikaty samego Claude Code) maja zera.
                int syn = l.IndexOf("\"model\":\"<synthetic>\"", m, StringComparison.Ordinal);
                long kont = Math.Max(0, we) + Math.Max(0, tw) + Math.Max(0, od);
                if ((syn < 0 || syn > u) && kont > 0 && czas >= pl.Ostatnio) { pl.Kontekst = kont; pl.Ostatnio = czas; }
                if (pl.Cwd.Length == 0) { string c = Tekst(l, "\"cwd\":\""); if (!string.IsNullOrEmpty(c)) pl.Cwd = c; }
              }
              DateTime dzien = czas.ToLocalTime().Date;
              if (dzien < odDnia || dzien >= doDniaWylacznie) continue;
              string id = null;
              int ii = l.IndexOf("\"id\":\"", m, StringComparison.Ordinal);
              if (ii >= 0 && ii < u) {
                ii += 6;
                int ki = l.IndexOf('"', ii);
                if (ki > ii) id = l.Substring(ii, ki - ii);
              }
              Odpowiedz o;
              if (id != null && odp.TryGetValue(id, out o)) {
                // Kolejna linia tej samej odpowiedzi: pierwsza ma output_tokens czesciowy,
                // wiec zostaje najwieksza wartosc z wszystkich linii tego id (P26).
                w.Duble++;
                if (we > o.We) o.We = we;
                if (tw > o.Tw) o.Tw = tw;
                if (od > o.Od) o.Od = od;
                if (wy > o.Wy) o.Wy = wy;
                continue;
              }
              o = new Odpowiedz();
              o.Dzien = dzien.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
              o.Plik = nr;
              o.We = Math.Max(0, we); o.Tw = Math.Max(0, tw); o.Od = Math.Max(0, od); o.Wy = Math.Max(0, wy);
              if (id != null) odp[id] = o; else bezId.Add(o);
            }
          }
        } catch (Exception e) {
          if (w.Bledy.Count < 5) w.Bledy.Add(Path.GetFileName(p) + ": " + e.Message);
          else w.Bledy.Add("");
        }
        pl.Tytul = tytulWlasny ?? tytulAi ?? "";
      }
      foreach (var o in odp.Values) Dodaj(w, info[o.Plik], o);
      foreach (var o in bezId) Dodaj(w, info[o.Plik], o);
      if (zPlikami) {
        foreach (var pl in info) { if (pl.Wywolania > 0 || pl.Kontekst > 0) w.PlikiZOdpowiedziami.Add(pl); }
      }
      return w;
    }
    static void Dodaj(Wynik w, Plik pl, Odpowiedz o) {
      Dzien z;
      if (!w.Dni.TryGetValue(o.Dzien, out z)) { z = new Dzien(); w.Dni[o.Dzien] = z; }
      long razem = o.We + o.Tw + o.Od + o.Wy;
      z.Wejscie += o.We; z.Tworzenie += o.Tw; z.Odczyt += o.Od; z.Wyjscie += o.Wy; z.Odpowiedzi++;
      if (pl.Worker) { z.Workerzy += razem; z.OdpowiedziWorkerow++; }
      else { z.Rozmowy += razem; z.OdpowiedziRozmow++; }
      pl.Tokeny += razem; pl.Wywolania++;
    }
  }
}
'@

# Plik podreczny wyniku dnia. W trybie probnym NIE w katalogu domowym ("-Proba
# nic nie zapisuje"), tylko w katalogu tymczasowym, osobno dla kazdego
# podstawionego katalogu domowego - proba negatywna nie miesza sie z prawdziwa.
function Plik-Zuzycia {
  if ($script:NadzProba) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $h = [BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:NadzDom.ToLowerInvariant()))).Replace("-", "").Substring(0, 12)
    return (Join-Path ([System.IO.Path]::GetTempPath()) "megaruchacz-proba-zuzycie-$h.txt")
  }
  return (Join-Path $script:NadzDom ".claude\.megaruchacz-zuzycie.txt")
}

# Kompilacja licznika - raz na proces (typ zostaje w procesie do konca). Dwa watki
# okna naraz go nie kompiluja (krok liczy sie najwyzej raz), ale gdyby jednak:
# blad "typ juz istnieje" przy gotowym typie nie jest bledem.
function Wczytaj-Licznik-Tokenow {
  if ('MegaRuchacz.Tokeny.Licznik' -as [type]) { return }
  try { Add-Type -TypeDefinition $KOD_LICZNIKA_ZUZYCIA -ErrorAction Stop }
  catch { if (-not ('MegaRuchacz.Tokeny.Licznik' -as [type])) { throw } }
}

# CIEZKIE liczenie - wolane w osobnym procesie (Odpal-Liczenie-Zuzycia) albo
# wprost w wydruku -Raport, gdzie nikt nie czeka na okno. Zawsze konczy sie
# zapisem pliku: z wynikiem albo z powodem.
function Policz-Zuzycie {
  $plik = Plik-Zuzycia
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $dzis = [datetime]::Today
  $wynik = [ordered]@{ wersja = $WERSJA_ZUZYCIA; dzien = $dzis.ToString('yyyy-MM-dd') }
  try {
    $slad = Czytaj-Klucze $plik
    $slad["liczy_od"] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Zapisz-Klucze $plik $slad
  } catch { Zanotuj-Wywrotke "slad startu liczenia zuzycia" $_ }
  try {
    $od = $dzis.AddDays(-$DNI_ZUZYCIA)
    $wynik["od"] = $od.ToString('yyyy-MM-dd')
    $wynik["do"] = $dzis.AddDays(-1).ToString('yyyy-MM-dd')
    $wynik["dni"] = $DNI_ZUZYCIA
    $katalog = Join-Path $script:NadzDom ".claude\projects"
    if (-not (Test-Path -LiteralPath $katalog)) {
      $wynik["powod"] = "nie ma katalogu z Twoimi rozmowami z Claude Code ($katalog)"
    } else {
      $pliki = @(Get-ChildItem -LiteralPath $katalog -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue -ErrorVariable bledyListy |
                 Where-Object { $_.LastWriteTime -ge $od } | ForEach-Object { $_.FullName })
      if (@($bledyListy).Count -gt 0) { $wynik["bledy_listy"] = @($bledyListy).Count }
      $wynik["pliki"] = $pliki.Count
      if ($pliki.Count -eq 0) {
        $wynik["powod"] = "w ostatnich $DNI_ZUZYCIA dniach nie było na tym komputerze ani jednej rozmowy z Claude"
      } else {
        Wczytaj-Licznik-Tokenow
        $w = [MegaRuchacz.Tokeny.Licznik]::Policz([string[]]$pliki, $od, $dzis, $false)
        $we = [long]0; $tw = [long]0; $odc = [long]0; $wy = [long]0; $odp = [long]0
        $roz = [long]0; $wor = [long]0; $odpR = [long]0; $odpW = [long]0
        foreach ($d in $w.Dni.Values) {
          $we += $d.Wejscie; $tw += $d.Tworzenie; $odc += $d.Odczyt; $wy += $d.Wyjscie; $odp += $d.Odpowiedzi
          $roz += $d.Rozmowy; $wor += $d.Workerzy; $odpR += $d.OdpowiedziRozmow; $odpW += $d.OdpowiedziWorkerow
        }
        $razem = $we + $tw + $odc + $wy
        $wynik["mb"] = [long][math]::Round($w.Bajty / 1MB)
        $wynik["odpowiedzi"] = $odp
        $wynik["dni_z_rozmowami"] = $w.Dni.Count
        $wynik["wejscie"] = $we; $wynik["tworzenie"] = $tw; $wynik["odczyt"] = $odc; $wynik["wyjscie"] = $wy
        $wynik["razem"] = $razem
        # P26: te same tokeny rozdzielone - Twoje rozmowy (glowne okna) i workerzy.
        $wynik["rozmowy"] = $roz; $wynik["workerzy"] = $wor
        $wynik["odpowiedzi_rozmow"] = $odpR; $wynik["odpowiedzi_workerow"] = $odpW
        if ($razem -gt 0) {
          $wynik["srednia_rozmowy"] = [long][math]::Round($roz / [double]$DNI_ZUZYCIA)
          $wynik["srednia_workerzy"] = [long][math]::Round($wor / [double]$DNI_ZUZYCIA)
        }
        $wynik["duble"] = $w.Duble
        $wynik["nieczytelne"] = $w.Nieczytelne
        if ($w.Bledy.Count -gt 0) {
          $wynik["bledy"] = $w.Bledy.Count
          $wynik["blad"] = (($w.Bledy | Where-Object { $_ } | Select-Object -First 1) -replace '[\r\n]+', ' ')
        }
        if ($razem -le 0) {
          $wynik["powod"] = "w $($pliki.Count) $(Odmiana $pliki.Count 'pliku' 'plikach' 'plikach') rozmów z ostatnich $DNI_ZUZYCIA dni nie znalazłem ani jednej odpowiedzi Claude z liczbą tokenów"
          if ($w.Bledy.Count -gt 0) { $wynik["powod"] += " (nie dało się otworzyć $($w.Bledy.Count), np. $($wynik['blad']))" }
        } else {
          $wynik["srednia"] = [long][math]::Round($razem / [double]$DNI_ZUZYCIA)
          $wynik["srednia_bez_bufora"] = [long][math]::Round(($razem - $odc) / [double]$DNI_ZUZYCIA)
        }
      }
    }
  } catch {
    Zanotuj-Wywrotke "liczenie dziennego zuzycia tokenow" $_
    $wynik["powod"] = "liczenie się wywróciło: $(($_.Exception.Message -replace '[\r\n]+', ' ').Trim())"
  }
  $wynik["sekundy"] = [math]::Round($sw.Elapsed.TotalSeconds, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
  $wynik["wyliczono"] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  try { Zapisz-Klucze $plik $wynik }
  catch { Zanotuj-Wywrotke "zapis dziennego zuzycia tokenow do $plik" $_ }
  Notuj "zuzycie tokenow policzone w $($wynik['sekundy']) s: $(if ($wynik['powod']) { 'BEZ WYNIKU - ' + $wynik['powod'] } else { 'srednio ' + $wynik['srednia'] + ' dziennie z ' + $wynik['pliki'] + ' plikow' })"
  return $wynik
}

# Liczenie w osobnym, niewidocznym procesie. Ten sam plik wczytany od nowa,
# te same ustawienia (zrodlo, dom, proba). Zamek "Local\MegaRuchacz-Zuzycie"
# pilnuje, zeby dwa okna nie liczyly naraz. W tym procesie najwyzej raz na
# $MINUT_LICZENIA_ZUZYCIA - kolejne odmalowania okna tylko czytaja plik.
function Odpal-Liczenie-Zuzycia {
  $teraz = [datetime]::Now
  if ($script:NadzZuzycieOdpalone -and (($teraz - $script:NadzZuzycieOdpalone).TotalMinutes -lt $MINUT_LICZENIA_ZUZYCIA)) { return $true }
  if (-not $script:NadzTenPlik -or -not (Test-Path -LiteralPath $script:NadzTenPlik)) {
    Zanotuj-Wywrotke "start liczenia zuzycia" "nie znam sciezki stan-nadzorcy.ps1 ($($script:NadzTenPlik))"
    return $false
  }
  $cyt = { param($t) "'" + ("$t" -replace "'", "''") + "'" }
  $proba = '$false'
  if ($script:NadzProba) { $proba = '$true' }
  $polecenie = (". $(& $cyt $script:NadzTenPlik); Ustaw-Nadzorce $(& $cyt $script:NadzZrodlo) $(& $cyt $script:NadzDom) $proba; " +
                "`$z = New-Object System.Threading.Mutex(`$false, 'Local\MegaRuchacz-Zuzycie'); " +
                "`$moj = `$false; try { `$moj = `$z.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { `$moj = `$true }; " +
                "if (`$moj) { Policz-Zuzycie | Out-Null } else { Notuj 'zuzycie tokenow: inny proces juz liczy' }")
  $kod = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($polecenie))
  $ogon = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $kod"
  $script:NadzZuzycieOdpalone = $teraz
  try {
    Start-Process -FilePath "conhost.exe" -ArgumentList ("--headless powershell.exe " + $ogon) -WindowStyle Hidden -ErrorAction Stop | Out-Null
    return $true
  } catch { Notuj "liczenie zuzycia: conhost --headless nie wystartowal, probuje zwyklym powershellem" }
  try {
    Start-Process -FilePath "powershell.exe" -ArgumentList $ogon -WindowStyle Hidden -ErrorAction Stop | Out-Null
    return $true
  } catch { Zanotuj-Wywrotke "start liczenia zuzycia w tle" $_; return $false }
}

# Odczyt dla okna - TANI: plik podreczny i ewentualnie odpalenie liczenia.
# $czekaj = $true (wydruk -Raport) liczy na miejscu, gdy wyniku z dzis nie ma.
# Stan: "jest" (Srednia), "licze" (za chwile bedzie) albo "brak" (Powod).
function Zuzycie-Dzienne([bool]$czekaj = $false) {
  $z = [pscustomobject]@{
    Stan = "brak"; Powod = ""; Srednia = $null; SredniaBezBufora = $null; Razem = $null; Odczyt = $null
    Dni = $DNI_ZUZYCIA; DniZRozmowami = $null; Od = $null; Do = $null; Pliki = $null; Mb = $null
    Odpowiedzi = $null; Sekundy = ""; Wyliczono = $null; Plik = ""
    # P26: podzial na Twoje rozmowy i workerow, odpowiedzi modelu (wyjscie)
    Rozmowy = $null; Workerzy = $null; SredniaRozmowy = $null; SredniaWorkerow = $null; Wyjscie = $null
  }
  $plik = Plik-Zuzycia
  $z.Plik = $plik
  $k = Czytaj-Klucze $plik
  $dzis = [datetime]::Today.ToString('yyyy-MM-dd')
  $swiezy = ("$($k['wersja'])" -eq $WERSJA_ZUZYCIA) -and ("$($k['dzien'])" -eq $dzis) -and ($k['srednia'] -or $k['powod'])
  if (-not $swiezy -and $czekaj) {
    $null = Policz-Zuzycie
    $k = Czytaj-Klucze $plik
    $swiezy = ("$($k['wersja'])" -eq $WERSJA_ZUZYCIA) -and ("$($k['dzien'])" -eq $dzis) -and ($k['srednia'] -or $k['powod'])
    if (-not $swiezy) { $z.Powod = "liczenie nie zapisało wyniku do $plik"; return $z }
  }
  if ($swiezy) {
    $z.Wyliczono = Data-Lub-Nic $k['wyliczono']
    $z.Srednia = Liczba-Z-Klucza $k "srednia"
    $z.SredniaBezBufora = Liczba-Z-Klucza $k "srednia_bez_bufora"
    $z.Razem = Liczba-Z-Klucza $k "razem"
    $z.Odczyt = Liczba-Z-Klucza $k "odczyt"
    $z.DniZRozmowami = Liczba-Z-Klucza $k "dni_z_rozmowami"
    $z.Pliki = Liczba-Z-Klucza $k "pliki"
    $z.Mb = Liczba-Z-Klucza $k "mb"
    $z.Odpowiedzi = Liczba-Z-Klucza $k "odpowiedzi"
    $z.Rozmowy = Liczba-Z-Klucza $k "rozmowy"
    $z.Workerzy = Liczba-Z-Klucza $k "workerzy"
    $z.SredniaRozmowy = Liczba-Z-Klucza $k "srednia_rozmowy"
    $z.SredniaWorkerow = Liczba-Z-Klucza $k "srednia_workerzy"
    $z.Wyjscie = Liczba-Z-Klucza $k "wyjscie"
    $z.Od = Data-Lub-Nic $k['od']
    $z.Do = Data-Lub-Nic $k['do']
    $z.Sekundy = "$($k['sekundy'])"
    if (($null -ne $z.Srednia) -and ($z.Srednia -gt 0) -and (-not $k['powod'])) {
      $z.Stan = "jest"
    } else {
      $z.Powod = "$($k['powod'])"
      if (-not $z.Powod) { $z.Powod = "liczenie zapisało wynik bez średniej ($plik)" }
      if ((-not $czekaj) -and $z.Wyliczono -and (([datetime]::Now - $z.Wyliczono).TotalMinutes -ge $MINUT_PONOWIENIA_ZUZYCIA) -and (-not $k['liczy_od'])) {
        $null = Odpal-Liczenie-Zuzycia
      }
    }
    return $z
  }
  # Wyniku z dzis nie ma: albo liczenie wlasnie trwa, albo sie zawiesilo, albo
  # trzeba je odpalic.
  $lo = Data-Lub-Nic $k['liczy_od']
  if ($lo -and (([datetime]::Now - $lo).TotalMinutes -lt $MINUT_LICZENIA_ZUZYCIA)) { $z.Stan = "licze"; return $z }
  if ($lo) {
    $z.Powod = "liczenie ruszyło o $($lo.ToString('HH:mm')) i nie skończyło się w $MINUT_LICZENIA_ZUZYCIA minut"
    $null = Odpal-Liczenie-Zuzycia
    return $z
  }
  $byl = $script:NadzZuzycieOdpalone
  if ($byl -and (([datetime]::Now - $byl).TotalMinutes -ge 2) -and (([datetime]::Now - $byl).TotalMinutes -lt $MINUT_LICZENIA_ZUZYCIA)) {
    $z.Powod = "liczenie odpalone o $($byl.ToString('HH:mm')) nie zostawiło śladu w $plik"
    return $z
  }
  if (Odpal-Liczenie-Zuzycia) { $z.Stan = "licze" }
  else { $z.Powod = "nie udało się uruchomić liczenia w tle (szczegóły w dzienniku nadzorcy)" }
  return $z
}

# Liczby tokenow po ludzku (P17): "~40 000", "~193 mln", "~5,2 mln". Dokladna
# liczba stoi obok tam, gdzie ma znaczenie.
function Tokeny-Okolo($n) {
  if ($null -eq $n) { return "?" }
  $v = [double]$n
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($v -ge 1e9) { return "~" + ($v / 1e9).ToString("0.#", $pl) + " mld" }
  if ($v -ge 1e7) { return "~" + ([math]::Round($v / 1e6)).ToString("0", $pl) + " mln" }
  if ($v -ge 1e6) { return "~" + ($v / 1e6).ToString("0.#", $pl) + " mln" }
  if ($v -ge 1e4) { return "~" + (Liczba-Ludzka ([long]([math]::Round($v / 1000.0) * 1000))) }
  if ($v -ge 1e3) { return "~" + (Liczba-Ludzka ([long]([math]::Round($v / 100.0) * 100))) }
  return (Liczba-Ludzka ([long]$v))
}

# Udzial w procentach z tyloma miejscami po przecinku, ile trzeba, zeby nie
# wyszlo zero: 12%, 3,4%, 0,21%, 0,021%. Ponizej 0,001% - "mniej niż 0,001%".
function Procent-Udzialu([double]$czesc, [double]$calosc) {
  if ($calosc -le 0) { return "" }
  $p = 100.0 * $czesc / $calosc
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($p -ge 10) { return "$([int][math]::Round($p))%" }
  if ($p -ge 1) { return ($p.ToString("0.#", $pl) + "%") }
  if ($p -ge 0.1) { return ($p.ToString("0.0#", $pl) + "%") }
  if ($p -ge 0.01) { return ($p.ToString("0.0##", $pl) + "%") }
  if ($p -ge 0.001) { return ($p.ToString("0.000", $pl) + "%") }
  if ($p -gt 0) { return "mniej niż 0,001%" }
  return "0%"
}

# "ok. 0,02% wszystkich tokenów, które zużywasz dziennie w rozmowach z Claude
# (średnio ~193 mln dziennie)" - albo pusty tekst, gdy nie ma z czym porownac.
function Udzial-W-Dniu($tokeny, $z) {
  if (($null -eq $tokeny) -or (-not $z) -or ($z.Stan -ne "jest")) { return "" }
  return "ok. $(Procent-Udzialu ([double]$tokeny) ([double]$z.Srednia)) wszystkich tokenów, które zużywasz dziennie w rozmowach z Claude (średnio $(Tokeny-Okolo $z.Srednia) dziennie)"
}

# Zdanie, gdy porownania nie ma. Nigdy zero - mowimy dlaczego.
function Bez-Porownania($z) {
  if ($z -and ($z.Stan -eq "licze")) { return "porównanie z całym Twoim dziennym zużyciem jeszcze się liczy - za kilka sekund będzie" }
  $p = "nie wiem, ile tokenów zużywasz dziennie"
  if ($z -and $z.Powod) { $p = $z.Powod }
  return "nie mam z czym porównać, bo $p"
}

# Drobny druk pod porownaniem: co liczymy, z ilu dni, i ile z tego to tanie
# tokeny z pamieci podrecznej. Uczciwie obie liczby - glowna i bez bufora.
function Drobny-Druk-Zuzycia($z, $tokenyNauki) {
  if (-not $z -or ($z.Stan -ne "jest")) { return "" }
  $okres = ""
  if ($z.Od -and $z.Do) { $okres = "$($z.Od.ToString('dd'))–$($z.Do.ToString('dd.MM'))" }
  if ($null -ne $z.DniZRozmowami) { $okres = (@($okres, "rozmowy w $($z.DniZRozmowami)") | Where-Object { $_ }) -join ", " }
  if ($okres) { $okres = " ($okres)" }
  # Jedna linia drobnego druku - okno ma sie miescic bez przewijania.
  $t = "Średnia z $($z.Dni) dni na tym komputerze$okres. Liczę wszystkie tokeny"
  if (($null -ne $z.Odczyt) -and ($null -ne $z.Razem) -and ($z.Razem -gt 0) -and ($null -ne $z.SredniaBezBufora)) {
    # 1/10 - cena odczytu z pamieci podrecznej wzgledem zwyklego wejscia w cenniku Anthropic.
    $t += ": $(Procent-Udzialu ([double]$z.Odczyt) ([double]$z.Razem)) to tekst czytany ponownie z pamięci podręcznej, 10× tańszy;"
    $t += " bez niego $(Tokeny-Okolo $z.SredniaBezBufora)/dzień"
    if (($null -ne $tokenyNauki) -and ($z.SredniaBezBufora -gt 0)) {
      $t += ", a to czytanie - najwyżej $(Procent-Udzialu ([double]$tokenyNauki) ([double]$z.SredniaBezBufora))"
    }
  }
  return "$t."
}

# Teksty karty nauki (P17) - jedne dla okna i dla wydruku -Raport. $t to wynik
# Liczba-Nauki. Duza liczba to TOKENY; pod nia jedno zdanie porownania z calym
# dziennym zuzyciem albo "nie mam z czym porownac, bo ...".
function Teksty-Nauki($t, $z) {
  $x = [pscustomobject]@{ Duza = ""; Jednostka = ""; Porownanie = ""; PorownanieJest = $false; Drobny = "" }
  if (-not $t -or ($null -eq $t.Liczba)) { return $x }
  $x.Duza = Tokeny-Okolo $t.Liczba
  $ogon = ""
  if ($t.Ogon) { $ogon = ", $($t.Ogon)" }
  $x.Jednostka = "tokenów dziennie - tyle kosztuje jedno takie czytanie (dokładnie $(Liczba-Ludzka $t.Liczba)$ogon)"
  $ud = Udzial-W-Dniu $t.Liczba $z
  if ($ud) {
    $x.Porownanie = "To $ud."
    $x.PorownanieJest = $true
    $x.Drobny = Drobny-Druk-Zuzycia $z $t.Liczba
  } else {
    $x.Porownanie = (Z-Wielkiej (Bez-Porownania $z)) + "."
  }
  return $x
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["zuzycie"] = $true
