# Fleet Command & Tactical Mode — Feature Specification (Stub)

*See [core_spec.md](core_spec.md) Section 3 (Tactical mode), Section 19 Build Order step 13.*

## Overview

RTS-style fleet control when **Tactical** mode is active (Tab): selection, move/attack/mine orders, and coordination with `NavigationController` / `GameEventBus` tactical signals defined in [feature_spec-game_event_bus_signals.md](feature_spec-game_event_bus_signals.md).

## Status

This document is a **placeholder** until the full spec is written (selection box, order queue, UI). Implementation should follow signal contracts already in `GameEventBus.gd` (`request_tactical_*`, `tactical_selection_changed`, `game_mode_changed`).

## Dependencies

- `NavigationController.gd` — converts destinations to ship unified input.
- `GameCamera` — tactical zoom and overview (see `feature_spec-camera_system.md`).
- `feature_spec-ai_patrol_behavior.md` — AI shares movement pipeline with tactical orders.

## Success Criteria (MVP slice)

- [ ] Tab toggles `pilot` / `tactical` via `game_mode_changed`.
- [ ] Move order emits `request_tactical_move` with `Vector3` destination (Y = 0).
- [ ] Player ship can be selected and issued orders like AI ships.
