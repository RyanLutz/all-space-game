class_name SFStarRecord
extends RefCounted

## Unique catalog index.
var id: int

## Position in galaxy space (not world/scene space).
var galaxy_position: Vector3

## Recomputed on each warp — normalized direction from player system to this star.
var sky_direction: Vector3

## true = navigable system; false = backdrop only.
var is_destination: bool

## &"red_dwarf", &"yellow_dwarf", &"blue_giant", &"neutron_star", &"white_dwarf"
var star_type: StringName

## Derived from star_type + galactic position color gradient at generation.
var color: Color

## Angular size on sky dome; derived from type luminosity.
var apparent_size: float

## Luminosity weight; blue giants > 1.0, red dwarfs < 0.5.
var brightness: float

## Destination systems only — stable unique name (e.g. "sys_00421").
var system_id: StringName

## Deferred to Economy spec.
var faction_id: StringName

## Max distance from which this system can be jumped to.
var warp_range: float
