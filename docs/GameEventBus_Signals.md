# GameEventBus — Signal Contract
*All Space Combat MVP — Cross-System Event Catalog*

All cross-system communication goes through `GameEventBus.gd`. No system should ever call methods on another system directly or use `get_node()` to reach across system boundaries.

Signals are defined in `core/GameEventBus.gd`. **Define signals here before implementing them.** The emitter and listener columns define the dependency graph between systems.

**Naming convention:**
- Past tense for events: `projectile_hit`, `ship_destroyed`, `weapon_fired`
- Present tense for requests: `request_spawn_dumb`, `request_fire_hitscan`

---

## Combat Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `projectile_hit` | `target: Node2D, damage: float, type: String, position: Vector2` | ProjectileManager | Ship (damage system) |
| `ship_destroyed` | `ship: Node2D, position: Vector2, faction: String` | Ship | ChunkStreamer (debris), AI (threat update) |
| `weapon_fired` | `ship: Node2D, weapon_id: String, position: Vector2` | WeaponComponent | Audio, visual FX |
| `hardpoint_destroyed` | `ship: Node2D, hardpoint_index: int` | HardpointComponent | Ship (capability update) |
| `projectile_spawned` | `position: Vector2, velocity: Vector2, weapon_data: Dictionary` | ProjectileManager, GuidedProjectilePool | ProjectileRenderer (debug), VFX |

---

## Request Signals (Present Tense)

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `request_spawn_dumb` | `position: Vector2, velocity: Vector2, lifetime: float, weapon_id: String, owner_id: int` | HardpointComponent | ProjectileManager |
| `request_fire_hitscan` | `origin: Vector2, direction: Vector2, range_val: float, weapon_id: String, owner_id: int` | HardpointComponent | ProjectileManager |
| `request_spawn_guided` | `position: Vector2, velocity: Vector2, guidance_mode: String, weapon_data: Dictionary, owner_id: int` | HardpointComponent | GuidedProjectilePool |

---

## Ship State Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `shield_depleted` | `ship: Node2D` | Ship | AI (behavior change) |
| `hull_critical` | `ship: Node2D, percent: float` | Ship | AI (flee trigger — future) |
| `power_depleted` | `ship: Node2D` | Ship | WeaponComponent (cease fire) |

---

## AI Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `ai_state_changed` | `{ ship_id: int, old_state: String, new_state: String }` | AIController | Debug overlay, future UI |
| `ai_target_acquired` | `{ ship_id: int, target_id: int }` | AIController | Future UI, audio |
| `ai_target_lost` | `{ ship_id: int }` | AIController | Future UI, audio |

---

## World Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `chunk_loaded` | `chunk_coords: Vector2i` | ChunkStreamer | AI (spawn), Asteroids |
| `chunk_unloaded` | `chunk_coords: Vector2i` | ChunkStreamer | AI (despawn), Asteroids |

---

## Station Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `dock_requested` | `ship: Node2D, station: Node2D` | Ship | Station |
| `dock_complete` | `ship: Node2D, station: Node2D` | Station | UI (open loadout) |
| `undock_requested` | `ship: Node2D` | UI | Station |

---

## Player State Signals

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `player_ship_changed` | `ship: Node2D` | PlayerState | Camera (follow), Input, UI |

---

## How to Add a New Signal

1. Define the signal in `core/GameEventBus.gd`
2. Add a row to the relevant table above with emitter and listener columns filled in
3. Signal names must be past tense for events, present tense for requests
4. The emitter and listener columns are the dependency graph — keep them accurate
