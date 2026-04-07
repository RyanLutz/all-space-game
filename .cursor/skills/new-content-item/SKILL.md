---
name: new-content-item
description: Creates a new ship, weapon, or module for All Space following the folder-per-item content architecture. Use when the user wants to add a new ship, weapon, or module to the game, or asks about content/item structure under /content/.
---

# New Content Item

All Space uses a folder-per-item architecture. Every ship, weapon, and module is a self-contained folder. Adding content = adding a folder. No code changes required.

**Full spec:** `docs/Ship_Content_Data_Architecture_Spec.md`

## Workflow

1. Determine item type: `ship`, `weapon`, or `module`
2. Choose an ID — the folder name IS the ID (lowercase, underscores: `autocannon_light`)
3. Create the folder at the correct path
4. Write the JSON from the template below
5. Note which asset files are needed (glb, icon.png)
6. `ContentRegistry` auto-picks it up on next launch — no code changes

## Folder Paths

```
content/ships/<id>/       ship.json + model.glb + icon.png
content/weapons/<id>/     weapon.json + model.glb + icon.png
content/modules/<id>/     module.json + icon.png  (no model needed)
```

---

## Ship Template (`ship.json`)

```json
{
  "_comment": "<display_name> hull definition. See docs/Ship_Content_Data_Architecture_Spec.md.",
  "display_name": "My Ship",
  "class": "fighter",
  "description": "One-sentence description.",
  "behavior_profile": "default",

  "hull": {
    "hp": 200,
    "mass": 800,
    "max_speed": 450,
    "linear_drag": 0.8,
    "alignment_drag": 0.2,
    "thruster_force": 12000,
    "torque_thrust_ratio": 0.3,
    "power_capacity": 100,
    "power_regen": 15,
    "shield_max": 120,
    "regen_rate": 10,
    "regen_delay": 3.0,
    "regen_power_draw": 10
  },

  "hardpoints": [
    {
      "id": "hp_nose",
      "offset": [32, 0],
      "facing": 0,
      "type": "gimbal",
      "size": "small",
      "groups": ["primary"]
    }
  ],

  "module_slots": [
    { "id": "slot_shield", "type": "shield",     "size": "small" },
    { "id": "slot_engine", "type": "engine",     "size": "small" },
    { "id": "slot_power",  "type": "powerplant", "size": "small" },
    { "id": "slot_armor",  "type": "armor",      "size": "small" }
  ],

  "default_loadout": {
    "weapons": {
      "hp_nose": "autocannon_light"
    },
    "modules": {
      "slot_shield": "shield_standard",
      "slot_engine": "engine_fast",
      "slot_power":  "powerplant_heavy",
      "slot_armor":  "armor_reinforced"
    }
  },

  "assets": {
    "model": "model.glb",
    "icon":  "icon.png"
  }
}
```

### Hull property reference

| Property | Effect |
|---|---|
| `hp` | Base hit points |
| `mass` | Affects inertia and torque |
| `max_speed` | Soft cap (drag increases above this) |
| `linear_drag` | Base drag coefficient |
| `alignment_drag` | Lateral velocity bleed on turns |
| `thruster_force` | Shared budget for thrust/strafe/torque |
| `torque_thrust_ratio` | Turning cost fraction (0.3 = turns cost 30%) |
| `power_capacity` | Ship power pool size |
| `power_regen` | Power/sec restored passively |
| `shield_max` | Shield hit points |
| `regen_rate` | Shield HP/sec during regen |
| `regen_delay` | Seconds after hit before regen starts |
| `regen_power_draw` | Power/sec consumed while regenerating |

### Hardpoint types
- `fixed` — locked to ship facing
- `gimbal` — limited arc (small aim correction)
- `partial_turret` — wider arc, slower traverse
- `full_turret` — 360°, slowest traverse

### `default_loadout` maps hardpoint/slot IDs → content IDs (folder names)

---

## Weapon Template (`weapon.json`)

**Archetypes and their required stats differ — use the correct template.**

### ballistic
```json
{
  "_comment": "<name> — ballistic projectile weapon. See docs/Weapons_Projectiles_Spec.md.",
  "display_name": "My Weapon",
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
  "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### energy_beam (continuous hitscan, held fire)
```json
{
  "_comment": "<name> — continuous hitscan energy beam. See docs/Weapons_Projectiles_Spec.md.",
  "display_name": "My Beam",
  "archetype": "energy_beam",
  "size": "medium",
  "fire_rate": 60.0,
  "damage_per_second": 80,
  "heat_per_second": 30,
  "power_per_second": 25,
  "heat_per_shot": 0.5,
  "power_per_shot": 0.417,
  "component_damage_ratio": 0.1,
  "range": 600,
  "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### energy_pulse (hitscan rapid discrete shots)
```json
{
  "_comment": "<name> — rapid-fire hitscan energy pulse. See docs/Weapons_Projectiles_Spec.md.",
  "display_name": "My Pulse",
  "archetype": "energy_pulse",
  "size": "small",
  "stats": {
    "damage": 10,
    "fire_rate": 12.0,
    "heat_per_shot": 8,
    "power_per_shot": 6,
    "component_damage_ratio": 0.05,
    "range": 500
  },
  "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### missile_dumb
```json
{
  "_comment": "<name> — unguided rocket. See docs/Weapons_Projectiles_Spec.md.",
  "display_name": "My Rocket",
  "archetype": "missile_dumb",
  "size": "medium",
  "stats": {
    "damage": 120,
    "fire_rate": 0.5,
    "muzzle_speed": 600,
    "heat_per_shot": 5,
    "power_per_shot": 0,
    "component_damage_ratio": 0.3,
    "projectile_lifetime": 3.0
  },
  "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### missile_guided
```json
{
  "_comment": "<name> — guided missile. See docs/Weapons_Projectiles_Spec.md.",
  "display_name": "My Missile",
  "archetype": "missile_guided",
  "size": "medium",
  "guidance_mode": "auto_lock",
  "stats": {
    "damage": 180,
    "fire_rate": 0.3,
    "muzzle_speed": 400,
    "turn_rate": 120,
    "heat_per_shot": 5,
    "power_per_shot": 0,
    "component_damage_ratio": 0.4,
    "projectile_lifetime": 6.0
  },
  "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

**Guidance modes:** `track_cursor`, `auto_lock`, `click_lock`

**Sizes:** `small`, `medium`, `large` — must match the hardpoint size the weapon mounts in.

---

## Module Template (`module.json`)

Pick the template matching the `type`. Stats vary per type — the loader passes the `stats` dict straight to the consuming system.

### shield
```json
{
  "display_name": "My Shield",
  "type": "shield",
  "size": "small",
  "stats": { "shield_hp": 150, "regen_rate": 8.0, "regen_delay": 3.0, "regen_power_draw": 12.0 },
  "assets": { "icon": "icon.png" }
}
```

### engine
```json
{
  "display_name": "My Engine",
  "type": "engine",
  "size": "small",
  "stats": { "thrust_multiplier": 1.3, "max_speed_bonus": 50, "mass_addition": 100 },
  "assets": { "icon": "icon.png" }
}
```

### powerplant
```json
{
  "display_name": "My Powerplant",
  "type": "powerplant",
  "size": "medium",
  "stats": { "power_capacity": 200, "power_regen": 30.0, "mass_addition": 250 },
  "assets": { "icon": "icon.png" }
}
```

### armor
```json
{
  "display_name": "My Armor",
  "type": "armor",
  "size": "small",
  "stats": { "hull_hp_bonus": 80, "damage_reduction": 0.1, "mass_addition": 200, "speed_penalty": 25 },
  "assets": { "icon": "icon.png" }
}
```

---

## Checklist

- [ ] Folder name chosen (this is the item ID — no spaces, lowercase, underscores)
- [ ] Folder created at correct path under `content/`
- [ ] JSON created with correct template for type and archetype
- [ ] No hardcoded tunable values — all numbers are in JSON
- [ ] `default_loadout` references valid content IDs (other folder names that exist)
- [ ] `assets` section lists filenames relative to the item folder
- [ ] If this is a new ship for testing: wire it up in `test/TestScene.gd` via `ShipFactory.spawn_ship()`
