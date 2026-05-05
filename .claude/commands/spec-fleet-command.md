Write the Fleet Command & Tactical Mode feature spec for All Space.

## Context

`docs/spec/feature_spec-fleet_command.md` currently exists as a stub — it names the
system and lists three MVP success criteria but has no architecture, no algorithms,
and no data model. This session replaces that stub with a full spec.

This is build step 13 — it comes after the camera, AI, and NavigationController
systems are all built. The spec must be consistent with all of them.

## Before you write anything

Read these files in full:
1. `docs/agent_brief.md` — architecture rules, deviation protocol
2. `docs/spec/core_spec.md` §3 (Tactical Mode, Mode Transitions, Unified Ship Input Interface)
3. `docs/spec/feature_spec-camera_system.md` — tactical zoom and free-pan extension points
4. `docs/spec/feature_spec-ai_patrol_behavior.md` — NavigationController interface
5. `docs/spec/feature_spec-nav_controller.md` — flight computer (must exist before writing this spec)
6. `docs/spec/feature_spec-game_event_bus_signals.md` — tactical order signals already defined

If `docs/spec/feature_spec-nav_controller.md` does not exist yet, stop and report
that it must be written first (use `/spec-nav-controller`).

## What Tactical mode is

When the player presses Tab, the game switches from Pilot mode to Tactical mode.
The camera zooms out to an overview. The player commands their fleet using RTS
conventions — drag-select, right-click orders. The player's own ship is fully
included in the commandable fleet.

The mode switch is a signal (`game_mode_changed`) on GameEventBus. Every system
that cares about the current mode listens to that signal — there is no global
mode variable that systems poll.

## What this spec must cover

1. **Mode switching** — Tab key handling, `game_mode_changed` signal emission,
   what changes on enter/exit for each mode (camera, input routing, cursor behaviour).

2. **Ship selection** — drag-select box in screen space converted to world-space
   bounds; click to select single ship; shift-click to add/remove; selection state
   stored and broadcast via `tactical_selection_changed`.

3. **Order types** — right-click on empty space (move order), right-click on enemy
   (attack order), right-click on asteroid (mine order). Each emits the appropriate
   `request_tactical_*` signal already defined in GameEventBus. The spec must define
   how the right-click target is identified (raycast, group membership).

4. **Mouse-to-world for orders** — all order destinations are Vector3 with Y = 0,
   derived from ray-plane intersection against the XZ plane. Use the canonical
   pattern from the camera spec.

5. **Player ship in Tactical mode** — when the player's own ship is given a move
   order in Tactical mode, NavigationController drives it exactly as it drives AI
   ships. Input routing must switch from player keyboard/mouse → NavigationController.
   When Tab is pressed again to return to Pilot mode, input routing switches back.

6. **Camera handoff** — on entering Tactical mode, camera releases follow and zooms
   out; WASD or edge-scroll pans the free camera. On returning to Pilot mode, camera
   re-follows the player ship.

## Constraints

- No direct cross-system calls. All orders go through GameEventBus signals.
- All order destinations are Vector3 with Y = 0. No Vector2 positions.
- Selection box is a screen-space UI element (CanvasLayer) — not a 3D volume.
  Convert screen bounds to world bounds for the actual ship query.
- The player ship must be selectable and orderable exactly like AI ships.
- Tactical mode does not replace Pilot mode permanently — Tab always toggles back.

## Spec format

Follow the format in `docs/spec/core_spec.md` §18:
1. Overview
2. Architecture
3. Core properties / data model
4. Key algorithms (with GDScript pseudocode)
5. JSON data format (if any)
6. Performance Instrumentation
7. Files
8. Dependencies
9. Assumptions
10. Success Criteria

Output the completed spec to `docs/spec/feature_spec-fleet_command.md`, replacing the
existing stub content entirely.

After writing the spec, append a session record to `docs/decisions_log.md` and
update the build status in `docs/agent_brief.md` if applicable.
