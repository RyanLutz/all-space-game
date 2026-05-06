# Claude Code — Project Context

Read `docs/agent_brief.md` before doing anything else. It contains the build
status, deviation protocol, architecture rules, and everything needed to work
on this project correctly.

---

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

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
