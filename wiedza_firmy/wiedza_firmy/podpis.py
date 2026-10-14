"""Podpis prosby o token (POST /klient/token) kluczem komputera ed25519 - tym samym, ktorego klucz publiczny
JFTools podaje w GET keys ("ssh-ed25519 <base64>", jak w ecommerce-helper: id_ed25519 bez hasla).

Podpisywany tekst (umowa, raport wiedza-firmy-krok3-projekt.md sekcja 2), kodowany UTF-8, BEZ konca linii:

    jfwiedza-token|{computerId}|{ts}|{nonce}

computerId i ts to liczby calkowite zapisane dziesietnie bez zer z przodu (ts = sekundy Unix), nonce to
16-128 znakow [A-Za-z0-9_-]. Serwer sklada tekst sam z pol zadania - klient nie przysyla tekstu.

Serwer przyjmuje dwie postacie pola `podpis` (klient wybiera jedna, obie sprawdzane tak samo surowo):

1. surowy podpis ed25519 (64 bajty) zakodowany base64 (standardowy alfabet, z dopelnieniem `=`), np. z
   `cryptography`: base64(Ed25519PrivateKey.sign(tekst.encode("utf-8")));
2. podpis OpenSSH (SSHSIG, caly blok "-----BEGIN SSH SIGNATURE----- ... -----END SSH SIGNATURE-----")
   w przestrzeni nazw PRZESTRZEN_SSHSIG, czyli wynik `ssh-keygen -Y sign -n jfwiedza -f <klucz> <plik>`,
   gdzie plik zawiera dokladnie tekst powyzej (bez konca linii). Klucz publiczny wewnatrz SSHSIG musi byc
   tym samym kluczem, ktory JFTools ma dla tego komputera.

Klient narzedzia/wiedza-firmy-klient/klient.py (Klucz.podpisz) uzywa postaci 1 - pilnuje tego test zgodnosci
w tests/test_klienci.py. Postac 2 to zapasowa droga bez biblioteki cryptography po stronie klienta.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import re
import struct

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

PRZESTRZEN_SSHSIG = "jfwiedza"
_POCZATEK_SSHSIG = "-----BEGIN SSH SIGNATURE-----"
_KONIEC_SSHSIG = "-----END SSH SIGNATURE-----"
_HASZE_SSHSIG = {"sha256": hashlib.sha256, "sha512": hashlib.sha512}
_BASE64 = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")
# Najdluzszy sensowny podpis (SSHSIG z kluczem ed25519 to ok. 300 znakow) - wiecej = smiec, nie dekodujemy.
MAKS_DLUGOSC_PODPISU = 4096


class BladPodpisu(ValueError):
    """Podpis nie przechodzi - komunikat mowi dlaczego (bez tresci podpisu)."""


def tekst_do_podpisu(komputer: str, ts: int, nonce: str) -> str:
    return f"jfwiedza-token|{komputer}|{ts}|{nonce}"


def _napis(blob: bytes, poz: int) -> tuple[bytes, int]:
    """Pole 'string' z formatu SSH: uint32 dlugosc + bajty."""
    if poz + 4 > len(blob):
        raise BladPodpisu("uciety blok SSH")
    (dlugosc,) = struct.unpack(">I", blob[poz:poz + 4])
    poz += 4
    if poz + dlugosc > len(blob):
        raise BladPodpisu("uciety blok SSH")
    return blob[poz:poz + dlugosc], poz + dlugosc


def _ssh_napis(dane: bytes) -> bytes:
    return struct.pack(">I", len(dane)) + dane


def blob_klucza(klucz_ssh: str) -> bytes:
    """Blob klucza "ssh-ed25519 <base64>" (komentarz za nim pomijany) - te same kontrole co wtyczka (rules.ts)."""
    czesci = (klucz_ssh or "").strip().split()
    if len(czesci) < 2 or czesci[0] != "ssh-ed25519" or not _BASE64.match(czesci[1]):
        raise BladPodpisu("klucz komputera w JFTools nie jest kluczem ssh-ed25519")
    blob = base64.b64decode(czesci[1])
    typ, poz = _napis(blob, 0)
    surowy, poz = _napis(blob, poz)
    if typ != b"ssh-ed25519" or len(surowy) != 32 or poz != len(blob):
        raise BladPodpisu("klucz komputera w JFTools jest uszkodzony")
    return blob


def _klucz(blob: bytes) -> Ed25519PublicKey:
    _typ, poz = _napis(blob, 0)
    surowy, _ = _napis(blob, poz)
    return Ed25519PublicKey.from_public_bytes(surowy)


def _sprawdz_sshsig(blob_klucza_jftools: bytes, tekst: bytes, podpis: str) -> None:
    linie = [l.strip() for l in podpis.strip().splitlines()]
    if not linie or linie[0] != _POCZATEK_SSHSIG or linie[-1] != _KONIEC_SSHSIG:
        raise BladPodpisu("blok SSHSIG bez naglowka albo stopki")
    try:
        blob = base64.b64decode("".join(linie[1:-1]), validate=True)
    except (binascii.Error, ValueError):
        raise BladPodpisu("blok SSHSIG nie jest base64") from None
    if blob[:6] != b"SSHSIG":
        raise BladPodpisu("blok SSHSIG bez sygnatury formatu")
    if len(blob) < 10 or struct.unpack(">I", blob[6:10])[0] != 1:
        raise BladPodpisu("nieznana wersja SSHSIG")
    klucz, poz = _napis(blob, 10)
    przestrzen, poz = _napis(blob, poz)
    zarezerwowane, poz = _napis(blob, poz)
    hasz, poz = _napis(blob, poz)
    sygnatura, poz = _napis(blob, poz)
    if poz != len(blob):
        raise BladPodpisu("blok SSHSIG ma nadmiarowe bajty")
    if klucz != blob_klucza_jftools:
        raise BladPodpisu("SSHSIG podpisany innym kluczem niz klucz komputera w JFTools")
    if przestrzen != PRZESTRZEN_SSHSIG.encode():
        raise BladPodpisu(f"SSHSIG w przestrzeni nazw innej niz {PRZESTRZEN_SSHSIG!r}")
    funkcja = _HASZE_SSHSIG.get(hasz.decode("ascii", "replace"))
    if funkcja is None:
        raise BladPodpisu("SSHSIG z nieobslugiwana funkcja skrotu")
    typ, p2 = _napis(sygnatura, 0)
    surowy, p2 = _napis(sygnatura, p2)
    if typ != b"ssh-ed25519" or len(surowy) != 64 or p2 != len(sygnatura):
        raise BladPodpisu("SSHSIG nie jest podpisem ssh-ed25519")
    podpisane = (b"SSHSIG" + _ssh_napis(przestrzen) + _ssh_napis(zarezerwowane) + _ssh_napis(hasz)
                 + _ssh_napis(funkcja(tekst).digest()))
    try:
        _klucz(klucz).verify(surowy, podpisane)
    except InvalidSignature:
        raise BladPodpisu("podpis SSHSIG nie pasuje do tekstu i klucza") from None


def sprawdz(klucz_ssh: str, tekst: str, podpis: str) -> None:
    """Nic = podpis dobry. Kazda inna sytuacja (zly format, inny klucz, inny tekst) = BladPodpisu."""
    if not isinstance(podpis, str) or not podpis.strip():
        raise BladPodpisu("brak podpisu")
    if len(podpis) > MAKS_DLUGOSC_PODPISU:
        raise BladPodpisu("podpis za dlugi")
    blob = blob_klucza(klucz_ssh)
    dane = tekst.encode("utf-8")
    if podpis.lstrip().startswith(_POCZATEK_SSHSIG):
        _sprawdz_sshsig(blob, dane, podpis)
        return
    surowy_tekst = podpis.strip()
    if not _BASE64.match(surowy_tekst):
        raise BladPodpisu("podpis nie jest base64 ani blokiem SSHSIG")
    try:
        surowy = base64.b64decode(surowy_tekst, validate=True)
    except (binascii.Error, ValueError):
        raise BladPodpisu("podpis nie jest poprawnym base64") from None
    if len(surowy) != 64:
        raise BladPodpisu("podpis ed25519 ma 64 bajty")
    try:
        _klucz(blob).verify(surowy, dane)
    except InvalidSignature:
        raise BladPodpisu("podpis nie pasuje do tekstu i klucza komputera") from None
