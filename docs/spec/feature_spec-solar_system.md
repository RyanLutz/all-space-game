# Solar System Specification
*All Space — System Scale World: Stars, Planets, Orbital Bodies, and In-System Warp*

---

## 1. Overview

The Solar System spec owns the persistent, large-scale structure of a destination star
system: the star (or binary pair), its planets and moons, asteroid belt region definitions,
station placement, and the in-system warp mechanic. It is the authoritative source of truth
for what a system contains and where everything is. The ChunkStreamer handles what populates
the local neighborhood around the player as they fly through it; the Solar System defines the
regions, bodies, and layout that ChunkStreamer reads from.

**Design Goals:**

- Every destination system feels distinct — archetype-first generation within randomized
  parameters ensures recognizable "flavors" (barren, industrial, frontier) while no two
  systems look identical.
- Fully deterministic from the galaxy seed — the same galaxy always produces the same
  systems. No per-system save data is needed for world state.
- Visual scale is cinematic, not realistic. Planets are large enough to read clearly from
  the camera, not astronomically proportioned. Distances are compressed to be traversable.
- The star is an obstacle, not just scenery. It punches up through the play plane (Y = 0)
  and its circular intersection defines an exclusion zone lethal to ships.
- Planets are scenic backdrop — they do not block movement but give the system depth and
  presence at the camera's shallow angle.
- A hand-authoring override path allows specific story systems to be crafted manually while
  the rest of the universe generates procedurally from seed.

---

## 2. Architecture

```
SolarSystem (Node3D — root of the system scene)
    ├── SolarSystemRoot (Node3D — repositioned on origin shifts)
    │     ├── StarGroup (Node3D)
    │     │     ├── Star_0 (Node3D — Star.gd)
    │     │     │     ├── MeshInstance3D  (sphere centered at Y = -star_center_depth)
    │     │     │     ├── OmniLight3D
    │     │     │     └── ExclusionRingMesh (MeshInstance3D — visual indicator at Y=0)
    │     │     └── Star_1 (Node3D — binary only; optional)
    │     └── PlanetGroup (Node3D)
    │           ├── Planet_0 (Node3D — Planet.gd)
    │           │     ├── MeshInstance3D  (sphere centered at Y = -planet_depth)
    │           │     ├── AtmosphereGlow  (MeshInstance3D — unlit shader rim)
    │           │     ├── MoonGroup (Node3D)
    │           │     │     └── Moon_0 (Node3D — Planet.gd, moon_mode = true)
    │           │     └── StationGroup (Node3D)
    │           │           └── Station_0 (Node3D — Station.gd)
    │           └── Planet_1 ...
    └── OriginShifter (Node3D — OriginShifter.gd)
```

### Separation of Concerns

| Concern | Owner |
|---|---|
| What exists in a system and where | SolarSystem + SolarSystemGenerator |
| Asteroid belt region definitions | SolarSystem (`get_belt_context_at`) |
| Individual asteroid spawning | ChunkStreamer (reads belt context) |
| In-system warp state machine | WarpDrive.gd (attached to the player ship) |
| Floating origin management | OriginShifter.gd |
| Station docking/trading logic | Future Station spec |
| Interstellar warp | Future Warp / StarField spec |

### Visual Plane Architecture

All gameplay (ships, projectiles, asteroids, stations) sits at **Y = 0**.

- **Star:** A `SphereMesh` whose center is at `Y = -star_center_depth`. Its radius is large
  enough that the sphere surface intersects Y = 0, forming a circle. That circle is the
  exclusion zone. Ships that enter it take lethal heat/radiation damage.
- **Planets:** `SphereMesh` centers at `Y = -planet_center_depth`. Their radius is always
  less than their depth value, so the sphere never intersects Y = 0. Ships fly over them.
  The camera's shallow angle reveals them as large orbs beneath the play surface.
- **Binary stars:** Two Star nodes placed symmetrically around the system center. Each has
  its own exclusion zone. The gap between overlapping or adjacent zones creates a navigable
  corridor — extremely dangerous, potentially containing a unique authored content point.

### Floating Origin

Godot's 32-bit float physics precision degrades beyond ~10,000–20,000 units from the
world origin. The `OriginShifter` keeps all physics bodies near (0, 0, 0) by shifting
them periodically. Visual-only objects (star meshes, planet meshes) are repositioned
alongside physics bodies so the visual frame remains coherent.

Origin shifts are triggered when the player crosses a chunk boundary — a `chunk_loaded`
event already emitted by `ChunkStreamer`. The shift is atomic (applied before the next
physics step) and emits `origin_shifted` so every system that tracks absolute world
positions can update its references.

### ChunkStreamer Integration

`ChunkStreamer._populate_asteroids` calls `SolarSystem.get_belt_context_at(world_pos)`
before generating asteroid fields. The return value is a `Dictionary`:

```gdscript
{
  "in_belt": true,
  "density_multiplier": 2.5,   # relative to baseline world_config values
  "asteroid_type_weights": {   # overrides world_config size_weights if present
    "small": 0.3,
    "medium": 0.5,
    "large": 0.2
  }
}
```

If `in_belt` is false, ChunkStreamer generates asteroid fields at its baseline density
(open space — sparse or empty). If `in_belt` is true, it multiplies its field count and
asteroid count by `density_multiplier`. This is the only interface between these two
systems — ChunkStreamer does not know about orbits, planets, or system archetypes.

---

## 3. Core Properties / Data Model

### SolarSystem.gd

| Property | Type | Description |
|---|---|---|
| `system_id` | `String` | Unique identifier from the galaxy map |
| `system_seed` | `int` | Derived from galaxy seed + system_id hash |
| `archetype` | `String` | `"barren"`, `"inhabited"`, `"industrial"`, `"frontier"`, `"anomaly"` |
| `_stars` | `Array[Node3D]` | Star nodes (1 for single, 2 for binary) |
| `_planets` | `Array[Node3D]` | Planet nodes, ordered by orbital radius |
| `_belt_regions` | `Array[Dictionary]` | Orbital belt region definitions (see below) |
| `_world_origin` | `Vector3` | Cumulative origin offset since system load |
| `_config` | `Dictionary` | Loaded from `solar_system_archetypes.json` |

### Belt Region Dictionary

```gdscript
{
  "inner_radius": 12000.0,   # distance from system center (XZ plane)
  "outer_radius": 18000.0,
  "density_multiplier": 2.5,
  "asteroid_type_weights": { "small": 0.3, "medium": 0.5, "large": 0.2 }
}
```

### Planet.gd

| Property | Type | Description |
|---|---|---|
| `planet_type` | `String` | `"terrestrial"`, `"gas_giant"`, `"ice"`, `"barren"`, `"molten"` |
| `orbit_radius` | `float` | XZ distance from system center |
| `orbit_angle` | `float` | Current angular position in radians |
| `orbit_speed` | `float` | Radians per second (slow drift) |
| `planet_depth` | `float` | Y offset of mesh center below play plane |
| `visual_radius` | `float` | Mesh sphere radius |
| `moon_mode` | `bool` | If true, orbits its parent planet instead of the system center |
| `_stations` | `Array[Node3D]` | Station nodes parented to this planet |

### Star.gd

| Property | Type | Description |
|---|---|---|
| `star_type` | `String` | `"yellow_dwarf"`, `"red_giant"`, `"neutron"`, `"white_dwarf"`, `"binary_primary"`, `"binary_secondary"` |
| `star_center_depth` | `float` | Y distance of mesh center below play plane |
| `visual_radius` | `float` | Sphere mesh radius |
| `exclusion_radius` | `float` | Radius of the lethal zone at Y=0 (computed from JSON or set directly) |
| `damage_per_second` | `float` | Hull DPS applied inside exclusion zone |
| `light_energy` | `float` | OmniLight3D energy value |
| `light_range` | `float` | OmniLight3D range |

### OriginShifter.gd

| Property | Type | Description |
|---|---|---|
| `shift_threshold` | `float` | Distance from origin that triggers a shift (default: half a chunk width) |
| `_physics_group` | `String` | Group name queried to find all repositionable physics bodies |

### WarpDrive.gd

| Property | Type | Description |
|---|---|---|
| `warp_state` | `String` | `"IDLE"`, `"CHARGING"`, `"READY"`, `"ACTIVE"`, `"DECELERATING"` |
| `warp_mode` | `String` | `"PLOTTED"` or `"MANUAL"` |
| `charge_time` | `float` | Seconds to fill charge bar |
| `thrust_multiplier` | `float` | Multiplier on `thruster_force` during ACTIVE |
| `damp_override` | `float` | `linear_damp` value during ACTIVE (0 = coast) |
| `max_warp_speed` | `float` | Soft cap with cubic ease-out falloff |
| `interrupt_damage_threshold` | `float` | Single-hit damage that triggers interrupt |
| `exclusion_margin` | `float` | Distance beyond exclusion radius that auto-aborts |
| `min_distance` | `float` | Minimum destination distance for warp plot eligibility |
| `charge_energy_rate` | `float` | Energy drain per second while CHARGING |
| `hold_energy_rate` | `float` | Energy drain per second while READY |

---

## 4. Key Algorithms

### System Generation Pipeline

```gdscript
# SolarSystemGenerator.gd
func generate(system_id: String, galaxy_seed: int) -> Dictionary:
    # 1. Derive a repeatable per-system seed
    var seed := hash(str(galaxy_seed) + system_id)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    # 2. Check for hand-authored override first
    var override_path := "res://content/systems/%s/system.json" % system_id
    if ResourceLoader.exists(override_path):
        return _load_authored_system(override_path)

    # 3. Pick archetype
    var archetype := _pick_archetype(rng)

    # 4. Pick star configuration
    var star_config := _generate_stars(rng, archetype)

    # 5. Generate planets
    var planets := _generate_planets(rng, archetype, star_config)

    # 6. Generate belt regions
    var belts := _generate_belts(rng, archetype, planets)

    return {
        "system_id": system_id,
        "seed": seed,
        "archetype": archetype,
        "stars": star_config,
        "planets": planets,
        "belts": belts
    }
```

The returned Dictionary is the system manifest. `SolarSystem.gd` reads it and
instantiates all nodes. The generator itself does no scene manipulation.

### Orbital Drift

Planets update their XZ position every `_process` frame. Their Y position is fixed
at `-planet_center_depth` (a property set at generation time). Moons do the same but
orbit their parent planet node rather than the system center.

```gdscript
# Planet.gd
func _process(delta: float) -> void:
    orbit_angle += orbit_speed * delta
    var orbit_center: Vector3 = _get_orbit_center()  # system root or parent planet
    global_position = Vector3(
        orbit_center.x + cos(orbit_angle) * orbit_radius,
        orbit_center.y - planet_depth,
        orbit_center.z + sin(orbit_angle) * orbit_radius
    )
```

Stations are children of their planet node and follow automatically — no per-station
orbit math required.

### Exclusion Zone Check

The star exclusion zone is a distance check on the XZ plane only. It runs in
`Star._physics_process`. Because stars may be binary, the check is called for
each star independently.

```gdscript
# Star.gd
func _physics_process(_delta: float) -> void:
    var ships := get_tree().get_nodes_in_group("ships")
    for ship in ships:
        var flat_dist := Vector2(
            ship.global_position.x - global_position.x,
            ship.global_position.z - global_position.z
        ).length()
        if flat_dist < exclusion_radius:
            ship.apply_damage(damage_per_second * _delta, "heat", ship.global_position)
```

No physics collider is used. The check is O(ship count), which is negligible.

### Floating Origin Shift

The `OriginShifter` subscribes to `chunk_loaded` on `GameEventBus`. On each chunk
boundary crossing it checks whether the player has drifted beyond `shift_threshold`
from the world origin. If so, it shifts.

```gdscript
# OriginShifter.gd
func _on_chunk_loaded(_coords: Vector2i) -> void:
    var player_pos := _get_player_position()
    if player_pos.length() < shift_threshold:
        return

    var offset := Vector3(player_pos.x, 0.0, player_pos.z)  # Y stays at 0

    # Shift all physics bodies
    PerformanceMonitor.begin("SolarSystem.origin_shift")
    for body in get_tree().get_nodes_in_group("physics_bodies"):
        if is_instance_valid(body):
            body.global_position -= offset

    # Shift solar system visual root so sky backdrop stays aligned
    _solar_system_root.global_position -= offset

    # Update cumulative world origin tracker
    _solar_system.update_world_origin(offset)
    PerformanceMonitor.end("SolarSystem.origin_shift")

    GameEventBus.origin_shifted.emit(offset)
```

`physics_bodies` group includes: all ships (player and AI), all asteroids. It does
NOT include planets, moons, the star, or stations (all visual-only or static).

### Belt Context Query

Called by `ChunkStreamer._populate_asteroids` before generating each chunk's content:

```gdscript
# SolarSystem.gd
func get_belt_context_at(world_pos: Vector3) -> Dictionary:
    # Convert to absolute system coordinates using world origin
    var abs_pos := world_pos + _world_origin
    var flat_dist := Vector2(
        abs_pos.x - _system_center.x,
        abs_pos.z - _system_center.z
    ).length()

    for belt in _belt_regions:
        if flat_dist >= belt.inner_radius and flat_dist <= belt.outer_radius:
            return {
                "in_belt": true,
                "density_multiplier": belt.density_multiplier,
                "asteroid_type_weights": belt.asteroid_type_weights
            }

    return { "in_belt": false, "density_multiplier": 1.0, "asteroid_type_weights": {} }
```

### Warp State Machine (Dual Mode)

`WarpDrive.gd` is a component attached to every ship node. It supports two warp modes
that share a single state machine:

- **PLOTTED:** Right-click a distant point (> `min_distance`) in Tactical mode →
  select "Plot Warp Course" → charge builds → press **Y** to engage autopilot.
- **MANUAL:** Hold **Y** to charge → release to disengage. Player steers manually
  during ACTIVE with boosted thrust and zero damping.

```
                         ┌─(Y held, no plot)────┐
                         ▼                      │
IDLE ──(plot dest)──► CHARGING ──(charge full)──► READY ──(Y press)──► ACTIVE
  ▲                      │ (cancel / dmg / energy)                        │
  │                      │ (release Y [manual])                           │
  │                      ▼                                                  │
  └───────────────── IDLE ◄─── DECELERATING ◄─────────────────────────────┘
                              (arrive / release Y [manual] / dmg /
                               exclusion proximity / energy depleted)
```

State behaviors:
- **CHARGING:** Ship moves normally. Charge timer increments. Energy drains at
  `charge_energy_rate`. Cancelled by: releasing Y (manual), unselecting destination
  (plotted), damage > threshold, or energy depletion.
- **READY (plotted only):** Charge held at 100%. Low energy drain (`hold_energy_rate`).
  Awaiting Y press to engage.
- **ACTIVE:** `linear_damp = warp_damp_override` (0.0 = coast), `thruster_force` boosted
  by `thrust_multiplier`. Thrust curve applies cubic ease-out falloff as velocity
  approaches `max_warp_speed` — acceleration tapers but never truly stops.
  - **PLOTTED:** NavigationController flies to destination; natural braking distance
    produces accelerate-then-decelerate trajectory. Arrives cleanly.
  - **MANUAL:** Player inputs drive thrust directly. Release Y → DECELERATING.
  Weapons disabled during ACTIVE.
- **DECELERATING:** Stats restored. NavigationController emergency-brakes against
  current velocity until stopped. Returns to IDLE when speed < 1.0.

Interrupts (all modes):
- Damage in a single hit > `interrupt_damage_threshold` → immediate DECELERATING
- Approach within `exclusion_margin` of any star exclusion zone → DECELERATING
- Energy depleted → DECELERATING (or IDLE if in CHARGING/READY)

Queued actions: tactical move orders issued during CHARGING/READY/ACTIVE do not
cancel warp. They are deferred and executed after warp returns to IDLE.

---

## 5. JSON Data Format

### `data/solar_system_archetypes.json`

```json
{
  "_comment": "Solar system archetypes for All Space. Each archetype defines generation
               parameter ranges. Values are [min, max] pairs unless noted.",

  "archetypes": {
    "barren": {
      "weight": 0.30,
      "planet_count": [1, 6],
      "binary_star_chance": 0.05,
      "belt_count": [0, 2],
      "station_count_per_planet_weights": { "0": 0.85, "1": 0.12, "2": 0.03 },
      "planet_type_weights": { "barren": 0.65, "molten": 0.20, "ice": 0.15 }
    },
    "inhabited": {
      "weight": 0.25,
      "planet_count": [3, 12],
      "binary_star_chance": 0.10,
      "belt_count": [0, 3],
      "station_count_per_planet_weights": { "0": 0.40, "1": 0.30, "2": 0.15, "3": 0.10, "4+": 0.05 },
      "planet_type_weights": { "terrestrial": 0.50, "gas_giant": 0.25, "ice": 0.15, "barren": 0.10 }
    },
    "industrial": {
      "weight": 0.20,
      "planet_count": [4, 14],
      "binary_star_chance": 0.08,
      "belt_count": [1, 4],
      "station_count_per_planet_weights": { "0": 0.25, "1": 0.30, "2": 0.20, "3": 0.15, "4+": 0.10 },
      "planet_type_weights": { "barren": 0.40, "terrestrial": 0.30, "gas_giant": 0.20, "molten": 0.10 }
    },
    "frontier": {
      "weight": 0.20,
      "planet_count": [2, 10],
      "binary_star_chance": 0.12,
      "belt_count": [1, 3],
      "station_count_per_planet_weights": { "0": 0.60, "1": 0.25, "2": 0.10, "3": 0.05 },
      "planet_type_weights": { "barren": 0.35, "ice": 0.25, "terrestrial": 0.25, "gas_giant": 0.15 }
    },
    "anomaly": {
      "weight": 0.05,
      "planet_count": [1, 20],
      "binary_star_chance": 0.35,
      "belt_count": [0, 5],
      "station_count_per_planet_weights": { "0": 0.70, "1": 0.20, "2": 0.10 },
      "planet_type_weights": { "molten": 0.30, "gas_giant": 0.30, "barren": 0.20, "ice": 0.20 }
    }
  },

  "generation": {
    "planet_count_max_absolute": 20,
    "moon_count_per_planet": [0, 10],
    "station_count_per_planet_max_absolute": 12,
    "orbit_radius_first_planet": 4000.0,
    "orbit_radius_step_min": 2000.0,
    "orbit_radius_step_max": 6000.0,
    "orbit_speed_min": 0.002,
    "orbit_speed_max": 0.015,
    "moon_orbit_radius_min": 300.0,
    "moon_orbit_radius_max": 1200.0
  },

  "visual": {
    "star_center_depth_single": 2000.0,
    "star_visual_radius_single": 3500.0,
    "star_exclusion_radius_single": 2800.0,
    "star_center_depth_binary": 1200.0,
    "star_visual_radius_binary": 2200.0,
    "star_exclusion_radius_binary": 1800.0,
    "binary_star_separation": 5000.0,
    "planet_center_depth_min": 400.0,
    "planet_center_depth_max": 1200.0,
    "planet_visual_radius_min": 300.0,
    "planet_visual_radius_max": 1800.0,
    "gas_giant_visual_radius_min": 900.0,
    "gas_giant_visual_radius_max": 2500.0,
    "moon_visual_radius_min": 60.0,
    "moon_visual_radius_max": 250.0
  },

  "exclusion_zone": {
    "damage_per_second": 150.0,
    "damage_type": "heat",
    "warning_ring_visible": true
  },

  "warp": {
    "charge_time": 2.5,
    "thrust_multiplier": 8.0,
    "damp_override": 0.0,
    "max_warp_speed": 2500.0,
    "interrupt_damage_threshold": 20.0,
    "exclusion_margin": 500.0,
    "min_distance": 5000.0,
    "charge_energy_rate": 15.0,
    "hold_energy_rate": 5.0
  },

  "belt": {
    "width_min": 3000.0,
    "width_max": 8000.0,
    "density_multiplier_min": 1.5,
    "density_multiplier_max": 4.0
  }
}
```

### Hand-Authored System Override

Any system can be fully hand-authored by placing a `system.json` in
`res://content/systems/<system_id>/`. The generator checks for this file before
running any procedural logic. The file format is the same as the generator output —
identical keys, just filled in manually.

```json
{
  "_comment": "Hand-authored binary gap system. Story-significant — do not proceduralize.",
  "system_id": "binary_gap_001",
  "archetype": "anomaly",
  "stars": [
    {
      "star_type": "binary_primary",
      "position_offset": [-2500, 0, 0],
      "exclusion_radius": 1800.0,
      "damage_per_second": 200.0,
      "light_energy": 1.4,
      "light_range": 80000.0
    },
    {
      "star_type": "binary_secondary",
      "position_offset": [2500, 0, 0],
      "exclusion_radius": 1800.0,
      "damage_per_second": 200.0,
      "light_energy": 1.2,
      "light_range": 80000.0
    }
  ],
  "planets": [
    {
      "planet_type": "molten",
      "orbit_radius": 0.0,
      "orbit_speed": 0.0,
      "orbit_angle": 0.0,
      "visual_radius": 400.0,
      "planet_depth": 300.0,
      "moons": [],
      "stations": []
    }
  ],
  "belts": [],
  "authored_note": "The toasted planet sits dead-center in the binary gap."
}
```

---

## 6. Performance Instrumentation

```gdscript
# SolarSystemGenerator.gd — wrap the full generation pass
PerformanceMonitor.begin("SolarSystem.generate")
# ... full generation ...
PerformanceMonitor.end("SolarSystem.generate")

# SolarSystem.gd — orbit updates (all planets each frame)
PerformanceMonitor.begin("SolarSystem.orbit_update")
# ... planet _process calls (or manual loop if batched) ...
PerformanceMonitor.end("SolarSystem.orbit_update")

# OriginShifter.gd — origin shift cost (fires rarely, but expensive when it does)
PerformanceMonitor.begin("SolarSystem.origin_shift")
# ... reposition loop ...
PerformanceMonitor.end("SolarSystem.origin_shift")

# Static counts (set once at generation, update if bodies are added/removed)
PerformanceMonitor.set_count("SolarSystem.planet_count", _planets.size())
PerformanceMonitor.set_count("SolarSystem.station_count", _total_station_count())
PerformanceMonitor.set_count("SolarSystem.belt_count", _belt_regions.size())
```

Register custom monitors in `SolarSystem._ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/solar_generate_ms",
    func(): return PerformanceMonitor.get_avg_ms("SolarSystem.generate"))
Performance.add_custom_monitor("AllSpace/solar_orbit_ms",
    func(): return PerformanceMonitor.get_avg_ms("SolarSystem.orbit_update"))
Performance.add_custom_monitor("AllSpace/origin_shift_ms",
    func(): return PerformanceMonitor.get_avg_ms("SolarSystem.origin_shift"))
Performance.add_custom_monitor("AllSpace/planet_count",
    func(): return PerformanceMonitor.get_count("SolarSystem.planet_count"))
```

Orbit updates run every frame. They must stay below 0.1ms for a maximum system size
(20 planets × 10 moons = 210 orbital bodies). If profiling shows this is a bottleneck,
batch planet positions in a single loop in `SolarSystem._process` rather than letting
each Planet node run its own `_process`.

---

## 7. New Signals Required (GameEventBus additions)

These signals must be added to `GameEventBus_Signals` spec and `GameEventBus.gd` before
any Solar System implementation begins.

```gdscript
# ─── Solar System ──────────────────────────────────────────────────────────────
signal system_loaded(system_id: String)
signal system_unloaded(system_id: String)
signal origin_shifted(offset: Vector3)
signal exclusion_zone_entered(ship: Node, star_index: int)
signal exclusion_zone_exited(ship: Node, star_index: int)

# ─── Warp ──────────────────────────────────────────────────────────────────────
signal warp_state_changed(ship: Node, old_state: String, new_state: String)
signal warp_interrupted(ship: Node, reason: String)
signal warp_destination_plotted(destination: Vector3)
```

| Signal | Emitted By | Listened By |
|---|---|---|
| `system_loaded` | SolarSystem | ChunkStreamer (begin streaming), AI, UI |
| `system_unloaded` | SolarSystem | ChunkStreamer (clear chunks), AI |
| `origin_shifted` | OriginShifter | Any system tracking absolute world positions |
| `exclusion_zone_entered` | Star | VFX (heat shimmer), Audio (alarm), UI (warning) |
| `exclusion_zone_exited` | Star | VFX, Audio (clear alarm), UI |
| `warp_state_changed` | WarpDrive | VFX (engine trail), Audio (warp hum), UI |
| `warp_interrupted` | WarpDrive | VFX (discharge flash), Audio (interrupt SFX) |
| `warp_destination_plotted` | WarpPlotMenu | WarpDrive (sets destination and enters CHARGING) |

---

## 8. Files

```
/gameplay/world/
    SolarSystem.gd              ← scene manager; instantiates system from manifest;
                                  owns _world_origin; exposes get_belt_context_at()
    SolarSystemGenerator.gd     ← pure generation logic; no scene manipulation;
                                  returns Dictionary manifest; checks override path
    Planet.gd                   ← orbital drift; moon_mode flag; no physics
    Star.gd                     ← exclusion zone check; OmniLight3D management
    Station.gd                  ← placement node; docking handoff to future spec
    OriginShifter.gd            ← floating origin management; emits origin_shifted
    WarpDrive.gd                ← in-system warp state machine; attached to player ship

/data/
    solar_system_archetypes.json   ← all generation parameters and visual tuning
    world_config.json              ← extended: add "solar_system" section (see below)

/content/systems/
    <system_id>/
        system.json             ← hand-authored override (optional per system)

/core/
    GameEventBus.gd             ← MODIFIED: add Solar System and Warp signals
```

**`world_config.json` Solar System addition:**

```json
{
  "solar_system": {
    "origin_shift_threshold": 1000.0,
    "physics_bodies_group": "physics_bodies",
    "icon_lod_distance": 8000.0,
    "warp_key": "warp"
  }
}
```

---

## 9. Dependencies

- **`GameEventBus`** — `origin_shifted`, `system_loaded`, `system_unloaded`,
  `exclusion_zone_entered`, `warp_state_changed`, `warp_interrupted` must be defined
  before any system implementation begins.
- **`PerformanceMonitor`** — must be registered in the autoload before SolarSystem
  enters the scene tree.
- **`ChunkStreamer`** — must be modified to call `SolarSystem.get_belt_context_at()`
  in `_populate_asteroids`. ChunkStreamer must wait for `system_loaded` before
  beginning its first streaming pass. Review `feature_spec-chunk_streamer.md` and the
  existing implementation to determine the cleanest integration point.
- **`Ship.apply_damage()`** — exclusion zone damage calls this directly; ship must
  exist and expose this method before Star.gd can be fully integrated.
- **`Physics spec`** — WarpDrive needs to increase ship speed during active warp.
  Review `feature_spec-physics_and_movement.md` and the existing implementation to
  determine the best mechanism — whether that is a `warp_multiplier` property, a
  temporary stat override, or another approach consistent with the physics system's
  existing patterns.
- **Galaxy map / StarField** — provides `system_id` and `galaxy_seed` to
  `SolarSystemGenerator`. The handoff interface must be defined before this system
  can be integrated end-to-end. For MVP testing, hardcode a test `system_id` and seed.

---

## 10. Assumptions

- Orbital speeds (`0.002`–`0.015` rad/s) are placeholder. One full orbit takes
  ~7–52 minutes at these speeds. Tune for visual pleasure — the player should see
  planets noticeably move over a session without feeling like a simulation.
- Visual radii and depths are placeholder. All star and planet visual parameters need
  an art pass to feel right at the camera's default angle. Tune in the test scene before
  writing final JSON values.
- `star_exclusion_radius_single: 2800.0` is a guess. Tune so the star feels dangerous
  from the standard pilot camera view — threatening, not invisible.
- `warp_speed_multiplier: 80.0` is a placeholder. Crossing a system at maximum warp
  should take 30–90 seconds of engaged flight. Tune against actual system scale in testing.
- `station_count_per_planet` weights are first-pass guesses. Tune after content budget
  (station types, art assets) is established.
- Belt width and density multipliers are placeholder. Tune so belts feel meaningfully
  denser than open space without being impassable.
- Planet mesh materials are placeholder (solid color StandardMaterial3D per type).
  Shaders and texture passes are deferred to an art sprint; the spec does not gate on them.
- Station placement within a planet's orbital radius (angle around planet, distance from
  planet surface) is deferred to the Station spec. This spec places Station nodes under
  the correct planet node with a reasonable default offset.
- Moon orbital inclination is always 0 (moons orbit on the XZ plane same as planets).
  Off-plane moons are a future visual enhancement.
- The `physics_bodies` group must be added to all RigidBody3D ships and asteroids. This
  is an additive change to Ship.gd and Asteroid.gd — no behavior changes, just `add_to_group`.
- Chunk streamer modification (belt-aware generation) is an additive change only — open
  space behavior is unchanged. The `get_belt_context_at()` call adds one Dictionary lookup
  per chunk generation event.

---

## 11. Success Criteria

- [ ] Loading a system by `system_id` and `galaxy_seed` always produces the same layout
  on repeated calls — fully deterministic
- [ ] A hand-authored system JSON in `content/systems/<id>/system.json` loads exactly
  as defined — no procedural modification
- [ ] Binary star systems generate two stars with two independent exclusion zones; the
  gap between them is navigable
- [ ] Planets visibly drift over a 5-minute session — orbit is perceptible but not jarring
- [ ] Planets do not intersect Y = 0 — ships can fly over any planet without collision
- [ ] The star exclusion zone deals damage-per-second to any ship inside it — confirmed
  via `apply_damage()` call trace
- [ ] A ship entering the exclusion zone emits `exclusion_zone_entered` on GameEventBus
- [ ] `SolarSystem.get_belt_context_at()` returns `in_belt: true` for positions within
  a belt region and `in_belt: false` outside — confirmed with a test at known coordinates
- [ ] ChunkStreamer generates noticeably denser asteroid fields inside belt regions
  compared to open space at baseline density
- [ ] Origin shift fires when the player exceeds `origin_shift_threshold` distance from
  world origin — confirmed by watching `SolarSystem.origin_shift` metric spike in the
  PerformanceMonitor overlay
- [ ] After an origin shift, ships continue behaving correctly — no visible pop, no
  physics jitter
- [ ] Stations remain correctly parented to their planet and follow its orbital drift
- [ ] **Plotted warp:** Right-click > `min_distance` away → "Plot Warp Course" →
  charge fills over `charge_time` → press Y → ship autopilots to destination with
  accelerate-then-decelerate trajectory
- [ ] **Manual warp:** Hold Y to charge → release Y to disengage. Ship has zero damp
  + boosted thrust, player steers manually. Thrust tapers via cubic ease-out as
  velocity approaches `max_warp_speed`
- [ ] Energy drains at `charge_energy_rate` during CHARGING and `hold_energy_rate`
  during READY; energy depletion interrupts warp
- [ ] Weapons are disabled during ACTIVE warp (both modes)
- [ ] Taking a hit above `interrupt_damage_threshold` while warping transitions warp
  to DECELERATING state (or IDLE if in CHARGING/READY)
- [ ] Approaching a star exclusion zone while warping auto-aborts warp before the ship
  crosses the exclusion boundary
- [ ] `PerformanceMonitor` overlay (F3) shows `SolarSystem.orbit_update`,
  `SolarSystem.origin_shift`, `SolarSystem.planet_count`, and `SolarSystem.station_count`
- [ ] Orbit update cost stays below 0.1ms with a 20-planet, 10-moon-per-planet system
- [ ] No `Vector2`, `Node2D`, or 2D physics nodes appear anywhere in this system
- [ ] All tunable values (orbital speeds, exclusion radius, warp multiplier, belt density,
  DPS) are in JSON — no hardcoded numbers in any `.gd` file
```
