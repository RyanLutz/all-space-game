extends Node
class_name HardpointComponent

## Hardpoint behavior: type, arc constraints, heat management, damage state, fire groups.
## Attached to the hardpoint empty node (HardpointEmpty_*). Owns the weapon model instance.

# ─── Configuration (set at assembly time) ────────────────────────────────────
var hardpoint_id: String = ""
var hardpoint_type: String = "fixed"  # fixed, gimbal, partial_turret, full_turret
var size: String = "small"
var fire_arc_degrees: float = 5.0
var fire_groups: Array[int] = []  # 0-based indices (converted from 1-based JSON)

# ─── Heat System ─────────────────────────────────────────────────────────────
var heat_capacity: float = 100.0
var heat_current: float = 0.0
var heat_per_shot: float = 0.0  # Copied from weapon data at assembly
var passive_cooling: float = 15.0
var overheat_cooldown: float = 2.0
var is_overheated: bool = false
var _overheat_timer: float = 0.0

# ─── Damage State ────────────────────────────────────────────────────────────
var hp_max: float = 50.0
var hp_current: float = 50.0
var damage_state: String = "nominal"  # nominal, damaged, critical, destroyed

# ─── References ──────────────────────────────────────────────────────────────
var owner_ship: Ship = null
var _weapon_component: Node = null
var _weapon_model: Node3D = null
var _event_bus: Node = null


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")


func _process(delta: float) -> void:
	# Handle overheat lockout
	if is_overheated:
		_overheat_timer -= delta
		if _overheat_timer <= 0.0:
			is_overheated = false
	else:
		# Passive cooling
		heat_current = maxf(0.0, heat_current - passive_cooling * delta)


# ─── Fire Group Check ───────────────────────────────────────────────────────

func should_fire(input_fire: Array[bool]) -> bool:
	if damage_state == "destroyed":
		return false
	if is_overheated:
		return false

	# Check if any of our fire groups are active
	for group_idx in fire_groups:
		if group_idx < input_fire.size() and input_fire[group_idx]:
			return true
	return false


# ─── Aim Direction ────────────────────────────────────────────────────────────

func get_aim_direction() -> Vector3:
	var hardpoint_empty := get_parent() as Node3D
	if hardpoint_empty == null:
		return Vector3.FORWARD

	# Hardpoint's base forward direction (baked into mesh)
	var hardpoint_fwd := -hardpoint_empty.global_transform.basis.z
	hardpoint_fwd.y = 0.0
	hardpoint_fwd = hardpoint_fwd.normalized()

	# Fixed hardpoints don't track
	if hardpoint_type == "fixed":
		return hardpoint_fwd

	# Need weapon model and muzzle for tracking
	if _weapon_model == null or owner_ship == null:
		return hardpoint_fwd

	var muzzle := _weapon_model.get_node_or_null("Muzzle") as Node3D
	if muzzle == null:
		muzzle = _weapon_model.get_node_or_null("WeaponModel/Muzzle") as Node3D
	if muzzle == null:
		return hardpoint_fwd

	# Compute direction to aim target
	var to_target := owner_ship.input_aim_target - muzzle.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return hardpoint_fwd

	var desired_dir := to_target.normalized()

	# Full turret: no arc constraint
	if hardpoint_type == "full_turret":
		return desired_dir

	# Gimbal and partial_turret: clamp to fire arc
	var half_arc := deg_to_rad(fire_arc_degrees * 0.5)
	var angle_off := hardpoint_fwd.angle_to(desired_dir)

	if angle_off <= half_arc:
		return desired_dir

	# Target outside arc - rotate to arc edge toward target
	return hardpoint_fwd.slerp(desired_dir, half_arc / angle_off).normalized()


# ─── Heat Management ─────────────────────────────────────────────────────────

func apply_heat(amount: float) -> void:
	var multiplier := _get_damage_state_heat_multiplier()
	heat_current += amount * multiplier

	if heat_current >= heat_capacity:
		heat_current = heat_capacity
		trigger_overheat()


func trigger_overheat() -> void:
	is_overheated = true
	_overheat_timer = overheat_cooldown


func _get_damage_state_heat_multiplier() -> float:
	match damage_state:
		"damaged": return 1.3
		"critical": return 1.8
		_: return 1.0


# ─── Damage State Updates ───────────────────────────────────────────────────

func apply_damage(amount: float) -> void:
	if damage_state == "destroyed":
		return

	hp_current -= amount

	var prev_state := damage_state
	_update_damage_state()

	if damage_state == "destroyed" and prev_state != "destroyed":
		_event_bus.emit_signal("hardpoint_state_changed", owner_ship, hardpoint_id, "destroyed")


func _update_damage_state() -> void:
	var hp_percent := hp_current / hp_max
	if hp_percent <= 0.0:
		damage_state = "destroyed"
	elif hp_percent <= 0.25:
		damage_state = "critical"
	elif hp_percent <= 0.6:
		damage_state = "damaged"
	else:
		damage_state = "nominal"


# ─── Assembly ────────────────────────────────────────────────────────────────

func set_weapon_model(model: Node3D, component: Node) -> void:
	_weapon_model = model
	_weapon_component = component
	if component != null:
		component.hardpoint = self


func get_weapon_model() -> Node3D:
	return _weapon_model


func has_weapon() -> bool:
	return _weapon_component != null


# ─── Fire Rate Modifiers (from damage state) ─────────────────────────────────

func get_fire_rate_multiplier() -> float:
	match damage_state:
		"damaged": return 0.7
		"critical": return 0.4
		"destroyed": return 0.0
		_: return 1.0


# ─── Misfire Chance (critical state) ─────────────────────────────────────────

func roll_misfire() -> bool:
	if damage_state != "critical":
		return false
	# 15% misfire chance in critical state
	return randf() < 0.15
