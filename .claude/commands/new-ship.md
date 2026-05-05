Create a new ship class for All Space following the exact content architecture.

Arguments: $ARGUMENTS
Expected format: `<class_id> <class_type>`
  - class_id: folder name and content ID (e.g. `fighter_light`, `corvette_patrol`)
  - class_type: broad category for naming and role (e.g. `fighter`, `corvette`, `frigate`, `destroyer`)

## What to do

1. Read `docs/spec/feature_spec-ship_system.md` sections 4–6 to confirm the current schema before generating anything.

2. Create the folder `content/ships/<class_id>/` if it does not exist.

3. Create `content/ships/<class_id>/ship.json` using the schema below. Every field is required. Placeholder values are marked with `// TUNE` — do not remove the comment, leave it inline so it's obvious during balancing.

4. Report what was created and remind the user that `parts.glb` and `icon.png` must be added to the folder before ContentRegistry can fully load this class.

## ship.json schema

```json
{
    "ship_class": "<class_id>",
    "display_name": "<Human-readable class name>",
    "class": "<class_type>",
    "description": "<One sentence describing this ship's role and feel.>",

    "base_stats": {
        "hp":                      100,     // TUNE
        "mass":                    1000,    // TUNE — kg; drives inertia and turn lag
        "max_speed":               400,     // TUNE — world units/sec
        "linear_drag":             0.5,     // TUNE — low = near drag-free coast
        "alignment_drag":          1.5,     // TUNE — lateral bleed; low = wide turns
        "thruster_force":          10000,   // TUNE — N; shared budget for thrust + torque
        "torque_thrust_ratio":     0.3,     // TUNE — torque cost per unit of thrust budget
        "power_capacity":          200,     // TUNE
        "power_regen":             40,      // TUNE — units/sec
        "shield_max":              100,     // TUNE
        "shield_regen_rate":       10,      // TUNE — HP/sec while regenerating
        "shield_regen_delay":      4.0,     // TUNE — seconds after last hit before regen
        "shield_regen_power_draw": 15       // TUNE — power/sec while regenerating
    },

    "variants": {
        "<class_id>_standard": {
            "display_name": "<Neutral name>",
            "faction_display_names": {
                "militia":   "<Militia name>",
                "pirate":    "<Pirate name>",
                "megacorp":  "<Megacorp name>",
                "scavenger": "<Scavenger name>"
            },
            "rarity": "common",
            "parts": {
                "hull":   "<hull_node_name_in_parts_glb>",
                "engine": "<engine_node_name_in_parts_glb>"
            }
        }
    },

    "part_stats": {
        "<hull_node_name_in_parts_glb>":   { "hp": 100, "mass": 200 },  // TUNE
        "<engine_node_name_in_parts_glb>": { "thruster_force": 2000 }   // TUNE
    },

    "hardpoint_types": {
        "hp_nose":   "fixed"
    },

    "module_slots": [
        { "id": "slot_shield",    "type": "shield",      "size": "medium" },
        { "id": "slot_engine",    "type": "engine",      "size": "medium" },
        { "id": "slot_power",     "type": "powerplant",  "size": "medium" },
        { "id": "slot_armor",     "type": "armor",       "size": "medium" }
    ],

    "default_loadout": {
        "weapons": {
            "hp_nose": "autocannon_light"
        },
        "fire_groups": {
            "hp_nose": [0]
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

## Rules to follow

- The `class_id` is the folder name and is the content ID used in code. Use snake_case.
- The `parts` dictionary in each variant is freeform — category keys (`"hull"`, `"engine"`) are documentation only; code iterates values and ignores keys.
- Every part node name that appears in `variants[].parts` must have a corresponding entry in `part_stats`. Missing entries emit a warning and are treated as zero delta — but the warning is a signal something is wrong.
- Hardpoint IDs in `hardpoint_types` and `default_loadout.fire_groups` must match the `HardpointEmpty_{id}_{size}` naming convention baked into the GLB by the artist.
- Do not add fields that are not in the schema. ContentRegistry ignores unknown fields silently, making debugging harder.
- All stat values are placeholders until playtesting. Mark them `// TUNE`.
