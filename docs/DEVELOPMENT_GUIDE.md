# All Space — Development Guide for Cursor
*How to use this project setup with any AI model effectively*

---

## How the Context System Works

This project uses Cursor's **layered rules system** to give every AI model the right
context automatically:

| Layer | File | When It Loads |
|---|---|---|
| Always-on | `.cursorrules` | Every conversation, every model |
| Physics | `.cursor/rules/physics-system.mdc` | When you're editing files in `gameplay/physics/` |
| Weapons | `.cursor/rules/weapons-system.mdc` | When you're editing files in `gameplay/weapons/` |
| AI | `.cursor/rules/ai.mdc` | When you're editing files in `gameplay/ai/` |
| Camera | `.cursor/rules/camera-system.mdc` | When you're editing files in `gameplay/camera/` |
| Content/data | `.cursor/rules/content-architecture.mdc` | When you're editing files in `content/` |
| Perf monitor | `.cursor/rules/performance-monitor.mdc` | When you're editing `PerformanceMonitor` files |
| JSON data | `.cursor/rules/json-data.mdc` | When you're editing files in `data/` or `content/` |
| Event bus | `.cursor/rules/event-bus-contract.mdc` | When you're editing `GameEventBus` files |
| Spec writing | `.cursor/rules/spec-writing.mdc` | When you're editing files in `docs/` |
| C# | `.cursor/rules/csharp-projectiles.mdc` | When you're editing `.cs` files |
| Godot | `.cursor/rules/godot-conventions.mdc` | When you're editing `.gd`, `.tscn`, `.tres` files |

You don't need to paste context or explain the project. Open the relevant file,
start a conversation, and the model already knows the rules.

---

## Model Selection Guide

Different models have different strengths. Use the right one for the job:

### Complex Architecture / Spec Writing
**Use: Opus 4.6 or Kimi K2.5**
- Writing new system specs
- Resolving architectural conflicts between systems
- Designing event bus signal contracts
- Anything requiring cross-system reasoning

### Implementation / Code Generation
**Use: Sonnet 4.6 or Kimi K2.5**
- Implementing a system from a spec
- Writing GDScript classes and scenes
- Creating JSON data files
- Standard coding tasks

### Quick Fixes / Small Edits
**Use: Sonnet 4.6 (or whichever is fastest)**
- Bug fixes
- Adding PerformanceMonitor instrumentation to existing code
- Small refactors
- Updating JSON values

### Code Review / Spec Validation
**Use: Opus 4.6**
- Reviewing an implementation against its spec
- Checking for architecture rule violations
- Validating cross-system integration

---

## The Atomic Task Workflow

Every coding session should follow this pattern:

### 1. Pick ONE Task from the Build Order
Don't combine tasks. Each session implements one system or one component of a system.

### 2. Point the Model at the Spec
Start your prompt with: *"Read `docs/[SystemName]_Spec.md` and implement [specific component]."*
The rules files provide architecture context automatically.

### 3. Verify Against Success Criteria
Every spec ends with a Success Criteria checklist. Before closing the session,
verify each criterion is met.

### 4. Update Tracking
After completing a task, update the build order status in this file.

---

## Build Order — MVP

Each row is one atomic session. Do them in order. Check them off as you go.

### Foundation Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 1 | PerformanceMonitor singleton + debug overlay | `docs/PerformanceMonitor_Spec.md` | ✅ |
| 2 | GameEventBus with initial signal set | `docs/GameEventBus_Signals.md` | ✅ |
| 3 | GameBootstrap — autoload setup, service registration | — | ✅ |

### Physics Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 4 | SpaceBody base class — velocity, drag, mass | `docs/Physics_Movement_Spec.md` | ✅ |
| 5 | Ship movement — thruster budget, angular inertia, assisted steering | `docs/Physics_Movement_Spec.md` | ✅ |
| 6 | Player input — mouse aim + keyboard thrust/strafe | `docs/Physics_Movement_Spec.md` | ✅ |
| 7 | Physics test scene — ship flying around with debug overlay | — | ✅ |

### Weapons Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 8 | JSON data files — content/weapons/<id>/weapon.json + data/damage_types.json | `docs/Weapons_Projectiles_Spec.md`, `docs/Ship_Content_Data_Architecture_Spec.md` | ✅ |
| 9 | ProjectileManager.cs — dumb projectile pool (spawn, move, despawn) | `docs/Weapons_Projectiles_Spec.md` | ✅ |
| 10 | HardpointComponent — fire arc, heat tracking, damage states | `docs/Weapons_Projectiles_Spec.md` | ✅ |
| 11 | WeaponComponent — fire logic, power draw, projectile spawning | `docs/Weapons_Projectiles_Spec.md` | ✅ |
| 12 | GuidedProjectilePool — missile guidance modes | `docs/Weapons_Projectiles_Spec.md` | ✅ |
| 13 | Damage system — hit detection, shield/hull/component damage | `docs/Weapons_Projectiles_Spec.md` | ✅ |
| 14 | Weapons test scene — ship with weapons firing at target dummy | — | ✅ |

### AI Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 15 | AI state machine — idle, patrol, pursue, engage | `docs/AI_Patrol_Behavior_Spec.md` | ✅ |
| 16 | AI weapon usage — aim prediction, firing logic | `docs/AI_Patrol_Behavior_Spec.md` | ✅ |
| 17 | AI test scene — player vs 3 AI patrol ships | — | ✅ |

### World Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 19 | Write Chunk Streaming spec | — | ✅ |
| 20 | ChunkStreamer — load/unload chunks around player | `docs/ChunkStreamer_Spec.md` | ✅ |
| 21 | Asteroid spawner — populate chunks with asteroids | `docs/ChunkStreamer_Spec.md` | ✅ |
| 22 | World test scene — fly through streaming chunks | — | ✅ |

### Integration Layer
| # | Task | Spec | Status |
|---|---|---|---|
| 23 | Write Station & Loadout UI spec | `docs/Station_Loadout_UI_Spec.md` | ✅ |
| 24 | Station docking — approach, dock, open loadout screen | `docs/Station_Loadout_UI_Spec.md` | ✅ |
| 25 | Loadout UI — swap weapons/modules on ship | `docs/Station_Loadout_UI_Spec.md` | ✅ |
| 26 | MVP integration scene — full loop: fly, fight, dock, customize | — | ✅ |

---

## Prompt Templates

Copy-paste these when starting a session. They're designed to give any model
the right framing without wasting tokens.

### Implementing a System
```
Read docs/[SystemName]_Spec.md fully before writing any code.

Implement [specific component/class] following the spec exactly.
- All tunable values in JSON under data/
- Add PerformanceMonitor instrumentation per the spec's Performance section
- Cross-system communication through GameEventBus only
- Create a minimal test scene to verify the implementation works

Show me the implementation plan before writing code.
```

### Writing a New Spec
```
Read docs/ to see the existing spec format. New specs must follow the same
structure (see .cursor/rules/spec-writing.mdc for the required sections).

Write a spec for [System Name]. The system needs to:
- [requirement 1]
- [requirement 2]
- [requirement 3]

Include PerformanceMonitor metric names that follow the naming convention
in docs/PerformanceMonitor_Spec.md. Include full JSON schema for any data
files. Include concrete success criteria.
```

### Code Review Against Spec
```
Read docs/[SystemName]_Spec.md, then review the implementation in
[file path(s)].

Check for:
1. Spec compliance — does the code match what the spec says?
2. Architecture violations — hardcoded values, direct cross-system refs, missing perf instrumentation
3. Godot best practices — proper use of _physics_process vs _process, signal patterns, etc.
4. Edge cases — what happens at boundaries (zero health, empty power pool, no ammo)?

List every deviation from the spec with the specific section that's violated.
```

### Bug Fix
```
There's a bug in [file]: [describe the bug].

Before fixing:
1. Read the relevant spec in docs/ to understand intended behavior
2. Check if the fix requires changes to JSON data or just code logic
3. Make sure the fix doesn't violate architecture rules (see .cursorrules)

Explain the root cause before showing the fix.
```

---

## When to Come Back to Claude (chat, not Cursor)

Some tasks are better suited to a design conversation than a code session:

- **New system design** — when you need to think through a system's design before
  writing the spec. Do the design session here, then write the spec in Cursor.
- **Architecture decisions** — when a new system creates tension with existing ones
- **Scope questions** — "should this be in the MVP or deferred?"
- **Reviewing the overall build order** — making sure the sequence still makes sense
- **Updating the project skill** — when significant new systems are complete

---

## Maintenance

### When You Complete a System
1. Check off the task in the build order above
2. Update `.cursorrules` if the project structure changed
3. Add any new PerformanceMonitor metrics to `.cursor/rules/performance-monitor.mdc`
4. If you created a new system directory, consider whether it needs its own `.mdc` rule file

### When You Write a New Spec
1. Add it to the `docs/` folder
2. If the system has its own directory, create a `.cursor/rules/[system-name].mdc` file
3. Add its PerformanceMonitor metrics to the contract table
4. Update the build order in this file

### When You Hit a Problem
1. Check if the spec addresses it — if not, the spec needs updating first
2. Check if it's a cross-system issue — those usually mean the event bus contract needs work
3. If the architecture rules are getting in the way, that's a design conversation (come back to Claude chat)
