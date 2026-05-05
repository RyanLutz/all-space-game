# GameEventBus — Signal Contract
*All Space Combat MVP — Cross-System Event Catalog*

All cross-system communication goes through `GameEventBus.gd`. No system should ever
call methods on another system directly or use `get_node()` to reach across system
boundaries.

Signals are defined in `core/GameEventBus.gd`. **Define signals here before
implementing them.** The emitter and listener columns define the dependency graph
between systems. If a new system needs a new signal, add a row to this document
and the signal definition to `GameEventBus.gd` before any implementation begins.

---

## Naming Convention

- **Past tense for events:** something happened → `ship_destroyed`, `projectile_hit`
- **Present tense for requests:** do something → `request_spawn_dumb`, `request_fire_hitscan`

## Type Contract

All world-space positions and velocities are **`Vector3`**, even though Y is always 0.
This matches the 3D play plane contract in `All_Space_Core_Spec.md` Section 6.

- ✅ `position: Vector3` — correct (Y = 0 enforced by the emitting system)
- ✅ `velocity: Vector3` — correct (velocity.y = 0 always)
- ❌ `position: Vector2` — banned; no 2D world-space values anywhere
- ✅ `chunk_coords: Vector2i` — permitted for integer chunk grid indices only

Entity references use `Node` (not `Node3D` or `CharacterBody3D`) to keep listeners
decoupled from the concrete scene node type.

---

## GDScript Signal Definitions

Copy this block verbatim into `core/GameEventBus.gd`. Signals are grouped by category
for readability — GDScript does not require them to be grouped, but maintain this order.

```gdscript
# core/GameEventBus.gd
extends Node

# ─── Combat ────────────────────────────────────────────────────────────────────
signal projectile_hit(target: Node, damage: float, damage_type: String,
                      position: Vector3, component_ratio: float)
signal ship_destroyed(ship: Node, position: Vector3, faction: String)
signal weapon_fired(ship: Node, weapon_id: String, position: Vector3)
signal hardpoint_state_changed(ship: Node, hardpoint_id: String, new_state: String)
signal projectile_spawned(position: Vector3, velocity: Vector3,
                          weapon_data: Dictionary)

# ─── Requests ──────────────────────────────────────────────────────────────────
signal request_spawn_dumb(position: Vector3, velocity: Vector3, lifetime: float,
                          weapon_id: String, owner_id: int)
signal request_fire_hitscan(origin: Vector3, direction: Vector3, range_val: float,
                            weapon_id: String, owner_id: int, hardpoint_id: String)
signal hitscan_resolved(origin: Vector3, end: Vector3, hit: bool,
                        weapon_id: String, owner_id: int, hardpoint_id: String)
signal request_spawn_guided(position: Vector3, velocity: Vector3,
                            guidance_mode: String, weapon_data: Dictionary,
                            owner_id: int)

# ─── Ship State ─────────────────────────────────────────────────────────────────
signal shield_depleted(ship: Node)
signal hull_critical(ship: Node, percent: float)
signal power_depleted(ship: Node)

# ─── AI ────────────────────────────────────────────────────────────────────────
signal ai_state_changed(ship_id: int, old_state: String, new_state: String)
signal ai_target_acquired(ship_id: int, target_id: int)
signal ai_target_lost(ship_id: int)

# ─── World ─────────────────────────────────────────────────────────────────────
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal explosion_triggered(position: Vector3, radius: float, intensity: float)

# ─── Game Mode ─────────────────────────────────────────────────────────────────
signal game_mode_changed(old_mode: String, new_mode: String)

# ─── Tactical Orders ───────────────────────────────────────────────────────────
signal request_tactical_move(ship_ids: Array, destination: Vector3, queue_mode: String)
signal request_tactical_attack(ship_ids: Array, target_id: int, queue_mode: String)
signal request_tactical_mine(ship_ids: Array, asteroid_id: int, queue_mode: String)
signal request_tactical_dock(ship_ids: Array, station_id: int)
signal request_tactical_stop(ship_ids: Array)
signal request_tactical_set_stance(ship_id: int, stance: int)
signal request_tactical_set_escort_stance(stance: int)
signal request_tactical_add_to_escort(ship_id: int)
signal request_tactical_remove_from_escort(ship_id: int)
signal tactical_selection_changed(ship_ids: Array)
signal context_menu_requested(ship_id: int, screen_pos: Vector2)

# ─── Escort & Formation ───────────────────────────────────────────────────────
signal escort_queue_changed(ship_ids: Array)
signal escort_stance_changed(stance: int)
signal request_formation_destination(ship_id: int, destination: Vector3)
signal navigation_order_completed(ship_id: int)

# ─── Damage ───────────────────────────────────────────────────────────────────
signal ship_damaged(victim: Node, attacker: Node)

# ─── Station ───────────────────────────────────────────────────────────────────
signal dock_requested(ship: Node, station: Node)
signal dock_complete(ship: Node, station: Node)
signal undock_requested(ship: Node)
signal loadout_changed(ship: Node, slot_id: String, item_id: String)

# ─── Player State ──────────────────────────────────────────────────────────────
signal player_ship_changed(ship: Node)

# ─── Solar System ──────────────────────────────────────────────────────────────
signal system_loaded(system_id: String)
signal system_unloaded(system_id: String)
signal origin_shifted(offset: Vector3)
signal exclusion_zone_entered(ship: Node, star_index: int)
signal exclusion_zone_exited(ship: Node, star_index: int)

# ─── Warp ───────────────────────────────────────────────────────────────────────
signal warp_state_changed(ship: Node, old_state: String, new_state: String)
signal warp_interrupted(ship: Node, reason: String)

# ─── Debug ─────────────────────────────────────────────────────────────────────
signal debug_toggled(visible: bool)
```

---

## Combat Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `projectile_hit` | `target: Node, damage: float, damage_type: String, position: Vector3, component_ratio: float` | ProjectileManager, GuidedProjectilePool | Ship (damage pipeline) |
| `ship_destroyed` | `ship: Node, position: Vector3, faction: String` | Ship | SelectionState, EscortQueue, StanceController, future: VFX, Audio |
| `weapon_fired` | `ship: Node, weapon_id: String, position: Vector3` | WeaponComponent, ProjectileManager (hitscan) | Future: VFX, Audio |
| `hardpoint_state_changed` | `ship: Node, hardpoint_id: String, new_state: String` | HardpointComponent | Future: Ship (capability update), UI |
| `projectile_spawned` | `position: Vector3, velocity: Vector3, weapon_data: Dictionary` | *(not yet emitted)* | Future: VFX (tracer), Debug overlay |

**`hardpoint_state_changed` — `new_state` values:** `"nominal"`, `"damaged"`, `"critical"`, `"destroyed"`

**`projectile_hit` — `component_ratio` note:** The ratio of damage routed to the hardpoint vs hull. `0.0` for a pure-hull hit. Determined by `weapon_data.component_damage_ratio`. The Ship damage pipeline splits the hit internally using this value — listeners do not need to re-derive it.

**`projectile_spawned` — status:** Defined but not yet emitted by any system. Reserved for VFX tracer effects.

---

## Request Signals (Present Tense)

Request signals cross a system boundary: the sender cannot or should not call the
receiver directly. The receiver owns the behavior; the sender owns the trigger.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `request_spawn_dumb` | `position: Vector3, velocity: Vector3, lifetime: float, weapon_id: String, owner_id: int` | WeaponComponent | ProjectileManager |
| `request_fire_hitscan` | `origin: Vector3, direction: Vector3, range_val: float, weapon_id: String, owner_id: int, hardpoint_id: String` | WeaponComponent | ProjectileManager |
| `hitscan_resolved` | `origin: Vector3, end: Vector3, hit: bool, weapon_id: String, owner_id: int, hardpoint_id: String` | ProjectileManager | WeaponComponent |
| `request_spawn_guided` | `position: Vector3, velocity: Vector3, guidance_mode: String, weapon_data: Dictionary, owner_id: int` | WeaponComponent | GuidedProjectilePool |

**`owner_id` note:** Pass `ship.get_instance_id()`. ProjectileManager uses this to
prevent a ship from colliding with its own projectiles during their initial frames.

**`range_val` note:** The parameter is named `range_val` (not `range`) to avoid
shadowing GDScript's built-in `range()` function.

---

## Ship State Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `shield_depleted` | `ship: Node` | Ship | Future: AI (press advantage), Audio, VFX |
| `hull_critical` | `ship: Node, percent: float` | Ship | Future: AI (flee trigger), UI (hull warning) |
| `power_depleted` | `ship: Node` | *(not yet emitted)* | Future: WeaponComponent (cease fire), UI (power warning) |

**`hull_critical` threshold:** Emitted when hull drops below 25% of max. `percent`
is the current HP as a fraction of max HP (e.g. `0.18` for 18%). Emit only once per
threshold crossing — do not emit every frame while hull is below threshold.

**`shield_depleted` note:** Emitted when `shield_hp` reaches zero. Not re-emitted
while shields remain depleted. Emitted again the next time shields are depleted after
recovering above zero.

**`power_depleted` — status:** Defined but not yet emitted. Reserved for future power management.

---

## AI Signals

AI state transitions use flat scalar args rather than a Dictionary. Prefer flat args
for signals that are emitted at high frequency (once per state transition per ship)
— it avoids Dictionary allocation overhead.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `ai_state_changed` | `ship_id: int, old_state: String, new_state: String` | AIController | Future: Debug overlay, UI |
| `ai_target_acquired` | `ship_id: int, target_id: int` | AIController | Future: UI, Audio |
| `ai_target_lost` | `ship_id: int` | AIController | Future: UI, Audio |

**`ai_state_changed` — `new_state` values:** `"IDLE"`, `"PURSUE"`, `"ENGAGE"`,
`"FLEE"`, `"REGROUP"`, `"SEARCH"`, `"ORBIT"`, `"TACTICAL_ATTACK"` (TACTICAL_ATTACK added in Phase 14).

**`ship_id` / `target_id`:** Use `Node.get_instance_id()`. Listeners that need the
actual node call `instance_from_id(ship_id)` and null-check before use — the ship
may have been freed between emission and receipt.

---

## Damage Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `ship_damaged` | `victim: Node, attacker: Node` | Ship | StanceController (defensive fan-out) |

**`attacker` note:** May be `null` if the attacker is unknown or has been freed.
Listeners must null-check. `attacker_id` is resolved via `instance_from_id()` in
Ship.apply_damage before emitting.

---

## World Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `chunk_loaded` | `chunk_coords: Vector2i` | ChunkStreamer | Future: AI spawner, Debug overlay |
| `chunk_unloaded` | `chunk_coords: Vector2i` | ChunkStreamer | Future: AI spawner (despawn), Debug overlay |
| `explosion_triggered` | `position: Vector3, radius: float, intensity: float` | Asteroid (on destruction), GuidedProjectilePool (blast) | Future: VFX, Audio, physics impulse system |

**`chunk_coords` — `Vector2i` is permitted** for integer grid coordinates. This is
the one place `Vector2i` is used; world positions derived from chunk coordinates must
be `Vector3` with Y = 0.

**`explosion_triggered` — `intensity`:** A normalized float (0.0-1.0) representing
the relative scale of the explosion. `1.0` for a ship death or large asteroid.
`0.4-0.6` for a small asteroid. Used by VFX to select the appropriate effect tier.

---

## Game Mode Signals

Mode transitions affect the camera, input routing, UI, and audio. All systems that
care about the current mode listen to `game_mode_changed` rather than polling a global.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `game_mode_changed` | `old_mode: String, new_mode: String` | InputManager (Tab key) | GameCamera, SelectionState, TacticalInputHandler, FormationController |

**`new_mode` / `old_mode` values:** `"pilot"`, `"tactical"`. Galactic is a Phase 3
concern and is not defined here.

**Transition contract:** The signal is emitted **after** the mode variable has been
updated, so any listener can safely read the current mode from the emitter. Audio and
camera transitions should begin immediately on receipt — mode switches must complete
within one frame to feel responsive.

---

## Tactical Order Signals

These signals carry orders issued from the Tactical mode interface (RTS drag-select,
right-click commands). They are request signals — present tense — because they
instruct NavigationController to act, not notify that an act has occurred.

`ship_ids` is `Array` (untyped) rather than `Array[int]` because GDScript typed arrays
in signals have limited editor support in Godot 4.x. Listeners cast elements to `int`
and call `instance_from_id()`.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `request_tactical_move` | `ship_ids: Array, destination: Vector3, queue_mode: String` | TacticalInputHandler | NavigationController, EscortQueue (away-on-orders) |
| `request_tactical_attack` | `ship_ids: Array, target_id: int, queue_mode: String` | TacticalInputHandler, StanceController (defensive fan-out) | AIController, EscortQueue (away-on-orders) |
| `request_tactical_mine` | `ship_ids: Array, asteroid_id: int, queue_mode: String` | TacticalInputHandler | EscortQueue (away-on-orders), future: MiningController |
| `request_tactical_dock` | `ship_ids: Array, station_id: int` | TacticalInputHandler | Future: Station |
| `request_tactical_stop` | `ship_ids: Array` | TacticalInputHandler, EscortQueue (recall) | NavigationController, AIController, EscortQueue |
| `request_tactical_set_stance` | `ship_id: int, stance: int` | ContextMenu, EscortQueue (stance reset on remove) | StanceController |
| `request_tactical_set_escort_stance` | `stance: int` | EscortPanel | EscortQueue |
| `request_tactical_add_to_escort` | `ship_id: int` | ContextMenu | EscortQueue |
| `request_tactical_remove_from_escort` | `ship_id: int` | ContextMenu | EscortQueue |
| `tactical_selection_changed` | `ship_ids: Array` | SelectionState | Future: Tactical UI (status panels), GameCamera |
| `context_menu_requested` | `ship_id: int, screen_pos: Vector2` | TacticalInputHandler | ContextMenu |

**`queue_mode` note:** Added in Phase 13. Values: `"replace"` (clear existing orders),
`"append"` (queue after current). Default is `"replace"`. Used by EscortQueue to
detect when an escort ship receives direct orders (away-on-orders).

**`destination` note:** Always `Vector3` with Y = 0. TacticalInputHandler derives this
from a mouse-to-world ray-plane intersection against Y = 0 before emitting.

**`tactical_selection_changed` note:** Emitted on every selection change, including
clearing the selection (empty `ship_ids` array). UI must handle empty arrays gracefully.

**`context_menu_requested` — `screen_pos`:** `Vector2` is permitted here because this
is a screen-space coordinate, not a world-space position.

**`stance` values:** Use the `Stance` enum from StanceController: `0 = AGGRESSIVE`,
`1 = DEFENSIVE`, `2 = EVASIVE`, `-1 = clear stance`.

---

## Escort & Formation Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `escort_queue_changed` | `ship_ids: Array` | EscortQueue | StanceController, EscortPanel |
| `escort_stance_changed` | `stance: int` | EscortQueue | StanceController, EscortPanel |
| `request_formation_destination` | `ship_id: int, destination: Vector3` | FormationController | NavigationController |
| `navigation_order_completed` | `ship_id: int` | NavigationController, AIController | EscortQueue (return-to-escort check) |

**`escort_queue_changed` note:** Emitted whenever ships are added to or removed from
the escort queue. `ship_ids` is a duplicate of the internal queue array.

**`navigation_order_completed` note:** Emitted when a NavigationController finishes
its current tactical order, or when AIController completes a tactical attack. EscortQueue
uses this to return ships to formation if they were on away-orders.

---

## Station Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `dock_requested` | `ship: Node, station: Node` | *(not yet emitted)* | Future: Station |
| `dock_complete` | `ship: Node, station: Node` | *(not yet emitted)* | Future: LoadoutUI, Audio |
| `undock_requested` | `ship: Node` | *(not yet emitted)* | Future: Station |
| `loadout_changed` | `ship: Node, slot_id: String, item_id: String` | *(not yet emitted)* | Future: economy, save system |

**Status:** All station signals are reserved for the Station & Loadout UI phase (post-MVP). None are currently emitted or listened to.

---

## Player State Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `player_ship_changed` | `ship: Node` | PlayerState | GameCamera, InputManager, ChunkStreamer, ShipFactoryTest |

**`player_ship_changed` note:** Emitted on game start (initial ship) and any time the
active player ship changes (post-MVP: ship transfer, respawn). The signal carries the
new ship. A `null` value is valid — signals that the player has no active ship
(e.g. during a cinematic). Listeners must null-check before reading ship state.

---

## Debug Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `debug_toggled` | `visible: bool` | PilotLoopTest (F3 key) | Future: Debug overlays |

---

## Solar System Signals

These signals are required by `feature_spec-solar_system.md`. They must be added to
`GameEventBus.gd` before any Solar System implementation begins.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `system_loaded` | `system_id: String` | SolarSystem | ChunkStreamer (begin streaming), AI, UI |
| `system_unloaded` | `system_id: String` | SolarSystem | ChunkStreamer (clear chunks), AI |
| `origin_shifted` | `offset: Vector3` | OriginShifter | Any system tracking absolute world positions |
| `exclusion_zone_entered` | `ship: Node, star_index: int` | Star | VFX (heat shimmer), Audio (alarm), UI (warning) |
| `exclusion_zone_exited` | `ship: Node, star_index: int` | Star | VFX, Audio (clear alarm), UI |

**`origin_shifted` — `offset`:** The world-space translation applied to all physics
bodies. Systems that cache absolute positions (e.g. AI waypoints, navigation targets)
must subtract this offset from their stored values.

**`exclusion_zone_entered` / `exited` — `star_index`:** Zero-based index into the
system's star array. `0` for a single star; `0` or `1` for a binary pair. Listeners
that need the star node call `SolarSystem.get_star(star_index)`.

**Status:** Not yet implemented. These signals are reserved for the Solar System
implementation phase (step 26).

---

## Warp Signals

These signals are required by `feature_spec-solar_system.md` (WarpDrive state machine).
They must be added to `GameEventBus.gd` before WarpDrive implementation begins.

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `warp_state_changed` | `ship: Node, old_state: String, new_state: String` | WarpDrive | VFX (engine trail), Audio (warp hum), UI |
| `warp_interrupted` | `ship: Node, reason: String` | WarpDrive | VFX (discharge flash), Audio (interrupt SFX) |

**`warp_state_changed` — `new_state` / `old_state` values:** `"IDLE"`, `"SPOOLING"`,
`"ACTIVE"`, `"DECELERATING"`.

**`warp_interrupted` — `reason` values:** `"damage"` (hit above interrupt threshold),
`"exclusion"` (approached star exclusion zone), `"input"` (player released key).

**Status:** Not yet implemented. Reserved for the Solar System / WarpDrive
implementation phase (step 26).

---

## How to Add a New Signal

1. Add the signal definition to `core/GameEventBus.gd` in the correct category block.
2. Add a row to the relevant table above with emitter and listener columns filled in.
3. Follow the naming convention: past tense for events, present tense for requests.
4. Use `Vector3` for all world-space positions and velocities; `Node` for entity refs.
5. Keep the GDScript definitions block at the top of this document in sync.

Do not emit a signal from a system before it is defined in this document.
Do not listen to a signal without being listed in the Listened By column —
undocumented listeners create invisible dependencies that break future refactoring.

---

## Audit Log

**2026-05-04 — Solar System + Warp signals added (spec-only):**
Added `system_loaded`, `system_unloaded`, `origin_shifted`, `exclusion_zone_entered`,
`exclusion_zone_exited` (Solar System) and `warp_state_changed`, `warp_interrupted`
(WarpDrive) per `feature_spec-solar_system.md`. All are reserved — not yet implemented.
Signal definitions added to the GDScript block above.

**Phase 16 audit (2026-04-21):** Reconciled spec with code after phases 12-15.

Signals added to spec (were in code but undocumented):
- `request_tactical_stop`, `request_tactical_set_stance`, `request_tactical_set_escort_stance`,
  `request_tactical_add_to_escort`, `request_tactical_remove_from_escort` — Phase 13-14 tactical orders
- `context_menu_requested` — Phase 14 context menu
- `escort_queue_changed`, `escort_stance_changed`, `request_formation_destination`,
  `navigation_order_completed` — Phase 14 escort & formation
- `ship_damaged` — Phase 14 damage/stance system
- `debug_toggled` — PilotLoopTest debug toggle

Signature changes documented:
- `request_tactical_move`, `request_tactical_attack`, `request_tactical_mine` —
  gained `queue_mode: String` parameter (Phase 13)

Emitter/listener columns updated to reflect actual connections as built.

Signals defined but not yet emitted (reserved for future phases):
- `projectile_spawned` — future VFX tracers
- `power_depleted` — future power management
- `dock_requested`, `dock_complete`, `undock_requested`, `loadout_changed` — Station & Loadout UI (post-MVP)

---

## Files

```
/core/
    GameEventBus.gd     ← signal definitions; no logic, no state
```

`GameEventBus.gd` is a ServiceLocator-registered singleton that
contains only signal declarations. It holds no state and runs no logic. Systems
connect to its signals in their own `_ready()` calls and emit via the shared reference.

---

## Dependencies

- None. `GameEventBus` is the lowest-level dependency in the project.
- All other systems depend on it. Build it first, before any system that needs
  cross-system communication.

---

## Success Criteria

- [x] All signals listed in this document are defined in `core/GameEventBus.gd`
- [x] No system calls methods on another system directly — all cross-system
  communication goes through these signals
- [x] All world-space position and velocity arguments are `Vector3` — no `Vector2`
  in any signal argument (`context_menu_requested.screen_pos` is screen-space, permitted)
- [x] Adding a new signal requires a row in this document and a definition in
  `GameEventBus.gd` — nothing else
- [x] `tactical_selection_changed` with an empty array does not crash any listener
- [x] `player_ship_changed` with `null` does not crash any listener
- [x] AI signals (`ai_state_changed`, `ai_target_acquired`) survive the emitting
  ship being freed between emission and receipt — all listeners null-check
  `instance_from_id()` results
