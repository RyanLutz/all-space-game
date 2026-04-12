# All Space — Development Guide
*Human reference for working on this project. Not an agent context file.*

---

## What This Is

This guide explains how to work on All Space effectively — how sessions are structured, which tools to use for which tasks, and how to maintain the project as it grows. It is written for you, the developer, not for AI agents.

Agent context lives in `.cursor/rules/` — see the Cursor Setup section below.

---

## The Core Philosophy

**One system per session. Specs first. No hardcoded values.**

Every implementation session targets exactly one system. The spec for that system is read before any code is written. All tunable values go in JSON. This discipline keeps AI coding sessions focused and correct.

---

## Tech Stack

- **Engine:** Godot 4.6
- **Primary Language:** GDScript
- **Performance-Critical:** C# (ProjectileManager only)
- **Physics:** Jolt 3D (native to Godot 4.6) — `RigidBody3D` for ships and space objects
- **Camera:** `Camera3D`, perspective, looking down at XZ play plane
- **Data:** JSON configuration files for all game data and content
- **Inter-System Communication:** `GameEventBus.gd` — event bus only, no direct cross-system calls

---

## The Play Plane Contract

**All gameplay occurs on the XZ plane (Y = 0).** This is the single most important constraint in the project. Ships, projectiles, and all dynamic entities live at `position.y = 0`. The camera looks down from above at a shallow angle.

Read the Core Spec (`docs/All_Space_Core_Spec.md`) before working on any system. It defines this contract in full.

---

## Project Structure

```
/all_space/
    docs/                        ← all spec documents (read before implementing)
    .cursor/rules/               ← Cursor agent context files (one per system)
    core/                        ← services, event bus, bootstrap
    gameplay/                    ← all gameplay systems
    content/                     ← ships, weapons, modules (folder-per-item)
    data/                        ← global JSON config tables
    assets/                      ← shaders, textures
    test/                        ← test scenes
```

Full directory layout is in `docs/All_Space_Core_Spec.md`.

---

## Cursor Setup

Cursor uses `.mdc` rule files in `.cursor/rules/` to automatically load the right context based on which files you have open. You do not need to paste context or explain the project — open the relevant file and the agent already knows the rules.

| Rule File | Loads When Editing |
|---|---|
| `always-on.mdc` | Every session — core rules, play plane contract, architecture rules |
| `physics.mdc` | Files in `gameplay/entities/` |
| `weapons.mdc` | Files in `gameplay/weapons/` |
| `ai.mdc` | Files in `gameplay/ai/` |
| `camera.mdc` | Files in `gameplay/camera/` |
| `world.mdc` | Files in `gameplay/world/` |
| `content.mdc` | Files in `content/` |
| `data.mdc` | Files in `data/` |
| `event-bus.mdc` | Files named `GameEventBus*` |
| `performance-monitor.mdc` | Files named `PerformanceMonitor*` |
| `csharp.mdc` | Files ending in `.cs` |
| `godot.mdc` | Files ending in `.gd`, `.tscn`, `.tres` |
| `spec-writing.mdc` | Files in `docs/` |

These files are what Cursor agents actually read. Keep them current when systems change.

---

## Model Selection

| Task | Recommended Model |
|---|---|
| Architecture decisions, spec writing | Opus 4.6 or Kimi K2.5 |
| Implementing a system from spec | Sonnet 4.6 or Kimi K2.5 |
| Bug fixes, small edits | Sonnet 4.6 |
| Reviewing implementation against spec | Opus 4.6 |

---

## The Atomic Task Workflow

Every coding session follows this pattern:

**1. Pick one task from the build order below.**
Don't combine tasks. Each session implements one system or one component.

**2. Point the agent at the spec.**
Start your prompt with: *"Read `docs/[SystemName]_Spec.md` fully before writing any code."*
The `.cursor/rules/` files load the architecture context automatically.

**3. Verify against success criteria.**
Every spec ends with a Success Criteria checklist. Before closing the session, confirm each item is met.

**4. Update the build order.**
Check off the completed task in this file.

---

## Build Order

Build in dependency order. Do not skip ahead — later systems depend on earlier ones being correct.

### Foundation
| # | Task | Spec | Done |
|---|---|---|---|
| 1 | PerformanceMonitor singleton + F3 debug overlay | `PerformanceMonitor_Spec.md` | ⬜ |
| 2 | ServiceLocator + GameEventBus with initial signal set | `GameEventBus_Signals.md` | ⬜ |
| 3 | GameBootstrap — autoload setup, service registration | — | ⬜ |
| 4 | ContentRegistry — scan `/content/` at startup, index all items | `Ship_System_Spec.md` | ⬜ |

### Physics & Ship
| # | Task | Spec | Done |
|---|---|---|---|
| 5 | Ship — RigidBody3D, Jolt axes frozen to XZ, force/torque interface | `Physics_Movement_Spec.md` | ⬜ |
| 6 | Ship — thruster budget, assisted steering, alignment drag | `Physics_Movement_Spec.md` | ⬜ |
| 7 | Player input — mouse-to-world ray, keyboard thrust/strafe | `Physics_Movement_Spec.md` | ⬜ |
| 8 | Physics test scene — ship flying with debug overlay | — | ⬜ |

### Weapons
| # | Task | Spec | Done |
|---|---|---|---|
| 9 | Weapon JSON + damage_types.json | `Weapons_Projectiles_Spec.md` | ⬜ |
| 10 | ProjectileManager.cs — dumb projectile pool | `Weapons_Projectiles_Spec.md` | ⬜ |
| 11 | HardpointComponent — fire arc, heat tracking, damage states | `Weapons_Projectiles_Spec.md` | ⬜ |
| 12 | WeaponComponent — fire logic, power draw, projectile spawning | `Weapons_Projectiles_Spec.md` | ⬜ |
| 13 | GuidedProjectilePool — missile guidance modes | `Weapons_Projectiles_Spec.md` | ⬜ |
| 14 | Damage pipeline — shield/hull/component resolution | `Weapons_Projectiles_Spec.md` | ⬜ |
| 15 | Weapons test scene — ship firing at target dummy | — | ⬜ |

### Ship Visual Assembly
| # | Task | Spec | Done |
|---|---|---|---|
| 16 | ShipFactory — spawn from content ID, assemble parts, apply loadout | `Ship_System_Spec.md` | ⬜ |
| 17 | Colorization shader — vertex color channels, shared material | `Ship_System_Spec.md` | ⬜ |
| 18 | PlayerState singleton | `Ship_System_Spec.md` | ⬜ |

### Camera
| # | Task | Spec | Done |
|---|---|---|---|
| 19 | GameCamera — follow with cursor offset, critically damped spring | `Camera_System_Spec.md` | ⬜ |
| 20 | Camera zoom — scroll wheel, smooth interpolation | `Camera_System_Spec.md` | ⬜ |

### AI
| # | Task | Spec | Done |
|---|---|---|---|
| 21 | AIController — IDLE/PURSUE/ENGAGE state machine | `AI_Patrol_Behavior_Spec.md` | ⬜ |
| 22 | AI weapons — aim prediction, fire logic | `AI_Patrol_Behavior_Spec.md` | ⬜ |
| 23 | AI test scene — player vs 3 AI patrol ships | — | ⬜ |

### World
| # | Task | Spec | Done |
|---|---|---|---|
| 24 | ChunkStreamer — load/unload chunks around player | `ChunkStreamer_Spec.md` | ⬜ |
| 25 | Asteroid spawner — RigidBody3D, HP, destruction, debris | `ChunkStreamer_Spec.md` | ⬜ |
| 26 | World test scene — fly through streaming chunks | — | ⬜ |

### Integration
| # | Task | Spec | Done |
|---|---|---|---|
| 27 | Full MVP test scene — fly, fight, and survive | — | ⬜ |

### Post-MVP (Visual)
| # | Task | Spec | Done |
|---|---|---|---|
| 28 | Thruster VFX — GPUParticles3D at thruster markers, scaled by thrust | — | ⬜ |
| 29 | Muzzle flash VFX — spawn on `weapon_fired` signal | — | ⬜ |
| 30 | Destruction VFX — debris scatter + explosion on `ship_destroyed` | — | ⬜ |
| 31 | Station docking + loadout UI | — | ⬜ |

---

## Prompt Templates

### Implementing a System
```
Read docs/[SystemName]_Spec.md fully before writing any code.

Implement [specific component] following the spec exactly.
- All tunable values in JSON — never hardcoded
- PerformanceMonitor instrumentation per the spec's Performance section
- Cross-system communication through GameEventBus only
- All entity positions are Vector3 with y = 0

Show me your implementation plan before writing any code.
```

### Writing a New Spec
```
Read docs/All_Space_Core_Spec.md fully first.

Write a spec for [System Name]. The system needs to:
- [requirement 1]
- [requirement 2]

Follow the spec format from the Core Spec. Include PerformanceMonitor metric
names, full JSON schemas for any data files, and concrete success criteria.
Flag any decisions that conflict with the Core Spec rather than resolving them silently.
```

### Code Review Against Spec
```
Read docs/[SystemName]_Spec.md, then review the implementation in [file path].

Check for:
1. Spec compliance — does the code match what the spec says?
2. Architecture violations — hardcoded values, direct cross-system refs,
   missing perf instrumentation, any Vector2 for world positions
3. Play plane contract — is Y = 0 enforced after physics updates?
4. Edge cases — what happens at boundaries?

List every deviation from the spec with the specific section violated.
```

### Bug Fix
```
There is a bug in [file]: [describe the bug].

Before fixing:
1. Read the relevant spec in docs/ to understand intended behavior
2. Check if the fix requires changes to JSON data or just code logic
3. Confirm the fix does not violate the play plane contract or architecture rules

Explain the root cause before showing the fix.
```

---

## When to Use Claude Chat (Not Cursor)

Some tasks belong in a design conversation, not a coding session:

- **Designing a new system** before writing its spec
- **Resolving architectural conflicts** between systems
- **Updating the Core Spec** when significant decisions change
- **Reviewing the overall build order** and project direction
- **Writing feature spec prompts** for new conversations

---

## Maintenance

### When You Complete a System
1. Check off the task in the build order above
2. Update the relevant `.cursor/rules/*.mdc` file if the system's interface changed
3. Add any new PerformanceMonitor metrics to the Core Spec's canonical table
4. If you added a new system directory, create a corresponding `.mdc` rule file

### When You Write a New Spec
1. Add the spec to `docs/`
2. Create a `.cursor/rules/[system-name].mdc` file for it
3. Add its PerformanceMonitor metrics to the Core Spec
4. Add its build tasks to the build order above

### When a Design Decision Changes
1. Update `docs/All_Space_Core_Spec.md` first — it is the single source of truth
2. Update the affected feature spec(s)
3. Update the affected `.cursor/rules/*.mdc` file(s)
4. Note the change here if it affects the build order

---

## Architecture Rules (Quick Reference)

The full rules are in `docs/All_Space_Core_Spec.md`. The short version:

1. No hardcoded tunable values — everything in JSON
2. No direct cross-system references — use GameEventBus only
3. PerformanceMonitor instrumentation required in every system
4. One system per agent session
5. Specs are authoritative — follow them, flag conflicts
6. C# only for ProjectileManager — everything else GDScript
7. Enforce Y = 0 after every physics update
