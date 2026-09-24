"""The choice of material for the daily harvest — and the attempts to break it.

Every rule is tested both ways: the message it exists for goes in, and the message that only looks
like it stays out. A rule that nobody tried to fool is not counted as working.
"""

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timedelta, timezone

import pytest

from lore import facts, selection
from tests.test_facts import ago, answers, recorder, selective  # noqa: F401 — the fixture

REPLY = "Ustawiłem ceny FBM tak samo jak FBA, bo to prostsze w utrzymaniu."


def put(env, ts: str, role: str, text: str, session: str = "rozmowa-a", line: int = 1,
        part: int = 0, landed: str | None = None) -> int:
    """One chunk of a given conversation (its own file, like a real transcript)."""
    cur = env.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at)"
        " VALUES (?,?,?,?,?,?,?,?,?)",
        ("p", session, f"{session}.jsonl", line, part, ts, role, text, landed or ts))
    return cur.lastrowid


def chosen(env, since: str | None = None) -> list[selection.Message]:
    rows = env.conn.execute(
        "SELECT id, ts, session, file, line, part, role, text, indexed_at FROM chunks"
        " WHERE ts >= ? ORDER BY indexed_at, id", (since or ago(24 * 400),)).fetchall()
    return selection.choose(env.conn, rows).chosen


def texts(env, since: str | None = None) -> list[str]:
    return [m.text for m in chosen(env, since)]


# ---------------------------------------------------------------- corrections

@pytest.mark.parametrize("text", [
    "nie, ceny mają być jak FBM, nie ruszaj ich",
    "nei, sam nie wyliczaj",  # the typo the user really makes
    "przecież mówiłem, że sroper jest na koncie organizacji",
    "kurwa obudź się, pierwsze dwa słowa tytułu to nazwa zestawu",
    "miało być na laptopie, nie u mnie na pc",
    "czemu znowu wystawiasz na UK?",
    "no nie. to nie ta lokalizacja",
    "zostaw ceny w spokoju. mają być jak fbm",
])
def test_a_correction_after_a_reply_goes_in(selective, text):
    put(selective, ago(3), "assistant", REPLY, line=1)
    put(selective, ago(2), "user", text, line=2)

    (msg,) = chosen(selective)

    assert msg.reasons == [selection.CORRECTION] and msg.reply == REPLY


@pytest.mark.parametrize("text", [
    "sprawdź proszę raport sprzedaży z wczoraj",
    "nie rozumiem, co mam kliknąć",  # confusion, not a claim about how things are
    "a czemu w niektórych oknach mogę wybrać opus?",  # a real question
    "nie wiem, jak to zresetować",
    "Nie ma problemu, działaj dalej",  # "nie" opens it, but corrects nothing — see below
])
def test_an_ordinary_message_stays_out(selective, text):
    put(selective, ago(3), "assistant", REPLY, line=1)
    put(selective, ago(2), "user", text, line=2)

    picked = chosen(selective)

    # "nie ma problemu" is the one the openings are allowed to catch only through "nie ma opcji /
    # sensu / być" — it must stay out, or every polite answer becomes a correction
    assert picked == []


def test_a_correction_that_opens_a_conversation_corrects_nothing(selective):
    """The words alone are not enough: before the first message there is no reply to correct."""
    put(selective, ago(2), "user", "nie, zaczynamy od nowa: wystaw olejki na eBayu")

    assert chosen(selective) == []


def test_the_reply_from_an_earlier_indexing_pass_is_found(selective):
    """The reply was indexed yesterday, the correction today: the window holds only the correction,
    and the context still has to reach the model."""
    put(selective, ago(30), "assistant", "Dodałem nową miniaturkę obok starej.", line=5)
    put(selective, ago(2), "user", "przecież miałeś podmienić główną miniaturkę", line=6)

    (msg,) = chosen(selective, since=ago(5))

    assert msg.reply == "Dodałem nową miniaturkę obok starej."


def test_the_context_is_the_end_of_the_reply_and_it_is_short(selective):
    long_reply = "wstęp " * 200 + "OSTATNIE ZDANIE ODPOWIEDZI"
    put(selective, ago(3), "assistant", long_reply, line=1)
    put(selective, ago(2), "user", "nie, to nie tak", line=2)

    (msg,) = chosen(selective)
    piece = msg.piece()

    context = piece.split("\n")[1]
    assert context.startswith("model: …") and context.endswith("OSTATNIE ZDANIE ODPOWIEDZI")
    assert len(context) <= len("model: …") + selection.REPLY_CHARS


# ---------------------------------------------------------------- "zapamiętaj"

@pytest.mark.parametrize("text", [
    "zapamiętaj: nie ma danych brandowych z kwietnia 2026",
    "zapmaietaj że to ceny dla fbm",  # typed like this in the archive
    "Pamiętaj że na Anglię mają być oferty FBA",
    "zapisz sobie, że jfamazon.7m.pl już nie istnieje",
    "zapisz tez zasade do claude.md że ma prowadzić todo.md",
])
def test_remember_goes_in_always_even_opening_a_conversation(selective, text):
    put(selective, ago(2), "user", text)  # no reply before it — "zapamiętaj" needs none

    (msg,) = chosen(selective)

    assert selection.REMEMBER in msg.reasons


@pytest.mark.parametrize("text", [
    "pamiętasz te dublowane kadzidełka z wczoraj?",
    "nie pamiętam refresh tokena, sprawdź go",
    "zapisz plan do pliku",
    "zapisz to do planu",
])
def test_what_only_sounds_like_remember_stays_out(selective, text):
    put(selective, ago(2), "user", text)

    assert chosen(selective) == []


def test_remember_buried_in_the_middle_of_a_paste_does_not_count(selective):
    """A 20 000 character paste of a web page with "Zapamiętaj" somewhere inside is not the user
    asking for anything; he types before and after a paste, and only there is looked at."""
    paste = "Menu Search My business " * 400 + " zapamiętaj ustawienia strony " + "Orders " * 400
    put(selective, ago(2), "user", paste)

    assert chosen(selective) == []


def test_the_agents_words_pasted_back_are_not_the_user_correcting(selective):
    """Found in the archive: the user pastes the agent's own list back, and "za dużo" inside it was
    taken for his complaint. What sits inside the paste tags is not what he said."""
    put(selective, ago(3), "assistant", REPLY, line=1)
    put(selective, ago(2), "user", '<pasted_content id="d68b"> 9. Hako — za dużo znaków w opisie,'
        ' przecież to kurwa widać </pasted_content id="d68b"> popraw to', line=2)

    assert chosen(selective) == []


def test_the_users_own_words_after_a_paste_still_count(selective):
    put(selective, ago(3), "assistant", REPLY, line=1)
    put(selective, ago(2), "user", '<pasted_content id="1"> lista od agenta </pasted_content id="1">'
        " przecież mówiłem, że Hako pali stożki", line=2)

    (msg,) = chosen(selective)

    assert msg.reasons == [selection.CORRECTION]


def test_a_long_message_is_cut_in_the_middle_out_loud(selective):
    paste = "zapamiętaj: to jest wklejka " + "x" * 20_000 + " koniec wklejki"
    put(selective, ago(2), "user", paste)

    (msg,) = chosen(selective)
    piece = msg.piece()

    assert "zapamiętaj" in piece and "koniec wklejki" in piece
    assert "wycięto" in piece and len(piece) < 2_000


# ---------------------------------------------------------------- repetitions

MUST = "sroper trzymamy wyłącznie na koncie organizacji jf-investing, nigdy na moim prywatnym"
FILLER = ("wystaw {n} zapachów kadzidełek na eBayu", "sprawdź raport sprzedaży z dnia {n}",
          "ile kosztuje wysyłka paczki numer {n} do Niemiec", "popraw tytuł oferty olejku {n}",
          "uruchom robota alibaby i pokaż mi wiadomości od dostawcy {n}")


@pytest.fixture
def archive(selective):
    """The repetition weights are corpus statistics (Echoes): a real archive has thousands of
    messages, and a test with two would measure nothing. Sixty everyday ones, all older."""
    for n in range(60):
        put(selective, ago(24 * 60 + n), "user",
            FILLER[n % len(FILLER)].format(n=n) + ", zrób to jeszcze dzisiaj", session=f"codzienna-{n}")
    return selective


SAID_AGAIN = "sroper trzymamy tylko na koncie organizacji jf-investing, a nie na moim prywatnym"


def test_a_repetition_from_another_conversation_goes_in(archive):
    put(archive, ago(24 * 20), "user", MUST, session="rozmowa-stara")
    put(archive, ago(2), "user", SAID_AGAIN, session="rozmowa-nowa")

    (msg,) = chosen(archive, since=ago(5))

    assert msg.reasons == [selection.REPETITION]
    assert msg.echo == ago(24 * 20)
    assert "(to samo mówił już w innej rozmowie" in msg.piece()


def test_a_repetition_inside_the_same_conversation_does_not(archive):
    put(archive, ago(24 * 20), "user", MUST, session="rozmowa-a")
    put(archive, ago(2), "user", SAID_AGAIN, session="rozmowa-a")

    assert chosen(archive, since=ago(5)) == []


def test_the_same_text_carried_into_a_new_window_is_a_copy_not_a_repetition(archive):
    """Resuming a conversation copies it into a new session within hours — measured on the archive,
    every pair above 0.90 was exactly that."""
    put(archive, ago(5), "user", MUST, session="rozmowa-a")
    put(archive, ago(2), "user", MUST, session="rozmowa-a-wznowiona")

    assert chosen(archive, since=ago(3)) == []


def test_a_different_thing_in_another_conversation_is_not_a_repetition(archive):
    put(archive, ago(24 * 20), "user", MUST, session="rozmowa-stara")
    put(archive, ago(2), "user", "wystaw kadzidełka stożkowe na eBayu w wersji FBM, same DE",
        session="rozmowa-nowa")

    assert chosen(archive, since=ago(5)) == []


def test_a_too_small_archive_says_so_instead_of_finding_nothing_in_silence(selective, capsys):
    put(selective, ago(24 * 20), "user", MUST, session="rozmowa-stara")
    put(selective, ago(2), "user", SAID_AGAIN, session="rozmowa-nowa")

    chosen(selective, since=ago(5))

    assert "too few to tell a repeated claim" in capsys.readouterr().err




def test_the_threshold_sits_where_the_measurement_put_it():
    """Moving it is a decision with numbers behind it (see Echoes), not a tweak."""
    assert selection.ECHO_THRESHOLD == 0.40
    assert (selection.ECHO_MIN_CHARS, selection.ECHO_MAX_CHARS) == (40, 800)


# ---------------------------------------------------------------- where the messages live

def transcript(env, *turns: tuple[str, str], name: str = "sesja-glowna"):
    """A real transcript, indexed by the real indexer, its tail closed (the file is a day old)."""
    p = env.transcript(*turns, name=name)
    old = time.time() - 2 * 24 * 3600
    os.utime(p, (old, old))
    env.index(p)
    return p


def test_a_message_inside_a_glued_conversation_chunk_is_seen(selective):
    """The hole this module closes: short turns are glued into ONE chunk of role "conversation",
    and the harvest used to read only chunks of role "user"."""
    transcript(selective,
               ("user", "wystaw zestawy olejków na eBayu"),
               ("assistant", REPLY),
               ("user", "nie, ceny mają być jak FBM"))
    roles = [r[0] for r in selective.conn.execute("SELECT role FROM chunks")]
    assert roles == [selection.MIXED_ROLE]  # really glued — or this test proves nothing
    seen = []

    r = facts.run(ask=recorder(seen), conn=selective.conn)

    assert r["reviewed"] == 2 and r["candidates"] == 1 and r["reasons"] == {selection.CORRECTION: 1}
    assert "user: nie, ceny mają być jak FBM" in seen[0]
    assert "model: …" + REPLY in seen[0]
    assert "wystaw zestawy olejków" not in seen[0]  # an order, not a correction


def test_a_brief_for_a_subagent_never_goes_in_whatever_it_says(selective):
    """The manager's brief sits under "agent:user" — and it is full of exactly the words the rules
    look for. Indexed from a real subagent transcript, so the role is what the indexer really gives."""
    directory = selective.projects / "test-project" / "sesja-glowna" / "subagents"
    directory.mkdir(parents=True)
    p = directory / "agent-1.jsonl"
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        # a long brief is a chunk of its own ("agent:user"), the short turns get glued
        # ("agent:conversation") — both shapes have to stay out
        for role, text in (("user", "Zapamiętaj: nie, NIE ruszaj niczego poza listą. Przecież mówiłem. "
                                    + "Szczegóły zlecenia. " * 100),
                           ("assistant", "Rozumiem."),
                           ("user", "zapamiętaj to, kurwa"),
                           ("assistant", "Zrobione.")):
            f.write(json.dumps({"type": role, "sessionId": "sesja-glowna",
                                "timestamp": "2026-09-16T10:00:00.000Z",
                                "message": {"role": role, "content": text if role == "user" else
                                            [{"type": "text", "text": text}]}}) + "\n")
    old = time.time() - 2 * 24 * 3600
    os.utime(p, (old, old))
    selective.index(p)
    roles = {r[0] for r in selective.conn.execute("SELECT role FROM chunks")}
    assert {"agent:user", "agent:conversation"} <= roles  # both shapes, or this proves nothing
    assert all(role.startswith("agent:") for role in roles)
    seen = []

    r = facts.run(ask=recorder(seen), conn=selective.conn)

    assert (r["reviewed"], r["candidates"]) == (0, 0) and seen == []


def test_a_scheduled_task_prompt_is_not_chosen_even_asking_to_remember(selective):
    put(selective, ago(2), "user", '<scheduled-task name="x">\nZapamiętaj wynik i zapisz sobie raport')

    assert chosen(selective) == []


def test_parts_of_one_long_message_are_one_message(selective):
    """A turn longer than a chunk is stored in overlapping parts; cut apart, the "zapamiętaj" in the
    last part would be a message of its own without the beginning."""
    text = "a" * 1300 + "b" * 1300 + " zapamiętaj to"
    put(selective, ago(2), "user", text[:1500], line=3, part=0)
    put(selective, ago(2), "user", text[1300:], line=3, part=1)

    (msg,) = chosen(selective)

    assert msg.text == text


# ---------------------------------------------------------------- the run

def test_a_pass_that_chose_nothing_calls_nobody_and_still_moves_on(selective):
    """Reviewed is read: a message that was not chosen does not wait for anything. Without moving the
    marker the same window would be reviewed every day for ever."""
    put(selective, ago(3), "assistant", REPLY, line=1)
    last = put(selective, ago(2), "user", "sprawdź raport sprzedaży", line=2)
    facts.write_marker(ago(5))
    seen = []

    r = facts.run(ask=recorder(seen), conn=selective.conn)

    assert r["status"] == "no-material" and seen == []
    assert facts.since_marker() == facts.Marker(ago(2), last)
    assert facts.read_cost().get("wywolania", "0") == "0"


def test_a_dry_run_moves_nothing(selective):
    put(selective, ago(2), "user", "zwykła wiadomość")
    facts.write_marker(ago(5))

    facts.run(dry_run=True, ask=answers("nic"), conn=selective.conn)

    assert facts.since_marker().stamp == ago(5)
    assert not facts.learning_path().exists()


def test_the_model_is_told_not_to_take_facts_from_its_own_words():
    assert facts.run.__defaults__[1] is facts.ask_harvest
    assert "NIGDY nie bierz z linii \"model:\"" in facts.HARVEST_PROMPT
    assert facts.HARVEST_PROMPT.startswith(facts.PROMPT)


def test_what_day_zero_holds_back_counts_a_glued_chunk_of_the_user(selective):
    facts.DAY_ZERO_PATH.write_text(ago(1) + "\n", encoding="utf-8")
    put(selective, ago(5), "conversation", "assistant: " + REPLY + "\n\nuser: nie, źle")
    put(selective, ago(5), "conversation", "tool: [tool: Bash] ls\n\nresult: ok", line=2)
    put(selective, ago(5), "agent:conversation", "user: brief\n\nassistant: ok", line=3)
    facts.write_marker(ago(10))

    r = facts.run(ask=answers(), conn=selective.conn)

    assert r["before_zero"] == 1


def test_the_automated_prefixes_are_one_list():
    assert facts.AUTOMATED_PREFIXES is selection.AUTOMATED_PREFIXES


# ---------------------------------------------------------------- secrets

def test_a_key_pasted_to_be_remembered_does_not_reach_the_model(selective):
    """Found in the archive: a token the indexer's masking missed, pasted with "zapisz sobie ten
    klucz". The message is chosen — it is a "zapamiętaj" — so the key has to go before the model."""
    token = "tct_" + "HuJdPgSwRWDLRvjs5u9PcJ4jmQ8q"
    put(selective, ago(2), "user", f"{token} zapisz sobie ten klucz. hasło: tajne123")

    (msg,) = chosen(selective)
    piece = msg.piece()

    assert token not in piece and "tajne123" not in piece and "[MASKED]" in piece


def test_the_samples_for_a_human_mask_even_short_passwords():
    assert "159357dx2PO$" not in selection.redact_sample("zmieniłem hasło do bazy na 159357dx2PO$")
    assert "159357dx2PO$" not in selection.redact_sample("sprawdź 159357dx2PO$ jeszcze raz")


# ---------------------------------------------------------------- is the learning worth it

def test_every_pass_that_reviewed_something_leaves_its_numbers(selective):
    put(selective, ago(4), "assistant", REPLY, line=1)
    put(selective, ago(3), "user", "nie, ceny mają być jak FBM", line=2)
    put(selective, ago(2), "user", "zapamiętaj: ceny FBM to 7,90 euro", line=3)
    put(selective, ago(1), "user", "zwykłe polecenie bez niczego", line=4)
    facts.write_marker(ago(5))

    facts.run(ask=answers("Ceny FBM to 7,90 euro."), conn=selective.conn)
    saved = dict(line.split(": ", 1) for line in
                 facts.learning_path().read_text(encoding="utf-8").splitlines())

    assert saved["ostatni.przejrzane"] == "3" and saved["ostatni.wybrane"] == "2"
    assert (saved["ostatni.poprawki"], saved["ostatni.zapamietaj"]) == ("1", "1")
    assert saved["ostatni.fakty"] == "1" and int(saved["ostatni.znaki_materialu"]) > 0
    assert saved["dni14.przejrzane"] == "3" and saved["dni14.odsetek_wybranych"] == "66.7%"
    assert saved["nieprawidlowosc"] == ""
    for key in facts.SURVIVAL_KEYS:
        assert f"fakty14.{key}" in saved


def test_a_pass_that_chose_nothing_is_measured_too(selective):
    put(selective, ago(2), "user", "zwykłe polecenie")
    facts.write_marker(ago(5))

    facts.run(ask=answers(), conn=selective.conn)
    rows = facts._read_learning()

    assert [(r["przejrzane"], r["wybrane"], r["do_modelu"]) for r in rows] == [("1", "0", "0")]


def test_a_journal_that_cannot_be_written_says_so_in_the_summary(selective, monkeypatch, capsys):
    put(selective, ago(2), "user", "zapamiętaj: coś")
    facts.write_marker(ago(5))

    def broken(row):
        raise OSError("dysk pełny")
    monkeypatch.setattr(facts, "_append_learning", broken)

    facts.run(ask=answers(), conn=selective.conn)
    summary = facts.learning_path().read_text(encoding="utf-8")

    assert "nieprawidlowosc: nie udało się dopisać przebiegu" in summary
    assert "dysk pełny" in capsys.readouterr().err + summary


def trail_line(day: str, event: str, detail: str, text: str, sessions: bool = False) -> str:
    if sessions:
        return f"- {day} | {event} | {detail} | rozmowy {day}..{day} | sesje: s1 | {text}\n"
    return f"- {day} | {event} | {detail} | powód | {text}\n"


def test_survival_is_counted_off_the_trail_and_the_files(selective):
    today = datetime.now().strftime("%Y-%m-%d")
    old = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        trail_line(today, facts.SIGHTED, "stala/firma", "Firma sprzedaje olejki.", True),
        trail_line(today, "wpisany", "biezaca -> CLAUDE.md", "Firma sprzedaje olejki."),
        trail_line(today, facts.SIGHTED, "biezaca", "Stary numer magazynu to 12.", True),
        trail_line(today, "wpisany", "biezaca -> CLAUDE.md", "Stary numer magazynu to 12."),
        trail_line(today, "zastąpiony", "biezaca -> CLAUDE.md", "Stary numer magazynu to 12."),
        trail_line(today, facts.SIGHTED, "biezaca", "Sprawa z VAT czeka na księgową.", True),
        trail_line(today, "wpisany", "biezaca -> CLAUDE.md", "Sprawa z VAT czeka na księgową."),
        trail_line(today, "wygasł", "biezaca -> CLAUDE.md", "Sprawa z VAT czeka na księgową."),
        trail_line(today, facts.SIGHTED, "stala/praca", "Woli krótkie meldunki.", True),
        trail_line(today, "wpisany", "biezaca -> CLAUDE.md", "Woli krótkie meldunki."),  # hand-removed
        trail_line(today, facts.SIGHTED, "biezaca", "Czeka w poczekalni.", True),
        trail_line(old, facts.SIGHTED, "stala/firma", "Stary fakt sprzed dwóch tygodni.", True),
    ]
    (facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).write_text("".join(lines), encoding="utf-8")
    facts.RULES_PATH.write_text("## Co wiem\n\n- Firma sprzedaje olejki.\n", encoding="utf-8")

    out = facts.fact_survival(today)

    assert out == {"wylowione": 5, "wpisane": 4, "nadal_w_wiedzy": 1, "zastapione": 1,
                   "cofniete": 0, "wygasle": 1, "uspione": 0, "zniknely_bez_sladu": 1,
                   "nie_weszly": 1}


# ---------------------------------------------------------------- the dry run

def test_the_dry_run_report_compares_the_rules_and_masks_secrets(selective):
    put(selective, ago(3), "assistant", REPLY, line=1)
    put(selective, ago(2), "user", "nie, zmieniłem hasło na 159357dx2PO$", line=2)
    put(selective, ago(1), "user", "zwykłe polecenie bez niczego", line=3)

    r = selection.dry_run(selective.conn, days=7)
    text = selection.report(r)

    assert (r["reviewed"], r["chosen"], r["old_messages"]) == (2, 1, 2)
    assert "159357dx2PO$" not in text
    assert "WYBRANYCH" in text and "ODRZUCONYCH" in text
