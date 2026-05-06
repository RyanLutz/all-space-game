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

## 2026-05-02 — Star System Phase 4: ExclusionArea + star_exclusion_entered signal

Agent:   Claude Sonnet (Cursor)
System:  StarMesh / GameEventBus
Spec:    docs/spec/feature_spec-star_system.md § "Exclusion Zone"
Problem: Phase 3 left ExclusionArea.monitoring = false. Phase 4 wires it.
Decision: Added `signal star_exclusion_entered(star_id: int, ship_id: int)` to
         `GameEventBus.gd` (World section). In `StarMesh.gd _configure_exclusion()`:
         `collision_mask = 1` (ships default to layer 1); `monitoring = true`;
         `monitorable = false` (other areas don't need to detect this one);
         `body_entered` connected to `_on_exclusion_body_entered`. The handler
         checks `body is Ship` to filter out asteroids and debris sharing the
         same collision layer, then emits
         `_event_bus.star_exclusion_entered.emit(star_id, body.get_instance_id())`.
         GameEventBus resolved via `ServiceLocator.GetService("GameEventBus")` in
         `configure()`. Boundary-force enforcement is flagged as an integration
         point for the physics and nav specs — this session delivers the emitter
         only.
Spec updated: yes — LOD 2 + ExclusionArea description updated to remove "Phase 3
         stub" language; LOD 2 + screen-pass coexistence note updated for the
         reversed-Z depth fix (z=0.0001, not z=0.999).

---

## 2026-05-02 — Star System Phase 2 depth fix: reversed-Z occlusion

Agent:   Claude Sonnet (Cursor)
System:  star_screen_pass.gdshader (LOD 1)
Spec:    docs/spec/feature_spec-star_system.md § "LOD 1 — Screen-Space Glow"
Problem: Stars (screen-pass glow) were rendering in front of opaque scene
         geometry. Phase 2 placed the fullscreen quad at clip z = 0.999,
         intending that to be "just inside the far plane" in standard forward-Z
         (near=0, far=1). However, Godot 4 Forward+ uses reversed-Z (near=1,
         far=0, clear=0). In reversed-Z, z=0.999 is near the NEAR plane,
         not the far plane. The implicit transparent-pass depth test was
         therefore unreliable for occlusion.
Decision: Two changes to star_screen_pass.gdshader:
         1. Vertex stage: POSITION.z changed from 0.999 to 0.0001 (just inside
            the far plane in reversed-Z).
         2. Fragment stage: add `uniform sampler2D depth_texture :
            hint_depth_texture`. At the start of fragment(), sample the depth
            buffer at SCREEN_UV; if the value > 0.00001 (geometry present —
            reversed-Z scene objects write depth > 0, empty sky clears to 0),
            discard immediately. This replaces the implicit depth test, which
            is not reliable for transparent-pass objects in reversed-Z Godot 4.
Spec updated: yes — docs/spec/feature_spec-star_system.md LOD 1 section updated with
         "Depth occlusion — manual depth texture check" paragraph explaining
         reversed-Z, the depth texture approach, and why z=0.999 was wrong.

---

## 2026-05-01 — Star System Phase 3: LOD 2 mesh, surface + corona shaders, light range plumbing

Agent:   Claude Opus (Cursor) — Star System Phase 3 session
System:  StarRegistry / StarMesh / star_surface + star_corona shaders (LOD 2)
Spec:    docs/spec/feature_spec-star_system.md § "LOD 2 — Mesh + Light (close range)"
Problem: Phase 2 left LOD 2 as a placeholder: `_spawn_mesh()` was a no-op,
         `StarRecord` had no light range field, and there was no
         `star_mesh` tunable block in `world_config.json`. Implementing Phase
         3 also surfaced two design questions: (1) should the LOD 2 surface
         and atmosphere layers reuse one shader or each have their own; (2)
         should LOD-2 stars stay in the screen-pass list.
Decision: Implemented LOD 2 as a single reusable `StarMesh.tscn` consisting
         of three concentric `SphereMesh` `MeshInstance3D` layers (core +
         two atmospheres) all running a shared `star_surface.gdshader`, plus
         one billboarded `QuadMesh` running `star_corona.gdshader`, plus an
         `OmniLight3D` and an `Area3D + SphereShape3D` exclusion stub.
         `StarMesh.gd` is the configuration entry point — it duplicates the
         per-layer SphereMesh and ShaderMaterial so per-layer parameters
         (alpha, flow speed, rotation direction, noise scale) don't stomp
         each other across simultaneously-spawned stars.
         Surface shader uses object-local 3D fBm so the plasma pattern is
         stable on the surface and only `TIME` advances it; hot peaks bias
         toward white-hot for inverse-sunspot look. Corona shader uses the
         standard Godot 4 billboard MODELVIEW idiom + two-component falloff
         that mirrors the LOD 1 screen-pass character (continuous LOD 1 → 2
         handoff). `OmniLight3D.omni_range` derived per star type from a new
         per-type `light_range_multiplier` JSON key, computed once at
         generation and stored on `StarRecord.light_range`.
         Decided LOD-2 stars **stay in the screen-pass list**: at the star
         center the opaque core writes depth so the screen-pass quad
         (clip z = 0.999, depth-test LESS) loses; only the corona edge —
         where no opaque depth was written — admits the screen-pass glow.
         This keeps Phase 5's planned alpha-crossfade implementation
         straightforward (both representations are already coexisting; only
         the per-star alpha needs to ramp).
         Also fixed a latent bug in `_update_lod()`: the prior `continue`
         on backdrop-tier within `lod2_spawn_distance` skipped LOD state
         updates entirely, so a backdrop star inside LOD 2 distance could
         be stuck rendering as LOD 0. Now backdrop tier clamps to LOD 1
         within that distance and only ever transitions through the
         {0, 1} states.
         New `galaxy.star_mesh` block in `data/world_config.json` carries
         all LOD 2 tunables (per-layer scales, surface noise/flow,
         atmosphere alphas, atmosphere rotation speeds, corona intensity
         and falloff radii, light attenuation). Phase 3 leaves
         `ExclusionArea.monitoring = false`; Phase 4 will flip that and
         wire the signal to GameEventBus.
Spec updated: yes — `docs/spec/feature_spec-star_system.md` LOD 2 section rewritten
         to describe the layered shader strategy, the screen-pass-stays-on
         decision, and the Phase 3 / Phase 4 boundary on `ExclusionArea`;
         data model expanded with `light_range`; JSON section gains the
         full `star_mesh` tunable block; Files table marks Phase 3 files
         done.

---

## 2026-05-01 — Star System Phase 2: fullscreen 3D quad replaces SubViewport for LOD 1

Agent:   Claude Opus (Cursor) — Star System Phase 2 session
System:  StarRegistry / star_screen_pass shader (LOD 1)
Spec:    docs/spec/feature_spec-star_system.md § "LOD 1 — Screen-Space Glow (mid range)"
Problem: Spec called for a "SubViewport full-screen shader" rendering "with no
         depth test — always behind scene geometry by compositing order." User
         initially approved a CanvasLayer (`layer = -1`) + ColorRect canvas-item
         shader implementation. Pre-implementation research surfaced that
         CanvasLayer with negative layer for rendering behind 3D content is a
         tracked, unresolved Godot 4.x regression (godotengine/godot#67633);
         WorldEnvironment.BG_CANVAS workarounds are also affected.
Decision: Implemented LOD 1 as a single `MeshInstance3D` fullscreen quad parented
         to the active `Camera3D`. Spatial shader writes `POSITION` directly in
         NDC at clip z = 0.999 so quad geometry is screen-locked and the default
         depth test (`LESS`) fails wherever scene geometry wrote a closer
         fragment — opaque ships occlude the glow naturally. `depth_draw_never`
         keeps subsequent transparent passes (combat VFX) compositing normally
         on top of the stars. Star world positions are projected in the fragment
         shader using built-in `PROJECTION_MATRIX * VIEW_MATRIX`, which Godot
         binds per rendered frame — eliminates the rotation lag a CPU-passed VP
         uniform would introduce when LOD updates run on physics tick. Per-frame
         star cap of 256 (`MAX_SCREEN_PASS_STARS`) with closest-N selection when
         exceeded; frustum culling deferred to Phase 5. New tunables added to
         `data/world_config.json` under `galaxy.lod`:
         `screen_pass_max_stars`, `glow_world_radius_multiplier`,
         `glow_min_pixel_radius`, `glow_max_pixel_radius`, `glow_intensity`,
         `glow_core_radius`. Phase 2 verification scene at `test/StarSystemTest.tscn`
         (fly-cam + occluder boxes + PerformanceMonitor overlay).
Spec updated: yes — `docs/spec/feature_spec-star_system.md` LOD 1 section rewritten to
         describe the fullscreen-quad mechanism and the rotation-lag-prevention
         rationale; Files table updated with `star_screen_pass.gdshader` (Phase
         2) and `StarSystemTest.tscn` paths; JSON section gains the new
         `screen_pass_*` and `glow_*` tunables.

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
Spec:    docs/spec/feature_spec-physics_and_movement.md §JSON Data Format, docs/spec/feature_spec-ship_system.md §3
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
Spec:    docs/spec/feature_spec-physics_and_movement.md §Key Algorithms (Thruster Budget Allocation)
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
Spec:    docs/spec/feature_spec-nav_controller.md §6
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
Spec:    docs/spec/feature_spec-nav_controller.md §6, docs/spec/feature_spec-performance_monitor.md
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
Spec:    docs/spec/feature_spec-nav_controller.md §5
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
Spec:    docs/spec/feature_spec-weapons_and_projectiles.md §7
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
Spec:    docs/spec/feature_spec-weapons_and_projectiles.md §7
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
Spec:    docs/spec/feature_spec-weapons_and_projectiles.md §7
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
Spec:    docs/spec/feature_spec-weapons_and_projectiles.md §4.2, docs/spec/feature_spec-ship_system.md §3
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
Spec:    docs/spec/feature_spec-weapons_and_projectiles.md §7, §8
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
Spec:    docs/spec/feature_spec-ship_system.md §6, §8, §9, §11, §12
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

Spec updated: yes — `docs/spec/feature_spec-ship_system.md` §5 naming convention, examples,
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

All success criteria from `docs/spec/feature_spec-camera_system.md` are addressed by the implementation. No conflicts with core spec or other feature specs were found. No deviations required.

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

Aligned with `docs/spec/feature_spec-ai_patrol_behavior.md` intent; file any deviations in future sessions if spec audit finds gaps.

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
Spec:    `docs/spec/feature_spec-camera_system.md` §Future Extension, `docs/spec/feature_spec-fleet_command.md` §2–4

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
Spec:    `docs/spec/feature_spec-fleet_command.md` §2–9

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
Spec:    docs/spec/feature_spec-chunk_streamer.md

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
Spec:    docs/spec/feature_spec-game_event_bus_signals.md (all sections)
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

Spec updated: yes — docs/spec/feature_spec-game_event_bus_signals.md fully rewritten

## 2026-04-25 — Phase 17 Session 2: Local Effect Players

Agent:   Claude Sonnet 4.6 (Claude Code)
System:  Combat VFX
Spec:    docs/spec/feature_spec-combat_vfx.md §3, §4
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

---

## 2026-04-29 — Per-part `-colonly` collision from parts GLB

Agent:   Cursor agent (Composer)
System:  ShipFactory / ship collision
Spec:    docs/spec/feature_spec-ship_system.md §5 Parts GLB Structure (collision not previously specified)
Problem:  Single placeholder `BoxShape3D` on `Ship.tscn` did not match variant part silhouettes;
          author wanted collision authored in Blender alongside meshes (`appendage_*-colonly`).
Decision:  At spawn, for each variant part node `name`, look up `name-colonly` in the loaded
           parts scene; duplicate its `CollisionShape3D` (or extract from imported StaticBody3D
           wrapper) and parent under the ship `RigidBody3D`; name `CollisionShape3D_<category>`;
           `set_meta("part_category", category)` for future component damage. If any `-colonly`
           is present, `queue_free()` the scene’s default `CollisionShape3D`. Projectile hits
           still resolve `apply_damage` on the body — no per-part damage in this change.
           Committed: `ShipFactory.gd`, `content/ships/axum-fighter-1/parts.glb`,
           `assets/blender/axum-light-craft.glb`, graphify-out refresh.
Spec updated:  pending — document `-colonly` naming and factory behavior in ship system spec

---

## 2026-04-29 — UI Session 2: Pilot HUD

Agent:   Cursor agent (Sonnet)
System:  UI — PilotHUD, Radar
Spec:    docs/spec/feature_spec-ui_design.md §Pilot HUD Layout, §Indicator Types

### What was built

- `ui/radar/Radar.gd/.tscn` — Custom Control using `_draw()` for all rendering.
  Sweep angle advances in `_process()`, triggers `queue_redraw()` each frame.
  Wedge drawn as filled polygon (WEDGE_STEPS=24 segments). Enemy dots from
  `get_tree().get_nodes_in_group("ships")` — read-only scene tree query; acceptable
  per architecture rules (not a cross-system call). Radar orientation: X→right, -Z→up
  (world north-up). Enemy cull: distance-squared check before coordinate conversion.

- `ui/PilotHUD.gd/.tscn` — Five panels + hit flash overlay.
  All panels built programmatically in `_ready()` via helper methods.
  Anchors: Mode Tag top-left, Target Lock top-center, Vessel Status bottom-left,
  Weapon Systems bottom-center, Radar container bottom-right.
  Subscriptions: `player_ship_changed`, `game_mode_changed`, `ship_damaged`.
  Also checks `PlayerState.active_ship` at `_ready()` for late-add robustness.
  PerformanceMonitor wraps `_process()` body under `UI.pilot_hud_update`.

### Decisions made

1. **Hardpoint discovery** — PilotHUD walks the ship's ShipVisual subtree at bind time,
   collects HardpointComponent nodes sorted by `hardpoint_id` for stable slot assignment.
   This is the ship's own internal structure; not a cross-system violation.

2. **Heat polling** — `HardpointComponent.heat_current / heat_capacity` polled each
   frame. No new signal added; the ship's own components are accessible to its own
   HUD display system.

3. **Ammo** — Energy weapon archetypes show "∞" (U+221E). Ballistic/missile show "--".
   Full ammo tracking deferred to a future session when inventory system is specced.

4. **Active weapon slot** — A slot is visually "active" when any of its fire groups
   has `input_fire[group] == true` (i.e., the player is holding that fire button).
   This is the correct MVP interpretation: no separate "selected weapon" concept exists.

5. **Target Lock panel** — Built with all inner nodes (name label, HULL/DIST/THREAT
   readouts) but `visible = false`. No `target_locked` signal exists in GameEventBus.
   Structure is ready for wiring when the player targeting system is specced.

6. **Hit flash decay** — `FLASH_DECAY_PS = 3.3` (alpha units/second), derived from
   spec's `0.055/frame × 60fps`. Frame-rate-independent via `delta` multiplication.

7. **Old `ui/pilot/PilotHUD.gd`** — Superseded by `ui/PilotHUD.gd`. Old file left in
   place to avoid breaking `test/PilotHudTest.gd`. That test needs updating to use the
   event bus pattern (`player_ship_changed`) rather than `set_player_ship()`.

### Deviations
- None from spec intent.

Spec updated: no — spec unchanged; build status updated in agent_brief.md

---

## 2026-04-29 — UI Session 1: Foundation Layer

Agent:   Cursor agent (Sonnet)
System:  UI — tokens, theme, reusable components, mode switch
Spec:    docs/spec/feature_spec-ui_design.md

### What was built

- `ui/UITokens.gd` — Node autoload registered in project.godot as "UITokens".
  Exports all design token constants (GREY_*, ACCENT_*, TAC_ACCENT_*, HOSTILE_*,
  STATUS_*, SURFACE, SURFACE_RAISED, SIZE_*, CLIP_SIZE, PAD_*). Provides
  `get_font_label()`, `get_font_data()`, `apply_font_label()`, `apply_font_data()`
  helpers with graceful fallback when font files are not yet imported.

- `ui/UITheme.tres` — Godot 4 Theme resource. Styles: Panel, PanelContainer, Label,
  Button (normal / hover / pressed / focus / disabled). All values derived from tokens.
  No font references (applied programmatically per-component until fonts are imported).

- `ui/components/StatBar.gd/.tscn` — MarginContainer with ProgressBar.
  Exposes: `set_header()`, `set_fill_color()`, `set_ratio()`, `set_value_text()`,
  `mark_critical()`. ProgressBar styled via StyleBoxFlat overrides from UITokens.

- `ui/components/SegBar.gd/.tscn` — Control with 10-segment HBoxContainer.
  Exposes: `set_ratio()`, `set_active_color()`. Segments are ColorRect nodes.

- `ui/components/HeatBar.gd/.tscn` — Control with ProgressBar. Three-state
  machine: COOL / WARM / CRITICAL. Critical state runs sin-wave pulse in _process().
  Exposes: `set_heat()`, `set_cool_color()`.

- `ui/components/WeaponSlot.gd/.tscn` — PanelContainer. Top-bar accent line (2px,
  hidden by default), slot-num / weapon-name / ammo-count header row, embedded HeatBar.
  Inactive → surface/grey-20. Active → surface-raised/accent-dim + accent weapon name.
  Exposes: `set_weapon_name()`, `set_slot_index()`, `set_active()`, `set_heat()`,
  `set_ammo_text()`, `set_empty()`.

- `ui/components/RosterRow.gd/.tscn` — PanelContainer with bottom-border divider.
  Icon ColorRect + name/class/HP-bar/status column. HP bar (3px, no track border)
  uses STATUS_HULL / STATUS_POWER / HOSTILE by hull ratio. Selected: name → TAC_ACCENT.
  Exposes: `set_ship_data()`, `update_hull()`, `set_selected()`, `get_ship_id()`.

- `ui/ModeSwitch.gd/.tscn` — Control (full-rect, MOUSE_FILTER_IGNORE). Listens for
  "toggle_mode" input action. Emits `GameEventBus.game_mode_changed(old, new)`.
  Never holds references to PilotHUD or TacticalHUD — event-only coupling.
  Exposes: `set_mode()`, `get_current_mode()`.

- `project.godot` — Added `UITokens="*res://ui/UITokens.gd"` to [autoload] section.

### Decisions made

1. **Components build UI in _ready() via GDScript** (not editor-authored node trees in
   tscn). This matches the existing PilotHUD.gd pattern and avoids fragile hand-written
   sub-resource tscn syntax.

2. **UITheme.tres has no font references** until Orbitron and Share Tech Mono are
   imported. Font application is handled by `UITokens.apply_font_label/data()` in each
   component's _ready(), with graceful no-op if files are absent. Font files belong at:
   - `assets/fonts/Orbitron-Regular.ttf`
   - `assets/fonts/ShareTechMono-Regular.ttf`

3. **RosterRow HP bar uses _process() to sync fill width** after layout changes.
   This is a known pattern for ratio-based fills without a custom draw call.

4. **Corner-clip polygons deferred** — StyleBoxFlat with corner_radius=0 gives the
   hard angular aesthetic. True 14px diagonal polygon clips require custom _draw() or
   baked textures; deferred to post-MVP polish.

### Deviations
- None from spec intent. Corner-clip impl deferred by design (spec anticipates this).

Spec updated: no — spec unchanged; build status updated in agent_brief.md

---

## 2026-05-02 — Star System Phase 5: LOD Crossfade + Performance Validation

Agent:   Claude Sonnet (Cursor)
System:  StarRegistry / StarMesh / star shaders
Spec:    docs/spec/feature_spec-star_system.md § "LOD Crossfade", § "Performance Instrumentation"
Problem: LOD 0→1 and LOD 1→2 transitions produced a visible brightness/geometry pop.
         `lod_update` hot path called `distance_to()` (sqrt) for all 3000 stars per frame.
         `screen_pass_count` could exceed 200 with no culling, wasting shader iterations.

Decision:

### `StarRecord` additions
- `blend_alpha: float = 1.0` — progress of settling into current `lod_state`
  (0.0 = just entered, 1.0 = fully settled).
- `lod_prev_state: int = 0` — LOD before the most recent transition; drives which
  representation is fading out.

### Crossfade state machine (StarRegistry._update_lod)
- On LOD change: set `blend_alpha = 0.0`, `lod_prev_state = old state`.
- Each frame: advance `blend_alpha += 1.0 / lod_crossfade_frames`; mark dirty.
- LOD 2 mesh spawns invisible (`StarMesh.configure()` calls `set_blend_alpha(0.0)`).
- LOD 2 despawn is **delayed**: mesh fades out over `lod_crossfade_frames` frames
  before `queue_free()` — eliminates the hard pop when leaving close range.
- Stars transitioning LOD 1→0 remain in `_screen_pass_stars` until fade-out completes.

### Crossfade weight routing
- `_compute_screen_pass_weight()` encodes blend direction per transition pair and
  packs the result into `_u_color[i].w` (formerly `star.color.a`, always 1.0).
- LOD 0 point alpha uses `INSTANCE_CUSTOM.a`; `_update_multimesh()` writes
  `blend_alpha` (fade in) or `1 - blend_alpha` (fade out) into it each dirty frame.

### mix() in all four shaders
- `star_point.gdshader`: `ALPHA = mix(0.0, glow, INSTANCE_CUSTOM.a)`
- `star_screen_pass.gdshader`: `mix(0.0, glow * intensity, star_color[i].a)`
- `star_surface.gdshader`: `ALPHA = mix(0.0, layer_alpha, blend_alpha)`
- `star_corona.gdshader`: `ALPHA = mix(0.0, a, blend_alpha)`

### Performance optimisation
- Replaced `distance_to()` with `distance_squared_to()` + pre-computed squared
  thresholds (`_lod1_distance_sq`, `_lod2_spawn_distance_sq`) — eliminates
  3000 sqrt() calls per frame, the primary budget driver.

### Frustum-cull stub
- `_frustum_cull_screen_pass_stars()` runs only when `screen_pass_stars.size() > 200`.
- Simple half-space cull: remove stars where `(pos - cam).dot(cam_forward) < 0`.
- Full six-plane frustum cull deferred to Phase 6.

### All four overlay metrics confirmed
`StarRegistry.lod_update`, `StarRegistry.generate`,
`StarRegistry.active_meshes`, `StarRegistry.screen_pass_count`
all wired with `PerformanceMonitor.begin/end/set_count`.

Spec updated: yes — `lod_update` and crossfade sections already describe Phase 5 intent;
build status updated in agent_brief.md and development_guide.md.

---

## 2026-05-05 — StarField S2: Galactic Map UI Layer

**Session:** StarField Session 2 (development_guide.md step 24)
**Spec:** `feature_spec-star_field_2.md` §Galactic Map, `feature_spec-star_field-session_breakout.md` §Session 2

### Files created / modified

- `ui/galactic_map/GalacticMap.gd` — new
- `ui/galactic_map/GalacticMap.tscn` — new
- `core/GameEventBus.gd` — added `galactic_map_toggled(open: bool)` and `warp_destination_selected(system_id: StringName)`
- `test/StarFieldTest.gd` — M key, `_setup_galactic_map()`, `_on_warp_destination_selected()`
- `.cursor/rules/starfield_s2.mdc` — new

### Key decisions

**GalacticMap extends Control, not CanvasLayer.**
CanvasLayer cannot call `_draw()` directly. Following the established PilotHUD pattern:
GalacticMap.tscn root is a Control; the test scene wraps it in a programmatically created
CanvasLayer (layer 10). No spec deviation — spec says "as a CanvasLayer" meaning it lives
in one, not that it extends one.

**Projection:** top-down XZ with `_ISO_Y = 0.15` Y-offset for slight isometric feel
as specified. Zoom-to-cursor uses the invariant that the galaxy point under the cursor
must remain fixed through the scale change.

**Continuous zoom with three density thresholds:**
- `map_zoom < 0.15`: full-out (monochrome backdrop, no paths)
- `0.15 < map_zoom < 0.55`: mid (nav paths fade in, reachable systems glow)
- `map_zoom > 0.55`: close (star colors, system ID labels, jump distance)

**No nebula color in map (S2 scope).** S4 wires `GalacticMap.map_zoom` into the sky
shader to drive nebula opacity. The property is already exposed and updated on every
zoom gesture.

**Warp selection in test scene:** `warp_destination_selected` closes the map and calls
`_warp_to_position()`, updating `StarField.current_system` so the next map open shows
correct reachability from the new position.

---

## 2026-05-05 — StarField S4: Galactic Map Nebula + Polish

**Session:** StarField Session 4 (development_guide.md step 26)
**Spec:** `feature_spec-star_field_2.md` §Zoom-Dependent Opacity, `feature_spec-star_field-session_breakout.md` §Session 4

### Files modified

- `ui/galactic_map/GalacticMap.gd` — `_push_map_zoom_to_shader()`, called from `_recalc_map_zoom()` and map close
- `test/StarFieldTest.gd` — overlay now reads `StarField.rebuild_skybox` and `StarField.destination_count` from PerformanceMonitor; removed manual `_last_rebuild_ms` timing

### Key decisions

**map_zoom piped via GalacticMap direct call to StarField.sky_material.**
GalacticMap already holds a reference to `_starfield` (the autoload) for catalog access.
`_push_map_zoom_to_shader(zoom)` calls `_starfield.sky_material.set_shader_parameter("map_zoom", zoom)`
on every zoom gesture and resets to 0.0 on map close. No new signal needed.

**All four PerformanceMonitor metrics now in overlay:**
`StarField.generate`, `StarField.rebuild_skybox`, `StarField.backdrop_count`,
`StarField.destination_count`. The manual `_last_rebuild_ms` timing was removed —
PerformanceMonitor.get_avg_ms("StarField.rebuild_skybox") is authoritative.

### Success criteria status

All items from `feature_spec-star_field_2.md` satisfied by S1–S4 combined:
- Deterministic catalog generation ✓
- Sky renders without depth artifacts ✓
- Sky shifts on warp ✓
- Spiral arms, core density, Y-thickness visible ✓
- Nebula produces organic cloud shapes with dark voids ✓
- map_zoom suppresses nebula at full zoom, rich when zoomed in ✓
- Galactic map: monochrome at full, nebula at mid, labels at close ✓
- Reachable systems glow; selection emits warp_destination_selected ✓
- StarField.generate and StarField.rebuild_skybox in overlay ✓

---

## 2026-05-05 — SolarSystem Session A: Generator + Flyable Test Scene

**Session:** SolarSystem Session A (development_guide.md step 27)
**Spec:** `feature_spec-solar_system.md`, `feature_spec-solar_system-session_breakout.md` §Session A

### Prerequisites added

`GameEventBus.gd` — Solar System signals (system_loaded, system_unloaded, origin_shifted,
exclusion_zone_entered, exclusion_zone_exited) and Warp signals (warp_state_changed,
warp_interrupted) added as required before Session A.

### Files created

- `gameplay/world/SolarSystemGenerator.gd` — pure generation logic, returns Dictionary manifest
- `gameplay/world/SolarSystem.gd` — scene manager, instantiates nodes from manifest
- `gameplay/world/Star.gd` — star sphere mesh at Y=-depth, OmniLight3D, exclusion ring disc
- `gameplay/world/Planet.gd` — sphere mesh, orbital drift in _process, moon_mode support
- `gameplay/world/Station.gd` — placement stub (docking deferred to Station spec)
- `data/solar_system_archetypes.json` — all archetypes, generation ranges, visual block
- `test/SolarSystemTest.gd` + `test/SolarSystemTest.tscn` — flyable test scene

### Key decisions

**SolarSystem builds its node tree programmatically (no .tscn).** SolarSystem.gd creates
StarGroup and PlanetGroup in _ready(); load_system() calls the generator and instantiates
nodes. Avoids needing a complex scene file that would need constant sync with code.

**planet_center_depth_min bumped from spec's 400 → 600.** Original spec values allowed
visual_radius (up to 1800) to exceed planet_depth (min 400), causing sphere to intersect
Y=0. Also added generator constraint: visual_radius = min(visual_radius, planet_depth * 0.90).
Spec notes these are placeholder values requiring tuning.

**Moon orbit center Y = 0, not parent's Y.** Moon's _process formula: global_pos.y =
center.y - moon.planet_depth. Setting center.y = 0 places moon at Y = -moon.planet_depth
(correctly below play plane). Using parent's global_pos.y (which is at -parent_depth) would
double-dip the depth, placing moons too far underground.

**ExclusionRingMesh uses flat CylinderMesh disc.** A solid flat disc at Y=0 with radius =
exclusion_radius clearly shows the danger zone from the top-down camera. Proper ring
geometry (TorusMesh, ImmediateMesh) deferred as Session A is visual-only; damage and
proper ring geometry come in Session B.

**PerformanceMonitor wrapped in SolarSystem, not SolarSystemGenerator.** Generator is a
pure RefCounted with no Node access; PerformanceMonitor begin/end live in SolarSystem.gd
which wraps the generate() call.
