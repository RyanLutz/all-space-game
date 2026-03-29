# Weapons & Projectiles System Specification
*All Space Combat MVP — Weapons, Hardpoints, and Projectile Management*

## Overview

A data-driven weapon system built around fixed hardpoints on ships, three weapon archetypes, and a dual heat/power limiting model. All weapon definitions live in JSON — no weapon behavior is hardcoded. The projectile system is split into a C# `ProjectileManager` for performance-critical dumb/ballistic projectiles and a GDScript `GuidedProjectilePool` for missiles.

**Design Goals:**
- Weapon archetypes feel meaningfully different to use
- Hardpoint type and position create real tactical decisions
- Heat and power create interesting tradeoffs under sustained fire
- Damage types reward mixed loadouts
- Everything tunable via JSON — no recompile needed for balance passes

---

## Weapon Archetypes

### Ballistic
- Projectiles with travel time, momentum inherited from firing ship
- High ammo count, low power draw, generates moderate heat
- **Damage profile:** Poor vs shields, excellent vs hull
- Subtypes: autocannon (high ROF, low damage), mass driver (low ROF, high damage, high penetration)

### Energy — Continuous Beam
- Instant hitscan raycast, held fire key
- Deals damage per second while active
- **High** power draw and heat generation — primary limiting factor
- **Damage profile:** Excellent vs shields, poor vs hull
- Visually: sustained beam VFX between muzzle and impact point

### Energy — Rapid Pulse
- Fast discrete hitscan shots, high fire rate
- Moderate power draw, moderate heat per shot
- **Damage profile:** Good vs shields, moderate vs hull
- Visually: rapid short beam segments, feels like a blaster

### Missiles — Dumb Rocket
- Travels in a straight line after launch, no guidance
- High damage on impact, area damage on explosion
- Low power draw, no heat, limited ammo
- **Damage profile:** Balanced vs shields and hull — but explosion is blocked by shields (hull damage only after shield strip)

### Missiles — Guided
- Guidance mode defined per missile type in JSON (see Guidance Modes below)
- Slower than dumb rockets, higher damage, longer range
- Heat generated at launch only, not in flight
- **Damage profile:** Same as dumb rocket — explosion blocked by shields

---

## Damage Type Matrix

| Weapon Type | vs Shields | vs Hull | Notes |
|---|---|---|---|
| Ballistic | 0.4x | 1.5x | Kinetic energy dissipates on shields |
| Energy (beam/pulse) | 1.8x | 0.5x | Armor reflects/absorbs heat |
| Missile (explosion) | 0.6x | 1.4x | Must strip shields first for full hull damage |

> **Balancing note:** These multipliers are starting values for prototype testing. Adjust freely during balance passes — the matrix is data-driven and lives in `damage_types.json`.

---

## Hardpoints

### Hardpoint Types

| Type | Fire Arc | Notes |
|---|---|---|
| Fixed | ~5° | No rotation. Requires ship to aim. |
| Gimbal | ~25° | Slight rotation to compensate for turn rate lag |
| Partial Turret | ~120° | Side-mounted or secondary. Cannot fire directly behind. |
| Full Turret | 360° | Can fire in any direction. Heaviest, slowest traverse. |

**Gimbal detail:** The gimbal automatically tracks the player's aim point within its arc, compensating for the angular lag described in the Physics spec. On heavy ships, gimballed weapons can maintain fire on a target even when the ship's heading hasn't fully caught up. This is a module property, not automatic on all hardpoints.

### Hardpoint Positions

Each ship defines its hardpoints in JSON with:
- **World-space offset** from ship center (e.g. `[24, -8]`)
- **Base facing angle** (e.g. `0` = forward, `90` = starboard)
- **Hardpoint type** (fixed, gimbal, partial_turret, full_turret)
- **Allowed weapon sizes** (small, medium, large)
- **Damage state** (see Component Damage below)

```json
"hardpoints": [
  { "id": "hp_nose", "offset": [32, 0], "facing": 0, "type": "gimbal", "size": "medium" },
  { "id": "hp_port", "offset": [-8, -20], "facing": 270, "type": "partial_turret", "size": "small" },
  { "id": "hp_stbd", "offset": [-8, 20], "facing": 90, "type": "partial_turret", "size": "small" }
]
```

### Hardpoint Damage States

Hardpoints are targetable components with their own HP. Damage states degrade performance:

| State | HP % | Effect |
|---|---|---|
| Nominal | 100–60% | Full performance |
| Damaged | 59–25% | Reduced fire rate, increased heat generation |
| Critical | 24–1% | Weapon fires unreliably (chance to misfire per shot) |
| Destroyed | 0% | Weapon non-functional until repaired |

Hit detection for hardpoints uses simplified point regions per ship (see HitDetection spec). When a projectile impact point falls within a hardpoint's region, damage is split between hull and hardpoint HP based on a `component_damage_ratio` defined per weapon type.

---

## Heat System

Heat is tracked **per hardpoint**, not per ship. Each hardpoint has:

| Property | Description |
|---|---|
| `heat_capacity` | Max heat before overheat |
| `heat_per_shot` | Heat added per shot (or per second for beams) |
| `passive_cooling` | Heat dissipated per second when not firing |
| `overheat_cooldown` | Seconds locked out after hitting heat_capacity |

**Overheat behavior:** When a hardpoint reaches `heat_capacity`, the weapon locks out for `overheat_cooldown` seconds regardless of player input. Passive cooling then drains heat before it can fire again.

**Damage interaction:** A damaged hardpoint generates heat faster (`heat_per_shot` multiplied by damage state modifier). A critical hardpoint can trigger spontaneous overheat mid-burst.

---

## Power System

Power is tracked **per ship** via a shared pool. All energy draws compete for the same budget:

| Consumer | Draw Type |
|---|---|
| Energy weapons (beam) | Continuous draw while active |
| Energy weapons (pulse) | Per-shot draw |
| Shields (regen) | Continuous draw while regenerating |
| Engines (boost) | Spike draw (future — not MVP) |

```gdscript
# Ship.gd tracks:
var power_capacity: float     # max pool size
var power_current: float      # current available
var power_regen: float        # units restored per second (from power plant module)
```

**Brownout behavior:** If `power_current` drops to zero, energy weapons stop firing and shield regen pauses. Ballistic weapons and missiles are unaffected — they don't draw power. This creates a natural tradeoff: all-energy loadouts are powerful but vulnerable to power starvation under sustained fire.

---

## Shield System

### Properties

| Property | Description |
|---|---|
| `shield_hp` | Current shield strength |
| `shield_max` | Maximum shield strength |
| `regen_rate` | HP restored per second when regenerating |
| `regen_delay` | Seconds after last hit before regen begins |
| `regen_power_draw` | Power consumed per second while regenerating |

### Regen Behavior

```gdscript
func _process(delta: float) -> void:
    if time_since_last_hit >= regen_delay:
        if ship.power_current >= regen_power_draw * delta:
            shield_hp = min(shield_hp + regen_rate * delta, shield_max)
            ship.power_current -= regen_power_draw * delta
```

**Effect in play:** Constant pressure prevents shields from recovering mid-fight. Brief pauses in incoming fire let shields tick back up. Energy weapons are ideal for keeping shields suppressed.

---

## Missile Guidance Modes

Guidance mode is a property of the missile definition in JSON — not hardcoded. Three modes supported at MVP:

### `track_cursor`
Missile steers toward the player's cursor position each frame. Simple, intuitive, requires no lock-on. Works on anything the player points at.

### `auto_lock`
On launch, missile acquires the nearest enemy within a forward cone. Tracks that target until impact, timeout, or target destruction. No player lock-on input required.

### `click_lock`
Player must click a target to establish a lock before firing. Missile tracks that specific target. Lock is lost if target moves out of sensor range. Most accurate, requires most player attention.

```json
"missile_types": [
  { "id": "rocket_dumb", "guidance": "none", "speed": 600, "damage": 120, "blast_radius": 40 },
  { "id": "missile_heat", "guidance": "auto_lock", "speed": 400, "turn_rate": 90, "damage": 200, "blast_radius": 60, "fuel": 4.0 },
  { "id": "missile_smart", "guidance": "click_lock", "speed": 350, "turn_rate": 120, "damage": 280, "blast_radius": 80, "fuel": 6.0 }
]
```

`fuel` defines max flight time in seconds before the missile self-destructs — prevents missiles from orbiting forever.

---

## ProjectileManager (C#)

Manages all non-guided projectiles: ballistic rounds, pulse shots, dumb rockets, and hitscan beams.

### Dumb Pool (Ballistic + Pulse)

Pre-allocated array of `DumbProjectile` structs. Updated in a single tight loop per frame:

```csharp
struct DumbProjectile {
    public Vector2 Position;
    public Vector2 Velocity;      // includes inherited ship momentum
    public float Lifetime;
    public int WeaponDataId;
    public ulong OwnerEntityId;
    public bool Active;
}
```

Collision detection via raycast from last position to current position each frame — catches fast-movers that would tunnel through targets between frames.

### Hitscan (Continuous Beam)

Not pooled — resolved immediately on fire:

1. Cast ray from muzzle in aim direction
2. Find first collidable entity in range
3. Apply damage immediately
4. Notify VFX system with start/end points for beam rendering
5. Repeat each frame while fire input held and power available

### Guided Pool (GDScript)

Smaller pool of `GuidedProjectile` objects managed in GDScript — missiles are far less numerous than bullets, per-object overhead is acceptable.

```gdscript
class GuidedProjectile:
    var position: Vector2
    var velocity: Vector2
    var target                    # Node ref, Vector2, or null
    var guidance_mode: String
    var turn_rate: float          # degrees/sec
    var fuel: float               # seconds remaining
    var weapon_data: Dictionary
    var owner_id: int
```

Each guided projectile updates its own steering toward target per frame using the same angular approach as ship assisted steering — applies torque toward target, respects `turn_rate` limit.

---

## Weapon Data (JSON)

All weapon stats live in `weapons.json`. No weapon behavior is hardcoded.

```json
{
  "weapons": [
    {
      "id": "autocannon_light",
      "archetype": "ballistic",
      "size": "small",
      "damage": 18,
      "fire_rate": 8.0,
      "muzzle_speed": 900,
      "heat_per_shot": 12,
      "power_per_shot": 0,
      "component_damage_ratio": 0.15,
      "projectile_lifetime": 1.8,
      "ammo_capacity": 500
    },
    {
      "id": "beam_laser",
      "archetype": "energy_beam",
      "size": "medium",
      "damage_per_second": 80,
      "heat_per_second": 30,
      "power_per_second": 25,
      "component_damage_ratio": 0.1,
      "range": 600
    },
    {
      "id": "pulse_laser",
      "archetype": "energy_pulse",
      "size": "small",
      "damage": 22,
      "fire_rate": 6.0,
      "heat_per_shot": 8,
      "power_per_shot": 10,
      "component_damage_ratio": 0.08,
      "range": 500
    }
  ]
}
```

---

## Damage Resolution Pipeline

When any projectile hits a ship:

1. Determine hit point world position
2. Query `HitDetection` — is this a hardpoint region or general hull?
3. Apply shield absorption first (if shields > 0)
   - Remaining damage after shield = `raw_damage * (1 - shield_absorption_ratio)`
   - Shield HP reduced by `raw_damage * damage_type_vs_shields`
4. Apply hull damage with damage type multiplier
5. If hardpoint region hit: split damage between hull and hardpoint HP via `component_damage_ratio`
6. Check hardpoint damage state thresholds — update state if crossed
7. Check hull HP — trigger death if <= 0

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract:

```gdscript
# ProjectileManager.cs — wrap dumb pool update:
PerformanceMonitor.Begin("ProjectileManager.dumb_update");
UpdateDumbPool(delta);
PerformanceMonitor.End("ProjectileManager.dumb_update");

# Wrap guided pool update:
PerformanceMonitor.Begin("ProjectileManager.guided_update");
UpdateGuidedPool(delta);
PerformanceMonitor.End("ProjectileManager.guided_update");

# Wrap collision checks:
PerformanceMonitor.Begin("ProjectileManager.collision_checks");
ProcessCollisions();
PerformanceMonitor.End("ProjectileManager.collision_checks");

# Set counts each frame:
PerformanceMonitor.SetCount("ProjectileManager.active_count", activeDumbCount + activeGuidedCount);
```

Register in `_ready()`:
```gdscript
Performance.add_custom_monitor("AllSpace/projectiles_active",
    func(): return PerformanceMonitor.get_count("ProjectileManager.active_count"))
Performance.add_custom_monitor("AllSpace/projectile_dumb_ms",
    func(): return PerformanceMonitor.get_avg_ms("ProjectileManager.dumb_update"))
Performance.add_custom_monitor("AllSpace/projectile_guided_ms",
    func(): return PerformanceMonitor.get_avg_ms("ProjectileManager.guided_update"))
```

---

## Files

```
/gameplay/weapons/
    ProjectileManager.cs
    GuidedProjectilePool.gd
    WeaponComponent.gd            (attached to Ship, manages hardpoints)
    HardpointComponent.gd         (per hardpoint: heat, damage state, fire logic)
/data/
    damage_types.json
```

> **Migration note:** The `weapons.json` monolithic file referenced above is superseded by the
> folder-per-item content architecture (`docs/Ship_Content_Data_Architecture_Spec.md`). Each
> weapon now lives at `/content/weapons/<id>/weapon.json` alongside its model and icon. The
> per-weapon JSON schema is identical to individual entries from the old `weapons.json`. The
> `damage_types.json` global config table remains in `/data/` unchanged.

---

## Dependencies

- `PerformanceMonitor` registered before any weapon system initializes
- `SpaceBody.gd` / `Ship.gd` from Physics spec — ships expose `velocity` for momentum inheritance and `power_current` for draw
- `HitDetection` system (future spec) provides component region lookup
- VFX system (future spec) receives beam start/end points and projectile impact events via `GameEventBus`

---

## Assumptions (Revisit During Balancing)

- Damage type multipliers are placeholder starting values
- Heat capacity, cooling rates, and power draw values to be tuned in-engine
- Missile `turn_rate` values need playtesting — too high = unavoidable, too low = useless
- `component_damage_ratio` values are conservative defaults — increase if hardpoint destruction feels too rare
- Ammo capacity and reload are out of scope for MVP — assume infinite ammo for prototype

---

## Success Criteria

- [ ] Ballistic, beam, pulse, and missile weapons all fire and deal damage
- [ ] Damage type matrix visibly affects combat — energy strips shields faster, ballistic chews hull
- [ ] Continuous beam drains power — all-energy loadout can be starved under pressure
- [ ] Overheat lockout occurs and is visible to player
- [ ] Shield regen kicks in after damage delay, pauses while taking hits
- [ ] Guided missile tracks target using assigned guidance mode
- [ ] Hardpoint takes damage from hits — degraded state visibly affects weapon performance
- [ ] 200+ simultaneous dumb projectiles run within frame budget at 60fps
- [ ] All weapon stats modifiable in JSON without recompile
