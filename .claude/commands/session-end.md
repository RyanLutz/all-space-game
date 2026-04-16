Wrap up this agent session correctly. Do this before ending every session, no exceptions.

## Step 1 — Report what happened

Summarise this session in 3–6 bullet points:
- What was implemented or changed
- What was left incomplete and why
- Any problems encountered
- What the next session should pick up first

## Step 2 — Update build status

Open `docs/agent_brief.md` and update the Build Status table.

Status values:
- `Not started` — no work done
- `In progress (session: <date>)` — started but not complete
- `Implemented` — code written, not yet tested in a running scene
- `Tested ✓` — verified working in Godot with a running scene

Only change rows that actually moved this session. Do not mark anything `Tested ✓` unless it was verified in a running Godot scene this session.

## Step 3 — Update Recent Decisions in agent_brief.md

The `<!-- RECENT-DECISIONS-START -->` / `<!-- RECENT-DECISIONS-END -->` block in
`docs/agent_brief.md` holds the last 3 decisions. If any decisions were made this
session, prepend them to the list and drop the oldest entry if there are more than 3.

Format for each entry:
```
N. **YYYY-MM-DD — Short title** — One sentence summary. See decisions_log.md.
```

If no decisions were made, leave the block unchanged.

## Step 4 — Append to decisions log

Open `docs/decisions_log.md`. For each decision made this session — spec deviation,
architectural choice, API workaround — append one entry:

```
## YYYY-MM-DD — Short title
Agent:    <agent name / tool>
System:   <which system>
Spec:     <spec filename> §<section>
Problem:  <what triggered this decision>
Decision: <what was decided and why>
Spec updated: yes / no / pending
```

If no decisions were made this session, append a brief session record anyway:

```
## YYYY-MM-DD — Session: <what was built>
Agent:    <agent name / tool>
System:   <which system>
Result:   <implemented / in progress / blocked>
Notes:    <anything useful for the next session>
```

## Step 5 — Confirm

After completing the above, report:
> Session closed. Build status updated. Decisions logged. Next session should start at: [step or task].
