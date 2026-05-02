# UI Design Specification
*All Space — Visual Language, Design Tokens, and HUD Layout*

---

## Overview

This spec defines the visual language for all in-game UI in All Space. It establishes the
design token system, panel conventions, typography rules, indicator types, and per-mode HUD
layouts for Pilot and Tactical views.

**Design Goals:**

- A single coherent visual identity that reads as one game across both modes
- Mode identity communicated through accent color and layout density, not a completely
  different aesthetic
- Information hierarchy driven by opacity, not gradients or drop shadows
- Every panel, bar, and label derivable from the token set — no one-off values in any UI file
- Flat enough to implement cleanly in Godot's theme system without custom shaders
- Readable at 1080p under the stress of active combat

**Core Aesthetic Decisions:**

- Primary text color is light grey at varying opacity — never white, never colored
- Accent colors are reserved for game-state meaning (friendly/hostile/warning) — not decoration
- No gradients anywhere. Color transitions are handled by flat state classes (normal/warning/critical)
- Panels use corner-clip polygons (not rounded rects) for a utilitarian, angular character
- Two typefaces only: `Orbitron` for labels and headers, `Share Tech Mono` for data values

---

## Architecture

The UI lives entirely in a `CanvasLayer` that sits above the 3D world. It is never parented
to any ship or physics object.

```
Main Scene
    ├── GameWorld
    │       ├── Player Ship (RigidBody3D)
    │       └── ...
    ├── GameCamera (Camera3D)
    └── UILayer (CanvasLayer)
            ├── PilotHUD.tscn       ← visible in Pilot mode
            ├── TacticalHUD.tscn    ← visible in Tactical mode
            └── ModeSwitch.tscn     ← always visible, drives mode transition
```

`PilotHUD` and `TacticalHUD` are separate scenes. The `ModeSwitch` node (bound to Tab)
shows/hides them. Neither HUD scene holds a reference to the other — they both listen to
`GameEventBus` for state updates.

Each HUD is responsible for subscribing to only the events it needs. The game systems
(ShipSystem, WeaponSystem, AIController) emit events; the HUD nodes listen and update
their own display. No system holds a reference to any UI node.

---

## Design Tokens

These are the **only** values that UI code may use for color, typography, and surface
styling. Hardcoding any value that appears here is a spec violation.

### Grey Scale — Primary Text System

The entire text hierarchy is derived from one base color at varying opacity.
Base: `rgb(210, 218, 224)` — a slightly cool light grey, never pure white.

| Token             | Value                          | Usage                              |
|---|---|---|
| `grey-100`        | `rgba(210, 218, 224, 0.95)`    | Primary text — names, active values |
| `grey-80`         | `rgba(210, 218, 224, 0.70)`    | Secondary text — data readouts      |
| `grey-50`         | `rgba(210, 218, 224, 0.42)`    | Tertiary — labels, keys, hints      |
| `grey-20`         | `rgba(210, 218, 224, 0.16)`    | Borders, dividers, bar tracks       |
| `grey-08`         | `rgba(210, 218, 224, 0.06)`    | Subtle fills — inactive slots, bg   |

### Accent Colors — Mode Identity

Each mode has one accent color. Accents are used for: active state indicators, selected
ship highlights, the mode label itself, and active bar fills in that mode. They are not
used for body text.

| Token               | Value                          | Usage                               |
|---|---|---|
| `accent`            | `#22cca8`                      | Pilot mode — friendly, shields, active weapon |
| `accent-dim`        | `rgba(34, 204, 168, 0.42)`     | Pilot — selection rings, bar borders  |
| `accent-faint`      | `rgba(34, 204, 168, 0.12)`     | Pilot — active slot background fill  |
| `tac-accent`        | `#2ab8cc`                      | Tactical mode — selected ships, order buttons |
| `tac-accent-dim`    | `rgba(42, 184, 204, 0.42)`     | Tactical — selection rings           |
| `tac-accent-faint`  | `rgba(42, 184, 204, 0.12)`     | Tactical — active button background  |

### Status Colors — Game State

Status colors communicate health, threat, and urgency. They appear on bars and labels only
when those bars or labels are describing something that has entered a notable state.

| Token              | Value        | Usage                                |
|---|---|---|
| `hostile`          | `#d44c38`    | Enemy accent, hostile bars, threats  |
| `hostile-dim`      | `rgba(212, 76, 56, 0.42)` | Attack vectors, target rings |
| `hostile-faint`    | `rgba(212, 76, 56, 0.12)` | Target panel background fill |
| `status-hull`      | `#3db86a`    | Hull bar fill at > 66%               |
| `status-power`     | `#c89a28`    | Power bar fill; hull at 33–66%       |
| `status-warning`   | `#c87828`    | Heat bar mid-state; hull warning     |
| `status-critical`  | `#d43838`    | Heat bar critical-state; hull < 20%  |

### Surfaces

| Token             | Value                       | Usage                        |
|---|---|---|
| `surface`         | `rgba(6, 12, 22, 0.94)`     | All panel backgrounds         |
| `surface-raised`  | `rgba(10, 18, 32, 0.96)`    | Active button/slot backgrounds |

### Typography

| Token          | Value                       | Usage                                     |
|---|---|---|
| `font-label`   | `Orbitron`, sans-serif      | All labels, headers, mode names, panel headers, button labels |
| `font-data`    | `Share Tech Mono`, monospace | All data values, coordinates, ammo counts, percentages |

**Font size rules:**

| Role              | Font           | Size  | Weight | Letter-spacing |
|---|---|---|---|---|
| Mode name         | Orbitron       | 20px  | 700    | 2px            |
| Ship name         | Orbitron       | 16px  | 700    | 1px            |
| Panel header      | Orbitron       | 9px   | 400    | 3px            |
| Button label      | Orbitron       | 8px   | 600    | 1.5px          |
| Roster ship name  | Orbitron       | 9px   | 600    | 0.5px          |
| Data value        | Share Tech Mono | 10–11px | 400  | 1px            |
| Data label        | Orbitron       | 9px   | 400    | 3px            |
| Coordinate string | Share Tech Mono | 9px  | 400    | 1px            |

---

## Panel Conventions

### Shape

All panels use corner-clip polygons — not rounded rectangles. The clip size is always 14px.
The clipped corner identifies the panel's screen quadrant:

| Position         | Clip corner        | `clip-path` fragment                                                          |
|---|---|---|
| Top-left panel   | Bottom-right clipped | `polygon(0 0, 100% 0, 100% calc(100% - 14px), calc(100% - 14px) 100%, 0 100%)` |
| Top-right panel  | Bottom-left clipped  | `polygon(0 0, 100% 0, 100% 100%, 14px 100%, 0 calc(100% - 14px))`            |
| Bottom-left panel | Top-right clipped   | `polygon(0 0, calc(100% - 14px) 0, 100% 14px, 100% 100%, 0 100%)`            |
| Bottom-right panel | Top-left clipped   | `polygon(14px 0, 100% 0, 100% 100%, 0 100%, 0 14px)`                         |
| Bottom-center panel | Both top corners | `polygon(14px 0, calc(100% - 14px) 0, 100% 14px, 100% 100%, 0 100%, 0 14px)` |
| Top-center panel | Both bottom corners  | `polygon(0 0, 100% 0, 100% calc(100% - 14px), calc(100% - 14px) 100%, 14px 100%, 0 calc(100% - 14px))` |

In Godot, these are implemented as `StyleBoxFlat` with individual corner radii set to 0 and
corner detail 0 — or as `NinePatchRect` shapes where the clip is baked into the texture.
The preferred approach is a shared `PanelContainer` theme with the clip handled by a
`StyleBoxFlat` using a flat corner cut. The corner-cut direction is set per-panel instance.

### Border

All panels: `1px solid` using `grey-20`. No glow, no shadow.

Active state panels (e.g., active weapon slot, selected order button): border becomes
`accent-dim` (Pilot) or `tac-accent-dim` (Tactical), and a 2px solid accent-colored bar
sits flush at the top edge inside the border.

### Background

All panels: `surface`. Active slot backgrounds: `surface-raised`. No exceptions.

### Padding

Standard panel padding: `16px 20px`. Compact panels (mode tag, sector info): `10px 18px`.

---

## Indicator Types

### Segmented Bar — Shields

Used for: shields only. Communicates discrete shield layers rather than a continuous fill.

- 10 equal segments in a horizontal row
- Gap between segments: 2px
- Inactive segment: `grey-08` fill, `grey-20` border
- Active segment: `accent` fill (Pilot mode), no border
- Segment height: 8px
- Segment count lit = `floor(shield_pct / 10)`

### Filled Bar — Hull / Power

Used for: hull integrity, power level.

- Single flat fill, no gradient
- Track: `grey-08` fill, `grey-20` border, 6px height
- Fill colors by type:

| Bar type | Fill color      |
|---|---|
| Hull      | `status-hull` (green) |
| Power     | `status-power` (amber) |

Hull bar does not change color based on percentage — the percentage value label (`grey-80`)
shifts to `status-critical` when hull < 20%.

### Heat Bar — Weapons

Used for: per-weapon heat level. Three flat states, no gradient transitions.

| State    | Threshold  | Fill color         | Behavior           |
|---|---|---|---|
| Cool     | < 40%      | `accent` (Pilot)   | Static             |
| Warm     | 40–70%     | `status-warning`   | Static             |
| Critical | > 70%      | `status-critical`  | Pulse animation (opacity 0.75 → 1.0 at 0.5s) |

State is determined each frame and applied as a class/style swap. No interpolation between
states — the transition is instant. Height: 4px.

### Roster HP Bar — Tactical

Used for: ship hull in the fleet roster list. Thin (3px), no track border.

| Hull %      | Color            |
|---|---|
| > 66%       | `status-hull`    |
| 33–66%      | `status-power`   |
| < 33%       | `hostile`        |

---

## Pilot HUD Layout

The Pilot HUD has five panels and a hit-flash overlay.

```
┌──────────────────────────────────────────────────────────────────┐
│ [MODE TAG]                [TARGET LOCK]              [nothing]   │
│                                                                  │
│                        3D WORLD                                  │
│                                                                  │
│ [VESSEL STATUS]       [WEAPON SYSTEMS]              [RADAR]      │
└──────────────────────────────────────────────────────────────────┘
```

### Mode Tag — top-left
- Contents: mode sub-label ("FLIGHT MODE"), mode name ("PILOT")
- Mode name color: `accent`
- Corner clip: bottom-right

### Target Lock — top-center
- Visible when a target is locked. Hidden otherwise.
- Contents: label ("TARGET LOCKED"), target name (`hostile` color), three stat fields
  (HULL %, DIST, THREAT level)
- Target name: Orbitron 13px 700, `hostile`
- Corner clip: both-bottom

### Vessel Status — bottom-left
- Contents: panel header ("VESSEL STATUS"), ship name, three bar rows (shields, hull, power),
  coordinate/speed string
- Shield row uses segmented bar. Hull and power use filled bars.
- Coordinate string: `grey-50`, `font-data` 9px
- Corner clip: top-right

### Weapon Systems — bottom-center
- Grid of 4 weapon slots
- Each slot: slot number (`grey-50`), weapon name (`grey-80`), heat bar, ammo count (`grey-50`)
- Active slot: top accent bar, `accent-faint` background, weapon name shifts to `accent`
- Corner clip: both-top

### Radar — bottom-right
- Circular; no clip-path (border-radius 50%)
- Background: `rgba(4, 10, 20, 0.96)` flat
- Rings and crosshair: `grey-20`
- Sweep wedge: low-opacity `accent` fill
- Sweep line: `rgba(34, 204, 168, 0.65)`, 1.5px
- Player dot: `accent` filled
- Enemy dots: `hostile` filled
- Border: `grey-20` 1.5px

### Hit Flash Overlay
- Full-screen `rgba(212, 76, 56, N)` div at zero z-index above world, below panels
- On hull impact: flash to opacity ~0.15, decay at 0.055/frame
- No animation curve — linear decay is intentional (snappy, not soft)

---

## Tactical HUD Layout

The Tactical HUD has five panels. No radar, no weapon slots.

```
┌──────────────────────────────────────────────────────────────────┐
│ [MODE TAG]            [FLEET SELECTION]          [SECTOR INFO]   │
│                                                                  │
│                        3D WORLD                                  │
│                                                                  │
│ [FLEET ROSTER]        [ORDER TOOLBAR]            [nothing]       │
└──────────────────────────────────────────────────────────────────┘
```

### Mode Tag — top-left
- Same structure as Pilot mode tag
- Mode name: "TACTICAL", color: `tac-accent`
- Corner clip: bottom-right

### Fleet Selection — top-center
- Contents: label ("FLEET SELECTION"), selection summary line, three stat fields
  (HULL AVG, SPEED, WEAPONS status)
- Summary line: Orbitron 12px 700, `grey-100`
- Corner clip: both-bottom

### Sector Info — top-right
- Contents: label ("SECTOR"), sector name, elapsed mission time
- Text alignment: right
- Corner clip: bottom-left

### Fleet Roster — bottom-left
- Scrollable list of all player ships
- Each row: ship icon (SVG), ship name, class label, roster HP bar, status string
- Selected ships: name shifts to `tac-accent`, icon uses `tac-accent` stroke
- Divider between rows: `grey-20` 1px
- Corner clip: top-right

**Ship icons:**
- Selected: circle + forward-pointing chevron (filled `tac-accent`)
- Unselected: circle + center dot (filled `grey-50`)
- Enemy in roster (captured/hacked future case): diamond shape, `hostile`

### Order Toolbar — bottom-center
- Row of 5 order buttons: ATTACK, PATROL, ESCORT, DEFEND, HOLD
- Each button: icon glyph, label, keyboard shortcut hint
- Active button: `tac-accent-faint` background, `tac-accent-dim` border, 2px top bar
- Inactive button: `grey-08` background, `grey-20` border
- Second row: formation/stance sub-options as compact text buttons
- Corner clip: both-top

---

## World-Space Overlays — Tactical Mode

These are drawn on the canvas (2D or 3D debug draw), not in the CanvasLayer.

### Selection Rings
- Animated circle around selected ships
- Color: `tac-accent-dim` with subtle pulse (sin wave, ±2px radius, ±0.08 opacity)
- Rotating tick marks at 4 compass points: `tac-accent`, 1.5px, 8px length

### Attack Vectors
- Dashed line from selected ship to targeted enemy
- Color: `hostile-dim`, 1.2px
- Dash: 10px on, 8px off, animated offset (marching ants)
- Arrowhead at target end: open chevron, `hostile-dim`

### Formation Lines
- Dashed line between co-selected ships
- Color: `tac-accent-dim`, 0.8px
- Dash: 5px on, 10px off, static (not animated)

### Patrol Route
- Closed dashed polyline through waypoints
- Color: `rgba(100, 160, 255, 0.28)`, 1.2px
- Dash: animated offset (marching ants, slower than attack vectors)
- Waypoint dots: `rgba(100, 160, 255, 0.35)`, 4px radius
- Active patrol ship position: 5px filled dot, `rgba(100, 160, 255, 0.65)`

### Ship Labels (Tactical only)
- Ship name rendered above icon in canvas space
- Font: Orbitron 9px 600
- Friendly (unselected): `grey-50`
- Friendly (selected): `tac-accent`
- Enemy: `hostile`
- HP bar below icon: 56px wide, 3px tall, no track, same color rules as roster HP bar

---

## Mode Transition

- **Trigger:** Tab key, or ModeSwitch panel buttons
- **Behavior:** `PilotHUD.visible = false`, `TacticalHUD.visible = true` (or vice versa)
- **Camera:** GameCamera responds to `mode_changed` event — see Camera System spec
- **No animation at MVP.** Instant swap. Fade transition is a post-MVP polish item.
- **Ship icons vs meshes:** At MVP, ship meshes remain visible in Tactical mode — the
  icon overlay is drawn on top, not instead of. Full icon-swap (hide mesh, show icon sprite)
  is post-MVP.

---

## Godot Theme Resource

All token values are implemented once in a single `UITheme.tres`. No UI scene may override
theme properties inline — all styling flows through the theme.

**Theme structure:**

```
UITheme.tres
    Panel / StyleBoxFlat
        bg_color:        surface
        border_color:    grey-20
        border_width:    1
        corner_radius:   0 (all corners)
    Label
        font:            font-data (Share Tech Mono)
        font_color:      grey-80
    Button / normal StyleBoxFlat
        bg_color:        grey-08
        border_color:    grey-20
    Button / pressed StyleBoxFlat
        bg_color:        surface-raised (contextual — set per theme variation)
        border_color:    accent-dim or tac-accent-dim
```

**Color constants** (defined as `const` in a `UITokens.gd` autoload):

```gdscript
# UITokens.gd
class_name UITokens

const GREY_100 = Color(0.824, 0.855, 0.878, 0.95)
const GREY_80  = Color(0.824, 0.855, 0.878, 0.70)
const GREY_50  = Color(0.824, 0.855, 0.878, 0.42)
const GREY_20  = Color(0.824, 0.855, 0.878, 0.16)
const GREY_08  = Color(0.824, 0.855, 0.878, 0.06)

const ACCENT          = Color(0.133, 0.800, 0.659)   # #22cca8
const ACCENT_DIM      = Color(0.133, 0.800, 0.659, 0.42)
const ACCENT_FAINT    = Color(0.133, 0.800, 0.659, 0.12)

const TAC_ACCENT      = Color(0.165, 0.722, 0.800)   # #2ab8cc
const TAC_ACCENT_DIM  = Color(0.165, 0.722, 0.800, 0.42)
const TAC_ACCENT_FAINT= Color(0.165, 0.722, 0.800, 0.12)

const HOSTILE         = Color(0.831, 0.298, 0.220)   # #d44c38
const HOSTILE_DIM     = Color(0.831, 0.298, 0.220, 0.42)

const STATUS_HULL     = Color(0.239, 0.722, 0.416)   # #3db86a
const STATUS_POWER    = Color(0.784, 0.604, 0.157)   # #c89a28
const STATUS_WARNING  = Color(0.784, 0.471, 0.157)   # #c87828
const STATUS_CRITICAL = Color(0.831, 0.220, 0.220)   # #d43838

const SURFACE         = Color(0.024, 0.047, 0.086, 0.94)
const SURFACE_RAISED  = Color(0.039, 0.071, 0.125, 0.96)
```

---

## Performance Instrumentation

The UI layer is not expected to be a performance bottleneck. Instrumentation is minimal.

```gdscript
# In HUD update loop — only if per-frame rebuild becomes expensive
PerformanceMonitor.begin("UI.pilot_hud_update")
# ... update all pilot HUD labels and bars ...
PerformanceMonitor.end("UI.pilot_hud_update")

PerformanceMonitor.begin("UI.tactical_hud_update")
# ... update roster, selection summary ...
PerformanceMonitor.end("UI.tactical_hud_update")
```

Canonical metric names:

| Metric              | Name                      |
|---|---|
| Pilot HUD update    | `UI.pilot_hud_update`     |
| Tactical HUD update | `UI.tactical_hud_update`  |

Do not instrument individual label or bar updates — wrap the full HUD update call only.
Only add instrumentation if profiling reveals a frame budget problem in the UI layer.

---

## Files

| Path | Description |
|---|---|
| `docs/feature_spec-ui_design.md` | This file |
| `ui/UITokens.gd` | Autoload — all color/font constants |
| `ui/UITheme.tres` | Godot Theme resource — base styles |
| `ui/PilotHUD.tscn` | Pilot mode HUD scene |
| `ui/PilotHUD.gd` | Pilot HUD controller — subscribes to events, updates display |
| `ui/TacticalHUD.tscn` | Tactical mode HUD scene |
| `ui/TacticalHUD.gd` | Tactical HUD controller |
| `ui/ModeSwitch.tscn` | Always-visible mode toggle buttons |
| `ui/ModeSwitch.gd` | Emits `mode_changed` on Tab or button press |
| `ui/components/StatBar.tscn` | Reusable filled bar component (hull, power) |
| `ui/components/SegBar.tscn` | Reusable segmented bar component (shields) |
| `ui/components/HeatBar.tscn` | Reusable heat bar with state logic |
| `ui/components/WeaponSlot.tscn` | Single weapon slot panel |
| `ui/components/RosterRow.tscn` | Single fleet roster row |
| `ui/radar/Radar.tscn` | Radar display (Pilot only) |
| `ui/radar/Radar.gd` | Radar draw logic |

---

## Dependencies

| Dependency | Why |
|---|---|
| `GameEventBus.gd` | HUD nodes subscribe to ship state, weapon, and mode events |
| `PerformanceMonitor.gd` | Instrumentation contract |
| `GameCamera.gd` (Camera System spec) | Mode transition triggers camera behavior change |
| `Orbitron` font asset | Must be imported into Godot project |
| `Share Tech Mono` font asset | Must be imported into Godot project |
| Ship System | Emits hull, shield, power events that Pilot HUD listens for |
| Weapon System | Emits heat, ammo, active-weapon events that weapon slots display |

UI implementation should not begin until `GameEventBus` and at least one emitting system
(Ship or Weapon) exist, so that the HUD can be tested with real data.

---

## Assumptions

- Shield bar always uses 10 segments regardless of ship size or max shield value.
  Segment count lit is always `floor(pct / 10)`. Future shield expansion (stacked shields,
  overcharge) will require revisiting this.
- Weapon system always exposes exactly 4 active weapon slots in Pilot HUD at MVP.
  Ships with fewer than 4 weapons leave remaining slots empty/inactive.
- Fleet roster displays a maximum of 8 ships without scrolling. Scrolling behavior for
  larger fleets is deferred.
- Radar range is a fixed world-space radius (configurable in JSON), not dependent on
  ship sensor modules at MVP.
- The kill feed seen in early prototypes is deferred — it is not included in this spec.
  It will be added as a separate component when the event bus can supply kill events.
- Font licensing: Orbitron and Share Tech Mono are both Google Fonts (OFL licensed) and
  are cleared for use in commercial projects.

---

## Success Criteria

- [ ] `UITokens.gd` autoload exports all color constants; no UI file contains a hardcoded
      color value that is not derived from `UITokens`
- [ ] `UITheme.tres` applied to both HUD scenes; removing the theme visually breaks the
      layout (confirms nothing is hardcoded inline)
- [ ] Pilot HUD displays shield segments, hull bar, power bar, and 4 weapon slots with
      correct values driven by GameEventBus events from the Ship and Weapon systems
- [ ] Heat bar transitions correctly between cool / warm / critical states with pulse
      animation active only at critical
- [ ] Tactical HUD displays fleet roster with correct HP bar colors for each ship's
      hull percentage
- [ ] Order toolbar highlights exactly one active order at a time
- [ ] Tab key transitions between modes; correct HUD becomes visible, incorrect HUD hidden
- [ ] Radar sweep animates at constant rate and correctly plots enemy positions within range
- [ ] All text uses only `Orbitron` or `Share Tech Mono` — verified by font override test
      (set a third font in theme; nothing should change)
- [ ] Hit flash fires on hull impact event and decays within ~1 second
- [ ] Performance: `UI.pilot_hud_update` and `UI.tactical_hud_update` both measure < 0.5ms
      per frame on target hardware
