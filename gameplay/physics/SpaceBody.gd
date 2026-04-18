extends RigidBody3D
class_name SpaceBody

## Shared physics interface for all world entities (ships, asteroids).
## Provides common properties, helpers, and the SpaceBody contract
## defined in Core Spec Section 9.
##
## Subclasses (Ship.gd, Asteroid.gd) extend this and add their own logic.
## SpaceBody owns: heading helpers, damage interface, Y=0 enforcement pattern.

# ─── Physics properties (set by subclass at init) ─────────────────────────────
var max_speed: float = 0.0
var alignment_drag_base: float = 0.0
var alignment_drag_current: float = 0.0

# ─── Convenience getters ──────────────────────────────────────────────────────

## Current velocity with Y zeroed (read-only convenience).
var velocity_xz: Vector3:
	get:
		var v := linear_velocity
		v.y = 0.0
		return v

## Current yaw rate in radians/sec. Only Y component is ever non-zero.
var yaw_rate: float:
	get:
		return angular_velocity.y

# ─── Heading helpers ──────────────────────────────────────────────────────────

## Godot 3D forward is -Z.
func get_heading() -> Vector3:
	return -transform.basis.z


## Signed angle (radians) from current heading to a world-space target.
## Positive = turn left (counter-clockwise from above), negative = turn right.
func get_heading_error(target_world: Vector3) -> float:
	var to_target := target_world - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var target_yaw := atan2(-to_target.x, -to_target.z)
	return wrapf(target_yaw - rotation.y, -PI, PI)


# ─── SpaceBody contract — damage interface ────────────────────────────────────

## Override in subclass. Base implementation just applies impulse.
func apply_damage(amount: float, _damage_type: String,
				  _hit_pos: Vector3, _component_ratio: float) -> void:
	push_warning("SpaceBody.apply_damage() called on base class — override in subclass")


func apply_impulse_at(impulse: Vector3, _position: Vector3 = Vector3.ZERO) -> void:
	impulse.y = 0.0
	apply_central_impulse(impulse)


# ─── Y=0 enforcement ─────────────────────────────────────────────────────────

## Call at the end of _physics_process in subclasses.
func enforce_play_plane() -> void:
	if absf(global_position.y) > 0.0001:
		var p := global_position
		p.y = 0.0
		global_position = p
