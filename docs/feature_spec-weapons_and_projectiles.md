# Weapons & Projectiles System Specification
*All Space Combat MVP — Weapons, Hardpoints, and Projectile Management*

---

## 1. Overview

A data-driven weapon system built around hardpoints on ships, five weapon archetypes, a
dual heat/power resource model, and a high-performance projectile pipeline. Everything
that controls how a weapon behaves — damage, fire rate, heat, power draw, guidance mode
— lives in JSON. No weapon behavior is hardcoded.

The system operates fully in 3D. All positions and velocities are `Vector3` with
`y = 0` enforced at all times. Projectiles inherit the firing ship's 3D velocity at
spawn. Detection and trigger volumes use `Area3D`.

**Design Goals:**
- Weapon archetypes feel meaningfully different to use
- Hardpoint type and fire group assignment create real tactical decisions
- Heat and power create interesting tradeoffs under sustained fire
- Damage types reward mixed loadouts
- All tunable values live in JSON — no recompile for balance passes
- Weapon models are visually present on ships, positioned at hardpoint empties
- Each weapon is a self-contained folder — adding a new weapon requires no code changes

---

## 2. Architecture

```
Ship (CharacterBody3D)
    └── ShipVisual (Node3D)
            └── Hull_MeshInstance3D
                    └── HardpointEmpty_hp_nose_small (Node3D)   ← baked into mesh
                            ├── HardpointComponent.gd           ← type, arc, heat, damage state
                            └── WeaponModel (MeshInstance3D)    ← from content folder
                                    └── Muzzle (Marker3D)       ← projectile spawn point

ProjectileManager.cs        (C# — dumb pool for ballistic, pulse, hitscan beam)
GuidedProjectilePool.gd     (GDScript — missile pool)
```

`HardpointComponent.gd` is the behavioral owner of each hardpoint. It knows the type
(fixed/gimbal/turret), fire arc, current heat, damage state, and which fire groups it
belongs to. `WeaponComponent.gd` is attached to the weapon model and owns the firing
logic — it reads weapon stats from JSON and calls into `ProjectileManager` or
`GuidedProjectilePool` via `GameEventBus`.

The player ship and AI ships share identical hardpoint and weapon infrastructure. There
is no separate "player weapon" or "AI weapon" path.

---

## 3. Content Structure

Each weapon lives in its own folder under `/content/weapons/`. The folder name is the
weapon's content ID.

```
/content/weapons/
    /autocannon_light/
        weapon.json
        model.glb           ← MeshInstance3D with Muzzle marker child
        icon.png
    /beam_laser/
        weapon.json
        model.glb
        icon.png
    /pulse_laser/
        weapon.json
        model.glb
        icon.png
    /missile_dumb/
        weapon.json
        model.glb
        icon.png
    /missile_heatseeking/
        weapon.json
        model.glb
        icon.png
```

`ContentRegistry.gd` scans `/content/weapons/` at startup and indexes every folder
that contains a `weapon.json`. Weapon data and asset paths are always resolved through
`ContentRegistry` — no path is ever hardcoded in GDScript.

**Adding a new weapon requires only creating a new folder. No code changes.**

---

## 4. Hardpoints

### What a Hardpoint Is

A hardpoint is a **named empty node** (`Node3D`) baked into a ship part mesh at
authoring time. Its name follows the convention:

```
HardpointEmpty_{id}_{size}
```

Examples:
```
HardpointEmpty_hp_nose_small
HardpointEmpty_hp_port_wing_small
HardpointEmpty_hp_stbd_wing_small
HardpointEmpty_hp_dorsal_medium
```

The empty's **world transform** defines the hardpoint's position and default facing
direction. The forward axis (`-transform.basis.z`, matching Godot's 3D forward) is the
muzzle direction. No position or orientation data is needed in JSON — the mesh artist
bakes it into the node's transform.

### Hardpoint JSON (in ship.json)

Hardpoints are defined in the ship's JSON, not in `weapon.json`. Each entry matches a
named empty in the assembled mesh:

```json
"hardpoints": [
    { "id": "hp_nose",       "type": "gimbal", "size": "small" },
    { "id": "hp_port_wing",  "type": "fixed",  "size": "small" },
    { "id": "hp_stbd_wing",  "type": "fixed",  "size": "small" }
]
```

### Hardpoint Types and Fire Arcs

| Type | Default Arc | Notes |
|---|---|---|
| Fixed | ~5° | Ship must aim. No rotation. |
| Gimbal | ~25° | Auto-rotates within arc to compensate for heading lag. |
| Partial Turret | ~120° | Cannot fire directly behind. |
| Full Turret | 360° | Any direction. Heaviest, slowest traverse. |

Turrets and gimbals are distinguished only by arc width — the tracking logic is the
same. Gimbal tracking rotates the weapon model in local space toward the player's
aim point, clamped to arc limits.

**Gimbal behavior:** The gimbal compensates for the angular lag described in the Physics
spec. On heavy ships, gimballed weapons can maintain fire on a target even when the
ship's heading has not fully caught up. AI ships benefit from this identically to the
player.

### Fire Groups

Weapons are organized into fire groups. The player fires an entire group simultaneously:

| Group | Default Input |
|---|---|
| 1 — Primary | Left click |
| 2 — Secondary | Right click |
| 3 — Tertiary | TBD (middle mouse or dedicated key) |

Hardpoints use a **many-to-many** mapping — a single hardpoint can belong to multiple
groups. A hardpoint fires whenever any of its assigned groups is activated. Group
assignments are configured at the station loadout screen and stored in the ship's
loadout data.

```json
"default_loadout": {
    "weapons": {
        "hp_nose":      { "weapon_id": "beam_laser",      "groups": [1] },
        "hp_port_wing": { "weapon_id": "autocannon_light", "groups": [2] },
        "hp_stbd_wing": { "weapon_id": "autocannon_light", "groups": [2] }
    }
}
```

`HardpointComponent.gd` stores `fire_groups: Array[int]` and checks the ship's
`input_fire: Array[bool]` each frame.

### Hardpoint Ownership

The hardpoint owns its behavioral metadata. The weapon is unaware of these:

| Property | Owner | Source |
|---|---|---|
| Position & rotation | Hardpoint empty | Baked into mesh |
| Type (fixed/gimbal/turret) | Hardpoint | ship.json |
| Fire arc | Hardpoint | Derived from type |
| Size constraint | Hardpoint | ship.json and empty name |
| Heat capacity / cooling | Hardpoint | `HardpointComponent.gd` defaults by type |
| Damage state | Hardpoint | Runtime |
| Fire group assignment | Hardpoint | Loadout data |

### Hardpoint Damage States

Hardpoints are targetable components with their own HP. When a projectile impact point
falls within a hardpoint's region, damage is split between hull and hardpoint HP via
`component_damage_ratio` defined per weapon in `weapon.json`.

| State | HP % | Effect |
|---|---|---|
| Nominal | 100–60% | Full performance |
| Damaged | 59–25% | Reduced fire rate; increased heat generation |
| Critical | 24–1% | Chance to misfire per shot |
| Destroyed | 0% | Weapon non-functional until repaired |

Emit `hardpoint_destroyed` on `GameEventBus` when HP reaches 0.

### Weapon Model Assembly

When `ShipFactory.gd` assembles a ship:

1. Locate `HardpointEmpty_{id}_{size}` in the assembled part tree
2. Attach `HardpointComponent.gd` — set type, arc, size, fire groups from loadout
3. Look up weapon ID from resolved loadout
4. Load weapon data via `ContentRegistry.get_weapon(weapon_id)`
5. Get model path via `ContentRegistry.get_asset_path(weapon_data, "model")`
6. Instance the weapon model as a **child** of the hardpoint empty — transform inherited
7. Attach `WeaponComponent.gd` to the weapon model — configure from weapon data

```
HardpointEmpty_hp_nose_small (Node3D)           ← baked in mesh, Y = 0 enforced
    ├── HardpointComponent.gd                   ← attached to the empty node
    └── WeaponModel (MeshInstance3D)             ← from content/weapons/<id>/model.glb
            └── Muzzle (Marker3D)               ← projectile spawn point
```

### Weapon Colorization

Weapon models use the **same shared material instance** as the ship hull. The weapon
artist paints vertex colors using the same four-channel convention:

| Channel | Typical Weapon Use |
|---|---|
| R — Primary | Main body / barrel |
| G — Trim | Structural edges, grip |
| B — Accent | Faction markings |
| A — Glow | Charge ports, muzzle glow, energy conduits |

No separate material setup is needed per weapon. When the ship's faction color scheme
is applied, weapons inherit it automatically.

---

## 5. Weapon Archetypes

### Ballistic

Physical projectiles with travel time. Momentum inherited from the firing ship.

- **Damage profile:** 0.4× vs shields, 1.5× vs hull
- High ammo count, low power draw, moderate heat per shot
- Subtypes:
  - **Autocannon** — high fire rate, lower damage per shot
  - **Mass Driver** — low fire rate, high damage, high penetration (future)
- Projectiles managed by `ProjectileManager.cs` dumb pool
- `y` component of velocity is always 0

### Energy — Continuous Beam

Instant hitscan raycast, active while fire input held.

- **Damage profile:** 1.8× vs shields, 0.5× vs hull
- High power draw per second and heat per second — primary limiting factors
- Ray cast from `Muzzle` marker in weapon's forward direction (`-basis.z`)
- Beam VFX endpoints delivered to VFX system via `GameEventBus`
- Stops firing when `power_current` reaches 0 (brownout)

### Energy — Rapid Pulse

High-rate discrete hitscan shots.

- **Damage profile:** 1.5× vs shields, 0.6× vs hull
- Moderate power draw and heat per shot
- Each pulse is an independent ray cast — not a continuous beam
- Managed by `ProjectileManager.cs` hitscan path (not pooled structs)

### Missile — Dumb Rocket

Travels in a straight line after launch. No guidance.

- **Damage profile:** 0.6× vs shields, 1.4× vs hull; explosion blocked by active shields
- Area damage on detonation
- Limited ammo; low power draw; no heat after launch
- Managed by `ProjectileManager.cs` dumb pool (same struct as ballistic; no steering)

### Missile — Guided

Steered by guidance mode defined in `weapon.json`. See Section 8 for guidance modes.

- **Damage profile:** Same as dumb rocket
- Slower than dumb rockets; higher damage and longer range
- Heat generated at launch only, not during flight
- Managed by `GuidedProjectilePool.gd`

---

## 6. Resource Systems

### Heat System

Heat is tracked **per hardpoint** — not per ship. Each `HardpointComponent` maintains:

| Property | Type | Description |
|---|---|---|
| `heat_current` | float | Current thermal load |
| `heat_capacity` | float | Max heat before overheat (default by type) |
| `heat_per_shot` | float | Added per firing event (or per second for beams) — from weapon.json |
| `passive_cooling` | float | Heat dissipated per second when not firing |
| `overheat_cooldown` | float | Seconds locked out after reaching capacity |
| `is_overheated` | bool | Lockout flag |

**Overheat lockout:** When `heat_current >= heat_capacity`, the weapon locks out for
`overheat_cooldown` seconds. Passive cooling drains heat during lockout before the
weapon can fire again.

**Damage interaction:** A damaged hardpoint multiplies `heat_per_shot` by its damage
state modifier. A critical hardpoint can trigger spontaneous overheat mid-burst.

```gdscript
# HardpointComponent.gd
func _process(delta: float) -> void:
    if is_overheated:
        _overheat_timer -= delta
        if _overheat_timer <= 0.0:
            is_overheated = false
    else:
        heat_current = maxf(0.0, heat_current - passive_cooling * delta)

func _apply_heat(amount: float) -> void:
    heat_current += amount * _damage_state_heat_multiplier()
    if heat_current >= heat_capacity:
        heat_current = heat_capacity
        is_overheated = true
        _overheat_timer = overheat_cooldown
```

### Power System

Power is tracked **per ship** via a shared pool in `Ship.gd`:

| Property | Type | Description |
|---|---|---|
| `power_capacity` | float | Max pool size |
| `power_current` | float | Current available power |
| `power_regen` | float | Units restored per second |

All energy draws compete against the same pool:

| Consumer | Draw Type |
|---|---|
| Energy beam weapons | Continuous per second while active |
| Energy pulse weapons | Per-shot draw |
| Shield regen | Continuous per second while regenerating |
| Engine boost (future) | Spike draw |

**Brownout behavior:** When `power_current` reaches 0, energy weapons stop firing and
shield regen pauses. Ballistic weapons and missiles are unaffected. This is the natural
consequence of all-energy loadouts under sustained fire — no explicit "brownout mode"
flag needed.

```gdscript
# Ship.gd — called by WeaponComponent each frame for beams, per shot for pulses
func draw_power(amount: float) -> bool:
    if power_current >= amount:
        power_current -= amount
        return true
    return false    # fire denied — caller suppresses the shot
```

### Shield System

| Property | Type | Description |
|---|---|---|
| `shield_hp` | float | Current shield strength |
| `shield_max` | float | Maximum |
| `regen_rate` | float | HP per second when regenerating |
| `regen_delay` | float | Seconds after last hit before regen starts |
| `regen_power_draw` | float | Power per second while regenerating |

```gdscript
# Ship.gd
func _process(delta: float) -> void:
    _time_since_hit += delta
    if _time_since_hit >= shield_regen_delay and shield_hp < shield_max:
        if draw_power(shield_regen_power_draw * delta):
            shield_hp = minf(shield_hp + regen_rate * delta, shield_max)
```

Constant incoming damage prevents shield recovery. Brief pauses in fire let shields
tick back. Energy weapons are the ideal suppression tool for this reason.

---

## 7. Projectile Management

### ProjectileManager (C#)

Handles all non-guided projectiles: ballistic rounds, pulse shots, dumb rockets,
and hitscan beams.

#### Dumb Pool (Ballistic + Dumb Rocket)

Pre-allocated array of `DumbProjectile` structs updated in a tight loop per frame.

```csharp
struct DumbProjectile {
    public Vector3 Position;      // y always 0
    public Vector3 Velocity;      // y always 0; includes inherited ship momentum
    public float Lifetime;
    public int WeaponDataId;
    public ulong OwnerEntityId;
    public bool Active;
}
```

Collision detection per dumb projectile: raycast from last position to current position
each frame. This catches fast projectiles that would tunnel through targets between frames.

Spawned via `GameEventBus` signal `request_spawn_dumb`:

```gdscript
# HardpointComponent.gd — emits when firing a ballistic weapon
var muzzle_pos: Vector3 = _weapon_model.get_node("Muzzle").global_position
var aim_dir: Vector3 = _get_aim_direction()   # normalized Vector3, y = 0
var inherited_vel: Vector3 = owner_ship.velocity   # y = 0

GameEventBus.emit("request_spawn_dumb", {
    "position": muzzle_pos,
    "velocity": aim_dir * muzzle_speed + inherited_vel,
    "lifetime": weapon_data.stats.projectile_lifetime,
    "weapon_id": weapon_id,
    "owner_id": owner_ship.get_instance_id()
})
```

`ProjectileManager.cs` subscribes to `request_spawn_dumb` and populates a struct in
the pool.

#### Hitscan (Beam and Pulse)

Not pooled — resolved immediately on fire each frame (beam) or per shot (pulse).

```csharp
// ProjectileManager.cs
void FireHitscan(Vector3 origin, Vector3 direction, float range, string weaponId, ulong ownerId) {
    // Ray from muzzle forward (-basis.z in caller's world space)
    var result = PhysicsRaycast(origin, origin + direction * range, layerMask: enemyLayer);
    if (result.Hit) {
        ApplyHitscanDamage(result.Collider, weaponId, ownerId, result.Position);
    }
    // Notify VFX via GameEventBus with start/end points for beam rendering
    EmitBeamVFX(origin, result.Hit ? result.Position : origin + direction * range);
}
```

Subscribed via `request_fire_hitscan` signal.

### GuidedProjectilePool (GDScript)

Smaller pool of `GuidedProjectile` objects managed in GDScript — missiles are far less
numerous than bullets; per-object overhead is acceptable.

```gdscript
class GuidedProjectile:
    var position: Vector3         # y always 0
    var velocity: Vector3         # y always 0
    var target                    # Node3D ref, or null
    var guidance_mode: String
    var turn_rate: float          # degrees/sec
    var fuel: float               # seconds remaining before self-destruct
    var weapon_data: Dictionary
    var owner_id: int
    var active: bool
```

Each active guided projectile updates steering per frame using the same angular approach
as ship assisted steering — applies torque toward the target direction, clamped to
`turn_rate`. Velocity `y` is zeroed after every update.

```gdscript
func _update_guided(proj: GuidedProjectile, delta: float) -> void:
    proj.fuel -= delta
    if proj.fuel <= 0.0:
        _deactivate(proj)
        return

    var target_pos: Vector3 = _resolve_target_position(proj)
    var desired_dir: Vector3 = (target_pos - proj.position).normalized()
    desired_dir.y = 0.0

    var current_dir: Vector3 = proj.velocity.normalized()
    var max_turn_rad: float = deg_to_rad(proj.turn_rate) * delta

    var new_dir: Vector3 = current_dir.slerp(desired_dir, clampf(max_turn_rad, 0.0, 1.0))
    new_dir.y = 0.0
    new_dir = new_dir.normalized()

    proj.velocity = new_dir * proj.velocity.length()
    proj.position += proj.velocity * delta
    proj.position.y = 0.0
```

---

## 8. Missile Guidance Modes

Guidance mode is a property of the missile definition in `weapon.json`. Three modes at MVP:

### `track_cursor`

Missile steers toward the player's aim point (world position at Y = 0, derived from
mouse-to-plane intersection) each frame. Simple, intuitive, requires no lock-on.

```gdscript
func _resolve_target_position(proj: GuidedProjectile) -> Vector3:
    return PlayerState.get_active_ship().get_aim_world_pos()
```

### `auto_lock`

On launch, missile acquires the nearest enemy within a forward cone. Tracks that target
until impact, timeout, or target destruction. Falls back to `track_cursor` behavior if
no target acquired.

```gdscript
func _acquire_auto_lock(proj: GuidedProjectile, cone_angle_deg: float) -> void:
    var best: Node3D = null
    var best_dot: float = cos(deg_to_rad(cone_angle_deg * 0.5))
    var launch_forward: Vector3 = proj.velocity.normalized()
    for ship in get_tree().get_nodes_in_group("ai_ships"):
        var to_ship: Vector3 = (ship.global_position - proj.position).normalized()
        to_ship.y = 0.0
        if to_ship.dot(launch_forward) >= best_dot:
            best_dot = to_ship.dot(launch_forward)
            best = ship
    proj.target = best
```

### `click_lock`

Player must click a target to establish a lock before firing. The weapon fires only
when `PlayerState` reports an active lock target. Missile tracks that specific target.

Lock is cleared when the target is destroyed or moves outside sensor range. The lock UI
indicator is handled by the HUD (future).

---

## 9. Damage Resolution Pipeline

When any projectile hits a ship:

1. Determine hit position in world space (`Vector3`, y ≈ 0)
2. Query `HitDetection` — is this position within a hardpoint region or general hull?
3. Apply shield absorption first (if `shield_hp > 0`):
   - Shield HP reduced by `raw_damage * damage_type.vs_shields`
   - Remaining damage = `raw_damage - shield_absorbed` (floor at 0)
4. Apply hull damage with damage type multiplier:
   - `hull_damage = remaining * damage_type.vs_hull`
5. If hardpoint region hit: split hull damage via `component_damage_ratio`:
   - `hardpoint_damage = hull_damage * component_damage_ratio`
   - `hull_damage = hull_damage * (1.0 - component_damage_ratio)`
6. Apply `hull_damage` to ship HP
7. Apply `hardpoint_damage` to hardpoint HP
8. Update hardpoint damage state if threshold crossed; emit `hardpoint_destroyed` if HP ≤ 0
9. Emit `ship_destroyed` if ship HP ≤ 0

---

## 10. Damage Type Matrix

| Weapon Archetype | vs Shields | vs Hull | Notes |
|---|---|---|---|
| Ballistic | 0.4× | 1.5× | Kinetic dissipates on shields |
| Energy beam | 1.8× | 0.5× | Heat absorbed by armor |
| Energy pulse | 1.5× | 0.6× | Slightly less extreme than beam |
| Missile (explosion) | 0.6× | 1.4× | Full hull damage only after shields stripped |

> **Balancing note:** All values are placeholder starting points. Adjust freely during
> playtesting — the matrix lives in `/data/damage_types.json` and requires no recompile.

---

## 11. JSON Data Formats

### `/data/damage_types.json`

Global lookup table. Not per-item content — stays in `/data/`.

```json
{
    "damage_types": {
        "ballistic": { "vs_shields": 0.4, "vs_hull": 1.5 },
        "energy_beam": { "vs_shields": 1.8, "vs_hull": 0.5 },
        "energy_pulse": { "vs_shields": 1.5, "vs_hull": 0.6 },
        "missile": { "vs_shields": 0.6, "vs_hull": 1.4 }
    }
}
```

### `/content/weapons/<id>/weapon.json` — Ballistic

```json
{
    "display_name": "Light Autocannon",
    "archetype": "ballistic",
    "size": "small",

    "stats": {
        "damage": 18,
        "fire_rate": 8.0,
        "muzzle_speed": 900,
        "heat_per_shot": 12,
        "power_per_shot": 0,
        "component_damage_ratio": 0.15,
        "projectile_lifetime": 1.8,
        "ammo_capacity": 500
    },

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

### `/content/weapons/<id>/weapon.json` — Energy Beam

```json
{
    "display_name": "Beam Laser",
    "archetype": "energy_beam",
    "size": "medium",

    "stats": {
        "damage_per_second": 80,
        "heat_per_second": 30,
        "power_per_second": 25,
        "component_damage_ratio": 0.1,
        "range": 600
    },

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

### `/content/weapons/<id>/weapon.json` — Energy Pulse

```json
{
    "display_name": "Pulse Laser",
    "archetype": "energy_pulse",
    "size": "small",

    "stats": {
        "damage": 22,
        "fire_rate": 6.0,
        "heat_per_shot": 8,
        "power_per_shot": 10,
        "component_damage_ratio": 0.08,
        "range": 500
    },

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

### `/content/weapons/<id>/weapon.json` — Dumb Missile

```json
{
    "display_name": "Dumb Rocket",
    "archetype": "missile_dumb",
    "size": "medium",

    "stats": {
        "damage": 180,
        "blast_radius": 80,
        "speed": 600,
        "component_damage_ratio": 0.2,
        "projectile_lifetime": 3.0,
        "ammo_capacity": 12
    },

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

### `/content/weapons/<id>/weapon.json` — Guided Missile

```json
{
    "display_name": "Heat-Seeking Missile",
    "archetype": "missile_guided",
    "size": "medium",

    "stats": {
        "damage": 220,
        "blast_radius": 80,
        "speed": 420,
        "turn_rate": 90,
        "fuel": 4.0,
        "guidance": "auto_lock",
        "lock_cone_degrees": 60,
        "component_damage_ratio": 0.2,
        "ammo_capacity": 6
    },

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

---

## 12. Performance Instrumentation

Per the PerformanceMonitor integration contract:

```csharp
// ProjectileManager.cs
PerformanceMonitor.Begin("ProjectileManager.dumb_update");
UpdateDumbPool(delta);
PerformanceMonitor.End("ProjectileManager.dumb_update");

PerformanceMonitor.Begin("ProjectileManager.guided_update");
UpdateGuidedPool(delta);
PerformanceMonitor.End("ProjectileManager.guided_update");

PerformanceMonitor.Begin("ProjectileManager.collision_checks");
ProcessCollisions();
PerformanceMonitor.End("ProjectileManager.collision_checks");

PerformanceMonitor.SetCount("ProjectileManager.active_count", activeDumbCount + activeGuidedCount);
```

Register custom monitors in `_ready()` (GDScript side):

```gdscript
Performance.add_custom_monitor("AllSpace/projectiles_active",
    func(): return PerformanceMonitor.get_count("ProjectileManager.active_count"))
Performance.add_custom_monitor("AllSpace/projectile_dumb_ms",
    func(): return PerformanceMonitor.get_avg_ms("ProjectileManager.dumb_update"))
Performance.add_custom_monitor("AllSpace/projectile_guided_ms",
    func(): return PerformanceMonitor.get_avg_ms("ProjectileManager.guided_update"))
Performance.add_custom_monitor("AllSpace/projectile_collision_ms",
    func(): return PerformanceMonitor.get_avg_ms("ProjectileManager.collision_checks"))
```

Canonical metric names used by this system:

| Metric | Name |
|---|---|
| Dumb projectile pool update | `ProjectileManager.dumb_update` |
| Guided projectile pool update | `ProjectileManager.guided_update` |
| Projectile collision checks | `ProjectileManager.collision_checks` |
| Active projectile count | `ProjectileManager.active_count` |

---

## 13. Files

```
/gameplay/weapons/
    ProjectileManager.cs          ← C# only; dumb pool and hitscan
    GuidedProjectilePool.gd
    WeaponComponent.gd            ← firing logic; attached to weapon model node
    HardpointComponent.gd         ← type, arc, heat, damage state, fire groups
/content/weapons/
    /autocannon_light/
        weapon.json
        model.glb
        icon.png
    /beam_laser/
        weapon.json
        model.glb
        icon.png
    /pulse_laser/
        weapon.json
        model.glb
        icon.png
    /missile_dumb/
        weapon.json
        model.glb
        icon.png
    /missile_heatseeking/
        weapon.json
        model.glb
        icon.png
/data/
    damage_types.json             ← global config; stays in /data/
```

---

## 14. Dependencies

- `PerformanceMonitor` registered before any weapon system initializes
- `ContentRegistry` loaded before any ship spawns — provides weapon data and asset paths
- `Ship.gd` from Physics spec — exposes `velocity: Vector3`, `power_current`, `input_fire`
- `ShipFactory.gd` from Ship spec — handles hardpoint empty resolution and model assembly
- `PlayerState` — guided missiles in `track_cursor` and `click_lock` modes query
  `PlayerState.get_active_ship()` for aim point and lock target
- `HitDetection` system (future spec) — provides component region lookup at hit position
- VFX system (future spec) — receives beam endpoints and impact events via `GameEventBus`

---

## 15. Assumptions

- Damage type multipliers are placeholder starting values; tune after first combat playtest
- `aim_accuracy` equivalent for AI lead prediction lives in `ai_profiles.json` (AI spec)
- Heat capacity defaults by hardpoint type are TBD; author in `HardpointComponent.gd`
  as `@export` vars and tune in-editor before committing to JSON
- `component_damage_ratio` values are conservative defaults — increase if hardpoint
  destruction feels too rare
- Missile `turn_rate` of 90°/s is a guess — too high = unavoidable, too low = useless;
  adjust as the primary missile difficulty knob
- Ammo capacity and reload are deferred to post-MVP — assume unlimited ammo for prototype
- The `lock_cone_degrees` for `auto_lock` missiles defaults to 60°; tune per missile type
- Area explosion damage distribution (falloff over `blast_radius`) is deferred to post-MVP;
  MVP uses flat damage at impact point only
- Weapon visual models are placeholder geometry until the art pass — the `Muzzle` marker
  placement is what matters for correct projectile origin

---

## 16. Success Criteria

- [ ] Ballistic, beam, pulse, dumb rocket, and guided missile archetypes all fire and deal damage
- [ ] Weapon models appear positioned correctly at hardpoint empties on assembled ships
- [ ] Gimbal, fixed, and turret hardpoints correctly constrain weapon rotation and fire arc
- [ ] Fire groups work correctly — left click fires group 1, right click fires group 2
- [ ] A hardpoint in multiple groups fires when any of its groups is activated
- [ ] Damage type matrix visibly affects combat — energy strips shields faster, ballistic chews hull
- [ ] Continuous beam drains power — all-energy loadout is starved under sustained fire
- [ ] Overheat lockout occurs and is visible to the player
- [ ] Shield regen starts after delay, pauses when taking hits, competes with weapons for power
- [ ] Guided missile tracks target using its JSON-defined guidance mode
- [ ] `auto_lock` missile acquires the nearest enemy in its forward cone at launch
- [ ] Hardpoint takes damage from hits — degraded state visibly affects weapon performance
- [ ] Hardpoint destroyed at 0 HP — weapon non-functional, `hardpoint_destroyed` emitted
- [ ] All projectile positions and velocities maintain `y = 0` at all times
- [ ] Projectiles inherit firing ship velocity at spawn
- [ ] 200+ simultaneous dumb projectiles run within frame budget at 60fps
- [ ] All weapon stats modifiable in `weapon.json` without recompile
- [ ] A new weapon can be added by creating `/content/weapons/<id>/` — no code changes required
- [ ] Weapon models loaded via `ContentRegistry` — no hardcoded asset paths in GDScript
