"""lore_search puts subagent transcripts (role "agent:*") after the main conversation.

A query about a plan once returned 8/8 hits from workflow briefs: the brief repeats the query word
for word, so it outranks the conversation where the thing was actually settled.
"""

from lore import search


def add(conn, text: str, role: str, line: int) -> int:
    cid = conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at) VALUES (?,?,?,?,?,?,?,?,?)",
        ("test-project", "s1", "C:/t/s1.jsonl", line, 0, "2026-09-16T10:00:00.000Z", role, text, "x"),
    ).lastrowid
    conn.execute("INSERT INTO chunks_fts(rowid, text) VALUES (?,?)", (cid, text))
    return cid


def seed(conn):
    # the briefs repeat the query several times -> better BM25 than the real answer
    briefs = [add(conn, "plan pamieci plan pamieci plan pamieci wdrozenie", "agent:user", i) for i in range(1, 4)]
    monologue = add(conn, "plan pamieci plan pamieci czytam plik", "agent:assistant", 4)
    answer = add(conn, "ustalilismy plan pamieci w trzech krokach", "assistant", 5)
    return briefs, monologue, answer


def test_main_conversation_hit_comes_before_subagent_hits(environment):
    conn = environment.conn
    briefs, monologue, answer = seed(conn)
    plain = search.search("plan pamieci", conn=conn, agents=True)
    assert plain[0]["id"] != answer  # the premise: in the raw ranking the briefs win
    r = search.search("plan pamieci", conn=conn)
    assert r[0]["id"] == answer
    assert all(x["role"].startswith("agent:") for x in r[1:]) and len(r) == 5


def test_limit_keeps_the_main_hit_even_when_agents_fill_the_top(environment):
    """Break attempt: with limit=1 a cut taken before reordering would return a brief."""
    conn = environment.conn
    _, _, answer = seed(conn)
    assert [x["id"] for x in search.search("plan pamieci", conn=conn, limit=1)] == [answer]


def test_subagent_hits_still_shown_when_nothing_else_matches(environment):
    conn = environment.conn
    brief = add(conn, "tylko w zleceniu dla workera", "agent:user", 1)
    assert [x["id"] for x in search.search("zleceniu workera", conn=conn)] == [brief]


def test_agent_ranking_order_is_kept_within_the_group(environment):
    conn = environment.conn
    briefs, monologue, _ = seed(conn)
    plain = [x["id"] for x in search.search("plan pamieci", conn=conn, agents=True) if x["role"].startswith("agent:")]
    pushed = [x["id"] for x in search.search("plan pamieci", conn=conn) if x["role"].startswith("agent:")]
    assert pushed == plain
