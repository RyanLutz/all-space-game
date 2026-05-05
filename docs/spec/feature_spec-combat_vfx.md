# Combat VFX System Specification
*All Space Combat MVP — Weapon Effects, Impacts, and Explosions*

---

## 1. Overview

A data-driven visual effects system that delivers muzzle flashes, beam rendering, impact
sparks, shield ripples, and explosions across all combat. Every visual parameter — color,
lifetime, particle count, explosion layer timing — lives in JSON. No VFX value is
hardcoded.

The system uses a **distributed ownership model**: effects that belong to a specific
weapon or ship live locally on that node (muzzle flashes, beams, shield hits), while
world-space one-shot effects (impacts, explosions) are managed centrally by
`VFXManager.gd`. This keeps per-weapon authoring self-contained while avoiding the
overhead of a central system that must track every live weapon on every ship.

**Design Goals:**
- Each weapon archetype has a visually distinct firing signature
- Explosions read differently by hull size — a small fighter and a cruiser do not die
  the same way
- Effects are authored per content folder — adding a new weapon or ship explosion
  requires no code changes
- All VFX can be disabled via JSON (pool_size = 0) without errors — critical for
  isolated performance testing
- Y = 0 is enforced on all world-space effect spawns; no effect floats or sinks

---

## 2. Architecture

```
GameEventBus
    ├── projectile_hit  ──────────────────────────────► VFXManager.gd
    ├── shield_hit  ──────────────────────────────────► VFXManager.gd → ShieldEffectPlayer
    ├── ship_destroyed  ──────────────────────────────► VFXManager.gd
    └── missile_detonated  ───────────────────────────► VFXManager.gd

WeaponComponent.gd (fires)
    ├── → MuzzleFlashPlayer.play()           (direct call — same node tree)
    └── → BeamRenderer.update(from, to)      (direct call — same node tree)

Ship (RigidBody3D)
    └── ShipVisual (Node3D)
            ├── Hull_MeshInstance3D
            │       └── HardpointEmpty_{id}_{size}
            │               ├── WeaponModel (MeshInstance3D)
            │               │       ├── Muzzle (Marker3D)
            │               │       ├── MuzzleFlashPlayer.gd    ◄ local; no bus
            │               │       └── BeamRenderer.gd         ◄ local; no bus
            └── ShieldMesh (MeshInstance3D)
                    └── ShieldEffectPlayer.gd                   ◄ receives bus event via VFXManager

VFXManager.gd (autoload)
    └── EffectPool.gd   ← generic pool; one instance per pooled effect type
```

`VFXManager` subscribes to GameEventBus events at `_ready()`. It does not hold
references to ships or weapons — it receives world-space positions and effect IDs from
events, looks up the correct pool, and spawns from it.

`MuzzleFlashPlayer` and `BeamRenderer` are called directly by `WeaponComponent` because
they are siblings in the same subtree. The GameEventBus would add latency for something
that fires potentially hundreds of times per second across many ships.

---

## 3. Core Properties / Data Model

### Effect Types

| Type | Owner | Rendering |
|---|---|---|
| `particle_burst` | VFXManager pool | `GPUParticles3D`, one-shot |
| `beam` | BeamRenderer (local) | Stretched `MeshInstance3D`, per-frame update |
| `muzzle_flash` | MuzzleFlashPlayer (local) | `GPUParticles3D`, one-shot |
| `explosion` | VFXManager pool | Multi-layer, coroutine-sequenced |
| `shield_ripple` | ShieldEffectPlayer (local) | Shader parameter on shield mesh material |

### MuzzleFlashPlayer

```gdscript
# Attached as child of WeaponModel node
var effect_id: String       # loaded from weapon.json "effects.muzzle_flash"
var _particles: GPUParticles3D
var _pool_size: int         # from effect.json; 0 disables entirely

func play() -> void:
    if _pool_size == 0: return
    _particles.restart()
```

`MuzzleFlashPlayer` creates its `GPUParticles3D` instance at `_ready()` from the effect
definition loaded via `ContentRegistry`. It does not communicate with `VFXManager`.

### BeamRenderer

```gdscript
# Attached as child of WeaponModel node, sibling of MuzzleFlashPlayer
var effect_id: String       # loaded from weapon.json "effects.beam"
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _active: bool = false

func update(from: Vector3, to: Vector3) -> void
func stop() -> void
```

The beam is a `CapsuleMesh` (or `BoxMesh`) scaled along the local Z axis to span
`from` → `to`. The shader drives color, glow width, and flicker. `stop()` hides the
mesh immediately. `BeamRenderer` is only present on weapon models whose archetype is
`energy_beam`. `WeaponComponent` checks for its presence at `_ready()` and caches the
reference; it does not assume the node exists.

### ShieldEffectPlayer

```gdscript
# Attached as child of ShieldMesh node on ship scene
var effect_id: String       # from ship.json "effects.shield_hit"
var _material: ShaderMaterial

func play_hit(hit_position_local: Vector3) -> void
```

`play_hit()` sets shader uniforms (`u_hit_origin`, `u_hit_time`) to drive a ripple
animation originating at the approximate hit position in local shield mesh space.
`VFXManager` calls this after resolving the correct ship from the `shield_hit` event.

### VFXManager

```gdscript
# Autoload singleton
var _pools: Dictionary          # effect_id → EffectPool
var _beam_renderers: Array      # cache of active BeamRenderers (for perf monitoring)

func _ready() -> void:
    GameEventBus.projectile_hit.connect(_on_projectile_hit)
    GameEventBus.shield_hit.connect(_on_shield_hit)
    GameEventBus.ship_destroyed.connect(_on_ship_destroyed)
    GameEventBus.missile_detonated.connect(_on_missile_detonated)
    _build_pools()

func spawn_effect(effect_id: String, position: Vector3, normal: Vector3 = Vector3.UP) -> void
func spawn_explosion(explosion_id: String, position: Vector3) -> void
```

### EffectPool

```gdscript
var effect_id: String
var _instances: Array[GPUParticles3D]
var _next: int = 0

func acquire() -> GPUParticles3D   # returns next instance, wraps on overflow
func preload(count: int, parent: Node) -> void
```

Ring-buffer allocation — the oldest effect is silently recycled if the pool is
exhausted. This is correct behavior for muzzle flashes and impacts: a miss on pool
exhaustion is visually invisible.

---

## 4. Key Algorithms

### Pool Construction

At `_ready()`, `VFXManager` asks `ContentRegistry` for all effect IDs, reads each
`effect.json`, and builds a pool of the specified `pool_size`. If `pool_size` is 0, no
pool is built and spawn calls for that ID are silently ignored.

```gdscript
func _build_pools() -> void:
    PerformanceMonitor.begin("VFXManager.pool_build")
    var effect_ids := ContentRegistry.get_all_ids("effects")
    for id in effect_ids:
        var def: Dictionary = ContentRegistry.get_effect(id)
        if def.get("pool_size", 0) == 0:
            continue
        if def["type"] == "explosion":
            continue    # explosions use a separate spawn path; skip pool here
        var pool := EffectPool.new()
        pool.preload(def["pool_size"], self)
        _pools[id] = pool
    PerformanceMonitor.end("VFXManager.pool_build")
```

### Impact Spawn

```gdscript
func _on_projectile_hit(
        position: Vector3,
        normal: Vector3,
        surface_type: String        # "hull" or "shield" — determines effect_id
) -> void:
    position.y = 0.0
    var effect_id := "impact_hull" if surface_type == "hull" else "impact_shield"
    spawn_effect(effect_id, position, normal)

func spawn_effect(effect_id: String, position: Vector3, normal: Vector3) -> void:
    if not _pools.has(effect_id): return
    var instance: GPUParticles3D = _pools[effect_id].acquire()
    instance.global_position = position
    # Rotate to align with surface normal (rotates particle emission direction)
    instance.global_transform.basis = Basis(
        normal.cross(Vector3.FORWARD).normalized(),
        normal,
        Vector3.FORWARD
    )
    instance.restart()
```

### Explosion Sequencing

Explosions are coroutine-driven to stagger layers. Each layer is itself a pooled
`GPUParticles3D` instance. The explosion definition lists layers with individual delays
and scale multipliers.

```gdscript
func spawn_explosion(explosion_id: String, position: Vector3) -> void:
    position.y = 0.0
    var def: Dictionary = ContentRegistry.get_effect(explosion_id)
    PerformanceMonitor.begin("VFXManager.explosion_spawn")
    _sequence_explosion(def["layers"], position)
    PerformanceMonitor.end("VFXManager.explosion_spawn")

func _sequence_explosion(layers: Array, position: Vector3) -> void:
    for layer in layers:
        var effect_id: String = layer["effect"]
        var delay: float = layer.get("delay", 0.0)
        var scale: float = layer.get("scale", 1.0)
        if delay > 0.0:
            await get_tree().create_timer(delay).timeout
        if not _pools.has(effect_id): continue
        var instance: GPUParticles3D = _pools[effect_id].acquire()
        instance.global_position = position
        instance.scale = Vector3.ONE * scale
        instance.restart()
```

`_sequence_explosion` is an `async` function driven by `await`. Because it is called
from `spawn_explosion` without `await`, it runs concurrently and does not block
`VFXManager`. Multiple explosions can sequence simultaneously.

### Beam Rendering

`BeamRenderer.update()` is called by `WeaponComponent` every `_physics_process` frame
that the beam weapon is firing. The implementation stretches a mesh along the local Z
axis between `from` and `to`.

```gdscript
func update(from: Vector3, to: Vector3) -> void:
    _active = true
    _mesh_instance.visible = true
    var midpoint := (from + to) * 0.5
    var length := from.distance_to(to)
    global_position = midpoint
    look_at(to, Vector3.UP)
    # Scale the mesh along its local Z axis to span the beam length
    _mesh_instance.scale.z = length
    # Flicker: offset shader time uniform for variation between simultaneous beams
    _material.set_shader_parameter("u_time_offset", randf() * TAU)

func stop() -> void:
    _active = false
    _mesh_instance.visible = false
```

`WeaponComponent` calls `stop()` when `input_fire` goes false or the weapon overheats.
This is a direct call — no event needed.

---

## 5. JSON Data Format

### `weapon.json` — Effects Block (addition to existing format)

Added alongside the existing `assets` block:

```json
"effects": {
    "muzzle_flash": "muzzle_autocannon",
    "projectile_trail": "trail_ballistic"
}
```

For beam weapons only:

```json
"effects": {
    "muzzle_flash": "muzzle_beam_ignite",
    "beam": "beam_laser_blue"
}
```

For missiles:

```json
"effects": {
    "muzzle_flash": "muzzle_missile_launch",
    "projectile_trail": "trail_missile_exhaust"
}
```

### `ship.json` — Effects Block (addition to existing format)

```json
"effects": {
    "explosion": "explosion_small",
    "shield_hit": "shield_ripple_light"
}
```

Explosion tier is set per hull. Convention: `explosion_small` for interceptors and
fighters, `explosion_medium` for frigates and freighters, `explosion_large` for
capital ships.

### `/content/effects/<id>/effect.json` — Particle Burst

```json
{
    "type": "particle_burst",
    "pool_size": 8,
    "lifetime": 0.35,
    "color_primary":   [1.0, 0.6, 0.15, 1.0],
    "color_secondary": [1.0, 0.1, 0.0, 0.0],
    "particle_count": 20,
    "particle_speed_min": 30.0,
    "particle_speed_max": 100.0,
    "scale": 1.0,
    "emit_direction": "normal"
}
```

`emit_direction` of `"normal"` aligns particle emission to the surface hit normal.
`"sphere"` emits in all directions (used for muzzle flashes and explosions).

### `/content/effects/<id>/effect.json` — Beam

```json
{
    "type": "beam",
    "color_core":   [0.55, 0.85, 1.0, 1.0],
    "color_glow":   [0.2,  0.5,  1.0, 0.4],
    "width_core": 0.08,
    "width_glow":  0.35,
    "flicker_hz":  14.0,
    "impact_flash_color": [1.0, 1.0, 1.0, 1.0],
    "impact_flash_radius": 0.4
}
```

### `/content/effects/<id>/effect.json` — Explosion (Multi-Layer)

```json
{
    "type": "explosion",
    "layers": [
        { "effect": "explosion_flash",     "delay": 0.0,  "scale": 1.0 },
        { "effect": "explosion_fireball",  "delay": 0.04, "scale": 1.2 },
        { "effect": "explosion_shockwave", "delay": 0.08, "scale": 1.6 },
        { "effect": "explosion_debris",    "delay": 0.04, "scale": 0.9 }
    ]
}
```

The explosion references other effect IDs as its layers. `explosion_flash`,
`explosion_fireball`, etc. are themselves simple `particle_burst` effect definitions
with their own pools. This means each sub-effect is independently tunable and reusable
across explosion tiers.

### `/content/effects/<id>/effect.json` — Shield Ripple

```json
{
    "type": "shield_ripple",
    "color":          [0.4, 0.7, 1.0, 0.8],
    "ripple_speed":   2.5,
    "ripple_falloff": 1.8,
    "flash_duration": 0.12
}
```

---

## 6. Performance Instrumentation

New metric names to be added to the PerformanceMonitor canonical table:

| Metric | Name |
|---|---|
| Active VFX effect instances | `VFXManager.active_effects` |
| Pool reclaim pass duration | `VFXManager.pool_reclaim` |
| Explosion spawn (per event) | `VFXManager.explosion_spawn` |
| Pool construction at startup | `VFXManager.pool_build` |
| Beam renderer update (all active) | `BeamRenderer.update` |

```gdscript
# VFXManager._process — reclaim pass
PerformanceMonitor.begin("VFXManager.pool_reclaim")
_reclaim_expired()
PerformanceMonitor.end("VFXManager.pool_reclaim")
PerformanceMonitor.set_count("VFXManager.active_effects", _count_active())

# BeamRenderer._physics_process
PerformanceMonitor.begin("BeamRenderer.update")
update(_muzzle.global_position, _hit_position)
PerformanceMonitor.end("BeamRenderer.update")
```

Register custom monitors in `VFXManager._ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/vfx_active",
    func(): return PerformanceMonitor.get_count("VFXManager.active_effects"))
Performance.add_custom_monitor("AllSpace/vfx_pool_reclaim_ms",
    func(): return PerformanceMonitor.get_avg_ms("VFXManager.pool_reclaim"))
Performance.add_custom_monitor("AllSpace/vfx_explosion_spawn_ms",
    func(): return PerformanceMonitor.get_avg_ms("VFXManager.explosion_spawn"))
```

---

## 7. Files

```
/gameplay/vfx/
    VFXManager.gd               ← autoload; subscribes to bus; owns world-space pools
    EffectPool.gd               ← generic ring-buffer pool for GPUParticles3D instances
    MuzzleFlashPlayer.gd        ← local to weapon model; called directly by WeaponComponent
    BeamRenderer.gd             ← local to weapon model; called directly by WeaponComponent
    ShieldEffectPlayer.gd       ← local to shield mesh; called by VFXManager on shield_hit

/content/effects/
    /muzzle_autocannon/
        effect.json
    /muzzle_pulse_laser/
        effect.json
    /muzzle_beam_ignite/
        effect.json             ← brief flash at beam weapon startup
    /muzzle_missile_launch/
        effect.json
    /trail_ballistic/
        effect.json             ← tracer visual for autocannon rounds
    /trail_missile_exhaust/
        effect.json
    /beam_laser_blue/
        effect.json
    /beam_laser_red/
        effect.json
    /impact_hull/
        effect.json
    /impact_shield/
        effect.json
    /shield_ripple_light/
        effect.json
    /shield_ripple_heavy/
        effect.json
    /explosion_flash/
        effect.json             ← sub-effect; used as a layer by explosion definitions
    /explosion_fireball/
        effect.json
    /explosion_shockwave/
        effect.json
    /explosion_debris/
        effect.json
    /explosion_small/
        effect.json             ← fighter/interceptor; references sub-effects as layers
    /explosion_medium/
        effect.json
    /explosion_large/
        effect.json
```

`weapon.json` files (in `/content/weapons/<id>/`) are **modified** to add an `effects`
block. `ship.json` files are **modified** to add an `effects` block. No new data files
elsewhere.

---

## 8. Dependencies

- `GameEventBus.gd` — must emit the following signals (new additions to the bus spec):
  - `projectile_hit(position: Vector3, normal: Vector3, surface_type: String)`
  - `shield_hit(ship: Node3D, hit_position_local: Vector3)`
  - `ship_destroyed(ship: Node3D, explosion_id: String)`
  - `missile_detonated(position: Vector3, explosion_id: String)`
- `ContentRegistry.gd` — must scan `/content/effects/` at startup alongside weapons
- `PerformanceMonitor` — must be registered before VFXManager initializes
- `WeaponComponent.gd` — calls `MuzzleFlashPlayer.play()` and `BeamRenderer.update()`
  directly; must cache references at `_ready()`
- Ship scene — must include a `ShieldMesh (MeshInstance3D)` node with
  `ShieldEffectPlayer.gd` attached; the node path is resolved at ship assembly time
  by `ShipFactory.gd`
- Weapons spec `weapon.json` — `effects` block must be added to every weapon definition
- Ship spec `ship.json` — `effects` block must be added to every hull definition

---

## 9. Assumptions

- `GPUParticles3D` is the particle renderer throughout; `CPUParticles3D` is not used
- Particle process material is authored as a `.tres` resource and referenced from the
  Godot scene side — `effect.json` defines tunable parameters; the raw `.tres` lives
  alongside the GDScript files, not in the content folder
- Beam mesh type (CapsuleMesh vs BoxMesh vs QuadMesh) is deferred to the implementing
  agent — the spec requires only that it scales along the local Z axis
- Explosion debris is purely visual; no `RigidBody3D` fragments are spawned — debris is
  particle emission only
- Shield mesh is a separate `MeshInstance3D` node present on all ships, even those
  whose stats give them minimal shield capacity — visual presence is decoupled from
  shield HP value
- Projectile trail effects (tracers, missile exhaust) are handled by `ProjectileManager`
  attaching the appropriate trail to each projectile at spawn; `VFXManager` does not
  manage trail lifetimes — this is a `ProjectileManager` concern deferred to its
  implementation phase
- All world-space VFX spawn positions enforce `y = 0` — no 3D vertical scatter even for
  explosion debris particles
- Effect colors are placeholder values; an art pass will tune them once combat feels
  correct mechanically

---

## 10. Success Criteria

- [ ] Muzzle flash plays at the correct world position for each weapon archetype when fired
- [ ] Autocannon produces a brief, bright flash; pulse laser produces a softer pop
- [ ] Beam laser renders a continuous line from Muzzle marker to hit point, updated every frame
- [ ] Beam disappears immediately (same frame) when fire input is released or weapon overheats
- [ ] Hull impact sparks appear at the correct world position, oriented to the surface normal
- [ ] Shield ripple shader activates on the correct ship's shield mesh when that ship is hit
- [ ] Ship destruction spawns the explosion tier defined in that hull's `ship.json`
- [ ] Missile detonation spawns an explosion at the world position of detonation
- [ ] Multi-layer explosion plays each layer in sequence with delays matching `effect.json`
- [ ] `explosion_small`, `_medium`, and `_large` read visually distinct at gameplay distance
- [ ] All world-space effect spawn positions enforce `y = 0`
- [ ] Setting `pool_size: 0` in any `effect.json` disables that effect with no errors
- [ ] A new effect is added by creating a new `/content/effects/<id>/` folder — no code changes
- [ ] `weapon.json` `effects` block drives which muzzle flash and trail each weapon uses
- [ ] `ship.json` `effects` block drives which explosion tier and shield ripple a hull uses
- [ ] 50+ simultaneous active effect instances run within frame budget at 60fps
- [ ] `VFXManager.active_effects` count is visible in the PerformanceOverlay
