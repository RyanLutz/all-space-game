# Camera System Specification
*All Space Combat MVP — Perspective Camera with Cursor-Offset Follow*

## Overview

An independent camera system that follows a target (typically the player ship) from above and
behind at a configurable angle, with a cursor-direction offset and critically damped spring
smoothing. Zoom is implemented by adjusting the camera's height (Y position) while keeping the
viewing angle constant — the world simply gets farther away without any FOV distortion.

**Design Goals:**

- Camera feels smooth and responsive — no overshoot, no wobble, no snap
- Shallow angle gives the player visual depth cues and forward visibility
- Cursor offset leads the view toward where the player is aiming
- Zoom via scroll wheel with smooth interpolation
- Camera is completely decoupled from any specific ship — retargeting is a single function call
- Architecture supports free-pan tactical view, camera shake, and death cam without refactoring

---

## Why Perspective + Height Zoom (Not FOV)

**Shallow perspective:** A modest downward angle gives ships visual weight, makes the play
surface feel like a physical space, and preserves forward visibility without flattening the scene.

**Height zoom vs FOV zoom:** Adjusting FOV to zoom changes the perspective distortion of the
scene — a very narrow FOV makes everything look flat (telephoto), a very wide FOV warps edges.
Zooming by raising and lowering the camera along the Y axis keeps distortion constant and feels
natural. The world simply looks closer or farther, like a camera crane moving up and down.
The tunable angle remains fixed during zoom; only height changes.

---

## Architecture

```
Main Scene
    ├── GameWorld
    │       ├── Player Ship (RigidBody3D)
    │       ├── AI Ships
    │       └── ...
    ├── GameCamera (Camera3D)         ← NOT a child of any ship
    │       └── GameCamera.gd
    └── UI Layer (CanvasLayer)
```

`GameCamera` is a sibling of the game world, never a child of the player ship. It computes its
own position each frame from the follow target's position. This means:

- Switching the followed ship = one call: `follow(new_ship)`
- Free-pan mode = `release()`, then respond to pan input directly
- Camera survives the player ship being destroyed — holds position, watches the explosion,
  then retargets to a respawn or new ship

---

## Core Properties / Data Model

### Camera Geometry

The camera is positioned at a fixed angle relative to its follow target. The angle is measured
as **degrees from straight down** (0° = directly overhead, 90° = horizontal). A value around
20–35° provides a strong sense of depth while keeping the ship well-centered.

The camera always looks at a point on the XZ plane — its rig is computed from the follow target
and current height each frame.

```
Camera position in world:
    X = target.x + horizontal_offset (cursor and angle-derived)
    Y = current_height                (zoom level)
    Z = target.z + depth_offset       (derived from angle, so camera tilts toward positive Z)

Camera looks at:
    look_target = target.position + cursor_offset_3d
    camera.look_at(look_target, Vector3.UP)
```

The `depth_offset` pulls the camera behind the target along Z so that the angle reads correctly:

```gdscript
var depth_offset = current_height * tan(deg_to_rad(camera_angle))
# camera_angle: degrees from straight down (e.g. 25.0)
# depth_offset: how far behind the target the camera sits at this height
```

### Exported Properties

```gdscript
@export_group("Angle & Position")
@export var camera_angle: float = 25.0          # degrees from straight down (0 = top-down)
@export var smoothing_speed: float = 10.0       # spring response; higher = snappier
@export var max_cursor_offset: float = 120.0    # world-space units of cursor lead

@export_group("Zoom")
@export var height_min: float = 300.0           # closest zoom (camera Y)
@export var height_max: float = 1200.0          # farthest zoom (camera Y)
@export var height_default: float = 500.0       # starting zoom
@export var zoom_step: float = 50.0             # world units per scroll tick
@export var zoom_smoothing: float = 10.0        # zoom interpolation speed
```

### Runtime State

```gdscript
var _follow_target: Node3D = null
var _spring_velocity: Vector3 = Vector3.ZERO    # damped spring internal state
var _target_height: float                       # desired height (from scroll input)
var _current_height: float                      # interpolated height
```

---

## Key Algorithms

### Mouse-to-World (Canonical Pattern)

**`get_global_mouse_position()` does not exist in 3D.** Use ray-plane intersection against
the Y = 0 play plane. This is the canonical pattern for any system that needs the world-space
cursor position — every system in this project that needs cursor position should use or call
a version of this.

```gdscript
func get_cursor_world_position() -> Vector3:
    var mouse_pos: Vector2 = get_viewport().get_mouse_position()
    var ray_origin: Vector3 = project_ray_origin(mouse_pos)
    var ray_dir: Vector3 = project_ray_normal(mouse_pos)
    var play_plane := Plane(Vector3.UP, 0.0)    # Y = 0
    var intersect = play_plane.intersects_ray(ray_origin, ray_dir)
    if intersect != null:
        return intersect
    # Fallback: cursor above horizon (shouldn't happen with a downward-facing camera)
    return Vector3.ZERO
```

This method is defined on `GameCamera.gd`. Other systems that need cursor world position should
either call this directly on the camera reference or expose it via `PlayerState` post-MVP.

### Desired Camera Position

Each frame, compute where the camera wants to be:

```gdscript
func _compute_desired_position() -> Vector3:
    if _follow_target == null:
        return global_position    # no target — hold position

    var target_pos: Vector3 = _follow_target.global_position

    # Cursor offset: lead the camera toward the aim point on XZ
    var cursor_world: Vector3 = get_cursor_world_position()
    var to_cursor: Vector3 = cursor_world - target_pos
    to_cursor.y = 0.0    # stay on XZ

    # Scale offset by distance from ship to cursor, capped at max
    var offset_magnitude: float = clampf(to_cursor.length(), 0.0, max_cursor_offset)
    # Scale down with zoom: farther out = player can see more anyway
    var effective_offset: float = offset_magnitude * (height_default / _current_height)
    var cursor_offset_3d: Vector3 = to_cursor.normalized() * effective_offset

    # Depth pullback from angle (camera sits behind and above the look target)
    var depth_back: float = _current_height * tan(deg_to_rad(camera_angle))

    return Vector3(
        target_pos.x + cursor_offset_3d.x,
        _current_height,
        target_pos.z + cursor_offset_3d.z + depth_back
    )
```

### Critically Damped Spring Follow

The camera position uses a critically damped spring — not lerp. A critically damped spring
settles precisely on its target with no overshoot and no oscillation, regardless of delta time.

```gdscript
func _smooth_follow(desired: Vector3, delta: float) -> Vector3:
    var omega: float = smoothing_speed   # response frequency; 8–15 is the useful range
    var exp_term: float = exp(-omega * delta)

    var delta_pos: Vector3 = global_position - desired
    var new_pos: Vector3 = desired + (delta_pos + (_spring_velocity + omega * delta_pos) * delta) * exp_term
    _spring_velocity = (_spring_velocity - omega * omega * delta_pos * delta) * exp_term

    return new_pos
```

The spring integrates `_spring_velocity` so the camera doesn't jitter between frames. Reset
`_spring_velocity` to `Vector3.ZERO` when retargeting or releasing to prevent residual motion
carrying over.

### Camera Orientation

After positioning, the camera always looks at the follow target's world position (plus the
cursor offset, already built into desired position):

```gdscript
func _update_orientation() -> void:
    if _follow_target != null:
        look_at(_follow_target.global_position, Vector3.UP)
    # If no target: hold current orientation
```

`GameCamera.gd` is attached directly to the `Camera3D` node — `self` is the camera.
There is no child `camera` reference. Call `look_at()` on self.

### Zoom (Height Interpolation)

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                _target_height = clampf(_target_height - zoom_step, height_min, height_max)
            MOUSE_BUTTON_WHEEL_DOWN:
                _target_height = clampf(_target_height + zoom_step, height_min, height_max)

func _update_zoom(delta: float) -> void:
    _current_height = lerpf(_current_height,
                            _target_height,
                            1.0 - exp(-zoom_smoothing * delta))
```

Simple exponential lerp is sufficient for zoom — no spring needed here since zoom is
user-initiated and doesn't need to track a moving target.

### Main Process Loop

```gdscript
func _physics_process(delta: float) -> void:
    # Guard: target may have been freed
    if _follow_target != null and not is_instance_valid(_follow_target):
        release()

    _update_zoom(delta)

    var desired: Vector3 = _compute_desired_position()
    global_position = _smooth_follow(desired, delta)
    _update_orientation()
```

---

## Target Management

```gdscript
func follow(target: Node3D) -> void:
    _follow_target = target
    _spring_velocity = Vector3.ZERO    # don't carry over motion from last target

func release() -> void:
    _follow_target = null
    _spring_velocity = Vector3.ZERO    # camera holds position naturally (desired = current)

func get_follow_target() -> Node3D:
    return _follow_target
```

### Initial Setup

```gdscript
func _ready() -> void:
    _current_height = height_default
    _target_height = height_default

    # Find player ship on startup
    var player = get_tree().get_first_node_in_group("player")
    if player:
        follow(player)

    # Listen for player ship changes (e.g. respawn, ship swap post-MVP)
    GameEventBus.connect("player_ship_changed", _on_player_ship_changed)

func _on_player_ship_changed(ship: Node) -> void:
    follow(ship)
```

---

## Smoothing Speed Reference

| `smoothing_speed` | Feel |
|---|---|
| 6.0 | Cinematic — noticeable trail, good for cutscenes |
| 10.0 | Responsive — subtle lag, good default |
| 15.0 | Snappy — nearly instant, barely perceptible |
| 20.0+ | Effectively locked — no visible smoothing |

Tune `smoothing_speed` per gameplay feel, not per ship class — the camera doesn't know which
ship it is following. If different ships want different camera feel, that's a post-MVP concern.

---

## Future Extension Points

| Feature | How It Fits |
|---|---|
| **Free-pan (Tactical mode)** | `release()`, then handle WASD/edge-scroll input each frame to move `global_position` directly (no follow target; spring is idle) |
| **Snap back to ship** | `follow(player_ship)` — spring pulls camera back smoothly |
| **Switch followed ship** | `follow(other_ship)` — spring transitions to new target |
| **Camera shake** | Add a shake offset (sum of decaying sinusoids) to the final position after spring calculation |
| **Death cam** | On `ship_destroyed`: `release()`, optionally `follow(killing_ship)` or hold on debris |
| **Cinematic path** | `_follow_target` can point to a `PathFollow3D` marker — no architecture change needed |
| **Zoom limits per mode** | Expose `set_zoom_limits(min, max)` — Tactical mode calls this to allow wider zoom-out |

---

## Performance Instrumentation

The camera is lightweight — one spring calculation and one `look_at` per frame. No per-frame
instrumentation is registered unless profiling identifies it as a concern.

If camera becomes a profiling target:

```gdscript
PerformanceMonitor.begin("Camera.update")
# ... full _physics_process body ...
PerformanceMonitor.end("Camera.update")
```

`Camera.update` is a reserved metric name in the canonical table (`All_Space_Core_Spec.md`
Section 10). Do not instrument it by default — the camera should cost < 0.05ms per frame and
does not need to appear in the F3 overlay at MVP.

---

## Files

```
/gameplay/camera/
    GameCamera.gd
    GameCamera.tscn         ← Camera3D node with GameCamera.gd attached
```

`GameCamera.tscn` is placed in the main scene as a **sibling of the game world**, not a child
of any entity or the world root's children. It is never nested inside a ship scene.

---

## Dependencies

- Player ship must be in the `"player"` group for initial target acquisition in `_ready()`
- `GameEventBus` must be registered (for `player_ship_changed` signal) before camera enters
  the scene tree
- `PlayerState.gd` — camera listens to `player_ship_changed` to retarget; this signal is
  emitted by `PlayerState` (see Ship System Spec)
- No dependency on `PerformanceMonitor` (optional instrumentation only)
- No dependency on any specific ship implementation — follows any `Node3D`

---

## Assumptions

- `camera_angle` default of 25° is a starting point — adjust during first playtest to taste.
  Shallower angles (15°) feel more arcade; steeper angles (35–45°) feel more cinematic.
- `max_cursor_offset` of 120 world units assumes a medium zoom level — will need tuning against
  actual ship speeds and screen coverage.
- `smoothing_speed` of 10.0 is a reasonable starting default for a fighter. Heavier ships may
  warrant a lower value to emphasize their mass — deferred to balancing.
- The cursor-to-world intersection assumes the camera never has a horizontal tilt that would
  put the horizon above the ship. With `camera_angle` <= ~60°, this is safe.
- Zoom bounds (300–1200 world units) are untested — adjust after seeing actual content scale.
- Scroll step of 50 world units per tick is arbitrary — tune during first playtest.

---

## Success Criteria

- [ ] Camera follows the player ship with no overshoot or wobble at any ship speed
- [ ] Camera offset visibly leads toward the cursor — aiming right shifts the view right
- [ ] Cursor offset is proportional to mouse distance from ship — centered mouse = minimal offset
- [ ] Cursor offset scales down when zoomed out, so it doesn't overcorrect at wide view
- [ ] Scroll wheel zooms smoothly with no snapping or FOV distortion
- [ ] Zooming in and out does not change the camera angle
- [ ] Destroying the follow target holds camera position — no snap to origin, no crash
- [ ] `follow(new_target)` smoothly transitions to the new target with no discontinuity
- [ ] `get_cursor_world_position()` returns the correct XZ world position under the cursor at all zoom levels
- [ ] Camera is never a child of the ship node in the scene tree
- [ ] `camera_angle`, `smoothing_speed`, `max_cursor_offset`, `height_min`, `height_max`,
  `height_default`, `zoom_step`, and `zoom_smoothing` are all `@export` vars, tunable in editor
- [ ] `GameEventBus.player_ship_changed` causes camera to smoothly retarget the new ship
