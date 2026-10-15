"""The source badge must work for every MCP client, not only for the owner - it lives in the server instructions."""

from lore.server import mcp


def test_instructions_ask_for_source_badge():
    text = mcp.instructions
    assert "`🟣 Lore`" in text and "`🟠 jfwiedza`" in text
    assert "lore_search" in text and "lore_context" in text and "Z ARCHIWUM" in text
    assert "no badge" in text
    assert len(text) < 4096  # Claude Code cuts server instructions at about 4096 characters
