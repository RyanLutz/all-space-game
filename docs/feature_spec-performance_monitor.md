# PerformanceMonitor System Specification
*All Space Combat MVP — Cross-Cutting Observability Service*

## Overview

A lightweight, always-on performance monitoring service that provides per-system timing data, custom metric tracking, and an in-game debug overlay. Built first, referenced by every other system spec.

**Design Goals:**
- Consistent instrumentation contract across all systems
- Minimal overhead — safe to leave enabled in release builds
- Integrates with Godot's built-in Performance debugger
- Single source of truth for all runtime metrics

---

## Architecture

### Service Registration

`PerformanceMonitor` is registered as a global service via the existing `ServiceLocator` on bootstrap, before any other system initializes.

```gdscript
# GameBootstrap.gd — add before other system inits
ServiceLocator.register("PerformanceMonitor", PerformanceMonitor.new())
```

### Canonical Metric Names

All metric names use the format `"System.method"`. Use these exact names — consistency matters for the overlay and Godot's debugger graphs.

| System | Metric Name |
|---|---|
| Dumb projectile pool update | `ProjectileManager.dumb_update` |
| Guided projectile pool update | `ProjectileManager.guided_update` |
| Projectile collision checks | `ProjectileManager.collision_checks` |
| AI state machine updates | `AIController.state_updates` |
| Navigation controller update | `Navigation.update` |
| Ship thruster allocation (integrate_forces) | `Physics.thruster_allocation` |
| Hit detection / component resolve | `HitDetection.component_resolve` |
| Chunk load | `ChunkStreamer.load` |
| Chunk unload | `ChunkStreamer.unload` |
| Active projectiles (count) | `ProjectileManager.active_count` |
| Active AI ships (count) | `AIController.active_count` |
| Active physics bodies (count) | `Physics.active_bodies` |
| Active ships (count) | `Ships.active_count` |
| Loaded chunks (count) | `ChunkStreamer.loaded_chunks` |
| Content registry startup scan | `ContentRegistry.load` |

New systems must add their metric names to this table before implementation.

---

## API

### Timing (wrap critical loops)

```gdscript
PerformanceMonitor.begin("ProjectileManager.dumb_update")
# ... critical code ...
PerformanceMonitor.end("ProjectileManager.dumb_update")
```

### Counters (set each frame)

```gdscript
PerformanceMonitor.set_count("ProjectileManager.active_count", pool.active_count)
```

### Query (for overlay or other systems)

```gdscript
PerformanceMonitor.get_avg_ms("ProjectileManager.dumb_update")   # → float
PerformanceMonitor.get_peak_ms("ProjectileManager.dumb_update")  # → float
PerformanceMonitor.get_count("ProjectileManager.active_count")   # → int
```

---

## Implementation

```gdscript
# PerformanceMonitor.gd
extends Node

const WINDOW_SIZE = 60  # rolling average over 60 frames

var _timers: Dictionary = {}     # metric_name → start_time (usec)
var _samples: Dictionary = {}    # metric_name → CircularBuffer of ms values
var _counts: Dictionary = {}     # metric_name → int
var _peaks: Dictionary = {}      # metric_name → float (ms)

func begin(metric: String) -> void:
    _timers[metric] = Time.get_ticks_usec()

func end(metric: String) -> void:
    if not _timers.has(metric):
        return
    var elapsed_ms = (Time.get_ticks_usec() - _timers[metric]) / 1000.0
    if not _samples.has(metric):
        _samples[metric] = []
    _samples[metric].append(elapsed_ms)
    if _samples[metric].size() > WINDOW_SIZE:
        _samples[metric].pop_front()
    if elapsed_ms > _peaks.get(metric, 0.0):
        _peaks[metric] = elapsed_ms

func set_count(metric: String, value: int) -> void:
    _counts[metric] = value

func get_avg_ms(metric: String) -> float:
    if not _samples.has(metric) or _samples[metric].is_empty():
        return 0.0
    var total = 0.0
    for s in _samples[metric]:
        total += s
    return total / _samples[metric].size()

func get_peak_ms(metric: String) -> float:
    return _peaks.get(metric, 0.0)

func get_count(metric: String) -> int:
    return _counts.get(metric, 0)

func reset_peaks() -> void:
    _peaks.clear()
```

---

## Godot Custom Monitors

Register these in `_ready()` so they appear in Godot's built-in debugger graphs:

```gdscript
func _ready() -> void:
    Performance.add_custom_monitor("AllSpace/projectiles_active",
        func(): return get_count("ProjectileManager.active_count"))
    Performance.add_custom_monitor("AllSpace/ai_ships_active",
        func(): return get_count("AIController.active_count"))
    Performance.add_custom_monitor("AllSpace/chunks_loaded",
        func(): return get_count("ChunkStreamer.loaded_chunks"))
    Performance.add_custom_monitor("AllSpace/projectile_ms",
        func(): return get_avg_ms("ProjectileManager.dumb_update"))
    Performance.add_custom_monitor("AllSpace/ai_ms",
        func(): return get_avg_ms("AIController.state_updates"))
    Performance.add_custom_monitor("AllSpace/physics_ms",
        func(): return get_avg_ms("Physics.thruster_allocation"))
```

---

## In-Game Debug Overlay

A `CanvasLayer` toggled by **F3**. Renders live stats over the game view.

**Display format:**

```
[ All Space — Performance Monitor ]
───────────────────────────────────────────────────
Projectiles (dumb)   847 active   0.8ms avg   2.1ms peak
Projectiles (guided)  12 active   0.1ms avg   0.3ms peak
AI state updates      23 ships    1.2ms avg   3.4ms peak
Hit detection                     0.3ms avg
Physics bodies        31          0.6ms avg
Chunk streaming       idle        last: 4ms
───────────────────────────────────────────────────
Frame budget used    6.1ms / 16.6ms (37%)
```

Frame budget is calculated as `Engine.get_frames_per_second()` target (default 60fps = 16.6ms).

The overlay is its own scene (`PerformanceOverlay.tscn`) added as a child of the root — never a child of a gameplay node, so it survives scene changes.

---

## Integration Contract

**Every system spec must include a "Performance Instrumentation" section** listing:

1. Which `begin()`/`end()` pairs to add and where
2. Which `set_count()` calls to add and when
3. What to register in `_ready()` if the system owns a count metric

**Rules:**
- Only instrument operations expected to take > 0.1ms
- Never instrument inside inner loops — wrap the whole loop, not each iteration
- `begin()` / `end()` calls must always be paired — use `finally` patterns if exceptions are possible
- Use only canonical metric names from the table above

---

## Files

```
/core/services/
    PerformanceMonitor.gd
/ui/debug/
    PerformanceOverlay.tscn
    PerformanceOverlay.gd
```

---

## Success Criteria

- [ ] `PerformanceMonitor` registers successfully on bootstrap before other systems
- [ ] Custom monitors visible in Godot's debugger graph panel
- [ ] F3 overlay toggles on/off without affecting gameplay
- [ ] All subsequent system specs include a Performance Instrumentation section
- [ ] Overhead of monitor itself < 0.05ms per frame with all systems reporting
