Write the NavigationController feature spec for All Space.

## Context

`NavigationController.gd` is the flight computer that sits between high-level
destinations and a ship's raw thrust interface. It is build step 5 in the project
build order. It currently has no spec of its own — its behaviour is described
fragmentarily across three other specs. This session produces
`docs/spec/feature_spec-nav_controller.md`.

## Before you write anything

Read these files in full:
1. `docs/agent_brief.md` — architecture rules, deviation protocol
2. `docs/spec/core_spec.md` §3 (Unified Ship Input Interface), §13 (Physics Summary)
3. `docs/spec/feature_spec-physics_and_movement.md` — the NavigationController section
4. `docs/spec/feature_spec-ai_patrol_behavior.md` — the NavigationController Interface section
5. `docs/spec/feature_spec-fleet_command.md` — how Tactical mode uses NavigationController

Collect every constraint, interface detail, and algorithm fragment mentioned across
those files. The spec you write must be consistent with all of them.

## What NavigationController does

NavigationController converts a destination (Vector3, Y = 0) into per-frame
`input_forward` and `input_strafe` values on the ship's unified input interface.
It is the flight computer — it knows the ship's physics (mass, drag, max thrust)
and works out when to accelerate, when to brake, and what heading to face in order
to arrive at the target without overshooting.

It is used by:
- AI ships navigating to patrol points, pursuing targets, and disengaging
- The player's ship in Tactical mode when given a move order
- It is NOT used in Pilot mode — player inputs go directly to the thrust interface

It does NOT decide where to go. The AI controller and Tactical input handler decide
destination. NavigationController only decides how to get there physically.

## Interface (already established — do not change these)

```gdscript
# Called each frame by AIController or TacticalInputHandler
nav_controller.set_destination(pos: Vector3) -> void
nav_controller.set_thrust_fraction(f: float) -> void   # 0.0 to 1.0 of max thrust

# NavigationController writes these to the ship each frame
owner.input_forward = ...
owner.input_strafe  = ...
```

The aim target (`input_aim_target`) is set directly by the caller, not by
NavigationController. NavigationController only owns forward/strafe.

## Algorithms to specify

The spec must define concrete algorithms for:

1. **Arrival detection** — when is the ship "at" the destination? Define the arrival
   distance threshold and what happens on arrival (coast, hold, stop thrusting).

2. **Braking** — given current velocity, distance to destination, and max thrust,
   when should the ship start decelerating to avoid overshooting? This is the core
   problem. The physics spec describes the assisted steering stopping distance
   calculation as a reference pattern.

3. **Heading during travel** — should the ship face the destination, face its velocity
   vector, or something else? Define the rule.

4. **Thrust fraction application** — how does `thrust_fraction` scale the output?
   Is it applied to the raw force, the input values, or somewhere else?

5. **Strafe usage** — when, if ever, does NavigationController use `input_strafe`
   vs only `input_forward`?

## Constraints

- All positions are Vector3 with Y = 0. No Vector2.
- NavigationController reads ship physics properties (velocity, mass, thruster_force)
  from the ship it is attached to — it does not have its own physics model.
- It must work correctly for both slow AI wander speeds and full combat thrust fractions.
- It is a Node attached to the ship as a child — not an autoload.

## Spec format

Follow the format in `docs/spec/core_spec.md` §18:
1. Overview
2. Architecture
3. Core properties / data model
4. Key algorithms (with GDScript pseudocode)
5. JSON data format (if any — NavigationController reads ship stats, not its own JSON)
6. Performance Instrumentation — use metric name `Navigation.update`
7. Files
8. Dependencies
9. Assumptions
10. Success Criteria

Output the spec to `docs/spec/feature_spec-nav_controller.md`.

After writing the spec, append a session record to `docs/decisions_log.md` and
update the build status in `docs/agent_brief.md` if applicable.
