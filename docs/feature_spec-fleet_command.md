# Fleet Command & Tactical Mode — Feature Specification

*All Space — RTS Fleet Control, Escort Queue, and Stance System*

---

## 1. Overview

Fleet Command is the system that lets the player command their fleet. It owns the
**Tactical mode** interface (selection, orders), the **escort queue** — a
player-curated ordered list of ships that fly in formation with the player in Pilot
mode — and the **stance system** that governs each ship's combat disposition.

It is the layer between player intent and `NavigationController` / `AIController`.
The player clicks, drags, right-clicks, and uses context menus; Fleet Command
translates those actions into `GameEventBus` signals. It does not fly ships or run
AI logic — it only turns intent into orders and propagates mode, queue, and stance
changes.

**Design goals:**

- The player commands their fleet with RTS conventions (drag-select, right-click on
  world; context menu on fleet ships).
- The player's own ship is just another fleet ship — selectable, orderable, and
  subject to the same routing as AI ships.
- Mode switching (`Tab`) is a signal, not a variable poll — every system that cares
  listens to `game_mode_changed`.
- Escort is **opt-in and explicit**: ships only fly formation with the player after
  the player adds them to the escort queue via context menu.
- Stance is **scope-aware**: per-ship when the ship is an independent fleet member;
  queue-shared when the ship joins the escort.
- All cross-system communication goes through `GameEventBus`. Fleet Command does not
  hold direct references to NavigationController, AIController, or Ship.

**Not in this system's scope:**

- How NavigationController computes per-ship input from a destination.
- How AIController decides when and how to engage. Stance is Fleet Command's concept;
  acting on it is AI's job.
- How a ship becomes part of the player's fleet (fleet composition is a future
  concern — ships are marked by `player_fleet` group membership).
- The visual design of the context menu, escort panel, or selection indicators.

---

## 2. Architecture

```
Scene Root
├── GameCamera (Camera3D)                   ← sibling of world, not child of any ship
├── World (chunks, ships, asteroids)
├── TacticalUI (CanvasLayer)
│   ├── SelectionBox (Control)              ← drag-select visual
│   ├── ContextMenu (Control)               ← multilevel menu on right-click of fleet ship
│   └── EscortPanel (Control)               ← visible only when queue is non-empty
└── FleetCommand                            ← this system
    ├── InputManager.gd                     ← Tab key → mode change; routes Pilot/Tactical input
    ├── TacticalInputHandler.gd             ← selection, right-click dispatch, context menu trigger, Stop key
    ├── SelectionState.gd                   ← current selected ship ids; cleared on mode switch
    ├── EscortQueue.gd                      ← ordered list of escort ship ids; queue-shared stance
    ├── FormationController.gd              ← pushes slot destinations for queue members in Pilot mode
    └── StanceController.gd                 ← per-ship stance for non-escort ships; read by AIController
```

Each sub-node owns one concern:

| Node | Responsibility |
|---|---|
| `InputManager` | Tab key handling, `game_mode_changed` emission, input routing switch for the player ship |
| `TacticalInputHandler` | Mouse input: selection, drag-box, right-click dispatch (context menu vs. order), Stop key |
| `SelectionState` | The current selection; listens for `ship_destroyed` to prune dead ships |
| `EscortQueue` | Ordered list of escort ship ids; owns queue-shared stance; emits `escort_queue_changed` |
| `FormationController` | Runs formation tick in Pilot mode; pushes slot destinations for queue members not away on orders |
| `StanceController` | Per-ship stance for non-escort ships; translates `ship_damaged` into Defensive fan-out |

### Responsibility Split

| Concern | Owner |
|---|---|
| Tab key → mode switch | InputManager |
| Drag-select, click-select, shift-click | TacticalInputHandler |
| Right-click target classification (fleet/enemy/asteroid/empty) | TacticalInputHandler |
| Right-click on fleet ship → open context menu | TacticalInputHandler → TacticalUI |
| Right-click on enemy/asteroid/empty → order signal | TacticalInputHandler |
| Stop key / Esc → cancel order | TacticalInputHandler |
| Current selection (ship ids) | SelectionState |
| Mode-driven input routing for player ship | InputManager |
| Tactical camera entry/exit (zoom, release, re-follow) | GameCamera (triggered by `game_mode_changed`) |
| Escort queue membership (add/remove, order) | EscortQueue |
| Escort queue stance | EscortQueue |
| Formation slot assignment & destinations | FormationController |
| Per-ship stance storage (non-escort ships) | StanceController |
| Stance → combat behavior | AIController |
| Destination → ship input | NavigationController |
| Capability check (can this ship attack? mine?) | TacticalInputHandler (filters selection before emitting) |

### Signal Flow (canonical examples)

**Entering Tactical mode:**
```
Player presses Tab
  → InputManager: _current_mode = "tactical"
  → InputManager emits game_mode_changed("pilot", "tactical")
  → GameCamera: releases follow, begins zoom-out animation, enables free-pan
  → InputManager: stops routing player input → player ship
  → FormationController: halts formation ticks (escort ships idle at last position)
  → SelectionState: clears selection
  → TacticalUI: enables selection/order interface
  (EscortPanel visibility is independent of mode — driven by queue size)
```

**Issuing a move order:**
```
Player right-clicks in Tactical mode on empty XZ-plane ground
  → TacticalInputHandler: raycast classifies target (no hit → empty space)
  → TacticalInputHandler: ray-plane intersection → destination: Vector3 (Y = 0)
  → TacticalInputHandler: filters selection to move-capable ships
  → TacticalInputHandler: determines queue_mode (Shift held? append : replace)
  → Emits request_tactical_move(ship_ids, destination, queue_mode)
  → NavigationController (per ship): sets destination, begins flight
```

**Right-click on fleet ship:**
```
Player right-clicks a fleet ship (any mode, any selection state)
  → TacticalInputHandler: raycast classifies target as player_fleet
  → TacticalInputHandler emits context_menu_requested(ship_id, screen_pos)
  → TacticalUI opens the multilevel context menu
  → Player selects Stance → Aggressive (or Escort → Add to escort, etc.)
  → TacticalUI emits the corresponding signal
```

**Adding a ship to escort:**
```
Player selects "Escort → Add to escort" on a fleet ship's context menu
  → TacticalUI emits request_tactical_add_to_escort(ship_id)
  → EscortQueue: appends ship_id to queue
  → EscortQueue: emits request_tactical_stop([ship_id])  (cancels current orders)
  → EscortQueue: clears ship's per-ship stance (queue stance applies now)
  → EscortQueue: emits escort_queue_changed(ship_ids)
  → EscortPanel (UI): updates display (or becomes visible if queue was empty)
  → FormationController: on next tick, ship takes its slot
```

**Defensive stance escalation (queue-shared):**
```
Enemy fires at a queue member; Ship emits ship_damaged(victim, attacker)
  → StanceController listens, detects victim is in escort queue
  → Reads EscortQueue.stance — if DEFENSIVE, fans out attack orders
  → For each queue member, emits request_tactical_attack([member], attacker_id, "replace")
  → AIController / NavigationController handles like any attack order
  → Each member becomes "away on orders" (slot reserved but empty)
  → When attacker is dead or lost, each member returns to its slot automatically
```

No direct method calls between systems. Every coordination point is a signal.

---

## 3. Core Properties / Data Model

### 3.1 InputManager

```gdscript
# InputManager.gd — autoload or scene-singleton

var _current_mode: String = "pilot"      # "pilot" | "tactical"
var _player_ship: Node = null            # set via player_ship_changed signal
```

### 3.2 SelectionState

```gdscript
# SelectionState.gd

var _selected_ids: Array[int] = []       # instance ids of currently selected ships

func get_selection() -> Array[int]: return _selected_ids.duplicate()
func is_selected(ship_id: int) -> bool: return ship_id in _selected_ids
```

Cleared on every `game_mode_changed`. Prunes destroyed ships on `ship_destroyed`.

### 3.3 EscortQueue

```gdscript
# EscortQueue.gd

enum Stance { HOLD_FIRE, DEFENSIVE, AGGRESSIVE }

var _queue: Array[int] = []                        # ordered list; index = slot position
var _away_on_orders: Dictionary = {}               # { ship_instance_id: bool }
var _stance: Stance = Stance.DEFENSIVE             # queue-shared

func get_queue() -> Array[int]: return _queue.duplicate()
func is_in_queue(ship_id: int) -> bool: return ship_id in _queue
func slot_index_of(ship_id: int) -> int: return _queue.find(ship_id)
func is_away(ship_id: int) -> bool: return _away_on_orders.get(ship_id, false)
func get_stance() -> Stance: return _stance
```

**Queue semantics:**

- Insertion order determines slot index (first added → slot 0).
- Removing a ship compacts slot indices (ship in slot 2 shifts to slot 1 if slot 0
  is removed).
- A ship "away on orders" retains its slot position. Its slot remains **reserved
  but empty** — no other queue member shifts into it. When the ship completes or
  stops its order, it returns to the same slot.

**Stance:**

- One `Stance` value applies to every ship in the queue.
- When a ship is added, its per-ship stance is overridden by the queue's stance.
- When a ship is removed, its stance resets to `Stance.DEFENSIVE`. Prior per-ship
  stance is not restored.

### 3.4 StanceController

```gdscript
# StanceController.gd

enum Stance { HOLD_FIRE, DEFENSIVE, AGGRESSIVE }

var _stances: Dictionary = {}                      # { ship_instance_id: Stance }
const DEFAULT_STANCE := Stance.DEFENSIVE
```

`StanceController` stores stance for **non-escort** fleet ships. When a ship is in
the escort queue, its effective stance is `EscortQueue.get_stance()`.

```gdscript
func get_effective_stance(ship_id: int) -> Stance:
    if EscortQueue.is_in_queue(ship_id):
        return EscortQueue.get_stance()
    return _stances.get(ship_id, DEFAULT_STANCE)
```

This is the single call AIController makes to read stance. It never cares whether
the value came from the per-ship map or the queue.

### 3.5 FormationController

```gdscript
# FormationController.gd

var _formation_def: Dictionary = {}       # parsed from formations/<default>/formation.json
var _tick_timer: Timer                    # ~0.25 s tick in Pilot mode only
```

Formation state is derived — the controller holds no persistent slot assignments.
Each tick it reads the queue and pushes destinations. A ship's slot is always
`EscortQueue.slot_index_of(ship_id)`.

---

## 4. Key Algorithms

### 4.1 Tab Key & Mode Transition

```gdscript
# InputManager._input(event)
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("toggle_mode"):     # Tab, mapped in InputMap
        var old_mode := _current_mode
        _current_mode = "tactical" if _current_mode == "pilot" else "pilot"
        GameEventBus.game_mode_changed.emit(old_mode, _current_mode)
```

Player ship input routing:

```gdscript
func _physics_process(delta: float) -> void:
    if _player_ship == null:
        return
    if _current_mode == "pilot":
        _route_pilot_input_to(_player_ship)
    # In Tactical, InputManager writes nothing to the player ship.
    # If the ship has an order, NavigationController drives it.
    # If not, input fields remain at zero.
```

### 4.2 Right-Click Target Classification

Right-click is **target-type-dispatched**, not selection-gated. The raycast classifies
the target; the target type decides the action.

```gdscript
# TacticalInputHandler._on_right_click(screen_pos: Vector2)
func _on_right_click(screen_pos: Vector2) -> void:
    var camera := get_viewport().get_camera_3d()
    var ray_origin := camera.project_ray_origin(screen_pos)
    var ray_dir    := camera.project_ray_normal(screen_pos)

    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(
        ray_origin, ray_origin + ray_dir * 10000.0)
    var hit := space.intersect_ray(q)

    if hit:
        var node: Node = hit.collider
        if node.is_in_group("player_fleet"):
            # Context menu — independent of selection state
            context_menu_requested.emit(node.get_instance_id(), screen_pos)
            return
        if node.is_in_group("enemies"):
            _dispatch_order("attack", node.get_instance_id())
            return
        if node.is_in_group("asteroids"):
            _dispatch_order("mine", node.get_instance_id())
            return

    # No target or un-classified hit — empty-space move order
    var destination := _ray_plane_intersect(ray_origin, ray_dir, 0.0)
    _dispatch_move_order(destination)
```

Selection is **irrelevant** for fleet-ship context menus. It is **required** for
attack/mine/move orders — an order with an empty selection is silently ignored.

```gdscript
func _dispatch_order(order_type: String, target_id: int) -> void:
    if SelectionState.get_selection().is_empty():
        return
    var queue_mode := "append" if Input.is_key_pressed(KEY_SHIFT) else "replace"
    var capable := _filter_capable(SelectionState.get_selection(), order_type)
    if capable.is_empty():
        return
    match order_type:
        "attack":
            GameEventBus.request_tactical_attack.emit(capable, target_id, queue_mode)
        "mine":
            GameEventBus.request_tactical_mine.emit(capable, target_id, queue_mode)
```

### 4.3 Context Menu Actions

The context menu is multilevel with two top-level entries:

- **Stance** — submenu: Hold Fire / Defensive / Aggressive
  - **Hidden** when the target ship is in the escort queue. Escort stance is set via
    the escort panel, not via individual context menus.
- **Escort** — submenu:
  - **Add to escort** — shown only if the ship is *not* in the queue
  - **Remove from escort** — shown only if the ship *is* in the queue

```gdscript
# TacticalUI, on context menu item selected:
func _on_stance_selected(ship_id: int, stance: int) -> void:
    GameEventBus.request_tactical_set_stance.emit(ship_id, stance)

func _on_add_to_escort(ship_id: int) -> void:
    GameEventBus.request_tactical_add_to_escort.emit(ship_id)

func _on_remove_from_escort(ship_id: int) -> void:
    GameEventBus.request_tactical_remove_from_escort.emit(ship_id)
```

The context menu works in **both Pilot and Tactical modes**.

### 4.4 Escort Queue Operations

```gdscript
# EscortQueue._on_request_add_to_escort(ship_id: int)
func _on_request_add_to_escort(ship_id: int) -> void:
    if ship_id in _queue:
        return
    # Cancel any active orders — escort takes priority
    GameEventBus.request_tactical_stop.emit([ship_id])

    _queue.append(ship_id)
    _away_on_orders[ship_id] = false
    # Ship adopts queue stance (no prior-stance preservation)
    StanceController.clear_ship_stance(ship_id)
    GameEventBus.escort_queue_changed.emit(_queue.duplicate())


# EscortQueue._on_request_remove_from_escort(ship_id: int)
func _on_request_remove_from_escort(ship_id: int) -> void:
    if ship_id not in _queue:
        return
    _queue.erase(ship_id)
    _away_on_orders.erase(ship_id)
    # Per-ship stance resets to default when leaving the queue
    StanceController.set_stance(ship_id, StanceController.DEFAULT_STANCE)
    GameEventBus.escort_queue_changed.emit(_queue.duplicate())


# EscortQueue._on_request_set_escort_stance(stance: int)
func _on_request_set_escort_stance(stance: int) -> void:
    _stance = stance as Stance
    GameEventBus.escort_stance_changed.emit(_stance)
```

Slot indices are not stored — they're always `_queue.find(ship_id)`. Slot
compaction on removal is automatic.

### 4.5 "Away on Orders" Tracking

A queue member that receives a tactical order has its slot **reserved but not
filled**. The ship remains in the queue and keeps its index.

```gdscript
# EscortQueue listens to order signals to mark queue members as away
func _on_request_tactical_move(ship_ids: Array, _dest, _qm) -> void:
    for id in ship_ids:
        if id in _queue:
            _away_on_orders[id] = true

func _on_request_tactical_attack(ship_ids: Array, _target, _qm) -> void:
    for id in ship_ids:
        if id in _queue:
            _away_on_orders[id] = true
# (same for mine)

# When the ship's order completes or is stopped:
func _on_order_completed(ship_id: int) -> void:
    if ship_id in _queue:
        _away_on_orders[ship_id] = false
```

`_on_order_completed` depends on NavigationController emitting a completion signal.
If unavailable, the fallback heuristic is for `FormationController` to treat arrival
at any non-slot destination as completion. Explicit signal is preferred — see §9.

### 4.6 Formation Tick

Runs only in Pilot mode. Pushes slot destinations for queue members **not** away on
orders.

```gdscript
func _formation_tick() -> void:
    if InputManager.current_mode() != "pilot":
        return
    var player := PlayerState.get_player_ship()
    if player == null:
        return

    var slot_defs: Array = _formation_def.slots
    var queue := EscortQueue.get_queue()

    for i in queue.size():
        if i >= slot_defs.size():
            break    # more ships than slots; surplus ships idle
        var ship_id := queue[i]
        if EscortQueue.is_away(ship_id):
            continue    # slot reserved but empty — no destination push
        var ship := instance_from_id(ship_id) as Node
        if ship == null:
            continue
        _push_slot_destination(ship, player, slot_defs[i])
```

A slot destination is the player ship's world position plus the slot's offset
rotated by the player ship's yaw. The push uses a dedicated signal distinct from
the order stream:

```gdscript
signal request_formation_destination(ship_id: int, destination: Vector3)
```

NavigationController listens and sets the destination without involving order-queue
logic. This is critical: using `request_tactical_move` would mark the ship as
"away on orders" and create a recursive loop.

### 4.7 Stop / Cancel

```gdscript
func _on_stop_key() -> void:
    if SelectionState.get_selection().is_empty():
        return
    GameEventBus.request_tactical_stop.emit(SelectionState.get_selection())
```

Stopping a queue member clears their order; `_away_on_orders` clears on the next
completion hook; the ship returns to its slot on the next formation tick.

Stopping a non-queue ship clears the order and leaves it idle.

### 4.8 Defensive Stance Response

```gdscript
# StanceController._on_ship_damaged(victim: Node, attacker: Node)
func _on_ship_damaged(victim: Node, attacker: Node) -> void:
    if attacker == null:
        return
    if not victim.is_in_group("player_fleet"):
        return

    var victim_id := victim.get_instance_id()
    var attacker_id := attacker.get_instance_id()

    # Defensive is scoped to the escort queue.
    # Non-queue damage does NOT trigger fan-out.
    if not EscortQueue.is_in_queue(victim_id):
        return

    if EscortQueue.get_stance() != EscortQueue.Stance.DEFENSIVE:
        return

    for member_id in EscortQueue.get_queue():
        GameEventBus.request_tactical_attack.emit(
            [member_id], attacker_id, "replace")
```

Aggressive-stance behavior (engage in detection range while en route) is owned by
AIController — it reads stance via `StanceController.get_effective_stance()` and
acts on its own. Fleet Command only stores the value.

Hold Fire is the null case: stance stored; AI declines to initiate combat.

### 4.9 Mouse-to-World (Ray-Plane Intersection)

```gdscript
func _ray_plane_intersect(origin: Vector3, direction: Vector3, plane_y: float) -> Vector3:
    if absf(direction.y) < 0.0001:
        return Vector3(origin.x, plane_y, origin.z)
    var t := (plane_y - origin.y) / direction.y
    return origin + direction * t
```

All world-space destinations produced by this system are `Vector3` with Y = 0.

---

## 5. JSON Data Format

### 5.1 Formation Definitions

```
/content/formations/
    v_wing/formation.json        ← default
    line/formation.json          ← (optional, extensible)
```

```json
{
  "id": "v_wing",
  "display_name": "V-Wing",
  "default": true,
  "slots": [
    { "role": "wingman_port",      "offset": [-25.0, 0.0,  15.0] },
    { "role": "wingman_starboard", "offset": [ 25.0, 0.0,  15.0] },
    { "role": "trail_port",        "offset": [-40.0, 0.0,  30.0] },
    { "role": "trail_starboard",   "offset": [ 40.0, 0.0,  30.0] }
  ]
}
```

- `offset` is `[x, y, z]` in the player ship's local frame. `y` is always 0.
- `+z` is *behind* the player (Godot 3D forward is `-z`).
- Exactly one formation must have `default: true`. The loader asserts on startup.
- Slot count is the effective formation size — ships past the slot count are in
  the queue but fly idle at their last position (see Assumption 7).

### 5.2 Stance Values

Stance is an enum in code, not content data, because each stance changes load-bearing
AIController behavior.

```gdscript
enum Stance { HOLD_FIRE, DEFENSIVE, AGGRESSIVE }
```

A ship's *default per-ship stance* can be declared in its `ship.json`:

```json
{
  "id": "fighter_mk1",
  "hull": { /* ... */ },
  "default_stance": "DEFENSIVE"
}
```

If omitted, `StanceController.DEFAULT_STANCE` (Defensive) applies.

---

## 6. Performance Instrumentation

Fleet Command is input-triggered and low-frequency. Register via the
PerformanceMonitor contract:

```gdscript
# InputManager
PerformanceMonitor.begin("FleetCommand.mode_switch")
PerformanceMonitor.end("FleetCommand.mode_switch")

# TacticalInputHandler
PerformanceMonitor.begin("FleetCommand.right_click_dispatch")
PerformanceMonitor.end("FleetCommand.right_click_dispatch")

# EscortQueue
PerformanceMonitor.begin("FleetCommand.escort_queue_op")
PerformanceMonitor.end("FleetCommand.escort_queue_op")

# FormationController
PerformanceMonitor.begin("FleetCommand.formation_tick")
PerformanceMonitor.end("FleetCommand.formation_tick")

# StanceController
PerformanceMonitor.begin("FleetCommand.stance_response")
PerformanceMonitor.end("FleetCommand.stance_response")
```

Counters:
- `FleetCommand.selection_size` — sampled on `tactical_selection_changed`
- `FleetCommand.escort_queue_size` — sampled on `escort_queue_changed`
- `FleetCommand.orders_dispatched_per_sec` — rolling counter

---

## 7. Files

```
/systems/fleet_command/
    InputManager.gd
    TacticalInputHandler.gd
    SelectionState.gd
    EscortQueue.gd
    FormationController.gd
    StanceController.gd

/ui/tactical/
    SelectionBox.gd             ← CanvasLayer; drag-select visual
    ContextMenu.gd              ← multilevel menu; Stance / Escort submenus
    EscortPanel.gd              ← visible only when EscortQueue is non-empty; stance selector
    TacticalUI.tscn             ← scene root for the above

/content/formations/
    v_wing/formation.json       ← default
```

Files modified:

- `/core/GameEventBus.gd` — new signals and modified signatures (table below).
- `/docs/feature_spec-game_event_bus_signals.md` — document the new signals.

### New / Modified Signals

| Signal | Args | Emitted By | Listened By | Change |
|---|---|---|---|---|
| `request_tactical_move` | `ship_ids: Array, destination: Vector3, queue_mode: String` | TacticalInputHandler | NavigationController, EscortQueue | Added `queue_mode` |
| `request_tactical_attack` | `ship_ids: Array, target_id: int, queue_mode: String` | TacticalInputHandler, StanceController | AIController, EscortQueue | Added `queue_mode` |
| `request_tactical_mine` | `ship_ids: Array, asteroid_id: int, queue_mode: String` | TacticalInputHandler | (Future) MiningController, EscortQueue | Added `queue_mode` |
| `request_tactical_stop` | `ship_ids: Array` | TacticalInputHandler, EscortQueue | NavigationController, AIController, EscortQueue | New |
| `request_tactical_set_stance` | `ship_id: int, stance: int` | TacticalUI (context menu) | StanceController | New (single ship — per-ship scope) |
| `request_tactical_set_escort_stance` | `stance: int` | TacticalUI (escort panel) | EscortQueue | New |
| `request_tactical_add_to_escort` | `ship_id: int` | TacticalUI (context menu) | EscortQueue | New |
| `request_tactical_remove_from_escort` | `ship_id: int` | TacticalUI (context menu) | EscortQueue | New |
| `escort_queue_changed` | `ship_ids: Array` | EscortQueue | EscortPanel (UI) | New |
| `escort_stance_changed` | `stance: int` | EscortQueue | EscortPanel (UI) | New |
| `ship_damaged` | `victim: Node, attacker: Node` | Ship (damage pipeline) | StanceController, (future) AIController | New |
| `request_formation_destination` | `ship_id: int, destination: Vector3` | FormationController | NavigationController | New (distinct from order-based destinations) |

---

## 8. Dependencies

| Dependency | Why |
|---|---|
| `GameEventBus.gd` | Every order, queue change, mode change, and stance change is a signal |
| `PerformanceMonitor.gd` | Required instrumentation contract |
| `NavigationController.gd` | Receives move orders and formation destinations |
| `GameCamera` (Camera3D) | Must expose `release()`, `follow(ship)`, `set_zoom_limits(min, max)` |
| `AIController.gd` | Reads effective stance; handles attack orders |
| `Ship.gd` with unified input interface | Order routing writes to this interface via NavigationController |
| `Ship.gd` damage pipeline | Must emit `ship_damaged(victim, attacker)` |
| `player_fleet`, `enemies`, `asteroids` groups | Target classification depends on these |

Preferred but not strictly required:

- A `navigation_order_completed(ship_id)` signal from NavigationController. Without
  it, the fallback heuristic in §4.5 applies.

---

## 9. Assumptions

1. **Fleet composition.** How ships join `player_fleet` is outside this spec.
2. **Selection visual feedback.** Required behaviorally; mechanism deferred.
3. **Order destination markers.** Required behaviorally; mechanism deferred.
4. **Context menu layout.** Multilevel with Stance + Escort submenus is required;
   visual styling is the UI system's concern.
5. **Escort panel layout.** Panel is visible only when queue is non-empty. Stance
   selector lives in the panel. Layout and ship representation are UI concerns.
6. **Formation tick rate.** `~0.25 s` is a placeholder.
7. **Excess queue ships.** When queue exceeds formation slot count, surplus ships
   fly idle at their last position. Loose-follow fallback is a future refinement.
8. **Capability query shape.** `ship.can_attack()` / `ship.can_mine()` shape is the
   ship system's choice.
9. **Queue visualization of pending orders.** Chain visualization for queued orders
   is deferred.
10. **Edge-scroll vs WASD pan.** Owned by the camera spec.
11. **Order completion signal from NavigationController.** Preferred; fallback in §4.5.
12. **Context menu dismissal.** Click-elsewhere and Esc both dismiss. UI concern.

---

## 10. Success Criteria

### Behavioral — Mode & Camera

- [ ] Pressing Tab toggles between `"pilot"` and `"tactical"` mode.
- [ ] `game_mode_changed(old, new)` fires on every transition.
- [ ] On entering Tactical, camera releases follow and begins a smooth zoom-out
      from its current position.
- [ ] On exiting Tactical, camera smoothly zooms in and re-follows the player ship.
- [ ] Player input remains live during camera transitions.

### Behavioral — Selection

- [ ] Only ships in `player_fleet` are selectable.
- [ ] Click selects a single ship (clearing prior selection).
- [ ] Shift-click toggles membership in the selection.
- [ ] Drag-box selects all fleet ships whose world position falls within the
      screen-projected quad.
- [ ] Left-click on empty space (no drag) deselects all.
- [ ] Selection clears on every mode transition.
- [ ] `tactical_selection_changed(ship_ids)` fires on every change (including empty).
- [ ] Selected ships are visually distinct from unselected ships.
- [ ] A destroyed ship is removed from the selection automatically.

### Behavioral — Right-Click Dispatch

- [ ] Right-click on empty space emits `request_tactical_move` (Vector3, Y = 0).
- [ ] Right-click on an enemy emits `request_tactical_attack`.
- [ ] Right-click on an asteroid emits `request_tactical_mine`.
- [ ] Right-click on a fleet ship opens the multilevel context menu — regardless of
      mode or selection state.
- [ ] Orders dispatched only to ships capable of them.
- [ ] Each order signal carries a `queue_mode` of `"replace"` or `"append"`.
- [ ] Default queue_mode is `"replace"`; Shift at right-click makes it `"append"`.
- [ ] Pressing S or Esc with a non-empty selection emits `request_tactical_stop`.
- [ ] Destroyed attack/mine targets drop from the queue; next order (if any) begins.

### Behavioral — Context Menu

- [ ] Right-click on any fleet ship opens the context menu at the cursor position.
- [ ] The menu has two top-level entries: Stance and Escort.
- [ ] The Stance submenu is **hidden** when the target ship is in the escort queue.
- [ ] The Escort submenu shows "Add to escort" if the ship is not in the queue.
- [ ] The Escort submenu shows "Remove from escort" if the ship is in the queue.
- [ ] The menu works in both Pilot and Tactical modes.
- [ ] Clicking elsewhere or pressing Esc dismisses the menu.

### Behavioral — Escort Queue

- [ ] Adding a ship appends it (next available slot).
- [ ] Adding a ship cancels any active tactical orders for that ship immediately.
- [ ] Removing a ship compacts remaining ships' slot indices.
- [ ] Removing a ship resets its per-ship stance to Defensive.
- [ ] `escort_queue_changed(ship_ids)` fires on every add and remove.
- [ ] The escort panel UI is visible if and only if the queue is non-empty.
- [ ] Queue order is insertion order — no manual reorder.
- [ ] Ships past the formation slot count remain in the queue but do not receive a
      slot destination.

### Behavioral — Formation

- [ ] In Pilot mode, queue members (not away on orders) are pushed toward their
      slot destinations via `request_formation_destination`.
- [ ] Formation uses the default formation from `/content/formations/`.
- [ ] Slot destination is the player ship's position + slot offset, rotated by the
      player ship's yaw.
- [ ] In Tactical mode, the formation tick is halted — queue members idle at their
      last position.
- [ ] A queue member that receives a tactical order is marked "away on orders"; its
      slot remains reserved but empty.
- [ ] When a queue member's order completes or is stopped, it returns to the same
      slot on the next formation tick.

### Behavioral — Stance

- [ ] Every fleet ship has a stance: HOLD_FIRE, DEFENSIVE, or AGGRESSIVE.
- [ ] Default stance is DEFENSIVE (unless overridden by `default_stance` in ship.json).
- [ ] Setting stance on a non-escort ship via the context menu emits
      `request_tactical_set_stance(ship_id, stance)`.
- [ ] Setting stance on the escort queue via the escort panel emits
      `request_tactical_set_escort_stance(stance)`.
- [ ] A ship in the queue reports its effective stance as the queue's stance,
      overriding any per-ship value.
- [ ] When a queue member is damaged and queue stance is DEFENSIVE, every queue
      member receives an attack order targeting the attacker.
- [ ] A damaged non-queue fleet ship does **not** trigger Defensive fan-out.
- [ ] A ship executing an order continues to prioritize it; stance-triggered combat
      is transient.
- [ ] Aggressive-stance ships engage enemies in detection range per AI spec.

### Behavioral — Player Ship Routing

- [ ] In Pilot mode, player keyboard/mouse drives the player ship via the unified
      input interface.
- [ ] In Tactical mode, player keyboard/mouse does not write to the player ship's
      input interface.
- [ ] The player ship is selectable, drag-selectable, and orderable like AI ships.
- [ ] On Tab back to Pilot, player input resumes driving the ship.

### Architectural

- [ ] No direct method calls from Fleet Command to NavigationController,
      AIController, or Ship.
- [ ] All world-space positions in order payloads are `Vector3` with Y = 0.
- [ ] Selection box and context menu are CanvasLayer UI elements; ship queries use
      ray-plane intersection at Y = 0 for world-space conversion.
- [ ] `GameCamera` is never a child of any ship during any mode.
- [ ] PerformanceMonitor metrics listed in §6 are registered and emitted.
- [ ] `StanceController.get_effective_stance(ship_id)` is the single call sites use
      for stance lookup.