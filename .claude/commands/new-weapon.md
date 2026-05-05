Create a new weapon for All Space following the exact content architecture.

Arguments: $ARGUMENTS
Expected format: `<weapon_id> <archetype>`
  - weapon_id: folder name and content ID (e.g. `autocannon_heavy`, `beam_laser_mk2`)
  - archetype: one of `ballistic` | `energy_beam` | `energy_pulse` | `missile_dumb` | `missile_guided`

## What to do

1. Read `docs/spec/feature_spec-weapons_and_projectiles.md` sections 5 and 11 to confirm the current schema before generating anything.

2. Create the folder `content/weapons/<weapon_id>/` if it does not exist.

3. Create `content/weapons/<weapon_id>/weapon.json` using the archetype-specific schema below. Use the correct schema for the requested archetype — each archetype has a different `stats` block. Placeholder values are marked `// TUNE`.

4. Report what was created and remind the user that `model.glb` and `icon.png` must be added to the folder, and that `model.glb` must contain a `Muzzle` (Marker3D) child node for correct projectile spawn position.

## Archetype schemas

### ballistic
```json
{
    "display_name": "<Human-readable name>",
    "archetype": "ballistic",
    "size": "small",
    "stats": {
        "damage":                  18,    // TUNE
        "fire_rate":               8.0,   // TUNE — shots per second
        "muzzle_speed":            900,   // TUNE — world units/sec
        "heat_per_shot":           12,    // TUNE
        "power_per_shot":          0,
        "component_damage_ratio":  0.15,  // TUNE — fraction routed to hardpoint HP
        "projectile_lifetime":     1.8,   // TUNE — seconds before self-destruct
        "ammo_capacity":           500    // TUNE
    },
    "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### energy_beam
```json
{
    "display_name": "<Human-readable name>",
    "archetype": "energy_beam",
    "size": "medium",
    "stats": {
        "damage_per_second":       80,    // TUNE
        "heat_per_second":         30,    // TUNE
        "power_per_second":        25,    // TUNE — competes with shield regen
        "component_damage_ratio":  0.1,   // TUNE
        "range":                   600    // TUNE — world units
    },
    "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### energy_pulse
```json
{
    "display_name": "<Human-readable name>",
    "archetype": "energy_pulse",
    "size": "small",
    "stats": {
        "damage":                  22,    // TUNE
        "fire_rate":               6.0,   // TUNE — shots per second
        "heat_per_shot":           8,     // TUNE
        "power_per_shot":          10,    // TUNE
        "component_damage_ratio":  0.08,  // TUNE
        "range":                   500    // TUNE — world units
    },
    "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### missile_dumb
```json
{
    "display_name": "<Human-readable name>",
    "archetype": "missile_dumb",
    "size": "medium",
    "stats": {
        "damage":                  180,   // TUNE
        "blast_radius":            80,    // TUNE — world units
        "speed":                   600,   // TUNE — world units/sec
        "component_damage_ratio":  0.2,   // TUNE
        "projectile_lifetime":     3.0,   // TUNE — seconds before self-destruct
        "ammo_capacity":           12     // TUNE
    },
    "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

### missile_guided
```json
{
    "display_name": "<Human-readable name>",
    "archetype": "missile_guided",
    "size": "medium",
    "stats": {
        "damage":                  220,       // TUNE
        "blast_radius":            80,        // TUNE — world units
        "speed":                   420,       // TUNE — world units/sec
        "turn_rate":               90,        // TUNE — degrees/sec; primary difficulty knob
        "fuel":                    4.0,       // TUNE — seconds until self-destruct
        "guidance":                "auto_lock", // auto_lock | track_cursor | click_lock
        "lock_cone_degrees":       60,        // TUNE — forward cone for auto_lock acquisition
        "component_damage_ratio":  0.2,       // TUNE
        "ammo_capacity":           6          // TUNE
    },
    "assets": { "model": "model.glb", "icon": "icon.png" }
}
```

## Rules to follow

- The `weapon_id` is the folder name and content ID. Use snake_case.
- `size` must be `"small"`, `"medium"`, or `"large"` — this constrains which hardpoints can mount the weapon.
- Do not mix stat fields between archetypes. `damage_per_second` belongs only to `energy_beam`; `damage` + `fire_rate` belongs to discrete-shot archetypes. Using the wrong fields causes silent errors.
- All stat values are placeholders. Mark them `// TUNE`. Do not invent final balance values.
- `component_damage_ratio` controls what fraction of a hit routes to hardpoint HP vs ship hull HP. Default low — increase if hardpoint destruction feels too rare during playtesting.
