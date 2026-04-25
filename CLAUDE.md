# Claude Code — Project Context

Read `docs/agent_brief.md` before doing anything else. It contains the build
status, deviation protocol, architecture rules, and everything needed to work
on this project correctly.

---

## Quick Rules (full detail in agent_brief.md)

- No 2D nodes. No `Vector2` for world-space. Y = 0 always.
- No hardcoded values — everything tunable goes in JSON.
- No direct cross-system calls — use `GameEventBus` signals only.
- Ship.gd never writes velocity or position to produce motion — forces to Jolt only.
- Specs are authoritative. Deviations require a written report before any code.
- One system per session. Do not mix concerns.
- **graphify-first recon:** Before exploring the codebase manually, check if `graphify-out/` exists. If it does, read `graphify-out/GRAPH_REPORT.md` and query `graphify-out/graph.json` first. Only fall back to manual `glob`/`grep`/`read` if the graph is missing or stale.

## On Session End

Before ending any session, update two things:
1. Build status table in `docs/agent_brief.md`
2. `docs/decisions_log.md` — append any decisions made this session
