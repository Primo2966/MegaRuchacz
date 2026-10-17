"""Masking of passwords in addresses and after the word "hasło"/"password"."""

import pytest

from lore.masking import MASK, mask


@pytest.mark.parametrize(
    "text, secret",
    [
        ("DATABASE_URL=postgres://wms:Tajne123@10.0.0.5:5432/wms", "Tajne123"),
        ("polacz sie: postgresql://uzytkownik:haslo@host/baza", "haslo"),
        ("redis://:sekretny@localhost:6379", "sekretny"),
        ("mysql://root:p4ss@db", "p4ss"),
        ("Hasło: kot123", "kot123"),
        ("haslo=Zima2026", "Zima2026"),
        ("password: hunter2", "hunter2"),
        ("Password = abc", "abc"),
        ("hasło - Lato2025!", "Lato2025!"),
        ("hasło to Abc123", "Abc123"),
        ("haslo jest kot_7", "kot_7"),
        ("the password is s3cret", "s3cret"),
        ("HASŁO brzmi Wiosna1", "Wiosna1"),
    ],
)
def test_passwords_are_masked(text, secret):
    out = mask(text)
    assert secret not in out
    assert MASK in out
    assert "]]" not in out


def test_the_user_host_and_port_stay_readable():
    assert mask("postgres://wms:Tajne123@10.0.0.5:5432/wms") == (
        f"postgres://wms:{MASK}@10.0.0.5:5432/wms"
    )
    assert mask("Hasło: kot123") == f"Hasło: {MASK}"


@pytest.mark.parametrize(
    "text",
    [
        "https://example.com:8080/sciezka",
        "http://localhost:3000/api@v2",
        "zobacz https://tools.jfinvesting.pl/panel",
        "mailto:jan@example.com",
        "hasło to podstawa bezpieczeństwa",
        "Hasło jest w menedżerze haseł",
        "zmień hasło do konta Amazon",
        "the password is stored in the vault",
        "password reset link wysłany",
        "Hasło brzmi dobrze, zostaw je",
        "haslowanie i hasłowy nie są słowem hasło",
    ],
)
def test_ordinary_sentences_and_addresses_stay_untouched(text):
    assert mask(text) == text
