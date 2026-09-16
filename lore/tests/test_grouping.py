"""Gluing consecutive turns into a single chunk."""

from __future__ import annotations

from lore.index import (
    CHUNK_SIZE,
    MIXED_ROLE,
    OVERLAP,
    Turn,
    _chunks_from_group,
    group,
)

TS = "2026-09-16T10:00:00.000Z"


def t(role: str, text: str, line: int = 1) -> Turn:
    return Turn(line, TS, role, text)


def chunks(grp, role_prefix: str = "") -> list[str]:
    return [c.text for c in _chunks_from_group(grp, role_prefix)]


def test_short_turns_land_in_one_chunk():
    turns = [
        t("user", "Should I move the indexer to a new model?", 1),
        t("assistant", "I suggest e5-small, it is smaller.", 2),
        t("user", "yes, do it", 3),
    ]
    groups = group(turns)
    assert len(groups) == 1
    (text,) = chunks(groups[0])
    assert text == (
        "user: Should I move the indexer to a new model?\n\n"
        "assistant: I suggest e5-small, it is smaller.\n\n"
        "user: yes, do it"
    )


def test_single_turn_without_role_prefix():
    (grp,) = group([t("user", "a lone sentence")])
    assert chunks(grp) == ["a lone sentence"]


def test_group_does_not_exceed_the_limit():
    turns = [t("assistant" if i % 2 else "user", "a" * 200, i + 1) for i in range(30)]
    groups = group(turns)
    assert len(groups) > 1
    for g in groups:
        for text in chunks(g):
            assert len(text) <= CHUNK_SIZE


def test_long_turn_is_cut_with_overlap_and_not_glued():
    long = "x" * 4000
    turns = [t("user", "short before", 1), t("assistant", long, 2), t("user", "short after", 3)]
    groups = group(turns)
    assert [len(g) for g in groups] == [1, 1, 1]
    parts = chunks(groups[1])
    assert len(parts) > 1
    assert all(len(p) <= CHUNK_SIZE for p in parts)
    assert parts[0] == long[:CHUNK_SIZE]
    assert parts[1][:OVERLAP] == parts[0][-OVERLAP:]  # 200 character overlap
    assert "assistant:" not in parts[0]


def test_uniform_and_mixed_role():
    (uniform,) = group([t("user", "first", 1), t("user", "second", 2)])
    assert _chunks_from_group(uniform, "")[0].role == "user"

    (mixed,) = group([t("user", "question", 1), t("assistant", "answer", 2)])
    assert _chunks_from_group(mixed, "")[0].role == MIXED_ROLE


def test_mixed_role_keeps_the_subagent_prefix():
    (grp,) = group([t("agent:user", "question", 1), t("agent:assistant", "answer", 2)])
    assert _chunks_from_group(grp, "agent:")[0].role == "agent:" + MIXED_ROLE


def test_line_and_part_taken_from_the_start_of_the_group():
    (grp,) = group([t("user", "first", 7), t("assistant", "second", 8)])
    chunk_list = _chunks_from_group(grp, "")
    assert [(c.line, c.part) for c in chunk_list] == [(7, 0)]
