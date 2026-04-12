# All Space — Project Vision & Goals
*A Space Simulation from Personal Ship to Galactic Empire*

---

## What Is This Game?

All Space is a top-down 3D space simulation constrained to the XZ plane where players
begin as a lone pilot in a single ship and, over time, grow into a fleet commander,
infrastructure builder, and eventually a galactic power. The game is built around a single continuous
streaming map — no loading screens, no sector transitions — and a core philosophy of
seamless scale.

The game draws primary inspiration from Star Valor's reverse engineering and
customization depth, combined with the strategic scope of X4: Foundations and the
accessible immediacy of the Escape Velocity series.

---

## Core Philosophy

**"As complex or as simple as the player wants it to be."**

Every system in All Space is designed with a shallow entry point and a deep ceiling.
A player can pick up a found ship, fly it as-is, and have a complete and satisfying
experience. Another player can strip that same ship to its components, study its
construction, design a blueprint, and mass-produce a fleet of customized variants.
Both approaches are valid at every stage of the game.

Complexity is never forced — it is unlocked on demand.

---

## The Long-Term Vision: Four Phases of Play

The game's full progression spans four phases, each building on the last without
discarding what came before. At any phase, the player can drop back to personal
ship control at will.

### Phase 1 — Personal Pilot
The entry point. One ship, direct control of all movement and systems. The player
takes missions, trades goods, fights enemies, and begins customizing their ship.
Combat feels immediate and personal. Every upgrade is felt directly.

### Phase 2 — Small Fleet Commander
Triggered by acquiring a second ship. A command mode (toggled with a single key)
overlays an RTS-style interface where the player can issue orders to their fleet
while remaining able to jump back into direct control at any moment. Familiar RTS
conventions — drag-select, right-click commands — reduce the learning curve.

### Phase 3 — Infrastructure Builder
Resources accumulate. The player gains access to construction ships, begins building
shipyards and defensive installations, and manages multiple battle groups. Blueprint
systems allow mass production of learned ship and part designs.

### Phase 4 — Galactic Power
Territory. Faction diplomacy. Large-scale logistics and supply chains. The player
commands an organization spanning multiple systems. But the "Only You Can Do This"
principle keeps personal agency meaningful — espionage, first contact situations,
precision rescue operations, and archaeological expeditions remain things only the
player can handle directly.

---

## The Current Focus: Combat MVP

The four-phase vision is the north star. The immediate goal is a focused, polished
combat prototype that establishes the mechanical foundation everything else builds on.

**The MVP is a 2.5D top-down space combat simulator.** 3D ship assets render on a 2D
gameplay plane. A small streaming map — a handful of asteroid fields and points of
interest — hosts roaming AI patrol ships. The player fights, survives, and returns to
a station to swap modules. The loop is tight and testable.

Nothing in the MVP is throwaway. Every system is specced for modularity and future
expansion from the start.

---

## What the MVP Establishes

### Sim-Lite Physics
Ships have mass, momentum, and angular inertia. Turning takes time — heavy ships take
more. A shared thruster budget means strafing and turning compete for the same resource,
turning always winning. Hard turns bleed lateral velocity. Projectiles inherit the
firing ship's momentum. The universe applies gentle drag — not a vacuum, not an
arcade floor. Assisted steering ensures ships track the player's cursor cleanly without
oscillation, while still feeling physical.

### Weapons & Combat
Three archetypes — ballistic, energy, and missiles — each with distinct feel and
tactical purpose. Ballistic rounds chew through hull but scatter on shields. Energy
weapons strip shields efficiently but tax the ship's power pool. Missiles hit hard
but require shield stripping for full effect. Damage type interactions reward mixed
loadouts. Continuous beams and rapid-pulse energy weapons give the energy archetype
two distinct firing styles.

Heat is tracked per hardpoint. Power is shared across the whole ship. Both limit
sustained fire in different ways. Hardpoints themselves can be damaged — a destroyed
engine hardpoint kills thrust, a destroyed weapon hardpoint silences that gun. All
weapon stats live in JSON. No values are hardcoded.

### Ship Customization
Module slots for weapons and core systems — shields, engines, power plant, armor.
Swapped at stations. Real tradeoffs: fast engines eat power, heavy armor kills
maneuverability, energy-heavy loadouts risk power starvation under fire.

### Streaming Map
A small chunk-based world that loads and unloads as the player moves. No sector
transitions. The map feels like a continuous space rather than discrete levels.

### Observability From Day One
A PerformanceMonitor service instruments every system from the moment it is built.
Per-system timing data, active entity counts, and frame budget usage are visible
both in Godot's built-in debugger and via an in-game F3 overlay. No retrofitting
later — metrics are a first-class concern throughout development.

---

## Design Principles

**Seamless transitions.** No jarring shifts between gameplay modes or map areas.
Scale changes feel like a natural expansion of what the player is already doing.

**Persistent personal agency.** No matter how large the player's empire grows,
there are always things only they can do. Strategic scale never makes the personal
ship irrelevant.

**Meaningful progression.** Each advancement — a new ship, a new system, a new
phase — is earned and felt. Nothing is gated arbitrarily.

**Data-driven everything.** All tunable values live in JSON configuration files.
Balance passes happen without recompiling. The game is moddable by design.

**Modularity as a development forcing function.** Systems have single responsibilities
and clean interfaces. This serves both the architecture and the AI-assisted
development workflow — agent coding sessions stay focused and context stays manageable.

**Complexity on demand.** The game never forces depth on a player who wants
simplicity, and never caps the ceiling for a player who wants to go deep.

---

## Technical Foundation

| Concern | Approach |
|---|---|
| Engine | Godot 4.6 |
| Rendering | Full 3D on XZ plane; `Camera3D` perspective, top-down angle |
| Primary language | GDScript |
| Performance-critical | C# (projectile management) |
| Physics | `RigidBody3D` with Jolt for ships and asteroids; axis-locked to XZ plane (Y = 0) |
| Data | JSON configuration for all game data |
| Inter-system comms | Event bus — no direct cross-system references |
| Development method | Spec-first; one system per agent session; PerformanceMonitor built first |

---

## What Success Looks Like

### For the MVP
- The ship feels physical and responsive — mass and momentum are palpable
- Combat has tactical texture — weapon choice and positioning matter
- The streaming map feels seamless — no pops, no hitches, no loading screens
- The performance monitor shows healthy frame budgets under realistic combat load
- The whole loop — fly, fight, dock, customize, repeat — is satisfying on its own

### For the Full Game
- A player can spend their entire game never leaving their personal ship and have
  a rich, complete experience
- A player can build an empire spanning multiple systems and feel like a genuine
  galactic power
- The transition between those two modes of play happens gradually and naturally,
  never suddenly
- The game is as moddable as a player wants it to be

---

## What This Game Is Not

- Not a game where complexity is mandatory. Depth is always opt-in.
- Not a game with jarring mode switches. Every scale of play connects seamlessly.
- Not a game where the personal ship becomes obsolete. The player always has a
  reason to fly.
- Not a game balanced in the spec. Values are placeholders until playtesting says
  otherwise.
