"""Codex transcript ingestion, using synthetic records shaped like real sessions."""

from __future__ import annotations

import json
import os
import time

from lore import index


TS = "2026-09-16T15:06:23.000Z"


def _record(typ: str, payload: dict) -> dict:
    return {"timestamp": TS, "ordinal": 1, "type": typ, "payload": payload}


def _message(role: str, block_type: str, text: str) -> dict:
    return _record(
        "response_item",
        {"type": "message", "id": f"msg-{role}", "role": role,
         "content": [{"type": block_type, "text": text}]},
    )


def _write(path, *records: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
        encoding="utf-8",
    )


def test_codex_messages_are_indexed_while_reasoning_and_tools_are_noise(environment, tmp_path, monkeypatch):
    sessions = tmp_path / ".codex" / "sessions"
    transcript = sessions / "2026" / "09" / "16" / "rollout-example.jsonl"
    _write(
        transcript,
        _record("session_meta", {"id": "codex-session", "cwd": str(tmp_path / "MegaRuchacz")}),
        _message("developer", "input_text", "hidden instructions"),
        _message("user", "input_text", "Remember the blue variant."),
        _record("response_item", {"type": "reasoning", "summary": ["private reasoning"]}),
        _record("response_item", {"type": "function_call", "name": "read_file", "arguments": "{}"}),
        _record("response_item", {"type": "function_call_output", "output": "tool result"}),
        _record("response_item", {"type": "custom_tool_call", "name": "exec", "input": "secret"}),
        _record("response_item", {"type": "custom_tool_call_output", "output": "more noise"}),
        _record("event_msg", {"type": "item_completed", "item": {"type": "reasoning"}}),
        _message("assistant", "output_text", "I will remember it."),
    )
    old = time.time() - index.TAIL_CLOSING_AGE_S - 1
    os.utime(transcript, (old, old))
    monkeypatch.setattr(index, "CODEX_SESSIONS_DIR", sessions)

    assert index.find_files() == [transcript]
    assert environment.index(transcript) == 1
    assert environment.texts() == [
        "user: Remember the blue variant.\n\nassistant: I will remember it."
    ]
    assert environment.conn.execute(
        "SELECT project, session FROM chunks"
    ).fetchone() == ("MegaRuchacz", "codex-session")


def test_codex_metadata_survives_incremental_reads(environment, tmp_path, monkeypatch):
    sessions = tmp_path / ".codex" / "sessions"
    transcript = sessions / "2026" / "09" / "16" / "rollout-incremental.jsonl"
    _write(
        transcript,
        _record("session_meta", {
            "session_id": "stable-session",
            "id": "legacy-id",
            "cwd": str(tmp_path / "Shop"),
        }),
        _message("user", "input_text", "First decision."),
        _message("assistant", "output_text", "Recorded."),
    )
    monkeypatch.setattr(index, "CODEX_SESSIONS_DIR", sessions)
    old = time.time() - index.TAIL_CLOSING_AGE_S - 1
    os.utime(transcript, (old, old))
    assert environment.index(transcript) == 1

    with open(transcript, "a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(_record("response_item", {
            "type": "message",
            "role": "user",
            "content": [
                {"type": "input_text", "text": "Second"},
                {"type": "input_image", "image_url": "data:image/png;base64,ignored"},
                {"type": "input_text", "text": "decision."},
            ],
        })) + "\n")
        stream.write(json.dumps(_message("assistant", "output_text", "Also recorded.")) + "\n")
    os.utime(transcript, (old, old))

    assert environment.index(transcript) == 1
    assert environment.conn.execute(
        "SELECT DISTINCT project, session FROM chunks"
    ).fetchall() == [("Shop", "stable-session")]
    assert environment.texts()[-1] == (
        "user: Second\ndecision.\n\nassistant: Also recorded."
    )
