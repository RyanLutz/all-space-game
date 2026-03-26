# Project Standards Review (All Space) - 2026-03-25

## Executive Summary

The project already implements several of the core “always-on” standards well:
- `PerformanceMonitor` exists, registers Godot custom monitors, and the main hot-path systems wrap work with `begin()`/`end()` using canonical metric names (e.g. `Physics.move_and_slide`, `Physics.thruster_allocation`, `ProjectileManager.dumb_update`, `ProjectileManager.collision_checks`, `ProjectileManager.guided_update`).
- Cross-system *events* are partially routed through `GameEventBus.gd` (e.g. `beam_fired`, `weapon_fired`, `ship_destroyed`), and the F3 performance overlay is present.
- Weapons definitions are JSON-backed in `data/weapons.json`, and damage type effectiveness is sourced from `data/damage_types.json`.

However, there are several blocking deviations from the established development standards and spec expectations, mostly around:
- Event-bus contract correctness (signal signatures and payload semantics mismatch).
- Cross-system coupling rules (direct `get_node()`/method calls are used where the standards require bus-mediated communication).
- JSON data conventions/validation (missing `_comment` fields; parse errors not handled consistently).
- Weapon correctness gaps (notably `energy_pulse` dealing 0 damage with the current damage field mapping).
- Missing parts of the weapon damage pipeline (hardpoint/component damage is not wired into the current projectile->ship damage flow).

This report is intended to be used as a “gate” before authoring additional specs.

## Critical / Blocking Issues (address before new specs)

### 1) Event bus contract violations (signal signatures do not match the documented contract)

Status: Resolved by aligning `core/GameEventBus.gd` signal signatures and updating emitters/listeners.

Type: Rule violation (event-bus contract mismatch).

The documented contract in `[.cursor/rules/event-bus-contract.mdc]` specifies argument types and semantics, but `core/GameEventBus.gd` defines different argument lists.

Evidence:
- `core/GameEventBus.gd` defines `signal projectile_hit(position: Vector2, weapon_data: Dictionary, target: Node, owner_id: int)`
- `core/GameEventBus.gd` defines `signal weapon_fired(weapon_id: String, hardpoint_id: String, owner_id: int)`
- `core/GameEventBus.gd` defines `signal ship_destroyed(ship: Node, destroyer_id: int)`
- `core/GameEventBus.gd` defines `signal hardpoint_destroyed(ship: Node, hardpoint_id: String)`
- The contract expects (examples from `/.cursor/rules/event-bus-contract.mdc`):
- `projectile_hit` includes `target`, `damage`, `type`, and `position` (not `weapon_data`)
- `weapon_fired` includes `ship`, `weapon_id`, and `position`
- `ship_destroyed` includes `ship`, `position`, and `faction`
- `hardpoint_destroyed` includes `hardpoint_index`

Impact:
- Listener code (or future systems written against the contract) will be wrong even if they connect successfully.
- It becomes hard to reason about the dependency graph between systems, violating the “living document” intent of the contract.

Recommendation:
- Align `core/GameEventBus.gd` to the contract OR update the contract to reflect the intended current payload semantics.

### 2) Cross-system communication rule violations (direct `get_node()`/direct calls bypass the bus)

Type: Rule violation (architecture / cross-system coupling).

The always-on rule in `.cursorrules` states:
- “No direct cross-system references. Systems communicate through `GameEventBus.gd` (signals). Never `get_node()` across system boundaries.” (see `/home/lutz/Projects/All Space/.cursorrules`)

Evidence:
- `gameplay/weapons/HardpointComponent.gd` directly calls systems via `get_node("/root/ProjectileManager")` and calls `SpawnDumb` / `FireHitscan`
- `gameplay/weapons/HardpointComponent.gd` directly calls systems via `get_node("/root/GuidedProjectilePool")` and calls `spawn`
- `gameplay/weapons/GuidedProjectilePool.gd` directly reads other systems via `get_node_or_null("/root/ProjectileManager")` and calls `GetActiveCount()`
- `ui/debug/PerformanceOverlay.gd` reads metrics via `PerformanceMonitor`, but other systems still use direct node access patterns to locate services/singletons.

Impact:
- The architecture guarantee (“bus is the only allowed channel between systems”) is not met.
- Future systems can accidentally create new direct coupling.

Recommendation:
- Either strictly enforce bus-mediated “request” signals for projectile spawning and count queries, or explicitly document a narrow exception policy (and update the rules/contract accordingly so future specs remain consistent).

### 3) JSON data conventions are not met; JSON parsing validation is incomplete

Type: Rule violation (data conventions + validation).

The JSON convention in `/.cursor/rules/json-data.mdc` includes non-negotiable requirements:
- Each JSON file must include an `_comment` field at the top.
- JSON loaders should validate parse success and be noisy on failure.

Evidence:
- `data/weapons.json` has no `_comment` field (see `data/weapons.json`).
- `data/damage_types.json` has no `_comment` field (see `data/damage_types.json`).
- Loaders do not consistently check parse results and do not log/raise parse errors:
- `gameplay/weapons/WeaponComponent.gd`: `json.parse(file.get_as_text())` then immediately `json.get_data()` without checking error status (see `WeaponComponent.gd`).
- `gameplay/entities/Ship.gd`: `json.parse(damage_file.get_as_text())` without parse error checks (see `Ship.gd`).
- `gameplay/weapons/ProjectileManager.cs`: `json.Parse(file.GetAsText())` without error handling/validation before using `json.GetData()` (see `ProjectileManager.cs`).

Impact:
- Silent parse failures can lead to “default fallback values” and hard-to-debug runtime behavior.
- Spec authors can’t rely on data shape validation being enforced.

Recommendation:
- Add `_comment` to JSON files and standardize JSON parse validation (error logging + missing-field handling).

### 4) Weapon correctness bug: `energy_pulse` currently deals 0 damage

Type: Correctness bug.

Evidence chain:
- `data/weapons.json` defines `pulse_laser` as:
- `"archetype": "energy_pulse"`
- `"damage": 22`
- It does NOT define `damage_per_second` (see `data/weapons.json`).
- `gameplay/weapons/HardpointComponent.gd` routes `energy_pulse` through `_fire_pulse()` which calls `_fire_beam()`, which calls `ProjectileManager.FireHitscan(...)` (see `_fire_pulse` and `_fire_beam` in `HardpointComponent.gd`).
- `gameplay/weapons/ProjectileManager.cs` computes hitscan damage using:
- `GetWeaponValue(weapon, "damage_per_second", 0)` and then scales by `(1.0f / 60.0f)` (see `FireHitscan` in `ProjectileManager.cs`).

Impact:
- Since `damage_per_second` is absent for `energy_pulse`, the computed damage is 0.

Recommendation:
- Ensure `energy_pulse` uses the correct JSON field (either map to `damage` or adjust JSON schema to include `damage_per_second` for pulses).

### 5) Hardpoint/component damage pipeline is not implemented in the projectile->ship damage flow

Type: Spec-compliance gap (weapon damage pipeline).

The weapons spec expects a multi-stage pipeline that can split damage into hull and hardpoint HP using `component_damage_ratio`, driven by hit regions from `HitDetection`.

Evidence:
- `docs/Weapons_Projectiles_Spec.md` describes:
- shield absorption and hull damage
- then (if a hardpoint region is hit) splitting damage to hardpoint HP using `component_damage_ratio`
- (see “Damage Resolution Pipeline” in `docs/Weapons_Projectiles_Spec.md`)
- Current damage call chain:
- `ProjectileManager.cs` collision calls `collider.call("apply_damage", damage, damageType, hitPoint)` (see `ProjectileManager.cs` in `ProcessCollisions`)
- `Ship.gd` implements `apply_damage(...)` and only adjusts shield and hull (`shield_hp`, `hull_hp`) and emits `shield_depleted`, `ship_damaged`, `ship_destroyed` (see `Ship.gd`).
- `HardpointComponent.gd` has `apply_damage(amount: float)`, but nothing in `Ship.apply_damage` or the projectile pipeline routes hardpoint-region hits into that method.

Impact:
- Hardpoint HP and damage state degradation do not affect combat behavior because hardpoints are never damaged by projectile impacts.
- JSON fields like `component_damage_ratio` are unused in practice.

Recommendation:
- Wire `hit_position` into a `HitDetection`/hardpoint region lookup and apply shield/hull/hardpoint splitting as the spec describes.

### 6) Spec architecture mismatch: `PerformanceMonitor` is not registered through `ServiceLocator`

Type: Spec-compliance gap (service architecture).

Evidence:
- `docs/PerformanceMonitor_Spec.md` states `PerformanceMonitor` should be registered as a global service via `ServiceLocator` on bootstrap.
- Current implementation:
- `GameBootstrap.gd` instantiates and attaches `PerformanceMonitor` as a child node and keeps the `ServiceLocator.register(...)` line commented out (see `GameBootstrap.gd`).
- There is no `ServiceLocator.cs` in the repository right now (see `core/services/` structure).

Impact:
- The architecture described in the specs and C# conventions (`/.cursor/rules/csharp-projectiles.mdc`) is not what the code currently does.

Recommendation:
- Either implement `ServiceLocator.cs` and update integrations to use it, or update the spec to match the actual service wiring approach.

## High / Medium / Low Findings

### Cross-cutting “no hardcoded tunables” violations (numerous)

Rule: “No hardcoded tunable values. Anything a designer would tweak belongs in a JSON file under `data/`.” (see `.cursorrules`)

Evidence examples:
- Core ship physics/combat tunables are defined as `@export` with gameplay defaults in GDScript:
- `gameplay/physics/SpaceBody.gd`: `mass`, `linear_drag`, `alignment_drag`, `max_speed` are exported tunables.
- `gameplay/entities/Ship.gd`: `thruster_force`, `torque_thrust_ratio`, `max_angular_accel`, power/shield/hull tuning fields are exported.
- `gameplay/weapons/HardpointComponent.gd`: heat capacity and cooling/cooldown are exported.
- (see the respective files).
- `gameplay/weapons/WeaponComponent.gd` hardcodes default hardpoint configs when `hardpoint_configs` is empty: offsets, facings, arcs, groups, and weapon assignments are all embedded in GDScript (see the `_spawn_hardpoints()` default block).

Impact:
- Designers cannot rebalance via JSON-only workflows.
- Specs cannot reliably claim “everything tunable lives in JSON”.

Recommendation:
- Move these tunables into JSON (e.g., `ships.json`, `hardpoints.json` or ship-loadout JSON) and keep exported values either as derived/readonly or editor convenience only.

### Performance timing assumptions are hardcoded (potential correctness + scaling issue)

Evidence:
- `gameplay/weapons/ProjectileManager.cs` assumes `60fps` in collision stepping:
- `float step = 1.0f / 60.0f; // Assume 60fps step for raycast`
- and hitscan beam/pulse damage scaling uses `(1.0f / 60.0f)` inside `FireHitscan`.

Impact:
- If the physics tick rate changes or frame rate differs from 60, projectile movement/collision and “damage per second converted per shot/frame” will be incorrect.

Recommendation:
- Replace fixed-step scaling with delta-driven timing (or pass the correct time step).

### Performance overlay guided count is hardcoded to 0

Evidence:
- `ui/debug/PerformanceOverlay.gd` sets guided projectile “active” count to `0` with a comment that it’s not yet integrated (see the `"Projectiles (guided)"` formatting block).

Impact:
- The overlay is misleading for guided-missile performance monitoring.

Recommendation:
- Use `GuidedProjectilePool`’s active count metric (or `ProjectileManager.active_count` split metrics) to populate the overlay.

### Encapsulation breach: `ProjectileRenderer` accesses GuidedProjectilePool private state

Evidence:
- `gameplay/weapons/ProjectileRenderer.gd` directly reads `var pool = _guided_pool._pool`, i.e. a non-public internal member.

Impact:
- Tight coupling to internals increases refactor risk.

Recommendation:
- Expose a public getter or structured query API for renderer consumption.

## Spec Conflicts to Resolve Before Writing New Specs

### Physics spec (3D) vs implementation (2D)

Evidence:
- `docs/Physics_Movement_Spec.md` describes a 3D pipeline (CharacterBody3D, Vector3 heading on Y axis, XZ plane constraint).
- Actual implementation:
- `gameplay/physics/SpaceBody.gd` extends `CharacterBody2D` and uses `Vector2` physics and `rotation` about 2D.

Impact:
- New specs built on the current physics spec will conflict with real code.

Recommendation:
- Decide which physics approach is authoritative (update the spec to match current 2D implementation, or refactor code to match the 3D spec).

### Weapons spec pipeline (hardpoint splitting) vs implementation (ship-only damage)

Evidence:
- `docs/Weapons_Projectiles_Spec.md` requires hit detection + hardpoint-region damage splitting.
- Current code applies damage directly to the ship’s shield and hull in `Ship.gd` and never routes to `HardpointComponent.gd` in the projectile collision path (see `ProjectileManager.cs`, `Ship.gd`).

Impact:
- Any new weapon-related specs will be based on missing core behavior.

Recommendation:
- Update the weapons spec to reflect current MVP scope OR implement the missing pipeline first.

## Suggested Follow-up Checklist (non-invasive, report-driven)

1. Align the `GameEventBus.gd` signal signatures and payload ordering to `/.cursor/rules/event-bus-contract.mdc` (or update the contract to match intent).
2. Remove or document the exception to the “no direct cross-system references” rule for projectile spawning/count queries; prefer bus-based “request” signals if the rule is kept strict.
3. Make JSON data conventions consistent:
   Add `_comment` fields to all JSON files under `data/`, and standardize JSON parse error checks and missing-field logging.
4. Fix `energy_pulse` damage mapping (ensure `ProjectileManager.FireHitscan` uses the correct JSON field for pulse weapons).
5. Integrate hardpoint-region damage into the projectile collision path so hardpoint HP/damage state can affect gameplay as described in `docs/Weapons_Projectiles_Spec.md`.
6. Resolve the physics spec mismatch (2D vs 3D) so subsequent specs target the implemented movement model.
7. Decide on the global-service approach: implement `ServiceLocator.cs` or revise `docs/PerformanceMonitor_Spec.md` and C# conventions to match the current bootstrap wiring.

