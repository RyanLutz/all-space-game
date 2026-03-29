# Camera System Specification
*All Space Combat MVP — Independent Camera with Cursor-Offset Follow*

## Overview

An independent camera system that follows a target (typically the player ship) with a cursor-direction offset and critically damped smoothing. The camera is its own node — never a child of the ship — so it can be retargeted, zoomed, or released for free-pan in future modes without restructuring anything.

**Design Goals:**
- Camera feels smooth and responsive — no overshoot, no wobble, no snap
- Cursor offset gives the player forward visibility in the direction they're aiming
- Zoom via scroll wheel with smooth interpolation
- Camera is completely decoupled from any specific ship — retargeting is a single function call
- Architecture supports future tactical view (free-pan, zoom out, different follow targets) without refactoring

---

## Architecture

```
Main Scene
    ├── GameWorld
    │       ├── Player Ship
    │       ├── AI Ships
    │       └── ...
    ├── GameCamera (Camera2D)      ← NOT a child of any ship
    │       └── GameCamera.gd
    └── UI Layer
```

`GameCamera` is a sibling of the game world, not a child of the player ship. It reads its follow target's position each frame and computes its own position independently. This means:

- Switching the followed ship = changing one reference
- Releasing the camera for free-pan = clearing the follow target
- The camera survives the player ship being destroyed (can watch the explosion, then follow debris, then snap to a respawn)

---

## Follow Behavior

### Target Position Calculation

Each frame, the camera computes a **desired position** that is offset from the follow target toward the cursor:

```gdscript
func _compute_desired_position() -> Vector2:
    if _follow_target == null:
        return global_position    # no target — hold position (future: free-pan)

    var target_pos = _follow_target.global_position

    # Cursor offset: shift camera toward where the player is aiming
    var screen_center = get_viewport_rect().size * 0.5
    var mouse_screen = get_viewport().get_mouse_position()
    var cursor_offset_dir = (mouse_screen - screen_center).normalized()
    var cursor_offset_magnitude = (mouse_screen - screen_center).length() / screen_center.length()
    cursor_offset_magnitude = clampf(cursor_offset_magnitude, 0.0, 1.0)

    var offset = cursor_offset_dir * max_cursor_offset * cursor_offset_magnitude

    return target_pos + offset
```

`max_cursor_offset` controls how far the camera leads toward the cursor. This is a world-space distance (e.g. 120 pixels), scaled by how far the mouse is from screen center. When the cursor is near the ship, the offset is negligible. When the cursor is at the screen edge, the offset is at max.

### Critically Damped Smoothing

The camera does **not** lerp. It uses a critically damped spring, which produces smooth motion that settles on target without overshoot or oscillation.

```gdscript
# GameCamera.gd

var _velocity: Vector2 = Vector2.ZERO

func _smooth_follow(desired: Vector2, delta: float) -> Vector2:
    # Critically damped spring: omega controls response speed
    # Higher omega = snappier follow. Lower = more cinematic lag.
    var omega = smoothing_speed    # e.g. 8.0–15.0
    var exp_term = exp(-omega * delta)

    var delta_pos = global_position - desired
    var new_pos = desired + (delta_pos + (_velocity + omega * delta_pos) * delta) * exp_term
    _velocity = (_velocity - omega * omega * delta_pos * delta) * exp_term

    return new_pos
```

This is a standard second-order critically damped system. The `smoothing_speed` parameter controls how quickly the camera catches up:

| Value | Feel |
|---|---|
| 6.0 | Cinematic — noticeable trail, great for slow ships |
| 10.0 | Responsive — slight smoothing, good default |
| 15.0 | Snappy — nearly instant, subtle polish |
| 20.0+ | Effectively locked — minimal visible smoothing |

### Process Loop

```gdscript
func _physics_process(delta: float) -> void:
    var desired = _compute_desired_position()
    global_position = _smooth_follow(desired, delta)
    _update_zoom(delta)
```

---

## Zoom

### Controls

Scroll wheel only at MVP. Zoom is smooth — the camera interpolates between zoom levels rather than snapping.

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.pressed:
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                _target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                _target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
```

### Zoom Interpolation

Zoom also uses smooth interpolation (simple lerp is fine here — zoom doesn't need spring dynamics):

```gdscript
func _update_zoom(delta: float) -> void:
    var current = zoom.x    # Camera2D zoom is uniform x/y
    var new_zoom = lerpf(current, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
    zoom = Vector2(new_zoom, new_zoom)
```

### Zoom Parameters

| Property | Description | Default |
|---|---|---|
| `min_zoom` | Maximum zoom in (closest) | 0.5 |
| `max_zoom` | Maximum zoom out (farthest) | 2.5 |
| `default_zoom` | Starting zoom level | 1.0 |
| `zoom_step` | How much each scroll tick changes zoom | 0.1 |
| `zoom_smoothing` | Interpolation speed for zoom transitions | 10.0 |

> **Note:** Godot's `Camera2D.zoom` is inverse to what you might expect — `Vector2(0.5, 0.5)` means zoomed IN (things appear larger), `Vector2(2.0, 2.0)` means zoomed OUT (things appear smaller). The parameter names above use the Godot convention — `min_zoom` is the lowest zoom value (closest view).

### Zoom and Cursor Offset Interaction

When zoomed out, `max_cursor_offset` should scale down — the player can already see further, so the offset matters less. When zoomed in, the offset matters more.

```gdscript
var effective_offset = max_cursor_offset / zoom.x
```

This keeps the offset feeling consistent across zoom levels.

---

## Target Management

### Following a Target

```gdscript
var _follow_target: Node2D = null

func follow(target: Node2D) -> void:
    _follow_target = target

func release() -> void:
    _follow_target = null
    _velocity = Vector2.ZERO    # stop any spring motion

func get_follow_target() -> Node2D:
    return _follow_target
```

### Initial Setup

On game start, the camera finds the player ship and follows it:

```gdscript
func _ready() -> void:
    var player = get_tree().get_first_node_in_group("player")
    if player:
        follow(player)
    zoom = Vector2(default_zoom, default_zoom)
    _target_zoom = default_zoom
```

### Target Destruction

If the follow target is freed (ship destroyed), the camera should hold its last position gracefully rather than snapping to origin:

```gdscript
func _physics_process(delta: float) -> void:
    if _follow_target != null and not is_instance_valid(_follow_target):
        release()    # target was destroyed — hold position

    var desired = _compute_desired_position()
    global_position = _smooth_follow(desired, delta)
    _update_zoom(delta)
```

This naturally supports the future case of watching an explosion, then retargeting to a new ship or respawn point.

---

## Future Extension Points

These are **not** in scope for MVP, but the architecture accommodates them:

| Feature | How It Fits |
|---|---|
| **Tactical view** | `release()` the camera, enable free-pan input (WASD/edge scroll), zoom out further |
| **Snap back to ship** | Call `follow(player_ship)` — the spring smoothly pulls back |
| **Switch followed ship** | Call `follow(other_ship)` — camera smoothly transitions to new target |
| **Camera shake** | Add a shake offset to the final position after spring calculation |
| **Death cam** | On player death, `release()` and optionally follow the killing ship or debris |
| **Cinematic mode** | Follow a path of waypoints instead of a ship — `_follow_target` can be a `Path2D` marker |

---

## Exported Properties

These are `@export` vars on `GameCamera.gd` — tunable in the editor without touching code:

```gdscript
@export_group("Follow")
@export var smoothing_speed: float = 10.0
@export var max_cursor_offset: float = 120.0

@export_group("Zoom")
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
@export var default_zoom: float = 1.0
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 10.0
```

These are also candidates for JSON config if you want them data-driven, but `@export` is more practical for camera tuning since you'll adjust these in real-time in the editor.

---

## Performance Instrumentation

The camera is lightweight — no per-frame instrumentation needed. If profiling shows camera as a concern (unlikely), add:

```gdscript
PerformanceMonitor.begin("Camera.update")
# ... process loop ...
PerformanceMonitor.end("Camera.update")
```

No custom monitor registration at MVP — the camera should cost < 0.01ms per frame.

---

## Files

```
/gameplay/camera/
    GameCamera.gd
    GameCamera.tscn
```

`GameCamera.tscn` is a `Camera2D` node with `GameCamera.gd` attached. Placed in the main scene as a sibling of the game world, not a child of any entity.

---

## Dependencies

- Player ship must be in the `"player"` group for initial target acquisition
- No dependency on `PerformanceMonitor` (optional instrumentation only)
- No dependency on any specific ship implementation — follows any `Node2D`

---

## Success Criteria

- [ ] Camera smoothly follows the player ship with no overshoot or wobble
- [ ] Camera offsets toward the cursor — aiming right shifts the view right
- [ ] Cursor offset feels proportional — small mouse movements = small offset
- [ ] Scroll wheel zooms smoothly with no snapping
- [ ] Zooming out reduces cursor offset proportionally
- [ ] Destroying the followed target holds camera position (no snap to origin)
- [ ] Calling `follow(new_target)` smoothly transitions to the new target
- [ ] Camera is never a child of the ship in the scene tree
- [ ] All tuning values are adjustable via `@export` in the editor
