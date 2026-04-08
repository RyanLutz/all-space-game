# Station Docking & Loadout UI Specification
*All Space Combat MVP — Station Approach, Docking, and Ship Customization*

## Overview

Stations are static world objects that let the player pause combat and reconfigure their
ship's weapons and modules. The player flies close to a station, presses a dock key, and
a fullscreen loadout screen opens. From there they can swap weapons into hardpoints and
swap modules into module slots. Closing the loadout undocks and returns control.

**Design Goals:**
- Complete the "fly, fight, dock, customize, repeat" MVP loop
- Docking mechanics use the existing `GameEventBus` signals (`dock_requested`, `dock_complete`,
  `undock_requested`) — all three signals are already defined in `GameEventBus.gd`
- Loadout UI shows current configuration and all available items; player clicks slot then
  item to equip — no drag-and-drop for MVP
- Module stat application is MVP-scoped: weapons swap fully; module stat bonuses are
  applied additively on top of base hull stats at dock time

---

## Architecture

```
Station (StaticBody2D)
    └── DockZone (Area2D)             ← detects player proximity

LoadoutUI (CanvasLayer — layer 5)
    ├── Background (ColorRect)        ← dims the game world
    ├── ShipInfoPanel (VBoxContainer) ← display_name, class, current hull stats
    ├── HardpointsPanel (GridContainer)
    │       └── HardpointSlotButton × N  ← one per hardpoint
    ├── ModuleSlotsPanel (GridContainer)
    │       └── ModuleSlotButton × N     ← one per module slot
    ├── ItemListPanel (VBoxContainer) ← compatible items for selected slot
    │       └── ItemButton × N
    └── UndockButton (Button)
```

`Station.gd` listens on `dock_requested` to validate proximity and emit `dock_complete`.
`LoadoutUI.gd` listens on `dock_complete` to open; listens on `undock_requested` to close.
Both communicate exclusively through `GameEventBus`.

`LoadoutUI` is added to the root by `GameBootstrap` at startup — it exists in the scene
tree but stays hidden until `dock_complete` fires.

---

## Core Properties / Data Model

### Station (`Station.gd`)

```gdscript
@export var station_id: String = "station_01"
@export var display_name: String = "Station"
@export var dock_range: float = 200.0   # radius of DockZone shape
```

Runtime state:
- `_docked_ship: Node2D` — null when no ship is docked; set during `dock_complete`.

### LoadoutUI (`LoadoutUI.gd`)

```gdscript
var _ship: Ship                    # ship currently being configured
var _station: Node2D               # station we're docked at
var _selected_slot_id: String      # hardpoint or module slot ID
var _selected_slot_type: String    # "weapon" | "module"
var _event_bus: Node
var _content_registry: Node
```

### Slot State (runtime dictionary, not persisted)

For each slot the UI tracks:
```
{
    "id": "hp_nose",
    "type": "weapon" | "module",
    "slot_type_filter": "primary" | "shield" | ...,  # from ship.json
    "equipped_item_id": "autocannon_light"            # or "" if empty
}
```

---

## Key Algorithms

### Dock Trigger (Station.gd)

```gdscript
func _on_dock_zone_body_entered(body: Node) -> void:
    if body is Ship and body.is_player_controlled:
        _nearby_player = body

func _on_dock_zone_body_exited(body: Node) -> void:
    if body == _nearby_player:
        _nearby_player = null

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("dock") and _nearby_player != null:
        _event_bus.emit_signal("dock_requested", _nearby_player, self)

# Listens on dock_requested
func _on_dock_requested(ship: Node2D, station: Node2D) -> void:
    if station != self:
        return
    _docked_ship = ship
    ship.set_physics_process(false)   # freeze ship movement
    ship.set_process(false)
    _event_bus.emit_signal("dock_complete", ship, self)
```

### Open Loadout (LoadoutUI.gd)

```gdscript
func _on_dock_complete(ship: Node2D, station: Node2D) -> void:
    _ship = ship as Ship
    _station = station
    _build_ui()
    visible = true
    get_tree().paused = false  # don't pause; ship is frozen, AI can idle
```

### Build UI

Called once per dock. Clears and repopulates:

1. Ship info: read `_ship._pending_ship_data` for `display_name`, `class`, current
   `hull_hp`, `shield_hp`, `power_current`.
2. Hardpoint slots: iterate `_ship._pending_ship_data["hardpoints"]`; for each, create
   a `HardpointSlotButton` labelled with the hardpoint ID. Query
   `_ship._weapon_component` for the current weapon equipped at that hardpoint.
3. Module slots: iterate `_ship._pending_ship_data["module_slots"]`; for each, create
   a `ModuleSlotButton`. Read `_ship._active_modules` (a Dictionary `slot_id → module_id`)
   for what's currently installed.
4. Item list starts empty — populated when a slot is selected.

### Slot Selection

```gdscript
func _on_slot_pressed(slot_id: String, slot_type: String, slot_filter: String) -> void:
    _selected_slot_id = slot_id
    _selected_slot_type = slot_filter  # "weapon" archetype group or module type
    _populate_item_list(slot_type, slot_filter)
```

### Populate Item List

For `slot_type == "weapon"`:
```gdscript
for id in _content_registry.weapons.keys():
    var weapon = _content_registry.get_weapon(id)
    # Filter by hardpoint size compatibility (same or smaller)
    var hp_size = _get_hardpoint_size(slot_id)
    if _size_ok(weapon.get("size", "small"), hp_size):
        _add_item_button(id, weapon.get("display_name", id))
```

For `slot_type == "module"`:
```gdscript
for id in _content_registry.modules.keys():
    var module = _content_registry.get_module(id)
    if module.get("type", "") == slot_filter:
        _add_item_button(id, module.get("display_name", id))
```

### Apply Weapon

```gdscript
func _on_item_selected(item_id: String) -> void:
    if _selected_slot_type == "weapon":
        _equip_weapon(_selected_slot_id, item_id)
    else:
        _equip_module(_selected_slot_id, item_id)
    _refresh_slot_display(_selected_slot_id)
    _event_bus.emit_signal("loadout_changed", _ship, _selected_slot_id, item_id)

func _equip_weapon(hardpoint_id: String, weapon_id: String) -> void:
    var weapon_data = _content_registry.get_weapon(weapon_id)
    if weapon_data.is_empty():
        return
    # WeaponComponent exposes a method to swap one hardpoint's weapon.
    _ship._weapon_component.set_hardpoint_weapon(hardpoint_id, weapon_data)
```

### Apply Module (MVP-scoped stat patch)

MVP applies modules additively as stat deltas on top of base hull values. Because
`Ship._apply_hull_stats()` reads from JSON once at spawn, we store a separate
`_active_modules` dictionary on `Ship` and re-derive stats whenever modules change.

```gdscript
func _equip_module(slot_id: String, module_id: String) -> void:
    var module_data = _content_registry.get_module(module_id)
    if module_data.is_empty():
        return
    _ship._active_modules[slot_id] = module_id
    _ship.apply_module_stats()   # new Ship method — see below
```

`Ship.apply_module_stats()` sums all installed module stat bonuses and applies them:
```gdscript
func apply_module_stats() -> void:
    # Reset to base hull stats first
    _apply_hull_stats(_pending_ship_data.get("hull", {}))
    power_current = minf(power_current, power_capacity)
    shield_hp = minf(shield_hp, shield_max)
    hull_hp = minf(hull_hp, hull_max)
    # Clamp HP pools so we don't exceed new maxima mid-flight
    # Module bonuses stack additively
    for slot_id in _active_modules.keys():
        var mid: String = _active_modules[slot_id]
        var mdata = _content_registry_ref.get_module(mid)
        if mdata.is_empty():
            continue
        var stats: Dictionary = mdata.get("stats", {})
        shield_max  += float(stats.get("shield_hp", 0))
        regen_rate  += float(stats.get("regen_rate", 0))
        regen_delay  = maxf(0.1, regen_delay - float(stats.get("regen_delay_reduce", 0)))
        power_capacity += float(stats.get("power_capacity", 0))
        # hull_hp bonus would be permanent after first application — skip for MVP
```

### Undock

```gdscript
func _on_undock_pressed() -> void:
    _event_bus.emit_signal("undock_requested", _ship)

# Listens on undock_requested
func _on_undock_requested(ship: Node2D) -> void:
    if ship != _ship:
        return
    visible = false
    _ship.set_physics_process(true)
    _ship.set_process(true)
    if _station != null and _station.has_method("_on_undock"):
        _station._on_undock()
    _ship = null
    _station = null
```

On `Station.gd`:
```gdscript
func _on_undock() -> void:
    _docked_ship = null
```

### Hardpoint Size Compatibility Table

| Slot size | Can accept |
|-----------|-----------|
| small     | small      |
| medium    | small, medium |
| large     | small, medium, large |

---

## JSON Data Format

No new JSON data files are needed. The system reads from existing content:
- `content/ships/<id>/ship.json` — `hardpoints` and `module_slots` arrays
- `content/weapons/<id>/weapon.json` — used for filtering and display
- `content/modules/<id>/module.json` — used for filtering and stat application

One new signal entry is required in `GameEventBus.gd`:

```gdscript
signal loadout_changed(ship: Node2D, slot_id: String, item_id: String)
```

And in `docs/GameEventBus_Signals.md` (Station Signals table):

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `loadout_changed` | `ship: Node2D, slot_id: String, item_id: String` | LoadoutUI | (future: savegame, economy) |

---

## Performance Instrumentation

The loadout system is UI-only — it runs during a frozen game state (ship paused) and
fires at human interaction speed. No `PerformanceMonitor` instrumentation is required.
The station's `_unhandled_input` and `dock_requested` processing happen once per dock
event, not per frame.

---

## Files

| Path | Description |
|------|-------------|
| `gameplay/world/Station.gd` | Station logic: dock zone, proximity detection, dock/undock |
| `gameplay/world/Station.tscn` | Station scene: StaticBody2D + CollisionShape2D + Area2D + DockZone |
| `ui/loadout/LoadoutUI.gd` | Loadout screen logic |
| `ui/loadout/LoadoutUI.tscn` | Loadout screen scene (CanvasLayer) |
| `core/GameEventBus.gd` | Add `loadout_changed` signal |
| `docs/GameEventBus_Signals.md` | Document `loadout_changed` |
| `gameplay/entities/Ship.gd` | Add `_active_modules`, `_content_registry_ref`, `apply_module_stats()` |
| `gameplay/weapons/WeaponComponent.gd` | Add `set_hardpoint_weapon(id, data)` method |

Input map addition (project.godot):
- `"dock"` → key `E` (or `F`) — player triggers docking

---

## Dependencies

| Dependency | Why |
|-----------|-----|
| `GameEventBus.gd` | Signals `dock_requested`, `dock_complete`, `undock_requested` already defined |
| `ContentRegistry.gd` | Provides all weapons and modules for the item list |
| `Ship.gd` | Has `_weapon_component`, `_pending_ship_data`, hull stats methods |
| `WeaponComponent.gd` | Needs `set_hardpoint_weapon()` added |
| `ShipFactory.gd` | Spawns ships with `_active_modules = {}` initialized |
| `ServiceLocator.cs` | LoadoutUI and Station both get services via ServiceLocator |

---

## Assumptions

- The player never re-docks at a different station while the loadout UI is open.
- Only the player ship can dock; AI ships ignore stations.
- No credit/economy system in MVP — all items are freely available.
- Station visual (mesh/sprite) is out of scope for this spec; Station.tscn uses a
  placeholder `ColorRect` or simple polygon shape.
- Module unequipping (leaving a slot empty) is allowed; an empty slot simply contributes
  no stat bonus.
- The `dock` input action uses key `F` to avoid conflict with Godot's default `E` usage.
- `WeaponComponent.set_hardpoint_weapon()` finds the matching `HardpointComponent` child
  by `hardpoint_id` and calls `set_weapon(weapon_id, all_weapons_dict)`.

---

## Success Criteria

- [ ] Flying close to a station and pressing `F` opens the loadout screen
- [ ] Player ship freezes (no movement/rotation) while the loadout is open
- [ ] Loadout screen lists all hardpoints with their currently equipped weapon
- [ ] Loadout screen lists all module slots with their currently equipped module
- [ ] Clicking a hardpoint slot populates the item list with size-compatible weapons
- [ ] Clicking a module slot populates the item list with type-compatible modules
- [ ] Clicking an item in the list equips it to the selected slot (button label updates)
- [ ] Equipped weapon is immediately active when the player undocks and fires
- [ ] Clicking Undock closes the screen and restores ship movement
- [ ] `loadout_changed` signal fires once per item swap with correct args
- [ ] Pressing F outside dock range does nothing
- [ ] AI ships continue normal behavior while the player is docked
