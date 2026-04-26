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

---

## 2026-04-19 — Phase 13: Tactical mode camera + input layer

Agent:   Claude Opus (Claude Code)
System:  Fleet Command (camera + input layer), GameCamera, GameEventBus
Spec:    `feature_spec-camera_system.md` §Future Extension, `feature_spec-fleet_command.md` §2–4

**Decision:** Implemented the tactical mode camera and input layer as Phase 13.

### New files
- `gameplay/fleet_command/InputManager.gd` — Tab key mode toggle (`game_mode_changed` signal), pilot input routing (WASD + mouse → ship unified input interface). In tactical mode, stops writing to ship inputs.
- `gameplay/fleet_command/SelectionState.gd` — Selection tracking by instance id. Click-select, shift-toggle, drag-box select, cleared on mode switch, pruned on `ship_destroyed`.
- `gameplay/fleet_command/TacticalInputHandler.gd` — Tactical-only input: left-click select, drag-box, right-click target classification (fleet → context menu, enemy → attack, asteroid → mine, empty → move), Stop key (Esc + S).

### Modified files
- `gameplay/camera/GameCamera.gd` — Added tactical mode: `game_mode_changed` listener, free-pan (WASD + edge scroll), zoom-out on enter tactical, re-follow player on exit, `set_zoom_limits()`, separate tactical zoom bounds. Orientation uses look-at-ground when no follow target.
- `core/GameEventBus.gd` — Added `queue_mode: String` param to `request_tactical_move/attack/mine`. New signals: `request_tactical_stop`, `request_tactical_set_stance`, `request_tactical_set_escort_stance`, `request_tactical_add_to_escort`, `request_tactical_remove_from_escort`, `context_menu_requested`, `escort_queue_changed`, `escort_stance_changed`, `request_formation_destination`, `ship_damaged`.
- `project.godot` — Added `toggle_mode` (Tab) and `tactical_stop` (Esc + S) input actions.
- `test/PilotLoopTest.gd` — Refactored: removed inline `_physics_process` and `_input` player routing; now creates InputManager, SelectionState, and TacticalInputHandler as children.

### Deviation
- **File location:** Spec says `systems/fleet_command/`; used `gameplay/fleet_command/` to match the existing project layout where all gameplay code lives under `gameplay/`.

### Not yet implemented (later phases)
- EscortQueue, FormationController, StanceController (fleet command internals)
- TacticalUI (SelectionBox visual, ContextMenu, EscortPanel)
- AI integration with stance system

---

## 2026-04-20 — Phase 14: Fleet Command — selection, orders, stance, escort queue

Agent:   Claude Opus (Claude Code)
System:  Fleet Command, NavigationController, AIController, Ship, ProjectileManager, GuidedProjectilePool, ShipFactory
Spec:    `feature_spec-fleet_command.md` §2–9

**Decision:** Implemented the full RTS command layer (Phase 14).

### New files
- `gameplay/fleet_command/EscortQueue.gd` — Ordered escort ship list with queue-shared stance, away-on-orders tracking, and automatic pruning on ship_destroyed.
- `gameplay/fleet_command/StanceController.gd` — Per-ship stance for non-escort ships, `get_effective_stance()` single call for AIController. Caches escort membership via signals (no direct EscortQueue reference). Defensive fan-out: when escort queue member is damaged and stance is DEFENSIVE, all queue members attack the aggressor.
- `gameplay/fleet_command/FormationController.gd` — Timer-based tick (~0.25s) pushes slot destinations for escort queue members in Pilot mode via `request_formation_destination` signal. Slot = player position + offset rotated by player yaw.
- `content/formations/v_wing/formation.json` — Default 4-slot V-Wing formation.
- `ui/tactical/ContextMenu.gd` — PopupMenu with Stance + Escort submenus; listens to `context_menu_requested`, emits stance/escort signals. Stance hidden when ship is in escort queue. Player ship cannot be added to own escort.
- `ui/tactical/EscortPanel.gd` — PanelContainer with stance selector buttons and queue member list. Visible only when queue is non-empty.

### Modified files
- `core/GameEventBus.gd` — Added `navigation_order_completed(ship_id: int)` signal.
- `gameplay/entities/Ship.gd` — `apply_damage()` gains optional `attacker_id: int = 0` param; emits `ship_damaged(self, attacker_node)` on all damage.
- `gameplay/weapons/ProjectileManager.cs` — `ApplyDamage()` threads `OwnerEntityId` as 5th arg to GDScript `apply_damage`.
- `gameplay/weapons/GuidedProjectilePool.gd` — Threads `owner_id` through `_apply_damage()` and `_trigger_explosion()` to `apply_damage`.
- `gameplay/entities/ShipFactory.gd` — Player ship gets `player_fleet` group and a NavigationController for tactical move orders.
- `gameplay/ai/NavigationController.gd` — Added `DriveMode` enum (EXTERNAL/TACTICAL_ORDER/FORMATION), signal listeners for `request_tactical_move`, `request_tactical_stop`, `request_formation_destination`, `_physics_process()` self-drive, `has_tactical_order()` query.
- `gameplay/ai/AIController.gd` — Added `TACTICAL_ATTACK` state, signal listeners for `request_tactical_attack`/`request_tactical_stop`, fleet-friendly detection (fleet ships target `enemies` group, not `player` group), stance check via StanceController (HOLD_FIRE suppresses fire), nav override check (`has_tactical_order()`). Renamed `_target_player`/`_player_detected` to `_target`/`_target_detected`.
- `data/ai_profiles.json` — Added `fleet_default` profile (small wander, obedient personality, no autonomous engagement).
- `test/PilotLoopTest.gd` — Wires all Phase 14 systems: EscortQueue, FormationController, StanceController (registered via ServiceLocator), TacticalUI (CanvasLayer with ContextMenu + EscortPanel). Spawns 2 fleet ships (player faction, fleet_default profile, player_fleet group) + 1 enemy (enemies group).

### Key design decisions
1. **NavigationController self-drive via DriveMode.** EXTERNAL = legacy (AIController calls `update()`), TACTICAL_ORDER/FORMATION = self-driving via `_physics_process`. AIController checks `has_tactical_order()` before overriding nav.
2. **StanceController signal-cached escort state.** Listens to `escort_queue_changed` and `escort_stance_changed` to avoid direct reference to EscortQueue. Registered via ServiceLocator for AIController access.
3. **Player ship attack orders = move-to-target only.** No AIController on player ship; no auto-fire. Player switches to pilot mode to fire.
4. **Fleet-friendly detection.** `_on_detection_volume_body_entered` checks `player_fleet` membership to avoid targeting friendlies.
5. **`ship_damaged` attacker threading.** Optional param on `apply_damage()` preserves backward compat across the C#/GDScript boundary.

### Deviations
- **File location:** Spec says `systems/fleet_command/` and `ui/tactical/`; used `gameplay/fleet_command/` and `ui/tactical/` matching existing layout.
- **TacticalUI.tscn not created.** UI components are instantiated programmatically in PilotLoopTest.gd, consistent with how all Phase 13 components are wired. A .tscn can be extracted later.
- **Stance submenu disabled (not hidden)** when ship is in escort queue. PopupMenu item hiding for submenu entries is complex; disabled state provides equivalent behavioral correctness. Visual polish deferred per spec §9.4.

Spec updated: no — implementation matches spec intent; file locations follow existing convention

---

## 2026-04-21 — Phase 15: ChunkStreamer + Asteroid + Debris

Agent:   Claude Opus (Claude Code)
System:  ChunkStreamer, Asteroid, Debris
Spec:    feature_spec-chunk_streamer.md

### What was built
1. **`data/world_config.json`** — all tunable values: chunk size (2000), load radius (2), asteroid field params, HP tiers, debris config.
2. **`gameplay/world/Debris.gd` + `Debris.tscn`** — lightweight Node3D with manual velocity integration, alpha fade over lifetime, queue_free on expiry. No physics body.
3. **`gameplay/world/Asteroid.gd`** — extends SpaceBody (RigidBody3D). Jolt axis locks (Y linear, XZ angular). apply_damage matching Ship signature. Destruction spawns debris fragments with non-deterministic RNG. Placeholder SphereMesh + CollisionShape3D created in setup_mesh(). Added to "asteroids" group.
4. **`gameplay/world/ChunkStreamer.gd`** — Node3D that tracks follow target, computes chunk neighborhood, loads/unloads on boundary crossing. Deterministic RNG per chunk coordinate via hash(Vector2i). Asteroid field clustering, AI spawn point markers in "ai_spawn_points" group. PerformanceMonitor instrumentation.
5. **PilotLoopTest.gd** — ChunkStreamer wired as child, follow target set to player ship.

### Deviations
- None. Implementation follows spec exactly. GameEventBus signals (chunk_loaded, chunk_unloaded, explosion_triggered) already existed.

Spec updated: no — no deviations

---

## 2026-04-21 — Phase 16: GameEventBus signal audit

Agent:   Claude Opus (Claude Code)
System:  GameEventBus (cross-cutting)
Spec:    feature_spec-game_event_bus_signals.md (all sections)
Problem: Spec was written before phases 12-15 and had drifted from reality. 12 signals
         existed in code but not in the spec. 3 signals had signature mismatches
         (missing queue_mode parameter). Emitter/listener columns were stale.

Decision: Update the spec to match the code (code is authoritative — it was tested
through phases 12-15). No code changes needed.

### Changes to spec
1. Added 12 signals to spec: request_tactical_stop, request_tactical_set_stance,
   request_tactical_set_escort_stance, request_tactical_add_to_escort,
   request_tactical_remove_from_escort, context_menu_requested, escort_queue_changed,
   escort_stance_changed, request_formation_destination, navigation_order_completed,
   ship_damaged, debug_toggled.
2. Added new spec sections: Escort & Formation Signals, Damage Signals, Debug Signals.
3. Fixed queue_mode: String on request_tactical_move, request_tactical_attack,
   request_tactical_mine to match code.
4. Updated all emitter/listener columns to reflect actual .connect() and .emit() calls.
5. Marked reserved-but-unused signals: projectile_spawned, power_depleted, all 4
   station signals (dock_requested, dock_complete, undock_requested, loadout_changed).
6. Added TACTICAL_ATTACK to ai_state_changed documented values.
7. Corrected emitter for request_spawn_dumb/hitscan/guided from HardpointComponent
   to WeaponComponent (WeaponComponent emits, not HardpointComponent).
8. Added audit log section at bottom of spec.

### Deviations
- None. Spec-only update to match existing code.

Spec updated: yes — feature_spec-game_event_bus_signals.md fully rewritten

## 2026-04-25 — Phase 17 Session 2: Local Effect Players

Agent:   Claude Sonnet 4.6 (Claude Code)
System:  Combat VFX
Spec:    feature_spec-combat_vfx.md §3, §4
Problem: Session 2 scope — create local effect players attached at assembly time.

Decision:
- Created MuzzleFlashPlayer.gd: local GPUParticles3D per weapon; pool_size==0 disables.
  Discovers Muzzle marker in parent for correct world-space positioning at play().
- Created BeamRenderer.gd: local BoxMesh on BeamRenderer node; look_at(to) + scale.z=length
  stretches beam along direction. Placeholder uses StandardMaterial3D emission.
  ShaderMaterial/u_time_offset wired but guarded for art-pass shader upgrade.
- Created ShieldEffectPlayer.gd: reads ShaderMaterial from parent MeshInstance3D;
  play_hit() sets u_hit_origin and u_hit_time (engine uptime matches TIME in shader).
- Created assets/shaders/shield_ripple.gdshader: expanding ring ripple via TIME - u_hit_time;
  local-space vertex position passed through varying; blend_add + depth_draw_never.
- Modified ShipFactory._attach_weapon(): appends MuzzleFlashPlayer to every weapon model;
  appends BeamRenderer to energy_beam archetype weapons only.
- Added ShipFactory._create_shield_mesh(): creates ShieldMesh (SphereMesh) + ShieldEffectPlayer
  under ShipVisual for ships with shield_max > 0. Radius heuristic: pow(mass/1000, 0.33)*4.
  Skips if shader file missing (push_warning). Sets ship.shield_mesh reference.
- Modified Ship.gd: added var shield_mesh: MeshInstance3D = null for VFXManager lookup.

### Deviations
- None. All implementation follows phase_plan-combat_vfx.md Session 2 spec.

Spec updated: no — spec unchanged; build status updated in agent_brief.md
