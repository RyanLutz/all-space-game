# All Space — Decisions Log

Append-only. One entry per decision. Do not edit existing entries.

**Entry format:**
```
## YYYY-MM-DD — Short title
Agent:   <which agent / tool made this decision>
System:  <which system is affected>
Spec:    <spec filename> §<section>
Problem: <what triggered the decision>
Decision: <what was decided>
Spec updated: yes / no / pending
```

---

## 2026-04-16 — Pre-implementation spec audit and 3D cleanup

Agent:   Claude Sonnet (Claude Code) — session review-core-spec-QSCaF
System:  All systems
Spec:    All feature specs
Problem: Full audit of all feature specs before implementation begins revealed
         ten issues ranging from runtime crashes to policy violations to
         internal inconsistencies. Corrected before any code is written.
Decision: All issues fixed in the specs directly. Summary of fixes:

  PerformanceMonitor spec:
  - Removed dead `Physics.move_and_slide` custom monitor (ships are RigidBody3D,
    move_and_slide does not exist in this project)
  - Added three missing metrics to canonical table: Navigation.update,
    Physics.active_bodies, Ships.active_count

  Physics spec:
  - Rewrote Three Layers section to explicitly describe each layer's
    responsibilities and what it is forbidden from doing
  - Removed Vector2 from apply_thrust_forces() — replaced with scalar/Vector3
    math. Vector2 is banned from the physics pipeline.
  - Added explicit rule: Ship.gd never writes linear_velocity, angular_velocity,
    position, or rotation to produce motion

  Ship spec:
  - Added Physics Execution Model section echoing the three-layer contract
  - Defined `velocity` as a getter for RigidBody3D.linear_velocity
  - Fixed angular_velocity — clarified as angular_velocity.y (a component of
    RigidBody3D's Vector3 property), not a separate float; ship never writes
    rotation.y directly to produce motion
  - Fixed 3D Play Plane note that incorrectly described angular velocity as
    "applied to rotation.y"

  Camera spec:
  - Fixed _update_orientation(): removed undefined `camera` reference.
    GameCamera.gd is attached to the Camera3D node itself — call look_at() on self
  - Fixed _on_player_ship_changed: argument was Dictionary but the
    player_ship_changed signal emits Node. Changed to (ship: Node)
  - Fixed free-pan extension note: replaced undefined _target_position with
    correct approach (move global_position directly when no follow target)

  AI spec:
  - Fixed ENGAGE state strafe orbit: was computing world-space right vector and
    extracting .x component (wrong for non-cardinal headings). input_strafe is a
    local-space scalar — replaced with _circle_direction * strafe_thrust_fraction

  Weapons spec:
  - Defined missing _get_aim_direction() algorithm. Function was called in the
    projectile spawn code but never specified. Added full arc-clamping
    implementation: fixed returns baked axis; gimbal/partial_turret clamp via
    slerp; full_turret unconstrained.

  Chunk Streamer spec:
  - Fixed Debris.gd fade: Node3D has no modulate property (CanvasItem only).
    Replaced modulate.a with MeshInstance3D material albedo_color.a; noted that
    material transparency must be enabled in Debris.tscn
  - Replaced _debris_count_range: Vector2i with _debris_count_min: int and
    _debris_count_max: int. Vector2i is permitted only for chunk grid coordinates.

Spec updated: yes — all fixes applied directly to spec files

---

## 2026-04-17 — Ship physics stats: physics spec authoritative for hull fields

Agent:   Claude Opus (Claude Code) — Phase 4 implementation
System:  Ship physics / ContentRegistry
Spec:    feature_spec-physics_and_movement.md §JSON Data Format, feature_spec-ship_system.md §3
Problem: The physics spec defines the canonical JSON schema for ship hull physics
         stats, including `angular_drag`, `max_torque`, and `alignment_drag_base`.
         The ship system spec's `base_stats` section is incomplete — it references
         `torque_thrust_ratio` but omits `angular_drag` and `max_torque`, and uses
         `alignment_drag` instead of `alignment_drag_base`.
Decision: Physics spec is authoritative for all hull physics fields. Added
         `angular_drag`, `max_torque`, and `alignment_drag_base` to `base_stats`
         in corvette_patrol/ship.json. Renamed `alignment_drag` to
         `alignment_drag_base` in both base_stats and part_stats. Ship system spec
         will need a reconciliation pass when Step 9 (ShipFactory) is implemented.
Spec updated: no — ship system spec reconciliation deferred to Step 9

---

## 2026-04-17 — input_forward sign convention: positive = forward

Agent:   Claude Opus (Claude Code) — Phase 4 implementation
System:  Ship physics
Spec:    feature_spec-physics_and_movement.md §Key Algorithms (Thruster Budget Allocation)
Problem: The physics spec's `apply_thrust_forces()` uses `var fwd := -input_forward`
         with the comment "positive = thrust forward". Tracing the math:
         heading = -basis.z, fwd = -input_forward, so input_forward = 1.0 produces
         force along +basis.z (backward). The negation appears to be a sign error
         in the spec — the comment describes the desired behavior but the code
         inverts it.
Decision: Ship.gd uses `var fwd := input_forward` (no negation). input_forward = 1.0
         means "go forward". This matches the intuitive convention and
         Input.get_axis("move_backward", "move_forward") producing positive for W.
         If playtesting reveals a sign flip is needed, it is trivial to fix.
Spec updated: no — will update spec after playtesting confirms the correct sign

---

## 2026-04-17 — NavigationController monitor registration in PerformanceMonitor

Agent:   Claude Opus (Claude Code) — Phase 5 implementation
System:  NavigationController / PerformanceMonitor
Spec:    feature_spec-nav_controller.md §6
Problem: The nav controller spec shows `Performance.add_custom_monitor` in
         NavigationController's `_ready()`. However, multiple ship instances would
         each have a NavigationController, causing repeated registration of the
         same monitor name. The existing project pattern registers all custom
         monitors centrally in PerformanceMonitor.gd.
Decision: Registered `AllSpace/nav_update_ms` in PerformanceMonitor.gd alongside
         all other monitors. NavigationController calls `_perf.begin/end` as
         specified. The metric is visible in the debugger and F3 overlay regardless
         of which node registers it.
Spec updated: no — minor implementation detail, spec intent fully satisfied
Superseded by: 2026-04-17 — Custom monitor registration moved to GameBootstrap (below)

---

## 2026-04-17 — Custom monitor registration moved to GameBootstrap

Agent:   Claude Opus (Cursor) — Phase 5 follow-up
System:  GameBootstrap / PerformanceMonitor / all systems that expose monitors
Spec:    feature_spec-nav_controller.md §6, feature_spec-performance_monitor.md
Problem: `Performance.add_custom_monitor` calls were living inside
         `PerformanceMonitor.gd::_ready()`. That is an instrumentation-layer
         service — adding Godot-debugger wiring there conflates two concerns
         (per-call timing/counts vs. exposing a metric to the debugger) and
         forces every future monitor addition to touch an instance class that
         does not otherwise own startup sequencing.
Decision: `Performance.add_custom_monitor` calls moved from individual system
         `_ready()` to `GameBootstrap._ready()` via a new
         `_register_custom_monitors()` step, to avoid duplicate registration
         errors when multiple instances exist (NavigationController, AIController,
         etc.). All systems continue to call `PerformanceMonitor.begin/end`
         per-instance as specified. GameBootstrap owns all custom monitor
         registration going forward. Retroactive audit of Step 4 confirmed
         Ship.gd and SpaceBody.gd do not call `add_custom_monitor`; no further
         cleanup needed.
Spec updated: no — implementation-layer ownership decision; spec intent fully
         satisfied (metrics still visible in debugger / F3 overlay).

---

## 2026-04-17 — NavigationController tuning in base_stats (flat schema)

Agent:   Claude Opus (Cursor) — Phase 5 follow-up
System:  NavigationController / ContentRegistry / Ship
Spec:    feature_spec-nav_controller.md §5
Problem: Nav controller spec §5 places `arrival_distance` and
         `brake_safety_margin` in a `hull` sub-block. The existing
         `content/ships/corvette_patrol/ship.json` schema — which ContentRegistry
         and ShipPhysicsTest were built against in Step 4 — uses a flat
         `base_stats` block for all hull-level physics fields.
Decision: NavigationController tuning fields (`arrival_distance`,
         `brake_safety_margin`) added to `base_stats` block (flat) to match the
         existing corvette_patrol/ship.json schema. Physics spec §5 shows a
         `hull` block — reconciliation of flat vs. nested schema deferred to
         Ship System spec implementation (Step 9).
Spec updated: no — reconciliation deferred to Step 9

---

## 2026-04-17 — ProjectileManager extends Node3D instead of Node

Agent:   Claude Opus (Claude Code) — Step 6 implementation
System:  ProjectileManager
Spec:    feature_spec-weapons_and_projectiles.md §7
Problem: ProjectileManager needs `GetWorld3D()` to access
         `PhysicsDirectSpaceState3D` for sweep raycasts and hitscan. `Node` does
         not expose `GetWorld3D()`; `Node3D` is the minimal base class that does.
Decision: ProjectileManager extends `Node3D`. It has no visual/spatial presence —
         the inherited transform is unused. This is the standard Godot pattern for
         manager nodes that need physics space access.
Spec updated: no — minor implementation detail

---

## 2026-04-17 — DumbProjectile struct stores combat values directly

Agent:   Claude Opus (Claude Code) — Step 6 implementation
System:  ProjectileManager
Spec:    feature_spec-weapons_and_projectiles.md §7
Problem: Spec struct shows `WeaponDataId: int` but the `request_spawn_dumb` signal
         passes `weapon_id: String`. Resolving weapon data per-collision via
         cross-language ContentRegistry calls would be expensive in the hot loop.
Decision: Struct stores `Damage`, `ComponentDamageRatio`, and `DamageType` directly.
         Weapon data is looked up once at spawn time via a `Dictionary<string,
         WeaponCacheEntry>` that caches ContentRegistry results per weapon_id. The
         signal contract and behavior are preserved; only the internal struct layout
         differs from the spec illustration.
Spec updated: no — signal contract unchanged; struct is internal implementation

---

## 2026-04-17 — Hitscan requests queued for physics tick

Agent:   Claude Opus (Claude Code) — Step 6 implementation
System:  ProjectileManager
Spec:    feature_spec-weapons_and_projectiles.md §7
Problem: `request_fire_hitscan` signal may be emitted during `_process()` by
         WeaponComponent. Physics raycasts via `PhysicsDirectSpaceState3D` are only
         valid during `_physics_process()`.
Decision: Hitscan requests are queued in a `List<HitscanRequest>` when the signal
         fires, then processed at the start of the next `_PhysicsProcess()`. Max
         one-frame delay; invisible for continuous beams which fire every frame.
Spec updated: no — implementation detail; spec's immediate-fire illustration is
         conceptual

---

## 2026-04-17 — Fire group indexing: 1-based in JSON, 0-based internally

Agent:   Claude Sonnet (Cursor) — Step 7 implementation
System:  HardpointComponent / Ship / Weapon system
Spec:    feature_spec-weapons_and_projectiles.md §4.2, feature_spec-ship_system.md §3
Problem: The weapons spec JSON examples use 1-based indexing ("groups": [1], "groups": [2])
         and the success criteria say "left click fires group 1." But the ship system
         spec defines `input_fire: Array[bool]` as 0-based ([group0_active, group1_active,
         group2_active]). These don't agree.
Decision: Use 1-based in JSON for human readability (matches UI convention where
         Group 1 = Primary, Group 2 = Secondary), convert to 0-based internally when
         HardpointComponent reads from JSON (subtract 1 from each group index).
         This keeps the array access correct while the JSON remains intuitive.
         Ship system spec's `input_fire` comment needs update to clarify mapping.
Spec updated: pending — ship system spec needs `input_fire` comment updated to
         document: "JSON uses 1-based (Group 1 = index 0), internal array is 0-based"

---

## 2026-04-18 — Phase 8: GuidedProjectilePool implementation

Agent:   Claude Sonnet (Cursor) — Step 8 implementation
System:  GuidedProjectilePool.gd, WeaponComponent.gd
Spec:    feature_spec-weapons_and_projectiles.md §7, §8
Problem: PlayerState system does not exist yet (scheduled for later phase), but
         guided missiles in `track_cursor` and `click_lock` modes require
         querying `PlayerState.get_active_ship().get_aim_world_pos()` for aim
         point resolution per the spec.
Decision: Implement target resolution with fallback behavior:
         - `track_cursor` mode (default): Falls back to projecting missile forward
           when PlayerState is unavailable. Target acquisition deferred to PlayerState
           implementation phase.
         - `auto_lock` mode: Fully implemented — acquires nearest enemy in forward
           cone at launch using `get_tree().get_nodes_in_group("ai_ships")`.
         - `click_lock` mode: Treated as `auto_lock` until PlayerState provides
           explicit lock target functionality.
         Area damage (blast_radius) implemented with distance-based falloff. Collision
         detection uses sweep raycast from previous to current position.
Spec updated: no — spec's PlayerState dependency remains valid; implementation
         provides graceful degradation until PlayerState exists

---

## 2026-04-18 — GuidedProjectilePool: Shadowing and type inference fixes

Agent:   Claude Sonnet (Cursor) — Step 8 implementation
System:  GuidedProjectilePool.gd
Problem: Linter reported errors: "Cannot infer the type" for `collider_pos` and
         `to_ship` variables. Warnings: `position` parameter shadows Node3D property.
Decision: Explicit type annotations added for GDScript type inference:
         - `var collider_pos: Vector3` with if/else assignment instead of ternary
         - `var to_ship: Vector3` explicit type on declaration
         - Renamed `position` parameters to `spawn_position` and `explosion_position`
           to avoid shadowing Node3D base class property
Spec updated: no — implementation detail only

---

## 2026-04-18 — Phase 9: ShipFactory + Ship visual assembly implementation

Agent:   Claude Sonnet (Cursor) — Phase 9 implementation
System:  ShipFactory.gd, ContentRegistry.gd, PlayerState.gd, ServiceLocator.cs, ship_colorize.gdshader
Spec:    feature_spec-ship_system.md §6, §8, §9, §11, §12
Problem: Phase 9 implementation required creating several new core services that
         were referenced but not yet implemented: ServiceLocator (C# singleton for
         service registry), ContentRegistry (content indexing), PlayerState (active
         ship tracking), and the ShipFactory itself with full part assembly pipeline.
Decision: Implemented all missing services following spec architecture:
         - ServiceLocator.cs: C# autoload singleton providing GetService() for both
           C# and GDScript systems via Engine.get_singleton()
         - ContentRegistry.gd: Scans /content/ directories at startup, indexes ships
           weapons, and modules by folder name with _base_path for asset resolution
         - PlayerState.gd: Tracks active player ship, emits player_ship_changed signal
         - ShipFactory.gd: Full spawn_ship() pipeline with stat resolution, part
           assembly from GLB, hardpoint discovery/configuration, name resolution,
           faction color material application, and weapon attachment
         - ship_colorize.gdshader: Vertex color-driven shader with 4 channels
           (R=primary, G=trim, B=accent, A=glow emission)
         - Added test weapons (autocannon_light, pulse_laser) for verification
         - Updated GameBootstrap to register PlayerState and added custom monitors
         - Updated Ship.gd to track active ship count for PerformanceMonitor
Spec updated: no — implementation matches spec as written

---

### 2026-04-18 — Hardpoint empty naming must include part name for uniqueness

**Context:** When multiple part meshes are assembled as siblings under `ShipVisual`,
their child empties all land in the same node tree. Two parts with a hardpoint at
the same conceptual location (e.g. both `appendage_1` and `appendage_2` having a
`hp_wing_port_small` empty) would collide — Godot renames one silently or errors.

**Decision:** The hardpoint empty naming convention is updated to include the part
node name as a prefix component:

  Old: `HardpointEmpty_{id}_{size}`
  New: `HardpointEmpty_{part}_{id}_{size}`

The parser (`_parse_hardpoint_name`) is unchanged — it already treats everything
between the `HardpointEmpty_` prefix and the trailing size token as the id. The id
is simply longer and globally unique:

  `HardpointEmpty_hull_slim_hp_fore_port_small`
  → id: "hull_slim_hp_fore_port", size: "small"

`ship.json` references the full id in `hardpoint_types`, `default_loadout.weapons`,
and `default_loadout.fire_groups`. No code changes required.

Spec updated: yes — `feature_spec-ship_system.md` §5 naming convention, examples,
and parser comment updated.

---

## 2026-04-19 — Phase 10: GameCamera — Pilot mode

**Session:** Phase 10 implementation
**Status:** Implemented — no deviations from spec

### Files created

| File | Purpose |
|---|---|
| `gameplay/camera/GameCamera.gd` | Camera script — extends Camera3D |
| `gameplay/camera/GameCamera.tscn` | Camera3D scene with script attached |
| `test/CameraTest.tscn` | Manual test scene |
| `test/CameraTest.gd` | Test harness — WASD + mouse drive spawned ship |
| `.cursor/rules/camera.mdc` | Camera conventions for future agents |

### Implementation notes

- **`extends Camera3D`** — script attaches directly to the Camera3D node; `self` is the camera, no child node needed.
- **ServiceLocator for GameEventBus** — matches project convention. GameEventBus is not a Godot autoload; fetched via `Engine.get_singleton("ServiceLocator").GetService("GameEventBus")`.
- **Signal chain**: `ShipFactory.spawn_ship(... is_player=true)` → `PlayerState.set_active_ship()` → `GameEventBus.player_ship_changed` → `GameCamera._on_player_ship_changed()` → `follow()`. Camera does not need to find the ship by group at spawn time because the signal arrives after `_ready()`.
- **Spring reset**: both `follow()` and `release()` reset `_spring_velocity` to `Vector3.ZERO` to prevent velocity carry-over when retargeting.
- **Zero-vector guard** in `_compute_desired_position()`: `to_cursor.normalized()` is only called when `to_cursor.length() > 0.001` to avoid NaN from normalizing a zero vector.
- **`_on_player_ship_changed` type guard**: checks `is Node3D` before calling `follow()`; calls `release()` when `null` is passed (e.g. `PlayerState.clear_active_ship()`).
- **No PerformanceMonitor instrumentation** — per spec, Camera.update is reserved but not registered by default at MVP.

### Spec compliance

All success criteria from `feature_spec-camera_system.md` are addressed by the implementation. No conflicts with core spec or other feature specs were found. No deviations required.

---

## 2026-04-19 — Phase 11: AIController + NavigationController integration

**Session:** Phase 11 implementation  
**Status:** Implemented

### Files touched / created

| File | Purpose |
|---|---|
| `gameplay/ai/AIController.gd` | State machine; drives `input_*` and NavigationController |
| `data/ai_profiles.json` | Profile definitions (e.g. detection range) |
| `core/services/ContentRegistry.gd` | Load profiles; `get_ai_profile(id)` |
| `gameplay/entities/ShipFactory.gd` | `_attach_ai_components` — nav, DetectionVolume, AIController |
| `gameplay/ai/NavigationController.gd` | Resolve ship via `get_parent()`; ServiceLocator via `Engine.get_singleton` |
| `core/services/ServiceLocator.cs` | `Engine.RegisterSingleton("ServiceLocator", this)` for GDScript access |
| `test/ShipFactoryTest.tscn` / `.gd` | Spawn config tweaks for axum fighter + AI opponent |

### Implementation notes

- **Ship reference:** NavigationController is parented under the ship by ShipFactory without setting `owner`; `get_parent()` is the supported path (tests that set `owner` manually still work for the ship node as parent).
- **Deferred `add_child`:** Ship is added to the scene root with `call_deferred` so children added before tree insert run `_ready()` after the ship is in the tree.
- **ServiceLocator:** C# registry registers itself as an engine singleton so GDScript can call `Engine.get_singleton("ServiceLocator").GetService(...)` consistently with Phase 10 camera code.

### Spec compliance

Aligned with `feature_spec-ai_patrol_behavior.md` intent; file any deviations in future sessions if spec audit finds gaps.

---

## 2026-04-19 — Step 12: Pilot loop integration test scene

**Decision:** Added `test/PilotLoopTest.tscn` and `test/PilotLoopTest.gd` as the Step 12 harness: `ShipFactory` spawns player + AI, `GameCamera` for Pilot follow + cursor aim, `InputMap` actions `move_*` for thrust, LMB/RMB for fire groups 1–2. Tunables (`class_id`, variant, faction, spawns, `ai_profile_id`) are `@export` fields, not magic numbers in code.

**Main scene:** `project.godot` `run/main_scene` now points at `res://test/PilotLoopTest.tscn` so Run Project exercises the full Pilot loop instead of `CameraTest.tscn`.

**Default AI loadout:** AI uses `axum-fighter-1` / `axum_fighter_patrol` / `pirate` so both ships resolve against the same `ship.json` (the `corvette_patrol_heavy` variant belongs to class `corvette_patrol`, not `axum-fighter-1`).

**Commit packaging:** This Step 12 deliverable was committed as one changeset: `test/PilotLoopTest.tscn`, `test/PilotLoopTest.gd`, `project.godot` main scene, and updates to `docs/development_guide.md`, `docs/agent_brief.md`, and this file. Unrelated local edits to Blender sources and ship GLBs under `assets/` and `content/` were left unstaged.
