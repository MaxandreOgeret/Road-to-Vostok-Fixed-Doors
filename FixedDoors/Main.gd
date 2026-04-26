extends Node

const BASE_OPEN_ANGLE_META := &"fixed_doors_base_open_angle"
const CONFIG_AUTOLOAD_PATH := "/root/FixedDoorsConfig"
const OPENED_DOOR_COLLISION_KEY := "opened_door_collision"
const MOVING_DOOR_COLLISION_KEY := "moving_door_collision"
const INTERACTOR_PATHS := [
	"/root/Map/Core/Interactor",
	"/root/Map/Core/Player/Interactor",
	"Core/Interactor",
	"Core/Player/Interactor",
]
const LEGACY_OPEN_DOOR_INTERACTION_LAYER := 128
const CLOSED_DOOR_COLLISION_LAYER := 8
const CLOSED_DOOR_COLLISION_MASK := 1
const SIDE_EPSILON := 0.03
const ANGLE_EPSILON := 0.01
const CLOSED_POSITION_EPSILON := 0.25
const CLOSED_ROTATION_EPSILON := 8.0
const ACTIVE_DOOR_MAX_FRAMES := 300

var _interactor: RayCast3D
var _door_records: Dictionary = {}
var _active_doors: Dictionary = {}
var _current_scene: Node
var _player_colliders: Array[CollisionObject3D] = []
var _last_interact_frame := -1
var _opened_door_collision_enabled := false
var _moving_door_collision_enabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_sync_runtime_settings(true)
	_connect_config()

	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		_handle_interact_pressed()


func _process(_delta: float) -> void:
	_reset_scene_cache_if_needed()
	_sync_runtime_settings()

	_sync_active_door_collisions()

	if _active_doors.is_empty():
		set_process(false)


func _handle_interact_pressed() -> void:
	var frame := Engine.get_physics_frames()
	if _last_interact_frame == frame:
		return
	_last_interact_frame = frame
	_sync_runtime_settings(true)

	var interactor := _resolve_interactor()
	if interactor == null:
		return

	interactor.force_raycast_update()
	if not interactor.is_colliding():
		return

	var target := interactor.get_collider()
	if target == null:
		return

	var door := _door_from_target(target)
	if door == null:
		return
	_reset_scene_cache_if_needed()
	_track_door(door, target as CollisionObject3D if target is CollisionObject3D else null)
	_activate_door(door)

	if not bool(door.get(&"isOpen")):
		var player_position := _player_position(interactor)
		_configure_door(door, player_position)


func _configure_door(door: Node3D, player_position: Vector3) -> void:
	var base_open_angle := _base_open_angle(door)
	if absf(base_open_angle.y) <= ANGLE_EPSILON:
		return

	var side := _player_closed_side(door, player_position)
	if absf(side) <= SIDE_EPSILON:
		return

	var desired_open_angle := base_open_angle
	if side > 0.0:
		desired_open_angle.y = -base_open_angle.y
	else:
		desired_open_angle.y = base_open_angle.y

	var current_open_angle: Vector3 = door.get(&"openAngle")
	if current_open_angle.distance_to(desired_open_angle) <= ANGLE_EPSILON:
		return

	door.set(&"openAngle", desired_open_angle)


func _base_open_angle(door: Node3D) -> Vector3:
	if not door.has_meta(BASE_OPEN_ANGLE_META):
		door.set_meta(BASE_OPEN_ANGLE_META, door.get(&"openAngle"))
	return door.get_meta(BASE_OPEN_ANGLE_META)


func _player_closed_side(door: Node3D, player_position: Vector3) -> float:
	var default_basis := _closed_door_basis(door)
	var default_position: Vector3 = door.get(&"defaultPosition")
	var origin := door.global_position
	var parent := door.get_parent()

	if parent is Node3D:
		origin = (parent as Node3D).to_global(default_position)

	return (player_position - origin).dot(default_basis.z.normalized())


func _closed_door_basis(door: Node3D) -> Basis:
	var default_rotation: Vector3 = door.get(&"defaultRotation")
	var basis := Basis.from_euler(
		Vector3(
			deg_to_rad(default_rotation.x),
			deg_to_rad(default_rotation.y),
			deg_to_rad(default_rotation.z)
		)
	)
	var parent := door.get_parent()

	if parent is Node3D:
		basis = (parent as Node3D).global_transform.basis * basis

	return basis.orthonormalized()


func _player_position(interactor: RayCast3D) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	return interactor.global_position


func _door_from_target(target: Object) -> Node3D:
	if target is Node3D and _looks_like_door(target as Node3D):
		return target as Node3D

	if target is Node:
		var owner := (target as Node).owner
		if owner is Node3D and _looks_like_door(owner as Node3D):
			return owner as Node3D

		var node := target as Node
		while node != null:
			if node is Node3D and _looks_like_door(node as Node3D):
				return node as Node3D
			node = node.get_parent()

	return null


func _looks_like_door(node: Node3D) -> bool:
	return (
		node.has_method(&"Interact")
		and _has_property(node, &"openAngle")
		and _has_property(node, &"isOpen")
		and _has_property(node, &"defaultPosition")
		and _has_property(node, &"defaultRotation")
	)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if property.get("name") == property_name:
			return true
	return false


func _reset_scene_cache_if_needed() -> void:
	var scene := get_tree().current_scene
	if scene == _current_scene:
		return

	_current_scene = scene
	_interactor = null
	_door_records.clear()
	_active_doors.clear()
	_player_colliders.clear()
	set_process(false)


func _on_node_added(node: Node) -> void:
	if node is CollisionObject3D:
		call_deferred("_register_collision_object", node)


func _register_collision_object(node: Node) -> void:
	if not is_instance_valid(node) or not node is CollisionObject3D:
		return

	var collider := node as CollisionObject3D
	if collider.is_in_group("Player") and not _player_colliders.has(collider):
		_player_colliders.append(collider)

	if not collider.is_in_group("Interactable"):
		return

	var door := _door_from_target(collider)
	if door == null:
		return

	_reset_scene_cache_if_needed()
	_track_door(door, collider)

	var has_animation_time := _door_has_animation_time(door)
	if not _door_is_fully_closed(door, has_animation_time):
		var door_id := door.get_instance_id()
		_sync_door_collision(door, _door_records[door_id])
		if _door_is_moving(door, has_animation_time):
			_active_doors[door_id] = Engine.get_physics_frames() + ACTIVE_DOOR_MAX_FRAMES
			set_process(true)


func _connect_config() -> void:
	var config := get_node_or_null(CONFIG_AUTOLOAD_PATH)
	if config == null or not config.has_signal("settings_changed"):
		return
	if not config.is_connected("settings_changed", Callable(self, "_on_settings_changed")):
		config.connect("settings_changed", Callable(self, "_on_settings_changed"))


func _on_settings_changed() -> void:
	_sync_runtime_settings(true)


func _sync_runtime_settings(force: bool = false) -> void:
	var opened_collision_enabled := _bool_setting(OPENED_DOOR_COLLISION_KEY, false)
	var moving_collision_enabled := _bool_setting(MOVING_DOOR_COLLISION_KEY, false)
	if (
		not force
		and opened_collision_enabled == _opened_door_collision_enabled
		and moving_collision_enabled == _moving_door_collision_enabled
	):
		return

	_opened_door_collision_enabled = opened_collision_enabled
	_moving_door_collision_enabled = moving_collision_enabled


func _bool_setting(setting_key: String, default_value: bool) -> bool:
	var config := get_node_or_null(CONFIG_AUTOLOAD_PATH)
	if config != null and config.has_method("get_bool"):
		return bool(config.call("get_bool", setting_key, default_value))

	var config_file := ConfigFile.new()
	if config_file.load("user://MCM/FixedDoors/config.ini") == OK:
		var value: Variant = config_file.get_value("Bool", setting_key, default_value)
		if value is Dictionary:
			return bool((value as Dictionary).get("value", default_value))
		return bool(value)

	return default_value


func _track_door(door: Node3D, collider: CollisionObject3D = null) -> void:
	var door_id := door.get_instance_id()
	var record := _door_records.get(door_id, {})

	if record.is_empty():
		record = {
			"door": door,
			"colliders": [],
			"has_animation_time": _door_has_animation_time(door),
		}
		_door_records[door_id] = record

	if collider != null:
		var colliders: Array = record["colliders"]
		if not colliders.has(collider):
			colliders.append(collider)


func _activate_door(door: Node3D) -> void:
	var door_id := door.get_instance_id()
	var record: Dictionary = _door_records.get(door_id, {})
	if record.is_empty():
		return

	record["opened_door_collision_enabled"] = _opened_door_collision_enabled
	record["moving_door_collision_enabled"] = _moving_door_collision_enabled

	_active_doors[door_id] = Engine.get_physics_frames() + ACTIVE_DOOR_MAX_FRAMES
	set_process(true)


func _sync_active_door_collisions() -> void:
	var frame := Engine.get_physics_frames()

	for door_id in _active_doors.keys():
		var record: Dictionary = _door_records.get(door_id, {})
		if record.is_empty():
			_active_doors.erase(door_id)
			continue

		var door: Variant = record.get("door")
		if not is_instance_valid(door):
			_door_records.erase(door_id)
			_active_doors.erase(door_id)
			continue

		var interaction_only := _sync_door_collision(door as Node3D, record)
		if (
			frame >= int(_active_doors[door_id])
			and _door_collision_is_settled(door as Node3D, record, interaction_only)
		):
			_active_doors.erase(door_id)


func _sync_door_collision(door: Node3D, record: Dictionary) -> bool:
	var colliders: Array = record["colliders"]
	_remove_invalid_colliders(colliders)

	if colliders.is_empty():
		colliders.append_array(_door_interactable_colliders(door))

	var opened_door_collision_enabled := bool(
		record.get("opened_door_collision_enabled", _opened_door_collision_enabled)
	)
	var moving_door_collision_enabled := bool(
		record.get("moving_door_collision_enabled", _moving_door_collision_enabled)
	)
	var interaction_only := _door_should_be_interaction_only(
		door,
		bool(record["has_animation_time"]),
		opened_door_collision_enabled,
		moving_door_collision_enabled
	)
	if record.has("interaction_only") and bool(record["interaction_only"]) == interaction_only:
		return interaction_only

	for collider in colliders:
		if not is_instance_valid(collider):
			continue

		if interaction_only:
			_disable_player_collision(collider as CollisionObject3D)
		else:
			_restore_player_collision(collider as CollisionObject3D)

	record["interaction_only"] = interaction_only
	return interaction_only


func _door_collision_is_settled(door: Node3D, record: Dictionary, interaction_only: bool) -> bool:
	if _door_is_fully_closed(door, bool(record["has_animation_time"])):
		return not interaction_only
	if _door_is_moving(door, bool(record["has_animation_time"])):
		return false
	return true


func _door_should_be_interaction_only(
	door: Node3D,
	has_animation_time: bool,
	opened_door_collision_enabled: bool,
	moving_door_collision_enabled: bool
) -> bool:
	if _door_is_fully_closed(door, has_animation_time):
		return false
	if _door_is_moving(door, has_animation_time):
		return not moving_door_collision_enabled
	return not opened_door_collision_enabled


func _door_is_moving(door: Node3D, has_animation_time: bool) -> bool:
	return (
		has_animation_time
		and _has_property(door, &"animationTime")
		and float(door.get(&"animationTime")) > 0.0
	)


func _door_has_animation_time(door: Node3D) -> bool:
	return _has_property(door, &"animationTime")


func _remove_invalid_colliders(colliders: Array) -> void:
	var index := colliders.size() - 1
	while index >= 0:
		if not is_instance_valid(colliders[index]):
			colliders.remove_at(index)
		index -= 1


func _door_is_fully_closed(door: Node3D, has_animation_time: bool) -> bool:
	if bool(door.get(&"isOpen")):
		return false

	var default_position: Vector3 = door.get(&"defaultPosition")
	var default_rotation: Vector3 = door.get(&"defaultRotation")
	var is_near_closed := (
		door.position.distance_to(default_position) <= CLOSED_POSITION_EPSILON
		and door.rotation_degrees.distance_to(default_rotation) <= CLOSED_ROTATION_EPSILON
	)

	if has_animation_time:
		return float(door.get(&"animationTime")) <= 0.0 or is_near_closed

	return is_near_closed


func _door_interactable_colliders(door: Node) -> Array[CollisionObject3D]:
	var colliders: Array[CollisionObject3D] = []
	_collect_door_interactable_colliders(door, colliders)
	return colliders


func _collect_door_interactable_colliders(node: Node, colliders: Array[CollisionObject3D]) -> void:
	if node is CollisionObject3D and node.is_in_group("Interactable"):
		colliders.append(node as CollisionObject3D)

	for child in node.get_children():
		_collect_door_interactable_colliders(child, colliders)


func _disable_player_collision(collider: CollisionObject3D) -> void:
	_restore_closed_layer_if_needed(collider)

	for player_collider in _resolve_player_colliders():
		if is_instance_valid(player_collider):
			collider.add_collision_exception_with(player_collider)


func _restore_player_collision(collider: CollisionObject3D) -> void:
	_restore_closed_layer_if_needed(collider)

	for player_collider in _resolve_player_colliders():
		if is_instance_valid(player_collider):
			collider.remove_collision_exception_with(player_collider)


func _restore_closed_layer_if_needed(collider: CollisionObject3D) -> void:
	if (
		collider.collision_layer <= 0
		or collider.collision_layer == LEGACY_OPEN_DOOR_INTERACTION_LAYER
	):
		collider.collision_layer = CLOSED_DOOR_COLLISION_LAYER
	if collider.collision_mask <= 0:
		collider.collision_mask = CLOSED_DOOR_COLLISION_MASK


func _resolve_player_colliders() -> Array[CollisionObject3D]:
	_remove_invalid_colliders(_player_colliders)
	if not _player_colliders.is_empty():
		return _player_colliders

	for node in get_tree().get_nodes_in_group("Player"):
		if node is CollisionObject3D:
			_player_colliders.append(node as CollisionObject3D)

	return _player_colliders


func _resolve_interactor() -> RayCast3D:
	if _interactor != null and is_instance_valid(_interactor):
		return _interactor

	for path in INTERACTOR_PATHS:
		var node := get_node_or_null(path)
		if node is RayCast3D:
			_interactor = node as RayCast3D
			return _interactor

	var scene := get_tree().current_scene
	if scene == null:
		return null

	for path in INTERACTOR_PATHS:
		var node := scene.get_node_or_null(path)
		if node is RayCast3D:
			_interactor = node as RayCast3D
			return _interactor

	_interactor = _find_interactor(scene)
	return _interactor


func _find_interactor(node: Node) -> RayCast3D:
	if node is RayCast3D and node.name == "Interactor":
		return node as RayCast3D

	for child in node.get_children():
		var found := _find_interactor(child)
		if found != null:
			return found

	return null
