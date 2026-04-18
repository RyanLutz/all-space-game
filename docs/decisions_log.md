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
