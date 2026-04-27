# Star System Specification
*All Space — Galaxy-Scale Procedural Stars with LOD Rendering*

## Overview

Stars are first-class world objects — not decorative background sprites. Every star has a
world-space position, a data record, and a level-of-detail representation that scales from
a single GPU-drawn pixel at galactic zoom down to a lit mesh with dynamic lighting at close
range. The same star catalog powers the gameplay map, the galactic overview, and the
close-range visual — there is no separate skybox or background layer.

**Design Goals:**
- Stars feel like real places you are flying through, not painted backdrops
- Galactic zoom and sector zoom are the same scene at different camera distances
- Screen-space shader rendering for distant stars bypasses the depth buffer entirely —
  no Z-fighting, no clipping at extreme distances
- Ships can never enter a star — each star has an enforced exclusion zone
- All star properties (size, type, color temperature, exclusion radius) are driven by
  the procedural generator and stored in the world save; no hardcoded values
- The star catalog is loaded once at startup and always resident — stars are too
  large-scale and sparse for chunk streaming

---

## Architecture

```
StarRegistry (Node3D — autoload or child of world root)
    ├── Loaded once at startup from world_config.json seed
    ├── Holds all StarRecord data (always in memory)
    ├── Owns the MultiMeshInstance3D for galactic point rendering
    ├── Manages per-star LOD state based on camera distance
    └── Spawns / despawns StarMesh nodes as ships approach

StarRenderer (Viewport / full-screen shader — child of GameCamera)
    ├── Screen-space pass: projects distant star world positions to screen coords
    ├── Renders glow discs behind all geometry (no depth test)
    └── Receives visible star list from StarRegistry each frame

StarMesh (Node3D — spawned by StarRegistry at close range)
    ├── MeshInstance3D × N (layered billboard spheres for volumetric appearance)
    ├── OmniLight3D (color and intensity from StarRecord)
    └── ExclusionArea (Area3D — enforces the no-fly exclusion radius)

StarRegistry
    └── reads → data/world_config.json  (galaxy seed, star count, distribution params)
```

Stars are never chunk-streamed. `StarRegistry` is always loaded and owns all star data
for the lifetime of the game session.

---

## Star Tiers

| Tier | Y range | Gameplay role | LOD behavior |
|---|---|---|---|
| **Backdrop** | ±Y offset from plane | Visual landmark only | Point → glow shader; no mesh ever spawned |
| **Destination** | Y near 0 (within threshold) | Flyable destination: faction, economy, missions | Full LOD: point → glow → mesh + light |

The tier is determined at generation time from the star's Y position and stored in its
`StarRecord`. The threshold for "near the plane" is a tunable value in `world_config.json`.

---

## Core Properties / Data Model

### StarRecord

```gdscript
class StarRecord:
    var id: int                  # Unique index within the catalog
    var position: Vector3        # World-space position; Y = 0 for destination stars
    var tier: StringName         # &"backdrop" or &"destination"
    var star_type: StringName    # &"red_dwarf", &"yellow_dwarf", &"blue_giant", etc.
    var radius: float            # Visual radius in world units
    var exclusion_radius: float  # Hard no-fly boundary (always >= radius)
    var color: Color             # Derived from star_type at generation time
    var light_energy: float      # OmniLight3D intensity when mesh is active
    var lod_state: int           # 0=point, 1=glow, 2=mesh (runtime only)
    var mesh_node: Node3D        # null when not spawned (runtime only)

    # Destination stars only:
    var faction_id: StringName
    var economy_data: Dictionary
```

### StarRegistry

| Property | Type | Description |
|---|---|---|
| `_catalog` | `Array[StarRecord]` | All stars; always in memory |
| `_galaxy_seed` | `int` | Master seed from world_config.json |
| `_camera` | `Camera3D` | Reference to GameCamera for distance checks |
| `_multimesh` | `MultiMeshInstance3D` | Galactic-scale point rendering |
| `_screen_pass_stars` | `Array[StarRecord]` | Stars visible this frame; passed to shader |

---

## LOD Levels

### LOD 0 — Point (galactic and sector scale)

`MultiMeshInstance3D` renders all stars as transformed unit meshes (single quad or
sphere) in one draw call. Instance transforms encode world position; the material shader
colors each instance from the star's `color` packed into instance custom data.

At this distance the star is sub-pixel or a few pixels wide. The shader sizes it to a
minimum apparent size so it is always visible regardless of distance.

### LOD 1 — Screen-Space Glow (mid range)

A full-screen `SubViewport` shader receives the list of visible stars (world positions,
colors, apparent angular sizes) as a uniform array each frame. The shader:

1. Projects each star's world position to NDC using the camera's view-projection matrix
2. Draws a soft radial glow disc at that screen coordinate
3. Renders with no depth test — always behind scene geometry by compositing order

This pass replaces the MultiMesh instance for stars that have crossed the LOD 0 → 1
threshold. The transition is crossfaded over a configurable number of frames.

**Why this approach:** At mid-range distances, world-space geometry suffers from depth
buffer precision loss at extreme Z values. The screen-space pass bypasses the depth
buffer entirely — no Z-fighting, no clipping, no scale problems. The star's apparent
size is computed from real angular size math, so it looks physically correct.

### LOD 2 — Mesh + Light (close range)

When camera distance drops below `lod2_spawn_distance` (tunable), `StarRegistry`
spawns a `StarMesh` node:

```
StarMesh (Node3D)
    ├── Core sphere (MeshInstance3D — opaque base color)
    ├── Atmosphere layer 1 (MeshInstance3D — transparent, noise shader, slow rotation)
    ├── Atmosphere layer 2 (MeshInstance3D — transparent, different noise, faster rotation)
    ├── Corona billboard (MeshInstance3D — additive, camera-facing)
    ├── OmniLight3D (color = star.color, energy = star.light_energy, range from data)
    └── ExclusionArea (Area3D + SphereShape3D, radius = star.exclusion_radius)
```

The layered billboard approach produces a volumetric-looking plasma ball from any camera
angle without true GPU volumetrics. The noise shader on each atmosphere layer is driven
by a time uniform so the surface appears to roil.

Post-process bloom in Godot's `WorldEnvironment` amplifies the corona for free.

---

## Exclusion Zone

Every destination star has an `ExclusionArea` (`Area3D + SphereShape3D`) sized to
`exclusion_radius`. This is always larger than the visual `radius` — tunable gap
in `world_config.json`.

**Enforcement:** When a ship enters the `ExclusionArea`, `StarRegistry` emits
`GameEventBus.star_exclusion_entered(star_id, ship_id)`. The physics system and
navigation system both listen and apply a hard boundary force pushing the ship out.
Player input is not suppressed — the boundary force overrides it physically.

Backdrop stars do not spawn `ExclusionArea` nodes — they are never reachable.

---

## Key Algorithms

### Galaxy Generation

```gdscript
func generate_catalog(seed: int, config: Dictionary) -> Array[StarRecord]:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed
    var stars: Array[StarRecord] = []

    var total := config.star_count  # from world_config.json
    var galaxy_radius: float = config.galaxy_radius
    var plane_threshold: float = config.destination_y_threshold

    for i in total:
        var record := StarRecord.new()
        record.id = i

        # Distribute in a disc shape with spiral arm bias
        var angle := rng.randf() * TAU
        var dist := _sample_galaxy_radius(rng, galaxy_radius)
        var y_offset := rng.randf_range(-config.galaxy_thickness, config.galaxy_thickness)

        record.position = Vector3(cos(angle) * dist, y_offset, sin(angle) * dist)
        record.tier = &"destination" if abs(y_offset) <= plane_threshold else &"backdrop"
        record.star_type = _pick_star_type(rng, config.star_type_weights)
        _apply_type_stats(record, config.star_types[record.star_type], rng)

        stars.append(record)
    return stars
```

### LOD Update (called each physics frame)

```gdscript
func _update_lod(camera_pos: Vector3) -> void:
    PerformanceMonitor.begin("StarRegistry.lod_update")

    _screen_pass_stars.clear()

    for star in _catalog:
        var dist := camera_pos.distance_to(star.position)

        if dist > lod1_distance:
            # LOD 0: handled by MultiMesh, nothing per-star to do
            if star.lod_state != 0:
                _despawn_mesh(star)
                star.lod_state = 0

        elif dist > lod2_spawn_distance:
            # LOD 1: screen-space glow
            star.lod_state = 1
            _screen_pass_stars.append(star)
            if star.mesh_node:
                _despawn_mesh(star)

        else:
            # LOD 2: real mesh
            if star.tier == &"backdrop":
                continue  # backdrop stars never reach LOD 2
            star.lod_state = 2
            _screen_pass_stars.append(star)
            if not star.mesh_node:
                _spawn_mesh(star)

    _update_shader_uniforms(_screen_pass_stars)
    _update_multimesh()

    PerformanceMonitor.end("StarRegistry.lod_update")
    PerformanceMonitor.set_count("StarRegistry.active_meshes", _active_mesh_count)
    PerformanceMonitor.set_count("StarRegistry.screen_pass_count", _screen_pass_stars.size())
```

### LOD Crossfade

LOD transitions blend over `lod_crossfade_frames` frames. A per-star `blend_alpha`
float drives a `mix()` in the shader between the outgoing and incoming representation.
Prevents visible pops at transition boundaries.

---

## JSON Data Format

### world_config.json (additions for star system)

```json
{
  "galaxy_seed": 8675309,
  "star_count": 3000,
  "galaxy_radius": 500000.0,
  "galaxy_thickness": 8000.0,
  "destination_y_threshold": 1200.0,
  "exclusion_margin": 1.4,

  "star_type_weights": {
    "red_dwarf":    0.60,
    "yellow_dwarf": 0.25,
    "blue_giant":   0.08,
    "neutron_star": 0.05,
    "white_dwarf":  0.02
  },

  "star_types": {
    "red_dwarf": {
      "color": [1.0, 0.3, 0.1, 1.0],
      "radius_range": [800, 1400],
      "light_energy_range": [1.0, 2.0],
      "light_range_multiplier": 6.0
    },
    "yellow_dwarf": {
      "color": [1.0, 0.9, 0.5, 1.0],
      "radius_range": [1200, 2000],
      "light_energy_range": [2.0, 4.0],
      "light_range_multiplier": 8.0
    },
    "blue_giant": {
      "color": [0.5, 0.7, 1.0, 1.0],
      "radius_range": [3000, 6000],
      "light_energy_range": [6.0, 12.0],
      "light_range_multiplier": 14.0
    },
    "neutron_star": {
      "color": [0.8, 0.9, 1.0, 1.0],
      "radius_range": [200, 400],
      "light_energy_range": [8.0, 16.0],
      "light_range_multiplier": 10.0
    },
    "white_dwarf": {
      "color": [0.95, 0.97, 1.0, 1.0],
      "radius_range": [300, 600],
      "light_energy_range": [1.5, 3.0],
      "light_range_multiplier": 5.0
    }
  },

  "lod": {
    "lod1_distance": 80000.0,
    "lod2_spawn_distance": 8000.0,
    "lod_crossfade_frames": 30
  }
}
```

---

## Performance Instrumentation

New metric names — add to `PerformanceMonitor` canonical table:

| Metric | Name |
|---|---|
| Star LOD update | `StarRegistry.lod_update` |
| Stars in screen-space pass | `StarRegistry.screen_pass_count` |
| Active star meshes | `StarRegistry.active_meshes` |
| Star catalog generation | `StarRegistry.generate` |

Usage:
```gdscript
PerformanceMonitor.begin("StarRegistry.generate")
_catalog = generate_catalog(_galaxy_seed, _config)
PerformanceMonitor.end("StarRegistry.generate")
```

The LOD update runs every physics frame and is the hot path. If `screen_pass_count`
climbs above ~200, investigate culling by frustum before passing to the shader.

---

## Files

| Path | Description |
|---|---|
| `core/stars/StarRegistry.gd` | Autoload or world-root child; catalog owner, LOD manager |
| `core/stars/StarRecord.gd` | Data class for a single star |
| `core/stars/StarMesh.tscn` | Reusable scene: layered billboards + OmniLight3D + ExclusionArea |
| `core/stars/StarMesh.gd` | Script: receives StarRecord, configures shaders and light |
| `core/stars/star_surface.gdshader` | Noise-driven roiling plasma surface shader |
| `core/stars/star_corona.gdshader` | Additive corona billboard shader |
| `core/stars/star_screen_pass.gdshader` | Full-screen glow pass; projects world pos to screen |
| `data/world_config.json` | Extended with galaxy seed and star generation params |

---

## Dependencies

| Dependency | Reason |
|---|---|
| `PerformanceMonitor.gd` | Instrumentation; must be registered before StarRegistry init |
| `GameEventBus.gd` | Emits `star_exclusion_entered` signal |
| `GameCamera` (Camera3D) | StarRegistry needs camera reference for LOD distance checks |
| `data/world_config.json` | Galaxy seed and all generation parameters |

---

## Assumptions

- Galaxy scale numbers (`galaxy_radius`, `lod` distances) are first-pass estimates;
  requires playtesting to feel right
- `star_count: 3000` is the baseline; may increase if galactic density looks too sparse
- Backdrop stars with extreme Y offsets are not culled by frustum at MVP — revisit if
  `screen_pass_count` becomes a bottleneck
- Destination star economy and faction data format is deferred to the Economy spec
- Neutron stars and white dwarfs have gameplay effects (radiation, gravity well) deferred
  to a future spec; exclusion zone is the only gameplay behavior at MVP
- The spiral arm distribution algorithm (`_sample_galaxy_radius`) is an implementation
  detail deferred to the implementing agent
- LOD crossfade is frame-count based at MVP; distance-rate based crossfade deferred

---

## Success Criteria

- [ ] `StarRegistry` generates a deterministic catalog from the same seed every run
- [ ] Changing `galaxy_seed` in `world_config.json` produces a completely different galaxy
- [ ] At galactic zoom, all stars render in a single `MultiMeshInstance3D` draw call
- [ ] Distant stars render via screen-space shader with no Z-fighting or clipping artifacts
- [ ] LOD transitions crossfade — no visible pop between LOD levels
- [ ] A close-range star renders as a layered volumetric mesh with roiling surface
- [ ] `OmniLight3D` from a close star visibly colors nearby ships and asteroids
- [ ] A ship cannot enter any destination star — exclusion boundary pushes it out
- [ ] Backdrop stars never spawn a mesh or exclusion zone regardless of camera distance
- [ ] `star_exclusion_entered` fires on `GameEventBus` when a ship breaches the boundary
- [ ] All four `StarRegistry.*` metrics appear in the PerformanceMonitor overlay
- [ ] `StarRegistry.lod_update` completes in under 1ms with 3000 stars
