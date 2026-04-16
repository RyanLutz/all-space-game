# Ship System Specification
*All Space Combat MVP — Ship Architecture, Assembly, and Data*

## 1. Overview

The Ship System defines what a ship is, how it is assembled from data, and how it enters
the world. Ships are `RigidBody3D` nodes configured entirely at spawn time from JSON
— no ship-type-specific scene files. Every ship is the same `Ship.tscn` with different
data applied to it.

Three layered distinctions drive this entire system:

- **Ship class** — the broad category (fighter, corvette, frigate). One JSON file per class.
- **Ship variant** — a specific named configuration of parts within that class. Variants
  are discovered in the world, not selected by the player from a menu. The combination of
  parts determines the variant's stats and name.
- **Ship loadout** — what weapons and modules are currently installed. This is the only
  layer the player actively customizes.

Parts are not equipment. They are what the ship *is*. A player cannot swap hull variants
at a station any more than they can swap the frame of a car. To reproduce a variant, they
must find one, reverse engineer it, and unlock a blueprint.

**Design Goals:**
- One `Ship.tscn` for every ship type — configuration at spawn time from data
- All ship data is JSON-driven — no recompile to add ships, factions, or parts
- Adding a new ship class = adding a folder; no code changes required
- Parts carry stat deltas — no part is purely cosmetic; all contribute meaningfully
- Part variants are discovered, not selected — discovery is a gameplay loop
- Ship names reflect both variant identity and faction culture
- Weapons and modules are the player-customizable layer; parts are fixed at spawn
- The player's active ship is tracked by `PlayerState` — camera, input, and UI never
  hold a hardcoded ship reference

---

## 2. Architecture

```
ContentRegistry (autoload)
    └── Scans /content/ at startup, indexes ships/weapons/modules by folder name

ShipFactory.gd
    └── spawn_ship(class_id, variant_id, pos, faction, is_player, weapon_loadout_override)
            ├── Reads class data from ContentRegistry
            ├── Resolves final stats: base_stats + part deltas
            ├── Instantiates Ship.tscn
            ├── Loads parts.glb, instances named part nodes into ShipVisual
            ├── Discovers hardpoint empties from assembled part tree
            ├── Attaches HardpointComponent and WeaponComponent per discovered hardpoint
            ├── Resolves display name from faction + variant
            ├── Applies shared color material
            └── Attaches AIController (AI) or adds to "player" group (player)

Ship.tscn (RigidBody3D)
    ├── Ship.gd                          ← physics, stats, unified input interface
    └── ShipVisual (Node3D)
            ├── [hull part MeshInstance3D]
            │       ├── HardpointEmpty_hp_fore_port_small    ← Node3D baked into mesh
            │       └── HardpointEmpty_hp_fore_stbd_small
            ├── [engine part MeshInstance3D]
            └── [bridge part MeshInstance3D]
                    └── HardpointEmpty_hp_turret_medium

PlayerState (autoload)
    └── Tracks active player ship; emits player_ship_changed on GameEventBus
```

### 3D Play Plane

Ships live on the **XZ plane (Y = 0)**. Enforced explicitly at every physics step.

- All positions: `Vector3` with `position.y = 0` at all times
- All velocities: `Vector3` with `linear_velocity.y = 0` at all times — enforced
  explicitly as a backstop each physics step
- Rotation: **Y axis only (yaw)**. Jolt axis locks prevent pitch and roll.
  `RigidBody3D.angular_velocity` is a `Vector3`; only the Y component (`.y`) is ever
  non-zero. Ship.gd reads yaw rate as `angular_velocity.y`. It never writes to
  `rotation.y` directly to produce motion — torques are applied and Jolt integrates.
- Ship forward direction: `-transform.basis.z`
- Mouse-to-world: ray intersected with the Y = 0 plane — see Section 8

### Physics Execution Model

Ship.gd is a translator between input intent and Jolt force commands. It is not a
physics engine. Three layers, strictly separated:

1. **Input layer** — Player or AI writes `input_forward`, `input_strafe`,
   `input_aim_target`, and `input_fire` each frame. No physics knowledge required.
2. **Ship.gd** — Reads the input interface, computes thrust and torque demands
   (including corrective assisted-steering torque and alignment drag force), and calls
   `apply_central_force()` / `apply_torque()`. That is all.
3. **Jolt** — Integrates the queued forces against mass and inertia, applies axis locks
   and damping, and produces the next velocity and position. Ship.gd is not involved.

**Ship.gd never writes to `linear_velocity`, `angular_velocity`, `position`, or
`rotation` to produce motion.** The only direct position write is the Y = 0 backstop,
which is defensive, not locomotion.

### No 2D Nodes

`CharacterBody2D`, `Area2D`, `CollisionShape2D`, `Camera2D`, and `Node2D` are banned.
`Vector2` is banned for world-space positions and velocities. `Vector2i` is permitted
only for chunk grid coordinates.

---

## 3. Core Properties / Data Model

### Ship.gd Properties

**Physics — populated from resolved stats at spawn:**

| Property | Type | Description |
|---|---|---|
| `mass` | float | Affects inertia and torque response |
| `velocity` | Vector3 | Getter: returns `linear_velocity` (RigidBody3D built-in); Y always 0 |
| `yaw_rate` | float | Getter: returns `angular_velocity.y` — the only non-zero angular component |
| `max_speed` | float | Soft speed cap |
| `linear_drag` | float | Drag applied each physics step |
| `alignment_drag` | float | Lateral drag during heading misalignment |
| `thruster_force` | float | Total thrust budget shared by translation and rotation |
| `torque_thrust_ratio` | float | Fraction of budget consumed per unit of torque demand |
| `max_angular_accel` | float | Maximum angular acceleration (derived at init) |

**Combat resources:**

| Property | Type | Description |
|---|---|---|
| `hull_hp` | float | Current hull HP |
| `hull_max` | float | Maximum hull HP |
| `power_current` | float | Current power in the shared pool |
| `power_capacity` | float | Maximum power pool size |
| `power_regen` | float | Power restored per second |
| `shield_hp` | float | Current shield strength |
| `shield_max` | float | Maximum shield strength |
| `shield_regen_rate` | float | HP restored per second while regenerating |
| `shield_regen_delay` | float | Seconds after last hit before regen begins |
| `shield_regen_power_draw` | float | Power consumed per second while regenerating |
| `time_since_last_hit` | float | Tracks regen delay countdown |

**Identity:**

| Property | Type | Description |
|---|---|---|
| `class_id` | String | Content folder name — e.g. `"corvette_patrol"` |
| `variant_id` | String | Variant key — e.g. `"corvette_patrol_heavy"` |
| `faction` | String | Faction ID — drives name selection and color fallback |
| `display_name` | String | Resolved name for this faction + variant combination |
| `is_player` | bool | True for the player ship |

### Unified Input Interface

All ships — player and AI — are driven through the same interface. The physics system
reads only from here; it never checks which mode is active.

```gdscript
var input_forward: float        # -1.0 to 1.0
var input_strafe: float         # -1.0 to 1.0
var input_aim_target: Vector3   # world-space aim point (Y = 0)
var input_fire: Array[bool]     # [group0_active, group1_active, group2_active]
```

In **Pilot mode**, player keyboard and mouse populate these fields. In **Tactical mode**
or **AI control**, `NavigationController.gd` populates them. `Ship.gd` reads
unconditionally.

### Weapon Fire Groups

Weapons are assigned to fire groups. The player fires groups, not individual hardpoints.
Hardpoints have a many-to-many relationship with groups.

| Group | Index | Default Input |
|---|---|---|
| Primary | 0 | Left click |
| Secondary | 1 | Right click |
| Tertiary | 2 | TBD |

Group assignments live in loadout data. At MVP, defaults come from
`default_loadout.fire_groups` in ship.json. Post-MVP, the player configures these at
the station screen and they persist in save data.

### HardpointComponent.gd Properties

| Property | Type | Description |
|---|---|---|
| `hardpoint_id` | String | Parsed from node name — e.g. `"hp_fore_port"` |
| `hardpoint_type` | String | `"fixed"`, `"gimbal"`, `"partial_turret"`, `"full_turret"` |
| `fire_arc_degrees` | float | Derived from type |
| `size` | String | `"small"`, `"medium"`, `"large"` — parsed from node name |
| `heat_capacity` | float | Maximum heat before overheat lockout |
| `heat_current` | float | Current heat level |
| `passive_cooling` | float | Heat dissipated per second when not firing |
| `overheat_cooldown` | float | Lockout duration after reaching heat_capacity |
| `hull_hp` | float | Hardpoint's own HP |
| `damage_state` | String | `"nominal"`, `"damaged"`, `"critical"`, `"destroyed"` |
| `fire_groups` | Array[int] | Which groups this hardpoint belongs to |

**Hardpoint type fire arcs:**

| Type | Arc | Notes |
|---|---|---|
| Fixed | ~5° | Ship must aim. No rotation. |
| Gimbal | ~25° | Auto-tracks aim point within arc. Compensates heading lag. |
| Partial Turret | ~120° | Cannot fire directly behind. |
| Full Turret | 360° | Any direction. Heaviest, slowest traverse. |

**Hardpoint damage states:**

| State | HP% | Effect |
|---|---|---|
| Nominal | 100–60% | Full performance |
| Damaged | 59–25% | Reduced fire rate, increased heat generation |
| Critical | 24–1% | Fires unreliably — chance to misfire per shot |
| Destroyed | 0% | Non-functional until repaired |

### Module Slots

Non-weapon systems. Defined in ship.json so data structures are correct from day one.
Runtime swapping deferred to the Station & Loadout spec.

| Property | Type | Description |
|---|---|---|
| `slot_id` | String | Unique within the ship — e.g. `"slot_shield"` |
| `slot_type` | String | `"shield"`, `"engine"`, `"powerplant"`, `"armor"` |
| `size` | String | `"small"`, `"medium"`, `"large"` |

**MVP:** Ship initializes stats directly from resolved stats. Slot data is stored but
not processed at runtime. Full module math is deferred to the Station & Loadout spec.

---

## 4. Content Directory Structure

```
/content/
    /ships/
        /fighter_light/
            ship.json       ← class definition, all variants, all part stats
            parts.glb       ← all part variant meshes for this class
            icon.png
        /corvette_patrol/
            ship.json
            parts.glb
            icon.png
        /frigate_heavy/
            ship.json
            parts.glb
            icon.png
    /weapons/
        /autocannon_light/
            weapon.json
            model.glb
            icon.png
    /modules/
        /shield_standard/
            module.json
            icon.png
/data/
    factions.json           ← faction color palettes + name vocabularies
    damage_types.json
    ai_profiles.json
    world_config.json
```

**Rule:** Something the player can see, equip, or interact with → `/content/`.
System configuration tables → `/data/`.

---

## 5. Parts GLB Structure

Each ship class has one `parts.glb` containing **all part variant meshes** as separate
named objects. This is the single Blender source for that class, exported once.

```
# fighter_light/parts.glb contains:
hull_slim
hull_wide
hull_heavy
engine_single
engine_dual
engine_quad
wing_swept
wing_delta
wing_none          ← minimal mesh for the "no wing" case
cockpit_open
cockpit_enclosed

# corvette_patrol/parts.glb contains:
corvette_hull_standard
corvette_hull_heavy
corvette_engine_dual
corvette_engine_triple
corvette_bridge_open
corvette_bridge_armored
```

Each ship class owns its own namespace entirely. A fighter's `hull_slim` and a
corvette's `corvette_hull_standard` are in separate files and never interact.

### Hardpoint Empties Live Inside Part Meshes

Hardpoint positions are baked into part objects in Blender as named empty nodes
(`Node3D` with no mesh). They export into the GLB as children of their parent part
object and come along when that part is instanced.

```
hull_slim (MeshInstance3D)
    ├── HardpointEmpty_hp_fore_port_small
    └── HardpointEmpty_hp_fore_stbd_small

hull_wide (MeshInstance3D)
    ├── HardpointEmpty_hp_fore_port_small    ← same IDs, different positions
    ├── HardpointEmpty_hp_fore_stbd_small
    └── HardpointEmpty_hp_mid_port_small     ← extra hardpoint only on wide hull

wing_swept (MeshInstance3D)
    ├── HardpointEmpty_hp_wing_port_small
    └── HardpointEmpty_hp_wing_stbd_small

wing_none (MeshInstance3D)
    └── (no hardpoint empties)
```

**Empty naming convention:**
```
HardpointEmpty_{id}_{size}

Examples:
HardpointEmpty_hp_fore_port_small
HardpointEmpty_hp_mid_turret_medium
HardpointEmpty_hp_wing_stbd_large
```

The empty's Transform defines position and facing (`-Z` = forward = muzzle direction).
No position or orientation data belongs in JSON — the artist bakes this into the empty.

**Hardpoints appear and disappear with the parts that contain them.** `wing_none` brings
zero wing hardpoints. `hull_wide` brings a mid hardpoint that `hull_slim` does not.
No enable/disable logic exists — presence of the empty *is* the toggle.

### Weapon Model Scene Structure

```
HardpointEmpty_hp_fore_port_small (Node3D)
    └── WeaponModel (MeshInstance3D)    ← from /content/weapons/<id>/model.glb
            └── Muzzle (Marker3D)       ← projectile spawn point
```

`WeaponComponent.gd` attaches to `WeaponModel`. The `Muzzle` node's world transform
provides the exact spawn position and direction — no manual offset needed.

---

## 6. JSON Data Format

### ship.json

One file per ship class. Contains all variants, all part stat deltas, and name data.
The `parts` dictionary in each variant is **freeform** — category keys are documentation
for the designer; code iterates values and ignores keys entirely.

```json
{
    "ship_class": "corvette_patrol",
    "display_name": "Patrol Corvette",
    "class": "corvette",
    "description": "A versatile multi-role vessel. Slower than a fighter but considerably tougher.",

    "base_stats": {
        "hp":                      350,
        "mass":                    2000,
        "max_speed":               320,
        "linear_drag":             1.2,
        "alignment_drag":          2.8,
        "thruster_force":          18000,
        "torque_thrust_ratio":     0.28,
        "power_capacity":          280,
        "power_regen":             55,
        "shield_max":              200,
        "shield_regen_rate":       14,
        "shield_regen_delay":      4.0,
        "shield_regen_power_draw": 20
    },

    "variants": {
        "corvette_patrol_standard": {
            "display_name": "Wanderer",
            "faction_display_names": {
                "pirate":     "The Opportunist",
                "militia":    "Vigil",
                "megacorp":   "Patrol Unit",
                "scavenger":  "Close Enough"
            },
            "rarity": "common",
            "parts": {
                "hull":   "corvette_hull_standard",
                "engine": "corvette_engine_dual",
                "bridge": "corvette_bridge_open"
            }
        },
        "corvette_patrol_heavy": {
            "display_name": "Ironside",
            "faction_display_names": {
                "pirate":     "Broadside",
                "militia":    "Rampart",
                "megacorp":   "Suppressor",
                "scavenger":  "Still Works"
            },
            "rarity": "uncommon",
            "parts": {
                "hull":   "corvette_hull_heavy",
                "engine": "corvette_engine_dual",
                "bridge": "corvette_bridge_armored"
            }
        },
        "corvette_patrol_raider": {
            "display_name": "Cutthroat",
            "faction_display_names": {
                "pirate":     "Bloodwake",
                "militia":    "Pursuit",
                "megacorp":   "Enforcer MK-II",
                "scavenger":  "Fast Enough"
            },
            "rarity": "rare",
            "parts": {
                "hull":   "corvette_hull_standard",
                "engine": "corvette_engine_overdriven",
                "bridge": "corvette_bridge_open"
            }
        }
    },

    "part_stats": {
        "corvette_hull_standard":     { "hp": 120, "mass": 400 },
        "corvette_hull_heavy":        { "hp": 280, "mass": 900, "alignment_drag": 1.2 },
        "corvette_engine_dual":       { "thruster_force": 3000 },
        "corvette_engine_overdriven": { "thruster_force": 7000, "power_capacity": -40, "max_speed": 60 },
        "corvette_bridge_open":       { "power_regen": 8 },
        "corvette_bridge_armored":    { "hp": 60, "power_regen": -5 }
    },

    "hardpoint_types": {
        "hp_fore_port":  "gimbal",
        "hp_fore_stbd":  "gimbal",
        "hp_mid_turret": "full_turret"
    },

    "module_slots": [
        { "id": "slot_shield", "type": "shield",     "size": "medium" },
        { "id": "slot_engine", "type": "engine",     "size": "medium" },
        { "id": "slot_power",  "type": "powerplant", "size": "medium" },
        { "id": "slot_armor",  "type": "armor",      "size": "medium" }
    ],

    "default_loadout": {
        "weapons": {
            "hp_fore_port":  "autocannon_light",
            "hp_fore_stbd":  "autocannon_light",
            "hp_mid_turret": "pulse_laser"
        },
        "fire_groups": {
            "hp_fore_port":  [0],
            "hp_fore_stbd":  [0],
            "hp_mid_turret": [1]
        },
        "modules": {
            "slot_shield": "shield_standard",
            "slot_engine": "engine_standard",
            "slot_power":  "powerplant_standard",
            "slot_armor":  "armor_light"
        }
    },

    "assets": {
        "parts": "parts.glb",
        "icon":  "icon.png"
    }
}
```

### Key Concepts

**`base_stats`** is the floor — the ship with no parts. No ship ever has exactly these
stats; every variant's parts apply additive deltas on top of them.

**`variants`** are named, discoverable configurations. A player finds a
`corvette_patrol_heavy` in the wild — they do not find a corvette and then pick its
parts.

**`part_stats`** maps each part node name to stat deltas. All values are additive.
Negative values are valid (the overdriven engine trading power capacity for speed).
Every part must have an entry — no part is neutral or purely cosmetic.

**`parts` in each variant** is a freeform dictionary. The category key (`"hull"`,
`"engine"`, `"bridge"`) is documentation only — code iterates values, ignores keys.
A frigate can define `"hull_fore"`, `"hull_mid"`, `"hull_aft"`. A fighter can have
`"wing"`. A corvette has neither. This requires zero special handling.

**`hardpoint_types`** maps discovered hardpoint IDs to behavioral types. IDs absent
from this map default to `"fixed"`. Positions are owned by Blender empties; only
type lives here.

### factions.json

```json
{
    "factions": [
        {
            "id": "militia",
            "display_name": "Sector Militia",
            "color_scheme": {
                "primary": "#1A3A6A",
                "trim":    "#DDDDDD",
                "accent":  "#FFD700",
                "glow":    "#4488FF"
            },
            "name_vocabulary": {
                "corvette": {
                    "heavy_hull":    ["Rampart", "Bulwark", "Fortress", "Ironside"],
                    "standard_hull": ["Vigil", "Warden", "Sentinel", "Patrol"],
                    "fast_engine":   ["Interceptor", "Pursuit", "Ranger", "Scout"]
                },
                "fighter": {
                    "standard": ["Arrow", "Dart", "Lancer", "Talon"]
                }
            }
        },
        {
            "id": "pirate",
            "display_name": "Raiders",
            "color_scheme": {
                "primary": "#3A1A1A",
                "trim":    "#CC3300",
                "accent":  "#FF6600",
                "glow":    "#FF2200"
            },
            "name_vocabulary": {
                "corvette": {
                    "heavy_hull":    ["Broadside", "Ironjaw", "Deathmarch", "Ravager"],
                    "standard_hull": ["The Opportunist", "Marauder", "Brigand", "Cutthroat"],
                    "fast_engine":   ["Bloodwake", "Fang", "Reaver", "Jackal"]
                },
                "fighter": {
                    "standard": ["Fang", "Bite", "Scratch", "Sting"]
                }
            }
        },
        {
            "id": "megacorp",
            "display_name": "Hegemony Industrial",
            "color_scheme": {
                "primary": "#2A2A3A",
                "trim":    "#AAAACC",
                "accent":  "#0044FF",
                "glow":    "#0088FF"
            },
            "name_vocabulary": {
                "corvette": {
                    "heavy_hull":    ["Suppressor", "Pacifier", "Compliance Unit", "Asset-7"],
                    "standard_hull": ["Patrol Unit", "Enforcer", "Response Unit", "Sector-9"],
                    "fast_engine":   ["Enforcer MK-II", "Rapid Response", "Expeditor", "Vector"]
                },
                "fighter": {
                    "standard": ["Asset-3", "Unit-7", "Response-1", "Interceptor-A"]
                }
            }
        },
        {
            "id": "scavenger",
            "display_name": "Independents",
            "color_scheme": {
                "primary": "#4A3A2A",
                "trim":    "#887766",
                "accent":  "#CCAA44",
                "glow":    "#FFCC44"
            },
            "name_vocabulary": {
                "corvette": {
                    "heavy_hull":    ["The Accident", "Still Works", "Good Enough", "Last Resort"],
                    "standard_hull": ["Honest Mistake", "Why Not", "Close Enough", "Found It"],
                    "fast_engine":   ["Fast Enough", "Duct Tape Special", "Don't Ask", "Mostly Fine"]
                },
                "fighter": {
                    "standard": ["Probably Fine", "Fingers Crossed", "Trust Me", "It Flies"]
                }
            }
        }
    ]
}
```

---

## 7. Ship Naming

### Resolution Order

When a ship is spawned, its `display_name` is resolved in this priority order:

1. **Explicit faction name** — if the variant's `faction_display_names` has an entry for
   this ship's faction, use it. This is the preferred path for any variant that matters.
2. **Faction vocabulary fallback** — if no explicit entry exists (rare procedural edge
   cases), select deterministically from `factions.json` vocabulary using the variant's
   dominant part stat theme as the category key. Same combination always produces the
   same name.
3. **Default display_name** — if the faction has no vocabulary for this class, use the
   variant's base `display_name`.

### Effect in the World

The same physical ship — same stats, same hardpoints — reads completely differently
depending on who built it:

| Variant | Neutral | Militia | Pirate | Megacorp | Scavenger |
|---|---|---|---|---|---|
| `corvette_patrol_standard` | Wanderer | Vigil | The Opportunist | Patrol Unit | Close Enough |
| `corvette_patrol_heavy` | Ironside | Rampart | Broadside | Suppressor | Still Works |
| `corvette_patrol_raider` | Cutthroat | Pursuit | Bloodwake | Enforcer MK-II | Fast Enough |

### Vocabulary Fallback Algorithm

Used only when a variant lacks an explicit `faction_display_names` entry for a faction.

```gdscript
func _resolve_name_from_vocabulary(variant_data: Dictionary, class_type: String,
                                    faction_data: Dictionary, variant_id: String) -> String:
    var vocab: Dictionary = faction_data.get("name_vocabulary", {})
    var class_vocab: Dictionary = vocab.get(class_type, {})
    if class_vocab.is_empty():
        return variant_data["display_name"]

    var category := _dominant_part_category(variant_data)
    var pool: Array = class_vocab.get(category, [])
    if pool.is_empty():
        pool = class_vocab.values()[0]   # fallback to first available category

    # Deterministic — same variant + faction always produces the same index
    var idx := abs(hash(variant_id + faction_data["id"])) % pool.size()
    return pool[idx]
```

`_dominant_part_category()` inspects the variant's `part_stats` deltas and returns
`"heavy_hull"`, `"fast_engine"`, or `"standard_hull"` based on which stat theme is
most pronounced. Thresholds are tuned during content development.

---

## 8. Key Algorithms

### Stat Resolution

Final ship stats are base stats plus all part deltas for the chosen variant. Applied
once at spawn; stored directly on `Ship.gd`.

```gdscript
func _resolve_stats(class_data: Dictionary, variant_id: String) -> Dictionary:
    var stats := class_data["base_stats"].duplicate(true)
    var variant := class_data["variants"][variant_id]
    var part_stats: Dictionary = class_data["part_stats"]

    for category in variant["parts"]:
        var node_name: String = variant["parts"][category]
        var deltas: Dictionary = part_stats.get(node_name, {})
        if deltas.is_empty():
            push_warning("ShipFactory: no part_stats entry for '%s'" % node_name)
        for stat in deltas:
            stats[stat] = stats.get(stat, 0.0) + deltas[stat]

    return stats
```

### Part Assembly

```gdscript
func _assemble_parts(ship_visual: Node3D, variant_data: Dictionary,
                     parts_scene: PackedScene) -> void:
    var parts_root := parts_scene.instantiate()
    for category in variant_data["parts"]:
        var node_name: String = variant_data["parts"][category]
        var part_node := parts_root.find_child(node_name, true, false)
        if part_node == null:
            push_error("ShipFactory: part '%s' not found in parts.glb" % node_name)
            continue
        ship_visual.add_child(part_node.duplicate())
    parts_root.queue_free()
    # Category keys are never read by this function
```

### Hardpoint Discovery

After all parts are instanced, scan the assembled tree for nodes named
`"HardpointEmpty_*"`. Everything needed — position, facing, size — comes from the node
itself. Nothing is looked up in JSON.

```gdscript
func _discover_hardpoints(ship_visual: Node3D) -> Array[Node3D]:
    var found: Array[Node3D] = []
    _find_hardpoints_recursive(ship_visual, found)
    return found

func _find_hardpoints_recursive(node: Node, result: Array[Node3D]) -> void:
    if node.name.begins_with("HardpointEmpty_"):
        result.append(node as Node3D)
    for child in node.get_children():
        _find_hardpoints_recursive(child, result)

func _parse_hardpoint_name(node_name: String) -> Dictionary:
    # "HardpointEmpty_hp_fore_port_small" → { id: "hp_fore_port", size: "small" }
    var tokens := node_name.split("_")
    var size := tokens[-1]
    var id   := "_".join(tokens.slice(1, tokens.size() - 1))
    return { "id": id, "size": size }
```

### Hardpoint Configuration

For each discovered hardpoint, look up its type from `hardpoint_types`, its weapon from
the loadout, and its fire group. Weapons absent from the loadout for a given hardpoint
ID are silently skipped — the hardpoint exists but has nothing mounted.

```gdscript
func _configure_hardpoints(ship: Node, discovered: Array[Node3D],
                            class_data: Dictionary, loadout: Dictionary) -> void:
    var type_map:   Dictionary = class_data.get("hardpoint_types", {})
    var weapon_map: Dictionary = loadout.get("weapons", {})
    var group_map:  Dictionary = loadout.get("fire_groups", {})

    for hp_node in discovered:
        var parsed   := _parse_hardpoint_name(hp_node.name)
        var hp_id    := parsed["id"] as String

        var component := HardpointComponent.new()
        hp_node.add_child(component)
        component.hardpoint_id   = hp_id
        component.hardpoint_type = type_map.get(hp_id, "fixed")
        component.size           = parsed["size"]
        component.fire_groups    = group_map.get(hp_id, [0])

        var weapon_id: String = weapon_map.get(hp_id, "")
        if not weapon_id.is_empty():
            _attach_weapon(hp_node, weapon_id)
```

### Mouse-to-World (Pilot Mode)

```gdscript
func _get_aim_world_position() -> Vector3:
    var camera := get_viewport().get_camera_3d()
    var mouse_pos := get_viewport().get_mouse_position()
    var plane := Plane(Vector3.UP, 0.0)
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir    := camera.project_ray_normal(mouse_pos)
    var intersection = plane.intersects_ray(ray_origin, ray_dir)
    return intersection if intersection else global_position
```

### Physics Update Loop

```gdscript
func _physics_process(delta: float) -> void:
    _update_input(delta)
    PerformanceMonitor.begin("Physics.thruster_allocation")
    _allocate_thrust(delta)
    _apply_alignment_drag(delta)
    PerformanceMonitor.end("Physics.thruster_allocation")
    # Jolt integrates forces — no move_and_slide() call
    _update_shield_regen(delta)
    _update_power_regen(delta)
```

### Damage Resolution

```gdscript
func apply_damage(amount: float, damage_type: String,
                  hit_pos: Vector3, component_ratio: float) -> void:
    time_since_last_hit = 0.0
    if shield_hp > 0.0:
        var factor   := _damage_vs_shields(damage_type)
        var absorbed := minf(shield_hp, amount * factor)
        shield_hp -= absorbed
        amount = maxf(0.0, amount - absorbed / factor)
    if amount <= 0.0:
        return
    hull_hp -= amount * (1.0 - component_ratio)
    _apply_hardpoint_damage_at(hit_pos, amount * component_ratio, damage_type)
    if hull_hp <= 0.0:
        _die()

func _die() -> void:
    GameEventBus.emit_signal("ship_destroyed", self, global_position, faction)
    queue_free()
```

---

## 9. Ship Spawning Flow

### Signature

```gdscript
ShipFactory.spawn_ship(
    class_id:                String,     # e.g. "corvette_patrol"
    variant_id:              String,     # e.g. "corvette_patrol_heavy"
    pos:                     Vector3,
    faction:                 String,     # e.g. "pirate"
    is_player:               bool = false,
    weapon_loadout_override: Dictionary = {}
)
```

Parts are fixed by `variant_id`. Only weapons and modules are overridable at spawn.

### Steps Inside spawn_ship

```gdscript
func spawn_ship(class_id: String, variant_id: String, pos: Vector3, faction: String,
                is_player: bool = false,
                weapon_loadout_override: Dictionary = {}) -> RigidBody3D:
    var class_data := ContentRegistry.get_ship(class_id)
    if class_data.is_empty():
        push_error("ShipFactory: unknown class '%s'" % class_id)
        return null

    PerformanceMonitor.begin("ShipFactory.assemble")

    # 1. Resolve stats
    var resolved_stats := _resolve_stats(class_data, variant_id)

    # 2. Instantiate base scene
    var ship: RigidBody3D = preload("res://gameplay/entities/Ship.tscn").instantiate()
    ship.global_position = pos
    ship.position.y = 0.0

    # 3. Resolve loadout
    var loadout := class_data["default_loadout"].duplicate(true)
    loadout["weapons"].merge(weapon_loadout_override, true)

    # 4. Assemble parts from GLB
    var parts_path := ContentRegistry.get_asset_path(class_data, "parts")
    _assemble_parts(ship.get_node("ShipVisual"), class_data["variants"][variant_id],
                    load(parts_path))

    # 5. Discover and configure hardpoints
    var discovered := _discover_hardpoints(ship.get_node("ShipVisual"))
    _configure_hardpoints(ship, discovered, class_data, loadout)

    # 6. Resolve name
    var variant_data := class_data["variants"][variant_id]
    ship.display_name = _resolve_display_name(variant_data, class_data["class"],
                                               faction, variant_id)
    ship.faction    = faction
    ship.class_id   = class_id
    ship.variant_id = variant_id

    # 7. Apply color material
    _apply_color_material(ship, class_data, faction)

    # 8. Apply resolved stats
    ship.initialize_stats(resolved_stats)

    PerformanceMonitor.end("ShipFactory.assemble")

    # 9. Identity
    if is_player:
        ship.add_to_group("player")
        PlayerState.set_active_ship(ship)
    else:
        var ai := preload("res://gameplay/ai/AIController.tscn").instantiate()
        ship.add_child(ai)
        ship.add_to_group("ai_ships")

    get_tree().get_root().add_child(ship)
    return ship
```

---

## 10. Blueprint and Discovery System

### What Gets Unlocked

Discovering a variant unlocks it as a blueprint. Blueprints are stored as a set of
`variant_id` strings in save data:

```json
{
    "blueprints": [
        "corvette_patrol_standard",
        "corvette_patrol_heavy",
        "fighter_light_interceptor"
    ]
}
```

### Unlock Flow

1. Player encounters a ship with a variant they haven't seen before
2. Player reverse engineers it — mechanic TBD (cost, time, station required)
3. `variant_id` string is added to save data blueprints array
4. Phase 3 shipyard checks this array to determine what the player can build

### No Starting Blueprints

Players begin with a specific ship — a variant — but not automatically with its
blueprint. Reverse engineering must be done explicitly.

### ContentRegistry Variant Query

```gdscript
func get_variant(class_id: String, variant_id: String) -> Dictionary:
    var class_data := get_ship(class_id)
    return class_data.get("variants", {}).get(variant_id, {})

func get_class_for_variant(variant_id: String) -> String:
    for class_id in ships:
        if ships[class_id].get("variants", {}).has(variant_id):
            return class_id
    return ""
```

---

## 11. Colorization System

All parts and weapon models on one ship share a **single `ShaderMaterial` instance**.
Vertex colors painted in Blender drive the shader — no UV unwrapping required.

### Vertex Color Channels

| Channel | Region | Typical Use |
|---|---|---|
| R | Primary | Main hull surfaces, dominant body color |
| G | Trim | Panel seams, structural edges, frames |
| B | Accent | Faction markings, insignia, stripe details |
| A | Glow | Engine exhaust, running lights, weapon charge ports |

### Color Resolution

```gdscript
func _resolve_color_scheme(class_data: Dictionary, faction: String) -> Dictionary:
    if class_data.has("color_scheme"):
        return class_data["color_scheme"]        # ship-level override
    var faction_data := ContentRegistry.get_faction(faction)
    return faction_data.get("color_scheme", _default_color_scheme())
```

### Application

```gdscript
func _apply_color_material(ship: Node3D, class_data: Dictionary, faction: String) -> void:
    var scheme   := _resolve_color_scheme(class_data, faction)
    var material := ShaderMaterial.new()
    material.shader = preload("res://assets/shaders/ship_colorize.gdshader")
    material.set_shader_parameter("color_primary", Color(scheme["primary"]))
    material.set_shader_parameter("color_trim",    Color(scheme["trim"]))
    material.set_shader_parameter("color_accent",  Color(scheme["accent"]))
    material.set_shader_parameter("color_glow",    Color(scheme["glow"]))
    _apply_material_recursive(ship.get_node("ShipVisual"), material)

func _apply_material_recursive(node: Node, material: Material) -> void:
    if node is MeshInstance3D:
        (node as MeshInstance3D).material_override = material
    for child in node.get_children():
        _apply_material_recursive(child, material)
```

### Shader Logic (GLSL sketch)

```glsl
uniform vec4 color_primary;
uniform vec4 color_trim;
uniform vec4 color_accent;
uniform vec4 color_glow;

void fragment() {
    float r = COLOR.r;
    float g = COLOR.g;
    float b = COLOR.b;
    float a = COLOR.a;

    vec3 albedo = color_primary.rgb * r
                + color_trim.rgb    * g
                + color_accent.rgb  * b
                + vec3(0.08)        * (1.0 - r - g - b - a);

    ALBEDO   = albedo;
    EMISSION = color_glow.rgb * a;
}
```

Unweighted vertices fall back to a dark neutral — useful for thruster nozzle interiors
and other areas that should not take faction color.

---

## 12. ContentRegistry

```gdscript
# ContentRegistry.gd — autoload

var ships:    Dictionary = {}
var weapons:  Dictionary = {}
var modules:  Dictionary = {}
var _factions: Dictionary = {}

func _ready() -> void:
    PerformanceMonitor.begin("ContentRegistry.load")
    _scan_directory("res://content/ships",   ships,   "ship.json")
    _scan_directory("res://content/weapons", weapons, "weapon.json")
    _scan_directory("res://content/modules", modules, "module.json")
    _load_factions("res://data/factions.json")
    PerformanceMonitor.end("ContentRegistry.load")

func _scan_directory(base_path: String, target: Dictionary, filename: String) -> void:
    var dir := DirAccess.open(base_path)
    if dir == null:
        push_warning("ContentRegistry: cannot open %s" % base_path)
        return
    dir.list_dir_begin()
    var folder := dir.get_next()
    while folder != "":
        if dir.current_is_dir() and not folder.begins_with("."):
            var json_path := "%s/%s/%s" % [base_path, folder, filename]
            if FileAccess.file_exists(json_path):
                var data := _load_json(json_path)
                if data != null:
                    data["_id"]        = folder
                    data["_base_path"] = "%s/%s" % [base_path, folder]
                    target[folder] = data
        folder = dir.get_next()

func get_ship(id: String)    -> Dictionary: return ships.get(id, {})
func get_weapon(id: String)  -> Dictionary: return weapons.get(id, {})
func get_module(id: String)  -> Dictionary: return modules.get(id, {})
func get_faction(id: String) -> Dictionary: return _factions.get(id, {})

func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
    var filename: String = content_data.get("assets", {}).get(asset_key, "")
    if filename.is_empty(): return ""
    return "%s/%s" % [content_data["_base_path"], filename]
```

---

## 13. PlayerState

```gdscript
# PlayerState.gd — autoload

var active_ship: RigidBody3D = null

func set_active_ship(ship: RigidBody3D) -> void:
    active_ship = ship
    GameEventBus.emit_signal("player_ship_changed", ship)

func get_active_ship() -> RigidBody3D:
    return active_ship
```

No system holds a hardcoded ship reference. Camera, input routing, and UI all listen
to `player_ship_changed` and update accordingly.

---

## 14. Ship Classes

| Class | Role | Mass Range | Turn Feel |
|---|---|---|---|
| Fighter | Single-pilot combat | Low | Snappy |
| Corvette | Light multi-role | Low–medium | Responsive |
| Frigate | Medium warship | Medium | Deliberate |
| Destroyer | Heavy combat | Medium–high | Sluggish |
| Cruiser | Large multi-role | High | Very sluggish |
| Battleship | Fleet centerpiece | Very high | Ponderous |
| Transport | Cargo | Medium | Deliberate |
| Industrial | Mining / support | Medium | Deliberate |
| Explorer | Long-range | Low–medium | Responsive |

---

## 15. Performance Instrumentation

```gdscript
# ContentRegistry._ready():
PerformanceMonitor.begin("ContentRegistry.load")
PerformanceMonitor.end("ContentRegistry.load")

# ShipFactory.spawn_ship():
PerformanceMonitor.begin("ShipFactory.assemble")
PerformanceMonitor.end("ShipFactory.assemble")

# Ship._physics_process():
PerformanceMonitor.begin("Physics.thruster_allocation")
# _allocate_thrust() + _apply_alignment_drag()
PerformanceMonitor.end("Physics.thruster_allocation")
# Jolt integrates — no move_and_slide()

# Scene manager, once per frame:
PerformanceMonitor.set_count("Ships.active_count", active_ships.size())
```

Register in `_ready()`:
```gdscript
Performance.add_custom_monitor("AllSpace/ships_active",
    func(): return PerformanceMonitor.get_count("Ships.active_count"))
Performance.add_custom_monitor("AllSpace/ship_assembly_ms",
    func(): return PerformanceMonitor.get_avg_ms("ShipFactory.assemble"))
Performance.add_custom_monitor("AllSpace/content_load_ms",
    func(): return PerformanceMonitor.get_avg_ms("ContentRegistry.load"))
```

**Canonical metric names:**

| Metric | Name |
|---|---|
| Ship assembly | `ShipFactory.assemble` |
| Content registry scan | `ContentRegistry.load` |
| Active ships | `Ships.active_count` |
| Thruster allocation | `Physics.thruster_allocation` |

---

## 16. Files

```
/core/services/
    ContentRegistry.gd
    PlayerState.gd
/gameplay/entities/
    Ship.tscn               ← RigidBody3D — shared for all ship types
    Ship.gd
    ShipFactory.gd
/gameplay/weapons/
    HardpointComponent.gd
    WeaponComponent.gd
/content/
    /ships/                 ← one folder per ship class
        /corvette_patrol/
            ship.json
            parts.glb
            icon.png
    /weapons/               ← one folder per weapon
    /modules/               ← one folder per module
/data/
    factions.json
    damage_types.json
    ai_profiles.json
    world_config.json
/assets/shaders/
    ship_colorize.gdshader
```

---

## 17. Dependencies

- `PerformanceMonitor` registered before `ContentRegistry` loads
- `ContentRegistry` loaded before any `ShipFactory.spawn_ship()` call
- `PlayerState` available before camera or input initialization
- `GameEventBus` defines `player_ship_changed` and `ship_destroyed` before any ship spawns
- `WeaponComponent.gd` and `HardpointComponent.gd` from Weapons spec
- `NavigationController.gd` from Physics spec — used by AI and Tactical mode; not
  required for Pilot mode MVP
- `parts.glb` for each ship class authored with hardpoint empty nodes named per convention
- Vertex colors painted on all meshes per the four-channel convention

---

## 18. Assumptions

- All `base_stats` values are placeholder — tune after first playtest
- Every `part_stats` entry must be present; a warning is emitted for missing entries
- `_dominant_part_category()` thresholds for vocabulary fallback are deferred —
  implement with conservative defaults and tune with content
- Vocabulary pools should cover all common part combinations; add categories as needed
- Rarity values (`"common"`, `"uncommon"`, `"rare"`) are defined but spawn weighting
  is deferred to the AI spawner and world population spec
- `max_angular_accel` derivation from `thruster_force` and `mass` is deferred to
  implementation — validate that Fighter feels snappy and Destroyer feels sluggish
- Quality-tier color variation (battle-worn ships, elite ships) deferred to content pass
- Full module stat processing deferred to Station & Loadout spec
- Reverse engineering mechanic (cost, time, station) deferred to Station spec
- Blueprint construction at shipyard deferred to Phase 3
- No validation that `default_loadout` items exist in ContentRegistry at MVP — add post-MVP

---

## 19. Success Criteria

- [ ] `ContentRegistry` loads all ship classes, weapons, and modules at startup
- [ ] Adding a new ship class requires only a folder with `ship.json` and `parts.glb` — no code changes
- [ ] Adding a new variant requires only a new entry in `variants` and `part_stats` — no code changes
- [ ] `spawn_ship("corvette_patrol", "corvette_patrol_heavy", pos, "pirate")` produces a
      ship named "Broadside" in < 5ms
- [ ] Parts block category keys are never read by code — only node name values matter
- [ ] A variant using `wing_none` has no wing hardpoints in the assembled tree
- [ ] A variant using `hull_wide` has its extra mid hardpoint; `hull_slim` does not
- [ ] Hardpoints absent from `default_loadout.weapons` are present but have no weapon attached — no error
- [ ] `position.y` and `velocity.y` are both 0 after every physics update — enforced, not assumed
- [ ] Ship rotation uses Y axis only — `rotation.x` and `rotation.z` remain 0 always
- [ ] Mouse aim resolves via ray-plane intersection — `get_global_mouse_position()` is never called
- [ ] The same variant always produces the same name for the same faction (deterministic)
- [ ] Different factions produce different names for the same variant
- [ ] A faction with no vocabulary for a class falls back to the variant's `display_name`
- [ ] All assembled parts and weapon models share one material instance — one color change recolors the entire ship
- [ ] Fire groups route correctly — activating group 0 fires all hardpoints assigned to it
- [ ] `PlayerState.active_ship` correctly tracks the player ship; `player_ship_changed` fires on change
- [ ] Fighter and Destroyer feel meaningfully different — angular inertia difference is palpable
- [ ] All ship stats flow from JSON — no hardcoded values in GDScript
- [ ] 20 simultaneously assembled ships run within frame budget at 60fps
- [ ] `ShipFactory.assemble`, `ContentRegistry.load`, and `Physics.thruster_allocation` visible in F3 overlay
