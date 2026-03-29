# Ship & Content Data Architecture Specification
*All Space — Data Structure for Ships, Modules, and Weapons*

## Overview

A folder-per-item content architecture where every ship, module, and weapon is a self-contained folder with a JSON definition and its associated assets (3D models, images, icons). This spec defines the data structures and loading conventions — **not** the runtime module-swapping gameplay, which is deferred post-MVP. The goal is to establish the architecture now so that everything built from here forward (AI ships, player ships, weapons) uses the same patterns.

**Design Goals:**
- Every content item is a self-contained folder — JSON + assets together
- Ships are defined by their hull (stats, hardpoint layout, module slots) — not by their loadout
- Loadouts are separate — what's installed on a ship is distinct from what the ship *can* accept
- Adding a new ship, weapon, or module = adding a folder, no code changes
- The architecture supports modding naturally — drop a folder in, it exists in the game
- MVP uses one player ship and a handful of AI ship definitions, but the system handles any number

---

## Content Directory Structure

```
/content/
    /ships/
        /fighter_light/
            ship.json
            model.glb              (or .gltf — 3D asset)
            icon.png               (UI thumbnail)
        /corvette_patrol/
            ship.json
            model.glb
            icon.png
        /freighter_basic/
            ship.json
            model.glb
            icon.png
    /weapons/
        /autocannon_light/
            weapon.json
            model.glb              (mounted weapon visual)
            icon.png               (UI thumbnail)
        /beam_laser/
            weapon.json
            model.glb
            icon.png
        /missile_heat/
            weapon.json
            model.glb
            icon.png
    /modules/
        /shield_standard/
            module.json
            icon.png               (modules may not need 3D models)
        /engine_fast/
            module.json
            icon.png
        /powerplant_heavy/
            module.json
            icon.png
        /armor_reinforced/
            module.json
            icon.png
```

**Convention:** The folder name **is** the item's ID. `weapon.json` inside `/weapons/autocannon_light/` defines the weapon with ID `"autocannon_light"`. No separate ID field needed — it's derived from the folder name.

---

## Ship Definition (ship.json)

A ship definition describes the **hull** — its physical properties, what it can accept, and where things attach. It does **not** define what's currently installed.

```json
{
    "display_name": "Light Fighter",
    "class": "fighter",
    "description": "A nimble single-seat combat vessel. Fast and fragile.",

    "hull": {
        "hp": 200,
        "mass": 800,
        "max_speed": 450,
        "linear_drag": 0.8,
        "alignment_drag": 3.5,
        "thruster_force": 12000,
        "torque_thrust_ratio": 0.3
    },

    "hardpoints": [
        {
            "id": "hp_nose",
            "offset": [32, 0],
            "facing": 0,
            "type": "gimbal",
            "size": "small"
        },
        {
            "id": "hp_port_wing",
            "offset": [-8, -20],
            "facing": 270,
            "type": "fixed",
            "size": "small"
        },
        {
            "id": "hp_stbd_wing",
            "offset": [-8, 20],
            "facing": 90,
            "type": "fixed",
            "size": "small"
        }
    ],

    "module_slots": [
        { "id": "slot_shield", "type": "shield", "size": "small" },
        { "id": "slot_engine", "type": "engine", "size": "small" },
        { "id": "slot_power", "type": "powerplant", "size": "small" },
        { "id": "slot_armor", "type": "armor", "size": "small" }
    ],

    "assets": {
        "model": "model.glb",
        "icon": "icon.png"
    }
}
```

### Hull Properties

| Property | Description | Consumed By |
|---|---|---|
| `hp` | Hull hit points (before module bonuses) | Damage system |
| `mass` | Ship mass in kg-equivalent | Physics — affects inertia and torque |
| `max_speed` | Soft speed cap (before module modifiers) | Physics — drag increases above this |
| `linear_drag` | Base drag coefficient | Physics |
| `alignment_drag` | Lateral bleed on turns | Physics |
| `thruster_force` | Total thrust budget | Physics — shared between turn/thrust/strafe |
| `torque_thrust_ratio` | How expensive turning is | Physics |

### Hardpoints

Hardpoints define **where weapons can mount** and **what types fit**. The hardpoint data format is unchanged from the Weapons spec — this is the same data, just living inside the ship definition where it belongs.

### Module Slots

Module slots define **what non-weapon systems the ship can accept**. Each slot has:

| Property | Description |
|---|---|
| `id` | Unique slot identifier on this ship |
| `type` | What category of module fits here (shield, engine, powerplant, armor) |
| `size` | Size constraint (small, medium, large) |

**MVP note:** Module slots are defined in the ship JSON so the data structure is correct, but the runtime module-swapping system is not implemented. The MVP player ship uses hardcoded default modules. When the module system is built, it reads these slots and enforces compatibility.

---

## Weapon Definition (weapon.json)

Weapon data has been established in the Weapons spec. The change here is that each weapon lives in its own folder alongside its assets, rather than all weapons being entries in a single `weapons.json`.

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

**Migration note:** The existing `weapons.json` monolithic file should be broken up into per-weapon folders. The data format for individual weapons is the same — the only change is where it lives.

---

## Module Definition (module.json)

Modules are non-weapon systems that modify ship stats. Each module type has its own stat block.

```json
{
    "display_name": "Standard Shield Generator",
    "type": "shield",
    "size": "small",

    "stats": {
        "shield_hp": 150,
        "regen_rate": 8.0,
        "regen_delay": 3.0,
        "regen_power_draw": 12.0
    },

    "assets": {
        "icon": "icon.png"
    }
}
```

```json
{
    "display_name": "Fast Burn Engine",
    "type": "engine",
    "size": "small",

    "stats": {
        "thrust_multiplier": 1.3,
        "max_speed_bonus": 50,
        "mass_addition": 100
    },

    "assets": {
        "icon": "icon.png"
    }
}
```

```json
{
    "display_name": "Heavy Power Plant",
    "type": "powerplant",
    "size": "medium",

    "stats": {
        "power_capacity": 200,
        "power_regen": 30.0,
        "mass_addition": 250
    },

    "assets": {
        "icon": "icon.png"
    }
}
```

```json
{
    "display_name": "Reinforced Armor Plating",
    "type": "armor",
    "size": "small",

    "stats": {
        "hull_hp_bonus": 80,
        "damage_reduction": 0.1,
        "mass_addition": 200,
        "speed_penalty": 25
    },

    "assets": {
        "icon": "icon.png"
    }
}
```

**Module stats vary by type.** The loader doesn't enforce a universal stat schema — it passes the `stats` dictionary to whatever system consumes that module type. Shield stats go to the shield system, engine stats go to physics, etc.

---

## Ship Instance vs Ship Definition

This is a critical architectural distinction:

| Concept | What It Is | Where It Lives |
|---|---|---|
| **Ship Definition** | The hull — what the ship *is* (stats, slots, hardpoints) | `/content/ships/<id>/ship.json` |
| **Ship Loadout** | What's currently installed on a specific ship instance | Runtime state / save data |
| **Default Loadout** | What comes pre-installed on a new ship of this type | `ship.json` (optional field) |

```json
{
    "display_name": "Light Fighter",
    "class": "fighter",
    "hull": { ... },
    "hardpoints": [ ... ],
    "module_slots": [ ... ],

    "default_loadout": {
        "weapons": {
            "hp_nose": "autocannon_light",
            "hp_port_wing": "pulse_laser",
            "hp_stbd_wing": "pulse_laser"
        },
        "modules": {
            "slot_shield": "shield_standard",
            "slot_engine": "engine_fast",
            "slot_power": "powerplant_heavy",
            "slot_armor": "armor_reinforced"
        }
    }
}
```

`default_loadout` maps slot IDs to content IDs (folder names). When a ship is spawned without a specific loadout (e.g. an AI patrol ship), it uses the default. When the player customizes their ship (post-MVP), their loadout overrides the default and is stored in save data.

**MVP behavior:** All ships spawn with their `default_loadout`. No runtime swapping.

---

## Content Registry

A singleton service that scans the content directories on startup and indexes all available content.

```gdscript
# ContentRegistry.gd — registered as autoload or via ServiceLocator

var ships: Dictionary = {}       # id → ship data dict
var weapons: Dictionary = {}     # id → weapon data dict
var modules: Dictionary = {}     # id → module data dict

func _ready() -> void:
    _scan_directory("res://content/ships", ships, "ship.json")
    _scan_directory("res://content/weapons", weapons, "weapon.json")
    _scan_directory("res://content/modules", modules, "module.json")
    print("ContentRegistry: loaded %d ships, %d weapons, %d modules" %
        [ships.size(), weapons.size(), modules.size()])

func _scan_directory(base_path: String, target: Dictionary, json_filename: String) -> void:
    var dir = DirAccess.open(base_path)
    if dir == null:
        push_warning("ContentRegistry: cannot open %s" % base_path)
        return
    dir.list_dir_begin()
    var folder_name = dir.get_next()
    while folder_name != "":
        if dir.current_is_dir() and not folder_name.begins_with("."):
            var json_path = "%s/%s/%s" % [base_path, folder_name, json_filename]
            if FileAccess.file_exists(json_path):
                var data = _load_json(json_path)
                if data != null:
                    data["_id"] = folder_name
                    data["_base_path"] = "%s/%s" % [base_path, folder_name]
                    target[folder_name] = data
        folder_name = dir.get_next()

func get_ship(id: String) -> Dictionary:
    return ships.get(id, {})

func get_weapon(id: String) -> Dictionary:
    return weapons.get(id, {})

func get_module(id: String) -> Dictionary:
    return modules.get(id, {})

func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
    var assets = content_data.get("assets", {})
    var filename = assets.get(asset_key, "")
    if filename.is_empty():
        return ""
    return "%s/%s" % [content_data["_base_path"], filename]
```

**Usage:**

```gdscript
# Spawning a ship:
var ship_data = ContentRegistry.get_ship("fighter_light")
var model_path = ContentRegistry.get_asset_path(ship_data, "model")

# Getting a weapon for a hardpoint:
var weapon_data = ContentRegistry.get_weapon("autocannon_light")
```

---

## Ship Spawning Flow

How a ship goes from JSON data to a playable entity:

```
1. Decide which ship to spawn (by content ID)
2. ContentRegistry.get_ship(id) → ship data dict
3. Instantiate Ship.tscn (the shared ship scene)
4. Ship._ready() reads the data dict:
    a. Set hull stats (hp, mass, drag, thrust, etc.)
    b. Create hardpoint nodes at defined offsets
    c. Load default_loadout weapons from ContentRegistry
    d. Load default_loadout modules from ContentRegistry
    e. Load and attach the 3D model
5. If player ship: add to "player" group, camera follows
6. If AI ship: attach AIController, add to "ai_ships" group
```

**One Ship.tscn, many configurations.** There is no `FighterShip.tscn` vs `DestroyerShip.tscn`. Every ship is the same scene, configured at spawn time from data. This is essential for the content system to work — new ships don't require new scenes.

```gdscript
# ShipFactory.gd (or inline in a spawner)

func spawn_ship(ship_id: String, pos: Vector2, is_player: bool = false,
                loadout_override: Dictionary = {}) -> Node:
    var ship_data = ContentRegistry.get_ship(ship_id)
    if ship_data.is_empty():
        push_error("ShipFactory: unknown ship '%s'" % ship_id)
        return null

    var ship = preload("res://gameplay/entities/Ship.tscn").instantiate()
    ship.global_position = pos
    ship.initialize(ship_data, loadout_override)

    if is_player:
        ship.add_to_group("player")
    else:
        var ai = preload("res://gameplay/ai/AIController.tscn").instantiate()
        ship.add_child(ai)
        ship.add_to_group("ai_ships")

    return ship
```

---

## Active Ship Tracking

The player's currently piloted ship is tracked by a lightweight reference — not by the camera, not by the input system, not by any single system. A global reference that any system can query:

```gdscript
# PlayerState.gd — autoload or ServiceLocator service

var active_ship: Node = null

func set_active_ship(ship: Node) -> void:
    active_ship = ship
    GameEventBus.emit("player_ship_changed", { "ship": ship })

func get_active_ship() -> Node:
    return active_ship
```

When the player changes ships (post-MVP), this is the only thing that changes. The camera calls `follow(PlayerState.active_ship)`, input routes to `PlayerState.active_ship`, UI reads from `PlayerState.active_ship`. No system has a hardcoded reference to "the player."

---

## Migration from Monolithic JSON

The existing `weapons.json` should be split into per-weapon folders. The `damage_types.json` stays as-is — it's a global lookup table, not per-item content.

### Before (current):
```
/data/
    weapons.json         (all weapons in one file)
    damage_types.json
```

### After:
```
/content/
    /weapons/
        /autocannon_light/weapon.json
        /beam_laser/weapon.json
        /pulse_laser/weapon.json
        /missile_heat/weapon.json
        /rocket_dumb/weapon.json
/data/
    damage_types.json    (stays — global config, not content)
    ai_profiles.json     (stays — global config, not content)
```

**Rule of thumb:** If it's a *thing the player can see, equip, or interact with*, it's content → `/content/`. If it's a *system configuration table*, it's data → `/data/`.

---

## Modding Support

The folder-per-item structure is inherently mod-friendly. A mod is just additional folders:

```
/mods/
    /my_weapon_pack/
        /content/
            /weapons/
                /plasma_repeater/
                    weapon.json
                    model.glb
                    icon.png
```

The `ContentRegistry` would scan mod directories after scanning the base game. Mods can also override base content by using the same folder name — last-loaded wins. This is future work but the architecture supports it without changes.

---

## Performance Instrumentation

Content loading happens at startup — no per-frame cost. Instrument the initial scan:

```gdscript
func _ready() -> void:
    PerformanceMonitor.begin("ContentRegistry.load")
    _scan_directory("res://content/ships", ships, "ship.json")
    _scan_directory("res://content/weapons", weapons, "weapon.json")
    _scan_directory("res://content/modules", modules, "module.json")
    PerformanceMonitor.end("ContentRegistry.load")
```

No custom monitor registration — this is a one-time cost, not a per-frame metric.

---

## Files

```
/core/services/
    ContentRegistry.gd
    PlayerState.gd
/gameplay/entities/
    ShipFactory.gd           (or inline in scene manager)
/content/
    /ships/                  (one folder per ship)
    /weapons/                (one folder per weapon)
    /modules/                (one folder per module)
/data/
    damage_types.json        (global config — stays here)
    ai_profiles.json         (global config — stays here)
```

---

## Dependencies

- `ContentRegistry` must load before any ship spawns (register via ServiceLocator or autoload)
- `PlayerState` must be available before camera or input initialization
- `GameEventBus` for `player_ship_changed` events
- Ship.tscn must support data-driven initialization via `initialize(ship_data, loadout)`

---

## Assumptions (Revisit Later)

- Asset paths in JSON are relative to the item's folder — this works for `res://` but may need adjustment for user-mod directories
- `default_loadout` is assumed to always be valid — no validation that referenced weapons/modules actually exist (add validation post-MVP)
- Module stat application is deferred — MVP ships use hull stats directly without module modification
- No hot-reloading of content at runtime — game must restart to pick up new content folders

---

## Success Criteria

- [ ] ContentRegistry loads all ships, weapons, and modules from folder structure on startup
- [ ] A new ship can be added by creating a folder with `ship.json` — no code changes required
- [ ] A new weapon can be added by creating a folder with `weapon.json` — no code changes required
- [ ] Ship spawning works from data — `ShipFactory.spawn_ship("fighter_light", pos)` produces a configured ship
- [ ] AI ships and player ship use the same Ship.tscn, differentiated only by data and attached components
- [ ] `PlayerState.active_ship` correctly tracks the current player ship
- [ ] Weapon data migration from monolithic `weapons.json` to per-weapon folders produces identical behavior
- [ ] `damage_types.json` and `ai_profiles.json` remain in `/data/` as global config
