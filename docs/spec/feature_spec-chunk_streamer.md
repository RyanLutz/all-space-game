# Chunk Streamer System Specification
*All Space Combat MVP — World Streaming, Asteroids, and Environmental Content*

## Overview

A lightweight streaming system that loads and unloads rectangular map chunks around
the player as they fly. Each chunk is a `Node3D` container populated with procedurally
generated content — asteroid fields and AI spawn point markers — seeded deterministically
from the chunk's grid coordinates. The player sees a continuous, seamless space with no
loading screens and no visible pops.

**Design Goals:**
- Infinite-feeling map with bounded memory — only the player's local neighborhood is
  ever in the scene tree
- Procedural but deterministic — the same chunk always produces the same asteroid
  layout, so the world feels consistent on revisits
- Decoupled from gameplay systems — chunks publish their existence via `GameEventBus`;
  the AI spawner and other consumers react to those signals
- All tunable values (chunk size, load radius, asteroid density, HP tiers) in
  `data/world_config.json` — no hardcoded numbers in code

---

## Architecture

```
ChunkStreamer (Node3D — child of the world root, NOT an autoload)
    ├── Tracks player position each physics frame
    ├── Computes the square neighborhood of chunks that should be loaded
    ├── Loads chunks that just entered the neighborhood
    └── Unloads chunks that just left

Chunk (Node3D — created and freed at runtime)
    ├── Asteroid × N   (RigidBody3D — Jolt handles tumbling and collision)
    └── SpawnPoint × M (Node3D markers — AI spawner reads on chunk_loaded signal)

Asteroid (RigidBody3D)
    ├── MeshInstance3D  (placeholder geometry; replaced by art pass)
    ├── CollisionShape3D (SphereShape3D or ConvexPolygonShape3D)
    └── Has apply_damage() — can be destroyed, spawns Debris fragments

Debris (Node3D — lightweight, no physics body)
    ├── MeshInstance3D  (small fragment visual)
    └── Lifetime timer — fades alpha, then queue_frees
```

`ChunkStreamer` is a scene node because it must be the parent of the `Node3D` chunk
containers it creates at runtime. It is **not** an autoload.

Chunk content is generated at load time from a deterministic RNG seeded by the chunk's
`Vector2i` grid coordinate. No per-chunk asset files are needed — adding content is a
JSON tuning exercise.

---

## Core Properties / Data Model

### ChunkStreamer

| Property | Type | Description |
|---|---|---|
| `chunk_size` | `float` | World-space side length of one square chunk (XZ plane) |
| `load_radius` | `int` | Half-width of the loaded square: radius 2 = 5×5 = 25 chunks |
| `_loaded_chunks` | `Dictionary[Vector2i, Node3D]` | Grid coord → chunk root node |
| `_follow_target` | `Node3D` | Node whose position drives load/unload (player ship) |
| `_last_center_chunk` | `Vector2i` | Chunk the player was in last frame — skip if unchanged |

### Chunk Node

Each chunk is a `Node3D` named `"Chunk_%d_%d" % [coord.x, coord.y]`, positioned at the
chunk's world-space XZ origin with `position.y = 0`. All children are created
procedurally and freed with the chunk node.

### Asteroid

Extends `RigidBody3D`. Jolt handles collision response and ambient tumbling. Asteroids
are not ships — they do not need manual velocity control. Jolt Y-axis lock
(`axis_lock_linear_y = true`, `axis_lock_angular_x = true`, `axis_lock_angular_z = true`)
keeps them on the XZ play plane.

| Property | Type | Description |
|---|---|---|
| `hull_hp` | `float` | Current HP |
| `hull_max` | `float` | Max HP — set from `world_config.json` by size tier |
| `size_tier` | `String` | `"small"`, `"medium"`, or `"large"` |
| `_debris_count_min` | `int` | Minimum debris fragments on destruction |
| `_debris_count_max` | `int` | Maximum debris fragments on destruction |

**apply_damage signature** — identical to `Ship.apply_damage` so the projectile hit
pipeline can call either without branching:

```gdscript
func apply_damage(amount: float, damage_type: String = "",
                  hit_pos: Vector3 = Vector3.ZERO,
                  component_ratio: float = 0.0) -> void:
    hull_hp = maxf(0.0, hull_hp - amount)
    if hull_hp <= 0.0:
        _destroy()
```

### Debris

A plain `Node3D`. Does **not** extend `RigidBody3D` — it integrates its own velocity
manually and exists only for visual effect. No collision, no physics body.

| Property | Type | Description |
|---|---|---|
| `velocity` | `Vector3` | Initial impulse (Y component always 0) |
| `lifetime` | `float` | Seconds until `queue_free()` |
| `_elapsed` | `float` | Time accumulator for fade |

```gdscript
# Debris.gd — _process
func _process(delta: float) -> void:
    position += velocity * delta
    _elapsed += delta
    var t := _elapsed / lifetime
    # Node3D has no modulate property — fade by setting alpha on the mesh material.
    # Debris.tscn uses a StandardMaterial3D with transparency enabled on its MeshInstance3D.
    _mesh.get_active_material(0).albedo_color.a = 1.0 - t
    if _elapsed >= lifetime:
        queue_free()
```

`_mesh` is an `@onready var _mesh: MeshInstance3D` pointing to the child mesh node.
The material must have `transparency` set to `TRANSPARENCY_ALPHA` (or `ALPHA_SCISSOR`)
in `Debris.tscn` — opacity only works if the material's transparency mode supports it.

### SpawnPoint Marker

A plain `Node3D` with no script, added to each chunk at generation time. The AI
spawner listens to `chunk_loaded` on `GameEventBus` and queries
`get_children_of_class("SpawnPoint")` (or a group) to find marker positions. The
ChunkStreamer does not know about AI — it only places the markers.

---

## Key Algorithms

### Chunk Coordinate ↔ World Position

All world positions are `Vector3` with Y = 0. Chunk coordinates are `Vector2i`
(grid indices only — the one permitted use of `Vector2i` in this project).

```gdscript
func _world_to_chunk(world_pos: Vector3) -> Vector2i:
    return Vector2i(
        floori(world_pos.x / chunk_size),
        floori(world_pos.z / chunk_size)   # XZ plane — use Z, not Y
    )

func _chunk_to_world_origin(coord: Vector2i) -> Vector3:
    return Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)
```

Note: `coord.y` maps to world-space **Z**, not world-space Y. The chunk grid is a 2D
index into the XZ plane.

### Load / Unload Loop

Run in `_physics_process`. Early-exit if the player has not changed chunks since the
last frame — avoids rebuilding the neighborhood set 60 times per second while the
player is stationary or moving within a chunk.

```gdscript
func _physics_process(_delta: float) -> void:
    if not is_instance_valid(_follow_target):
        return

    var current_chunk := _world_to_chunk(_follow_target.global_position)
    if current_chunk == _last_center_chunk:
        return
    _last_center_chunk = current_chunk

    # Build the desired neighborhood
    var desired: Dictionary = {}
    for dx in range(-load_radius, load_radius + 1):
        for dy in range(-load_radius, load_radius + 1):
            var coord := current_chunk + Vector2i(dx, dy)
            desired[coord] = true

    # Load newly in-range chunks
    PerformanceMonitor.begin("ChunkStreamer.load")
    for coord in desired:
        if not _loaded_chunks.has(coord):
            _load_chunk(coord)
    PerformanceMonitor.end("ChunkStreamer.load")

    # Unload out-of-range chunks
    PerformanceMonitor.begin("ChunkStreamer.unload")
    var to_unload: Array[Vector2i] = []
    for coord in _loaded_chunks:
        if not desired.has(coord):
            to_unload.append(coord)
    for coord in to_unload:
        _unload_chunk(coord)
    PerformanceMonitor.end("ChunkStreamer.unload")

    PerformanceMonitor.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())
```

### Chunk Generation (Deterministic)

The RNG is seeded from the chunk coordinate so every visit to the same coordinate
produces the same content. The seed is computed from the coordinate's hash — a
lightweight, reproducible integer per grid cell.

```gdscript
func _load_chunk(coord: Vector2i) -> void:
    var origin := _chunk_to_world_origin(coord)

    var chunk_node := Node3D.new()
    chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
    chunk_node.global_position = origin
    add_child(chunk_node)

    var rng := RandomNumberGenerator.new()
    rng.seed = hash(coord)   # deterministic — same coord = same seed every time

    _populate_asteroids(chunk_node, rng)
    _populate_spawn_points(chunk_node, rng)

    _loaded_chunks[coord] = chunk_node
    GameEventBus.emit_signal("chunk_loaded", coord)

func _unload_chunk(coord: Vector2i) -> void:
    var chunk_node: Node3D = _loaded_chunks.get(coord)
    if is_instance_valid(chunk_node):
        chunk_node.queue_free()
    _loaded_chunks.erase(coord)
    GameEventBus.emit_signal("chunk_unloaded", coord)
```

### Asteroid Field Population

Asteroids are placed in clusters (fields) within each chunk. Empty chunks are valid
and intentional — open space to fly through breaks up the density and feels natural.

Positions are local to the chunk node (XZ only; Y = 0 in local space, which maps to
Y = 0 world-space since the chunk node itself sits at Y = 0).

```gdscript
func _populate_asteroids(chunk_node: Node3D, rng: RandomNumberGenerator) -> void:
    var field_count: int = rng.randi_range(0, _config.max_fields_per_chunk)

    for _f in range(field_count):
        # Field center — random within the chunk's XZ footprint
        var fc_x := rng.randf_range(0.0, chunk_size)
        var fc_z := rng.randf_range(0.0, chunk_size)

        var field_radius: float = rng.randf_range(
            _config.field_radius_min, _config.field_radius_max)

        var count: int = rng.randi_range(
            _config.asteroids_per_field_min, _config.asteroids_per_field_max)

        for _a in range(count):
            var angle := rng.randf() * TAU
            var dist  := rng.randf() * field_radius
            var local_pos := Vector3(
                fc_x + cos(angle) * dist,
                0.0,
                fc_z + sin(angle) * dist
            )
            var tier := _pick_size_tier(rng)
            _spawn_asteroid(chunk_node, local_pos, tier)

func _pick_size_tier(rng: RandomNumberGenerator) -> String:
    var r := rng.randf()
    var weights: Dictionary = _config.size_weights
    if r < weights["small"]:
        return "small"
    elif r < weights["small"] + weights["medium"]:
        return "medium"
    return "large"
```

### AI Spawn Point Population

Spawn points are placed at random positions within the chunk, far enough from the
chunk's center to avoid spawning AI ships directly on top of the player when they
first enter a region. The marker node is added to the `"ai_spawn_points"` group so
the AI spawner can find it without ChunkStreamer knowing about AI.

```gdscript
func _populate_spawn_points(chunk_node: Node3D, rng: RandomNumberGenerator) -> void:
    var count: int = rng.randi_range(0, _config.max_spawn_points_per_chunk)

    for _i in range(count):
        var angle := rng.randf() * TAU
        var dist  := rng.randf_range(_config.spawn_min_dist_from_center, chunk_size * 0.5)
        var local_pos := Vector3(
            chunk_size * 0.5 + cos(angle) * dist,
            0.0,
            chunk_size * 0.5 + sin(angle) * dist
        )
        var marker := Node3D.new()
        marker.name = "SpawnPoint_%d" % _i
        marker.position = local_pos
        marker.add_to_group("ai_spawn_points")
        chunk_node.add_child(marker)
```

### Asteroid Destruction and Debris Spawning

When an asteroid's HP reaches zero, it emits an explosion event, spawns debris
fragments as siblings (added to the chunk node, not the asteroid), and frees itself.
Debris velocity inherits a fraction of the asteroid's linear velocity at death time
plus a random outward spread. Destruction RNG is intentionally non-deterministic —
two identical asteroids blown up at different times should look different.

```gdscript
# Asteroid.gd
func _destroy() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = Time.get_ticks_usec()  # non-deterministic at destruction time

    var debris_count := rng.randi_range(
        _config.debris_count_min, _config.debris_count_max)

    for _i in range(debris_count):
        var debris: Node3D = _DEBRIS_SCENE.instantiate()
        var angle  := rng.randf() * TAU
        var speed  := rng.randf_range(_config.debris_speed_min, _config.debris_speed_max)
        # Spread outward from impact; also carry some of the asteroid's own velocity
        debris.velocity = Vector3(cos(angle), 0.0, sin(angle)) * speed \
                        + linear_velocity * 0.3
        debris.velocity.y = 0.0           # enforce XZ plane
        debris.lifetime   = _config.debris_lifetime
        debris.global_position = global_position
        get_parent().add_child(debris)    # sibling of asteroid, under chunk node

    GameEventBus.emit_signal("explosion_triggered",
        global_position, _explosion_radius_by_tier(), 0.6)

    queue_free()
```

### Asteroid Jolt Configuration

Asteroids use `RigidBody3D` with Jolt axis locks to stay on the XZ plane. They get a
small random angular impulse at spawn for visual tumbling, but they never leave Y = 0.

```gdscript
# Asteroid.gd — _ready()
func _ready() -> void:
    # Lock Y translation and XZ rotation so Jolt can't push them off the play plane
    axis_lock_linear_y  = true
    axis_lock_angular_x = true
    axis_lock_angular_z = true

    # Random slow spin (Y axis only — yaw)
    angular_velocity = Vector3(0.0, randf_range(-0.3, 0.3), 0.0)
```

---

## JSON Data Format

### `data/world_config.json`

```json
{
  "_comment": "ChunkStreamer and world environment tuning for All Space combat MVP.",

  "chunk_size": 2000.0,
  "load_radius": 2,

  "asteroid_fields": {
    "max_fields_per_chunk": 3,
    "field_radius_min": 80.0,
    "field_radius_max": 300.0,
    "asteroids_per_field_min": 3,
    "asteroids_per_field_max": 12,
    "size_weights": {
      "small":  0.55,
      "medium": 0.35,
      "large":  0.10
    }
  },

  "asteroid_hp": {
    "small":  40.0,
    "medium": 100.0,
    "large":  250.0
  },

  "asteroid_scale": {
    "small":  0.6,
    "medium": 1.0,
    "large":  1.8
  },

  "ai_spawn_points": {
    "max_per_chunk": 2,
    "min_distance_from_center": 400.0
  },

  "debris": {
    "count_min": 2,
    "count_max": 5,
    "lifetime": 3.5,
    "speed_min": 40.0,
    "speed_max": 160.0
  }
}
```

All of these values are placeholder starting points. Tune during the first playtest session.

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract:

```gdscript
# ChunkStreamer.gd — wrap load and unload loops
PerformanceMonitor.begin("ChunkStreamer.load")
# ... load loop ...
PerformanceMonitor.end("ChunkStreamer.load")

PerformanceMonitor.begin("ChunkStreamer.unload")
# ... unload loop ...
PerformanceMonitor.end("ChunkStreamer.unload")

PerformanceMonitor.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())
```

Register custom monitors in `_ready()`:

```gdscript
func _ready() -> void:
    Performance.add_custom_monitor("AllSpace/chunk_load_ms",
        func(): return PerformanceMonitor.get_avg_ms("ChunkStreamer.load"))
    Performance.add_custom_monitor("AllSpace/chunk_unload_ms",
        func(): return PerformanceMonitor.get_avg_ms("ChunkStreamer.unload"))
    Performance.add_custom_monitor("AllSpace/loaded_chunks",
        func(): return PerformanceMonitor.get_count("ChunkStreamer.loaded_chunks"))
```

The load/unload loops only fire when the player crosses a chunk boundary — they should
be near-zero cost on most frames. The metric still captures the occasional spike when
many chunks load at once (e.g. on game start).

---

## Files

```
/gameplay/world/
    ChunkStreamer.gd      ← streaming logic, chunk generation
    Asteroid.gd           ← RigidBody3D, apply_damage, destruction
    Debris.gd             ← Node3D, manual velocity integration, fade/lifetime
    Debris.tscn           ← lightweight scene: Node3D + MeshInstance3D (no script required)
/data/
    world_config.json
```

`ChunkStreamer.gd` is attached to a `Node3D` placed directly in the main scene (or
`TestScene.tscn`). It is a sibling of the game world root, not an autoload, because
it parents the chunk nodes it creates.

---

## Dependencies

- `PerformanceMonitor` — registered before `ChunkStreamer` enters the scene tree
- `GameEventBus` — `chunk_loaded`, `chunk_unloaded`, and `explosion_triggered`
  signals must be defined before any chunk loads
- Player ship must be in the `"player"` group — `ChunkStreamer` finds its follow
  target via `get_tree().get_first_node_in_group("player")` in `_ready()`
- `PlayerState` — `ChunkStreamer` listens to `player_ship_changed` on `GameEventBus`
  and retargets its follow reference if the player respawns in a different ship
- `Debris.tscn` — pre-built scene loaded via `preload()` in `Asteroid.gd`
- No dependency on `Ship.gd` or `AIController.gd` — the AI spawner reacts to
  `chunk_loaded` independently; `ChunkStreamer` does not know about either

---

## Assumptions

- `chunk_size` of 2000 units — a 5×5 load grid covers a 10,000 × 10,000 unit arena.
  Reduce `load_radius` to 1 (9 chunks) if chunk population proves expensive; increase
  if the player can see bare space at the grid edge.
- `max_fields_per_chunk` of 3 and field radii of 80–300 are conservative starting
  values. Increase asteroid density after the physics/performance baseline is established.
- Asteroid visual meshes are placeholder `SphereMesh` with per-tier scale applied.
  Art replacement requires only swapping the `MeshInstance3D` resource — no code changes.
- Debris does not collide with projectiles or ships — it is purely visual.
- Spawn point `min_distance_from_center` of 400 units is a guess; tune so AI ships
  don't appear in the player's immediate field of view when a chunk loads nearby.
- Asteroid HP values are placeholder; tune after the weapon damage system is established.
- Chunk persistence (remembering asteroid damage between visits) is explicitly deferred
  — revisited chunks regenerate fresh. Implement post-MVP if save-state matters.
- The `hash(coord)` function used as RNG seed is assumed stable across Godot versions.
  If reproducibility breaks, replace with a manual hash: `coord.x * 73856093 ^ coord.y * 19349663`.

---

## Future Extension Points

| Feature | How It Fits |
|---|---|
| **Named chunks** | In `_load_chunk`, check for a `data/chunks/<x>_<y>/` folder before falling back to procedural generation. Curated content overrides for story beats or unique locations. |
| **Station placement** | Add a `station` entry to world config; spawn a station node when `chunk_loaded` fires, as a sibling system — ChunkStreamer places a marker, Station system reacts. |
| **Resource nodes / loot** | Asteroid destruction already emits `explosion_triggered`. A loot system listens and spawns collectibles at the position. |
| **Nebula zones** | Chunk-level flag in generation data. A drag-multiplier system listens to `chunk_loaded` and applies area effects. |
| **Patrol regions** | `Area3D` nodes added to chunks define wander bounds for AI ships. AIController reads patrol region from the chunk it was spawned in. |
| **Chunk persistence** | A `ChunkState` dictionary keyed by `Vector2i` stores asteroid damage and destroyed states. Loaded chunks restore state instead of regenerating fresh. |
| **Asteroid mining** | `apply_damage` already reduces HP and destroys; a mining tool fires low-damage bursts and the loot system triggers on destruction with a "mining" source tag. |

---

## Success Criteria

- [ ] Flying in any direction continuously reveals a populated neighborhood of chunks —
  no "void at the edges"
- [ ] Crossing a chunk boundary loads new edge chunks and unloads distant ones within
  one physics frame — no frame drop during streaming
- [ ] The same chunk coordinate always produces the same asteroid layout on repeated
  visits (deterministic seed)
- [ ] Empty chunks exist — not every area of space is filled with rocks
- [ ] Asteroids receive `apply_damage()` calls from the projectile system using the
  same signature as `Ship.apply_damage` — no special-casing in the hit pipeline
- [ ] Destroyed asteroid spawns 2–5 `Debris` nodes that drift outward and fade over
  their lifetime, then queue_free
- [ ] Asteroids stay at Y = 0 — Jolt axis locks prevent them from being knocked off
  the play plane by collision
- [ ] `chunk_loaded` and `chunk_unloaded` signals are emitted with the correct
  `Vector2i` coordinates
- [ ] AI spawn point markers appear in chunks and are findable via the
  `"ai_spawn_points"` group
- [ ] All tunable values (chunk size, load radius, asteroid density, HP, debris
  lifetime) are in `data/world_config.json` — no hardcoded numbers in `.gd` files
- [ ] `PerformanceMonitor` overlay (F3) shows `ChunkStreamer.load`,
  `ChunkStreamer.unload`, and `ChunkStreamer.loaded_chunks` metrics
- [ ] 25 loaded chunks (5×5 grid) with asteroid fields at 60fps alongside active combat
  load (projectiles, AI ships)
- [ ] No `Vector2`, `Node2D`, or 2D physics nodes appear anywhere in this system
