# Chunk Streamer System Specification
*All Space Combat MVP — World Streaming, Asteroids, and Environmental Content*

## Overview

A lightweight streaming system that loads and unloads rectangular map chunks around
the player as they fly. Each chunk is a `Node2D` container populated with procedurally
generated content (asteroid fields, AI spawn points, points of interest) seeded
deterministically from the chunk's grid coordinates. The player sees a continuous,
seamless space — no loading screens, no visible pops.

**Design Goals:**
- Infinite-feeling map with bounded memory footprint — only the player's local neighborhood
  is ever in the scene tree
- Procedural but deterministic — the same chunk always has the same rocks and spawns,
  so the world feels consistent if the player revisits an area
- Decoupled from gameplay systems — chunks publish their existence via `GameEventBus`
  and gameplay systems (AI spawners, physics) react to those signals
- All tunable values (chunk size, load radius, asteroid density, HP) live in
  `data/world_config.json` — no hardcoded numbers in code

---

## Architecture

```
ChunkStreamer (Node — autoloaded or child of world root)
    ├── Tracks player position each physics frame
    ├── Computes the set of chunks that should be loaded (square neighborhood)
    ├── Loads chunks that just entered the neighborhood
    └── Unloads chunks that just left the neighborhood

Chunk (Node2D — created and freed at runtime)
    ├── Asteroid × N  (CharacterBody2D via SpaceBody)
    └── SpawnPoint × M  (Node2D markers; AI system reads on chunk_loaded)

Asteroid (CharacterBody2D — extends SpaceBody)
    ├── Polygon2D (visual placeholder)
    ├── CollisionShape2D (polygon or circle)
    └── Has apply_damage() — can be destroyed, spawns Debris

Debris (Node2D — lightweight, no physics after initial velocity)
    ├── Polygon2D (small fragment visual)
    └── Lifetime timer — fades then queue_frees itself
```

`ChunkStreamer` does not track a scene-file-per-chunk. Chunk content is generated at
load time from a deterministic RNG seeded by the chunk coordinate. This keeps the project
free of chunk asset management and makes content tuning a pure JSON exercise.

---

## Core Properties / Data Model

### ChunkStreamer

| Property | Type | Description |
|---|---|---|
| `chunk_size` | `float` | World-space side length of one chunk square (e.g. 2000.0) |
| `load_radius` | `int` | Chunks loaded in a `(2*load_radius+1)²` grid (e.g. 2 → 5×5 = 25 chunks) |
| `_loaded_chunks` | `Dictionary[Vector2i, Node2D]` | Map from chunk coord → chunk root node |
| `_follow_target` | `Node2D` | The node whose position drives load/unload (the player ship) |
| `_last_center_chunk` | `Vector2i` | Chunk the player was in last frame — used to skip redundant recalculations |

### Chunk Node

Each chunk is a `Node2D` named `"Chunk_%d_%d" % [coord.x, coord.y]`. Its children
are created procedurally and are freed with it.

### Asteroid

Extends `SpaceBody` (which extends `CharacterBody2D`). Asteroids are stationary — they
override `apply_thrust_forces` to do nothing, so they sit still but still receive
proper collision registration on physics layer 1.

| Property | Type | Description |
|---|---|---|
| `hull_hp` | `float` | Current HP; when it reaches 0 the asteroid is destroyed |
| `hull_max` | `float` | Max HP — loaded from `world_config.json` by size tier |
| `size_tier` | `String` | `"small"`, `"medium"`, or `"large"` — drives visual scale and HP |
| `_debris_count` | `int` | How many `Debris` nodes to spawn on destruction |

### Debris

A plain `Node2D`. Does not extend `SpaceBody` — debris is purely visual, not a physics
body. It carries an initial velocity that it integrates manually and a lifetime timer.

| Property | Type | Description |
|---|---|---|
| `velocity` | `Vector2` | Initial impulse direction and speed |
| `lifetime` | `float` | Seconds until `queue_free()` (e.g. 3.0) |
| `_alpha` | `float` | Fade factor — drives `modulate.a` over the lifetime |

---

## Key Algorithms

### Chunk Coordinate Calculation

```gdscript
func _world_to_chunk(world_pos: Vector2) -> Vector2i:
    return Vector2i(
        floori(world_pos.x / chunk_size),
        floori(world_pos.y / chunk_size)
    )

func _chunk_to_world_origin(coord: Vector2i) -> Vector2:
    return Vector2(coord.x * chunk_size, coord.y * chunk_size)
```

### Load / Unload Loop

Run in `_physics_process`. Early-exit if the player hasn't changed chunk to avoid
rebuilding the neighborhood set every frame.

```gdscript
func _physics_process(_delta: float) -> void:
    if not is_instance_valid(_follow_target):
        return

    var current_chunk := _world_to_chunk(_follow_target.global_position)
    if current_chunk == _last_center_chunk:
        return
    _last_center_chunk = current_chunk

    var desired: Dictionary = {}
    for dx in range(-load_radius, load_radius + 1):
        for dy in range(-load_radius, load_radius + 1):
            var coord := current_chunk + Vector2i(dx, dy)
            desired[coord] = true

    # Load newly in-range chunks
    _perf.begin("ChunkStreamer.load")
    for coord in desired:
        if not _loaded_chunks.has(coord):
            _load_chunk(coord)
    _perf.end("ChunkStreamer.load")

    # Unload out-of-range chunks
    _perf.begin("ChunkStreamer.unload")
    var to_unload: Array[Vector2i] = []
    for coord in _loaded_chunks:
        if not desired.has(coord):
            to_unload.append(coord)
    for coord in to_unload:
        _unload_chunk(coord)
    _perf.end("ChunkStreamer.unload")

    _perf.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())
```

### Chunk Generation (Deterministic Procedural)

```gdscript
func _load_chunk(coord: Vector2i) -> void:
    var chunk_node := Node2D.new()
    chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
    chunk_node.global_position = _chunk_to_world_origin(coord)
    add_child(chunk_node)

    # Seed the RNG with the chunk coordinate so the same chunk is identical
    # every time it is loaded.
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(coord)

    _populate_asteroids(chunk_node, coord, rng)
    _populate_spawn_points(chunk_node, coord, rng)

    _loaded_chunks[coord] = chunk_node
    _event_bus.emit_signal("chunk_loaded", coord)
```

```gdscript
func _unload_chunk(coord: Vector2i) -> void:
    var chunk_node: Node2D = _loaded_chunks.get(coord)
    if chunk_node != null:
        chunk_node.queue_free()
    _loaded_chunks.erase(coord)
    _event_bus.emit_signal("chunk_unloaded", coord)
```

### Asteroid Population

```gdscript
func _populate_asteroids(chunk_node: Node2D, coord: Vector2i, rng: RandomNumberGenerator) -> void:
    # Field count: 0 to max_asteroid_fields_per_chunk (from JSON).
    # Empty chunks are valid — leave open space to fly through.
    var field_count: int = rng.randi_range(0, _config.max_asteroid_fields_per_chunk)
    for _f in range(field_count):
        var field_center := Vector2(
            rng.randf_range(0.0, chunk_size),
            rng.randf_range(0.0, chunk_size)
        )
        var field_radius: float = rng.randf_range(
            _config.asteroid_field_radius_min,
            _config.asteroid_field_radius_max
        )
        var count: int = rng.randi_range(
            _config.asteroids_per_field_min,
            _config.asteroids_per_field_max
        )
        for _a in range(count):
            var angle := rng.randf() * TAU
            var dist := rng.randf() * field_radius
            var local_pos := field_center + Vector2(cos(angle), sin(angle)) * dist
            var tier: String = _pick_size_tier(rng)
            _spawn_asteroid(chunk_node, local_pos, tier)
```

### Asteroid Destruction & Debris

When an asteroid's HP reaches zero, it:
1. Spawns 2–5 `Debris` nodes at its position with random velocity vectors
2. Emits `explosion_triggered` on the bus for VFX/audio
3. Calls `queue_free()` on itself

```gdscript
# Asteroid.gd
func apply_damage(amount: float, _damage_type: String = "", _hit_pos: Vector2 = Vector2.ZERO,
        _comp_ratio: float = 0.0) -> void:
    hull_hp = maxf(0.0, hull_hp - amount)
    if hull_hp <= 0.0:
        _destroy()

func _destroy() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = Time.get_ticks_usec()  # intentionally non-deterministic at destruction time
    for i in range(rng.randi_range(2, 5)):
        var debris := _DEBRIS_SCENE.instantiate()
        var speed := rng.randf_range(40.0, 160.0)
        var angle := rng.randf() * TAU
        debris.velocity = Vector2(cos(angle), sin(angle)) * speed
        debris.global_position = global_position
        get_parent().add_child(debris)
    _event_bus.emit_signal("explosion_triggered", global_position, _get_explosion_radius(), 0.6)
    queue_free()
```

---

## JSON Data Format

### `data/world_config.json`

```json
{
  "_comment": "World streaming and environment tuning for All Space combat MVP.",
  "chunk_size": 2000.0,
  "load_radius": 2,

  "asteroid_fields": {
    "max_fields_per_chunk": 3,
    "field_radius_min": 80.0,
    "field_radius_max": 300.0,
    "asteroids_per_field_min": 3,
    "asteroids_per_field_max": 12,
    "size_weights": {
      "small": 0.55,
      "medium": 0.35,
      "large": 0.10
    }
  },

  "asteroid_hp": {
    "small": 40.0,
    "medium": 100.0,
    "large": 250.0
  },

  "asteroid_scale": {
    "small": 0.6,
    "medium": 1.0,
    "large": 1.8
  },

  "ai_spawn_points": {
    "max_per_chunk": 2,
    "min_distance_from_center": 200.0
  },

  "debris": {
    "lifetime": 3.5,
    "speed_min": 40.0,
    "speed_max": 160.0
  }
}
```

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract (canonical metric names from `CLAUDE.md`):

```gdscript
# ChunkStreamer.gd
_perf.begin("ChunkStreamer.load")    # wrap the load loop
_perf.end("ChunkStreamer.load")

_perf.begin("ChunkStreamer.unload")  # wrap the unload loop
_perf.end("ChunkStreamer.unload")

_perf.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())
```

Register custom monitors in `_ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/chunk_load_ms",
    func(): return _perf.get_avg_ms("ChunkStreamer.load"))
Performance.add_custom_monitor("AllSpace/chunk_unload_ms",
    func(): return _perf.get_avg_ms("ChunkStreamer.unload"))
Performance.add_custom_monitor("AllSpace/loaded_chunks",
    func(): return _perf.get_count("ChunkStreamer.loaded_chunks"))
```

---

## Files

```
/gameplay/world/
    ChunkStreamer.gd
    Asteroid.gd
    Debris.gd
    Debris.tscn           ← lightweight, no script, set up in scene
/data/
    world_config.json
```

`ChunkStreamer` must be added to the main scene (or `AITestScene`) as a child node.
It is **not** an autoload — it is a scene node because it needs to be a parent of
the chunk `Node2D` containers it creates.

---

## Dependencies

- `SpaceBody.gd` — `Asteroid` extends it
- `PerformanceMonitor` — registered before ChunkStreamer enters the scene tree
- `GameEventBus` — `chunk_loaded`, `chunk_unloaded`, `explosion_triggered` signals
  are already defined
- Player ship must be in the `"player"` group — ChunkStreamer finds its follow target
  via `get_tree().get_first_node_in_group("player")`
- `PlayerState` — ChunkStreamer listens to `player_ship_changed` to retarget if the
  player respawns in a different ship

---

## Assumptions

- Chunk size of 2000 px means a 5×5 load grid covers 10,000 × 10,000 px — sufficient
  for the combat MVP arena; tune after first playtest
- `load_radius` of 2 (25 chunks) is a conservative upper bound; reduce to 1 (9 chunks)
  if chunk population is expensive
- AI spawn points are `Node2D` markers — the actual AI spawning reacts to `chunk_loaded`
  in a separate spawner (not in scope for this spec; see AI spec)
- Asteroid visuals are placeholder `Polygon2D` shapes; real 3D models replace them later
  without any code changes to ChunkStreamer or Asteroid
- Debris is visual only — it does not collide with projectiles or ships
- Chunk content for MVP is purely procedural; a future `data/chunks/` folder-per-named-chunk
  approach could override specific coordinates with curated content without breaking the
  procedural path

---

## Future Extension Points

| Feature | How It Fits |
|---|---|
| **Named chunks** | Override `_load_chunk` to check for a `data/chunks/<x>_<y>/` folder before falling back to procedural generation |
| **Station placement** | Add a `station` field to chunk data; spawn Station node on `chunk_loaded` |
| **Ore/resource nodes** | New content type alongside asteroids; asteroid `apply_damage` drops loot on destruction |
| **Nebula zones** | Chunk-level flag that applies a drag multiplier to ships in that chunk |
| **Patrol regions** | `Area2D` nodes in chunks that define AI wander bounds (see AI spec extension point) |
| **Chunk persistence** | Track asteroid HP changes in a `ChunkState` dictionary so revisited chunks remember damage |

---

## Success Criteria

- [ ] Player ship flying in any direction continuously has a populated neighborhood of
  loaded chunks — no "empty void" at the edges
- [ ] Leaving a chunk boundary triggers load of new edge chunks and unload of distant ones
  within one physics frame — no frame drops during streaming
- [ ] The same chunk always contains the same asteroid layout on repeated visits (deterministic seed)
- [ ] Empty chunks exist — not every area of space is filled with rocks
- [ ] Asteroids receive projectile damage and are destroyed correctly — `apply_damage` is called
  by the projectile hit pipeline using the same signature as `Ship.apply_damage`
- [ ] Destroyed asteroid spawns 2–5 `Debris` nodes that drift and fade out
- [ ] `chunk_loaded` / `chunk_unloaded` signals are emitted with the correct `Vector2i` coordinates
- [ ] All tunable values (chunk size, load radius, field density, HP) are in `data/world_config.json`
- [ ] `PerformanceMonitor` overlay shows `ChunkStreamer.load`, `ChunkStreamer.unload`, and
  `ChunkStreamer.loaded_chunks` metrics (F3 key)
- [ ] 25 loaded chunks (5×5 grid) with asteroid fields do not drop below 60fps with combat
  load also active
