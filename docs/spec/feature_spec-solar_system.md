# Feature Spec — Solar System
*All Space — System Scale World: Star, Planets, Belts, Exclusion Zone, In-System Warp*

**Status:** Session A implemented. Sessions B–D not started.

---

## 1. Overview

The solar system spec owns the persistent large-scale structure of a destination star
system: the local star, its planets and moons, asteroid belt region definitions, station
placement, and the in-system warp mechanic. It is the authoritative source for what a
system contains and where everything is.

The solar system is a **visual backdrop** to gameplay. Ships, projectiles, and asteroids
all live at `Y = 0` on the play plane. Planets and the star exist below the play plane
— the camera's shallow angle reveals them as large bodies beneath the surface. They do
not collide with ships. Only the star's exclusion zone punishes ships that fly too close.

**Key architectural fact:** The solar system and the galaxy map are completely separate
coordinate systems. The solar system scene uses Godot world coordinates (thousands of
units). The galaxy uses its own coordinate space (hundreds of thousands of units). The
galaxy map is displayed by the camera-attached `GalaxyContainer` — it has nothing to do
with the solar system scene layout.

**Design goals:**
- Every system feels distinct — archetype-first generation within randomized parameters
- Fully deterministic from galaxy seed — same seed always produces same system
- Visual scale is cinematic, not realistic — planets large enough to read from camera
- Star is an obstacle — exclusion zone at Y=0 is lethal
- Planets are scenic backdrop — never block movement
- Hand-authored override path for story systems

---

## 2. Architecture

```
SolarSystem (Node3D — SolarSystem.gd)
    ├── SolarSystemRoot (Node3D — repositioned on origin shifts)
    │   ├── StarGroup (Node3D)
    │   │   ├── Star_0 (Node3D — Star.gd)
    │   │   │   ├── MeshInstance3D (QuadMesh billboard — solar_star_sdf.gdshader)
    │   │   │   ├── OmniLight3D
    │   │   │   ├── ExclusionRingMesh (MeshInstance3D — flat disc at Y=0)
    │   │   │   └── ExclusionArea (Area3D + SphereShape3D — damage trigger)
    │   │   └── Star_1 (Node3D — binary only, optional)
    │   └── PlanetGroup (Node3D)
    │       ├── Planet_0 (Node3D — Planet.gd)
    │       │   ├── MeshInstance3D (SphereMesh below play plane)
    │       │   ├── MoonGroup (Node3D)
    │       │   │   └── Moon_0 (Node3D — Planet.gd, moon_mode = true)
    │       │   └── StationGroup (Node3D)
    │       │       └── Station_0 (Node3D — Station.gd)
    │       └── Planet_1 ...
    └── OriginShifter (Node3D — OriginShifter.gd)
```

### Coordinate systems

**Game world space** — where ships fly. All gameplay at `Y = 0`. Measured in thousands
of units. ChunkStreamer, ships, projectiles, asteroids all live here.

**Galaxy space** — catalog coordinates only. Hundreds of thousands of units. Never
directly visible. Used by `StarField` for skybox direction vectors and galaxy map
positions. Has nothing to do with solar system layout.

The solar system generates its layout in game world space. `orbit_radius` values are
game world units. A planet at `orbit_radius: 8000` is 8,000 game world units from the
system center.

### The visual plane

All gameplay lives at `Y = 0`. The solar system bodies live below it:

- **Star:** `SphereMesh` or `QuadMesh` billboard centered at `Y = -star_center_depth`.
  Its radius is large enough that the body is visible from above. The circle where it
  would intersect `Y = 0` defines the exclusion zone.
- **Planets:** `SphereMesh` centered at `Y = -planet_center_depth`. Radius always less
  than depth — never intersects `Y = 0`. Ships fly over them.
- **Gameplay:** Always at `Y = 0`. Ships never go below the play plane.

---

## 3. Core Properties / Data Model

### SolarSystem.gd

```gdscript
var system_id: String
var system_seed: int
var archetype: String
var _stars: Array           # Star nodes (1 for single, 2 for binary)
var _planets: Array         # Planet nodes ordered by orbital radius
var _belt_regions: Array    # Dictionaries defining asteroid belt zones
var _world_origin: Vector3  # Cumulative origin offset since system load
var _config: Dictionary     # Loaded from solar_system_archetypes.json
```

### Star.gd

```gdscript
var star_type: String          # "yellow_dwarf", "red_giant", "neutron", etc.
var star_center_depth: float   # Y distance of body below play plane
var visual_radius: float       # Physical size of the star body
var exclusion_radius: float    # Radius of lethal zone at Y = 0
var damage_per_second: float   # Hull DPS inside exclusion zone
var light_energy: float        # OmniLight3D intensity
var light_range: float         # OmniLight3D range
```

**Rendering:** `Star.gd` uses a `QuadMesh` billboard with `solar_star_sdf.gdshader`
rather than a `SphereMesh`. The SDF shader computes a perfect sphere analytically from
UV coordinates. The billboard always faces the camera, so the star always presents a
perfect circle regardless of viewing angle.

Key advantages:
- No polygon faceting at any camera angle
- Corona glow extends analytically beyond the quad edge
- Multi-layer plasma surface, solar flares, limb darkening — all shader-computed
- Cheaper than a high-poly SphereMesh

The quad is positioned at `Vector3(0, -star_center_depth, 0)` and sized to
`visual_radius * 2.2` to accommodate corona bleed beyond the sphere edge.

The `ExclusionRingMesh` is a flat `CylinderMesh` disc at `Y = 0` with radius
`exclusion_radius` — a visual danger indicator for the player.

### Planet.gd

```gdscript
var planet_type: String      # "terrestrial", "gas_giant", "ice", "barren", "molten"
var orbit_radius: float      # XZ distance from system center
var orbit_angle: float       # Current angular position in radians
var orbit_speed: float       # Radians per second (slow drift)
var planet_depth: float      # Y offset of mesh center below play plane
var visual_radius: float     # SphereMesh radius
var moon_mode: bool          # If true, orbits parent planet instead of system center
```

Planet orbital drift is batched in `SolarSystem._process()` — not in individual
`Planet._process()` calls. This keeps orbit update cost to one loop regardless of
planet count.

```gdscript
# SolarSystem.gd
func _process(delta: float) -> void:
    PerformanceMonitor.begin("SolarSystem.orbit_update")
    for body in _orbiters:
        if is_instance_valid(body):
            body.update_orbit(delta, _world_origin)
    PerformanceMonitor.end("SolarSystem.orbit_update")
```

**Planet depth constraint:** `visual_radius` must always be less than `planet_depth`.
The generator enforces `visual_radius = min(visual_radius, planet_depth * 0.90)` to
prevent spheres from intersecting `Y = 0`.

### Belt Region Dictionary

```gdscript
{
    "inner_radius": 10500.0,   # XZ distance from system center
    "outer_radius": 13000.0,
    "density_multiplier": 2.5, # Relative to baseline world_config asteroid density
    "asteroid_type_weights": { "small": 0.3, "medium": 0.5, "large": 0.2 }
}
```

`SolarSystem.get_belt_context_at(world_pos: Vector3) -> Dictionary` is the only
interface between SolarSystem and ChunkStreamer. ChunkStreamer calls it per chunk to
determine whether to increase asteroid density.

### Spawn Zones (hand-authored systems only)

```gdscript
{
    "id": "outer_planet_patrol",
    "position": [14000, 0, 1500],
    "radius": 600,
    "ship_count": 3,
    "ship_class": "fighter_light",
    "variant": "axum_fighter_patrol",
    "ai_profile": "default",
    "faction": "pirate"
}
```

`spawn_zones` is a top-level array in `system.json`. `GameOrchestrator` reads this
on system load and spawns ships at random positions within each zone radius.
Procedurally generated systems do not have spawn zones — ChunkStreamer handles AI
spawning for those via `ai_spawn_points` group markers.

---

## 4. Key Algorithms

### 4.1 System generation pipeline

```gdscript
# SolarSystemGenerator.gd
func generate(system_id: String, galaxy_seed: int) -> Dictionary:
    # 1. Check for hand-authored override first
    var override_path := "res://content/systems/%s/system.json" % system_id
    if ResourceLoader.exists(override_path):
        return _load_authored_system(override_path)

    # 2. Derive deterministic per-system seed
    var seed := hash(str(galaxy_seed) + system_id)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    # 3. Pick archetype, generate stars, planets, belts
    var archetype := _pick_archetype(rng)
    var stars     := _generate_stars(rng, archetype)
    var planets   := _generate_planets(rng, archetype, stars)
    var belts     := _generate_belts(rng, archetype, planets)

    return {
        "system_id": system_id,
        "seed": seed,
        "archetype": archetype,
        "stars": stars,
        "planets": planets,
        "belts": belts
    }
```

The generator returns a pure data Dictionary — no scene manipulation. `SolarSystem.gd`
reads the manifest and instantiates nodes.

### 4.2 Exclusion zone damage

```gdscript
# Star.gd
func _physics_process(delta: float) -> void:
    var ships := get_tree().get_nodes_in_group("ships")
    for ship in ships:
        var flat_dist := Vector2(
            ship.global_position.x - global_position.x,
            ship.global_position.z - global_position.z
        ).length()
        if flat_dist < exclusion_radius:
            ship.apply_damage(damage_per_second * delta, "heat",
                              ship.global_position, 0.0, 0)
            if not _ship_inside.has(ship.get_instance_id()):
                _ship_inside[ship.get_instance_id()] = true
                GameEventBus.exclusion_zone_entered.emit(ship, _star_index)
        else:
            if _ship_inside.has(ship.get_instance_id()):
                _ship_inside.erase(ship.get_instance_id())
                GameEventBus.exclusion_zone_exited.emit(ship, _star_index)
```

Distance check is on the XZ plane only — `Y` is ignored because the star body is
below the play plane. The exclusion zone is a vertical cylinder at the play surface.

### 4.3 Belt context query

```gdscript
# SolarSystem.gd
func get_belt_context_at(world_pos: Vector3) -> Dictionary:
    var abs_pos  := world_pos + _world_origin
    var flat_dist := Vector2(abs_pos.x - _system_center.x,
                             abs_pos.z - _system_center.z).length()

    for belt in _belt_regions:
        if flat_dist >= belt.inner_radius and flat_dist <= belt.outer_radius:
            return {
                "in_belt": true,
                "density_multiplier": belt.density_multiplier,
                "asteroid_type_weights": belt.asteroid_type_weights
            }

    return { "in_belt": false, "density_multiplier": 1.0, "asteroid_type_weights": {} }
```

### 4.4 Origin shifting

`OriginShifter` subscribes to `chunk_loaded` on `GameEventBus`. When the player
crosses a chunk boundary and has drifted beyond `shift_threshold` from world origin,
it shifts all `physics_bodies` group nodes and the solar system visual root.

```gdscript
func _on_chunk_loaded(_coords: Vector2i) -> void:
    var player_pos := _get_player_position()
    if player_pos.length() < shift_threshold:
        return

    var offset := Vector3(player_pos.x, 0.0, player_pos.z)

    PerformanceMonitor.begin("SolarSystem.origin_shift")
    for body in get_tree().get_nodes_in_group("physics_bodies"):
        if is_instance_valid(body):
            body.global_position -= offset
    _solar_system_root.global_position -= offset
    _solar_system.update_world_origin(offset)
    PerformanceMonitor.end("SolarSystem.origin_shift")

    GameEventBus.origin_shifted.emit(offset)
```

`physics_bodies` group includes: all ships (player and AI), all asteroids.
It does **not** include planets, moons, stars, or stations (visual-only or static).

### 4.5 In-system warp (WarpDrive)

WarpDrive is a component attached to every ship. It supports two modes:

**PLOTTED:** Right-click a distant point → "Plot Warp Course" → charge builds →
press Y to engage → NavigationController autopilots to destination.

**MANUAL:** Hold Y to charge → ship boosts with boosted thrust and zero damping →
release Y to disengage → DECELERATING state brakes to a stop.

```
IDLE → CHARGING → READY (plotted only) → ACTIVE → DECELERATING → IDLE
```

Interrupt conditions (both modes): damage above threshold, approaching exclusion zone,
energy depletion. Weapons disabled during ACTIVE state.

During ACTIVE: `linear_damp = warp_damp_override` (near 0), `thruster_force` boosted
by `thrust_multiplier`. Cubic ease-out falloff as velocity approaches `max_warp_speed`.

---

## 5. Star Rendering — SDF Shader

`solar_star_sdf.gdshader` runs on a `QuadMesh` billboard. It produces a richer visual
than the galaxy map close-star shader with deeper plasma detail, solar flares, and
multi-layer corona — the player spends more time near the solar system star.

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never,
            blend_add, depth_test_disabled;

uniform vec3  core_color;
uniform vec3  mid_color;
uniform vec3  corona_color;
uniform float corona_intensity  = 1.2;
uniform float corona_falloff    = 2.0;
uniform float noise_scale       = 2.5;
uniform float flow_speed        = 0.05;
uniform float surface_brightness = 1.8;
uniform float limb_darkening    = 0.5;
uniform float star_radius       = 0.80;
uniform float flare_intensity   = 0.3;

// SDF sphere + multi-layer corona + solar flares + limb darkening + plasma
// See solar_star_sdf.gdshader for full implementation
```

Colors are set per `star_type` from a lookup in `Star.gd`:

| Star type | Core | Mid | Corona |
|---|---|---|---|
| yellow_dwarf | warm white | amber | orange-red |
| red_giant | orange | deep red | dark red |
| neutron | blue-white | blue | cool blue |

The quad size is `visual_radius * 2.2` — the extra 10% accommodates corona bleed
beyond the sphere edge without clipping.

`OmniLight3D` is retained unchanged for scene lighting on ships and asteroids.

---

## 6. JSON Data Format

### `data/solar_system_archetypes.json`

Defines generation parameter ranges per archetype. All distance and size values are
in game world units. All values are placeholders until playtesting.

```json
{
    "archetypes": {
        "barren": {
            "weight": 0.30,
            "planet_count": [1, 6],
            "binary_star_chance": 0.05,
            "belt_count": [0, 2]
        },
        "inhabited": { ... },
        "industrial": { ... },
        "frontier": { ... },
        "anomaly": { ... }
    },
    "generation": {
        "planet_count_max_absolute": 20,
        "moon_count_per_planet": [0, 10],
        "orbit_radius_first_planet": 4000.0,
        "orbit_radius_step_min": 2000.0,
        "orbit_radius_step_max": 6000.0,
        "orbit_speed_min": 0.002,
        "orbit_speed_max": 0.015
    },
    "visual": {
        "star_center_depth_single": 2000.0,
        "star_visual_radius_single": 3500.0,
        "star_exclusion_radius_single": 2800.0,
        "star_center_depth_binary": 1200.0,
        "star_visual_radius_binary": 2200.0,
        "star_exclusion_radius_binary": 1800.0,
        "binary_star_separation": 5000.0,
        "planet_center_depth_min": 600.0,
        "planet_center_depth_max": 1200.0,
        "planet_visual_radius_min": 300.0,
        "planet_visual_radius_max": 1800.0
    },
    "exclusion_zone": {
        "damage_per_second": 150.0,
        "damage_type": "heat"
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
    },
    "star_sdf": {
        "corona_intensity": 1.2,
        "corona_falloff": 2.0,
        "noise_scale": 2.5,
        "flow_speed": 0.05,
        "surface_brightness": 1.8,
        "limb_darkening": 0.5,
        "flare_intensity": 0.3
    }
}
```

### `content/systems/<id>/system.json` — Hand-authored override

Any system can be fully hand-authored. `SolarSystemGenerator` checks for this file
before running procedural logic. Format is identical to the generator output plus
an optional `spawn_zones` array:

```json
{
    "system_id": "sol_start",
    "archetype": "inhabited",
    "stars": [
        {
            "star_type": "yellow_dwarf",
            "position_offset": [0, 0, 0],
            "exclusion_radius": 2800.0,
            "damage_per_second": 150.0,
            "light_energy": 1.2,
            "light_range": 60000.0
        }
    ],
    "planets": [
        {
            "planet_type": "barren",
            "orbit_radius": 4000.0,
            "orbit_speed": 0.010,
            "orbit_angle": 0.0,
            "visual_radius": 400.0,
            "planet_depth": 500.0,
            "moons": [],
            "stations": []
        }
    ],
    "belts": [
        {
            "inner_radius": 10500.0,
            "outer_radius": 13000.0,
            "density_multiplier": 2.5,
            "asteroid_type_weights": { "small": 0.3, "medium": 0.5, "large": 0.2 }
        }
    ],
    "spawn_zones": [
        {
            "id": "outer_planet_patrol",
            "position": [14000, 0, 1500],
            "radius": 600,
            "ship_count": 3,
            "ship_class": "fighter_light",
            "variant": "axum_fighter_patrol",
            "ai_profile": "default",
            "faction": "pirate"
        }
    ]
}
```

`spawn_zones` is only present in hand-authored files. Procedural systems use
ChunkStreamer's `ai_spawn_points` group for AI placement.

---

## 7. GameEventBus Signals

These signals must exist in `core/GameEventBus.gd` before any solar system
implementation:

```gdscript
signal system_loaded(system_id: String)
signal system_unloaded(system_id: String)
signal origin_shifted(offset: Vector3)
signal exclusion_zone_entered(ship: Node, star_index: int)
signal exclusion_zone_exited(ship: Node, star_index: int)
signal warp_state_changed(ship: Node, old_state: String, new_state: String)
signal warp_interrupted(ship: Node, reason: String)
signal warp_destination_plotted(destination: Vector3)
```

---

## 8. Performance Instrumentation

```gdscript
PerformanceMonitor.begin("SolarSystem.generate")
var manifest := _generator.generate(system_id, galaxy_seed)
PerformanceMonitor.end("SolarSystem.generate")

PerformanceMonitor.begin("SolarSystem.orbit_update")
# planet orbit batch loop
PerformanceMonitor.end("SolarSystem.orbit_update")

PerformanceMonitor.begin("SolarSystem.origin_shift")
# physics body reposition loop
PerformanceMonitor.end("SolarSystem.origin_shift")

PerformanceMonitor.set_count("SolarSystem.planet_count", _planets.size())
PerformanceMonitor.set_count("SolarSystem.station_count", _total_station_count())
PerformanceMonitor.set_count("SolarSystem.belt_count", _belt_regions.size())
```

**Expected values:**
- `SolarSystem.orbit_update` — under 0.1ms at max system size (20 planets × 10 moons)
- `SolarSystem.origin_shift` — spikes occasionally, near-zero otherwise

---

## 9. Files

| File | Status | Purpose |
|---|---|---|
| `gameplay/world/SolarSystem.gd` | Active | Scene manager, manifest instantiation, belt query |
| `gameplay/world/SolarSystemGenerator.gd` | Active | Pure generation logic, returns Dictionary |
| `gameplay/world/Star.gd` | Active | SDF star visual, exclusion zone, OmniLight |
| `gameplay/world/Planet.gd` | Active | Orbital drift, moon_mode |
| `gameplay/world/Station.gd` | Active | Placement only — docking deferred |
| `gameplay/world/OriginShifter.gd` | Active | Floating origin management |
| `gameplay/world/WarpDrive.gd` | Not started | In-system warp state machine |
| `core/starfield/solar_star_sdf.gdshader` | Active | SDF sphere shader for solar star |
| `data/solar_system_archetypes.json` | Active | Generation parameters and visual tuning |
| `data/world_config.json` | Modified | `solar_system` block |
| `content/systems/sol_start/system.json` | Active | Hand-authored starting system |

---

## 10. Dependencies

| Dependency | Why |
|---|---|
| `GameEventBus.gd` | Solar system and warp signals required before implementation |
| `PerformanceMonitor.gd` | Required before SolarSystem enters scene tree |
| `ChunkStreamer` | Calls `get_belt_context_at()` — ChunkStreamer must exist first |
| `Ship.apply_damage()` | Exclusion zone calls this — Ship must exist first |
| `StarField` autoload | Provides `galaxy_seed` for deterministic generation |
| `GameOrchestrator.gd` | Calls `_load_system()` — orchestrates system transitions |

---

## 11. Assumptions

- Orbital speeds (`0.002–0.015 rad/s`) are placeholder — planets should visibly drift
  over a 5-minute session. Tune during playtesting.
- `planet_center_depth_min` is 600 (not 400 as in original spec) — bumped to prevent
  `visual_radius` from exceeding `planet_depth` and intersecting `Y = 0`.
- Generator enforces `visual_radius = min(visual_radius, planet_depth * 0.90)`.
- `star_sdf` color sets per star type are hardcoded in `Star.gd _colors_from_type()`.
  Adding new star types requires a code change. Deferred to content pass.
- `solar_star_sdf.gdshader` corona bleeds upward toward `Y = 0` naturally — the
  billboard faces the camera and the quad extends beyond the physical sphere edge.
  No additional geometry needed for the glow at play plane level.
- Moon orbital inclination is always 0 — moons orbit on the XZ plane like planets.
- Station placement within a planet's orbital radius uses a default offset. Full
  docking logic is deferred to the Station spec.
- `spawn_zones` in hand-authored systems are read by `GameOrchestrator`, not by
  `SolarSystem` itself. `SolarSystem` just returns them in the manifest.

---

## 12. Success Criteria

- [ ] Same `system_id` + `galaxy_seed` always produces identical layout (deterministic)
- [ ] Hand-authored `system.json` loads exactly as defined — no procedural modification
- [ ] Binary stars generate two exclusion zones with a navigable gap between them
- [ ] Planets visibly drift over a 5-minute session
- [ ] No planet intersects `Y = 0` — `visual_radius < planet_depth` always
- [ ] Star renders as smooth glowing disc from top-down camera view
- [ ] Star corona visible, no polygon faceting at any angle
- [ ] Solar flares animate at star edge
- [ ] `OmniLight3D` visibly colors nearby ships and asteroids
- [ ] Star exclusion zone deals `damage_per_second` heat damage inside boundary
- [ ] `exclusion_zone_entered` and `exclusion_zone_exited` emit correctly
- [ ] `get_belt_context_at()` returns `in_belt: true` inside belt radius
- [ ] ChunkStreamer generates denser asteroids inside belt regions
- [ ] Origin shift fires when player exceeds `shift_threshold` — no visible pop after
- [ ] `spawn_zones` in hand-authored systems spawn correct enemy ships on load
- [ ] All PerformanceMonitor metrics visible in F3 overlay
- [ ] `SolarSystem.orbit_update` under 0.1ms with maximum system size
- [ ] No hardcoded values in any `.gd` file — all tuning in JSON
- [ ] No `Vector2`, `Node2D`, or 2D physics nodes anywhere in this system
