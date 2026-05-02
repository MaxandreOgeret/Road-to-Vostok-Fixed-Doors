extends Node

const BASE_OPEN_ANGLE_META := &"fixed_doors_base_open_angle"
const CONFIG_AUTOLOAD_PATH := "/root/FixedDoorsConfig"
const OPENED_DOOR_COLLISION_KEY := "opened_door_collision"
const MOVING_DOOR_COLLISION_KEY := "moving_door_collision"
const DOOR_OBSTRUCTION_COLLISION_KEY := "door_obstruction_collision"
const OBSTRUCTION_BOX_SCALE_KEY := "obstruction_box_scale"
const COLLISION_LOGGING_KEY := "collision_logging"
const COLLISION_LOG_PATH := "user://fixeddoors_collision.log"
const INTERACTOR_PATHS := [
	"/root/Map/Core/Interactor",
	"/root/Map/Core/Player/Interactor",
	"Core/Interactor",
	"Core/Player/Interactor",
]
const LEGACY_OPEN_DOOR_INTERACTION_LAYER := 128
const CLOSED_DOOR_COLLISION_LAYER := 8
const CLOSED_DOOR_COLLISION_MASK := 1
const ENVIRONMENT_OBSTRUCTION_MASK := 1 | 8 | 16 | 32
const ITEM_COLLISION_LAYER := 4
const DEFAULT_OBSTRUCTION_BOX_SCALE := 0.7
const MIN_OBSTRUCTION_BOX_SCALE := 0.25
const MAX_OBSTRUCTION_BOX_SCALE := 1.0
const SIDE_EPSILON := 0.03
const ANGLE_EPSILON := 0.01
const CLOSED_POSITION_EPSILON := 0.25
const CLOSED_ROTATION_EPSILON := 8.0
const OBSTRUCTION_START_POSITION_EPSILON := 0.1
const OBSTRUCTION_START_ROTATION_EPSILON := 12.0
const ACTIVE_DOOR_MAX_FRAMES := 300
const MIN_OBSTRUCTION_BOX_SIZE := 0.01

var _interactor: RayCast3D
var _door_records: Dictionary = {}
var _active_doors: Dictionary = {}
var _current_scene: Node
var _player_colliders: Array[CollisionObject3D] = []
var _last_interact_frame := -1
var _opened_door_collision_enabled := false
var _moving_door_collision_enabled := false
var _door_obstruction_collision_enabled := false
var _obstruction_box_scale := DEFAULT_OBSTRUCTION_BOX_SCALE
var _collision_logging_enabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_sync_runtime_settings(true)
	_log_collision(
		(
			(
				"ready opened_collision=%s moving_collision=%s obstruction=%s"
				+ " obstruction_box_scale=%s logging=%s"
			)
			% [
				_opened_door_collision_enabled,
				_moving_door_collision_enabled,
				_door_obstruction_collision_enabled,
				_obstruction_box_scale,
				_collision_logging_enabled,
			]
		)
	)
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

	_sync_active_door_obstructions()
	_sync_active_door_collisions()

	if _active_doors.is_empty():
		set_process(false)


func _handle_interact_pressed() -> void:
	var frame := Engine.get_physics_frames()
	if _last_interact_frame == frame:
		return
	_last_interact_frame = frame
	_sync_runtime_settings(true)
	_log_collision("interact_pressed frame=%s" % frame)

	var interactor := _resolve_interactor()
	if interactor == null:
		_log_collision("interact_abort reason=no_interactor")
		return

	interactor.force_raycast_update()
	if not interactor.is_colliding():
		_log_collision(
			"interact_abort reason=raycast_not_colliding interactor=%s" % interactor.name
		)
		return

	var target := interactor.get_collider()
	if target == null:
		_log_collision("interact_abort reason=no_target interactor=%s" % interactor.name)
		return
	_log_collision("interact_target target=%s" % _object_debug_label(target))

	var door := _door_from_target(target)
	if door == null:
		_log_collision(
			"interact_abort reason=target_not_door target=%s" % _object_debug_label(target)
		)
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
	var obstruction_collision_enabled := _bool_setting(DOOR_OBSTRUCTION_COLLISION_KEY, false)
	var obstruction_box_scale := clampf(
		_float_setting(OBSTRUCTION_BOX_SCALE_KEY, DEFAULT_OBSTRUCTION_BOX_SCALE),
		MIN_OBSTRUCTION_BOX_SCALE,
		MAX_OBSTRUCTION_BOX_SCALE
	)
	var collision_logging_enabled := _bool_setting(COLLISION_LOGGING_KEY, false)
	if (
		not force
		and opened_collision_enabled == _opened_door_collision_enabled
		and moving_collision_enabled == _moving_door_collision_enabled
		and obstruction_collision_enabled == _door_obstruction_collision_enabled
		and is_equal_approx(obstruction_box_scale, _obstruction_box_scale)
		and collision_logging_enabled == _collision_logging_enabled
	):
		return

	_opened_door_collision_enabled = opened_collision_enabled
	_moving_door_collision_enabled = moving_collision_enabled
	_door_obstruction_collision_enabled = obstruction_collision_enabled
	_obstruction_box_scale = obstruction_box_scale
	_collision_logging_enabled = collision_logging_enabled
	_log_collision(
		(
			(
				"settings opened_collision=%s moving_collision=%s obstruction=%s"
				+ " obstruction_box_scale=%s logging=%s"
			)
			% [
				_opened_door_collision_enabled,
				_moving_door_collision_enabled,
				_door_obstruction_collision_enabled,
				_obstruction_box_scale,
				_collision_logging_enabled,
			]
		)
	)


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


func _float_setting(setting_key: String, default_value: float) -> float:
	var config := get_node_or_null(CONFIG_AUTOLOAD_PATH)
	if config != null and config.has_method("get_float"):
		return float(config.call("get_float", setting_key, default_value))

	var config_file := ConfigFile.new()
	if config_file.load("user://MCM/FixedDoors/config.ini") == OK:
		var value: Variant = config_file.get_value("Float", setting_key, default_value)
		if value is Dictionary:
			value = (value as Dictionary).get("value", default_value)
		if value is float or value is int:
			return float(value)

	return default_value


func _track_door(door: Node3D, collider: CollisionObject3D = null) -> void:
	var door_id := door.get_instance_id()
	var record := _door_records.get(door_id, {})

	if record.is_empty():
		record = {
			"door": door,
			"colliders": [],
			"collision_objects": [],
			"has_animation_time": _door_has_animation_time(door),
		}
		_door_records[door_id] = record

	if collider != null:
		var colliders: Array = record["colliders"]
		if not colliders.has(collider):
			colliders.append(collider)

		var collision_objects: Array = record["collision_objects"]
		if not collision_objects.has(collider):
			collision_objects.append(collider)

	if not record.has("last_safe_position"):
		_store_last_safe_door_pose(door, record)


func _activate_door(door: Node3D) -> void:
	var door_id := door.get_instance_id()
	var record: Dictionary = _door_records.get(door_id, {})
	if record.is_empty():
		return

	record["opened_door_collision_enabled"] = _opened_door_collision_enabled
	record["moving_door_collision_enabled"] = _moving_door_collision_enabled
	record["obstruction_debug_logged"] = false
	_store_last_safe_door_pose(door, record)
	_log_collision(
		(
			(
				"activate door=%s is_open=%s animation_time=%s obstruction=%s"
				+ " obstruction_box_scale=%s opened_collision=%s moving_collision=%s"
			)
			% [
				_door_label(door),
				bool(door.get(&"isOpen")),
				_door_animation_time(door, bool(record["has_animation_time"])),
				_door_obstruction_collision_enabled,
				_obstruction_box_scale,
				_opened_door_collision_enabled,
				_moving_door_collision_enabled,
			]
		)
	)

	_active_doors[door_id] = Engine.get_physics_frames() + ACTIVE_DOOR_MAX_FRAMES
	set_process(true)


func _sync_active_door_obstructions() -> void:
	if not _door_obstruction_collision_enabled:
		return

	for door_id in _active_doors.keys():
		var record: Dictionary = _door_records.get(door_id, {})
		if record.is_empty():
			continue

		var door: Variant = record.get("door")
		if not is_instance_valid(door):
			continue

		_sync_door_obstruction(door as Node3D, record)


func _sync_door_obstruction(door: Node3D, record: Dictionary) -> void:
	if not bool(record["has_animation_time"]):
		return
	if not _door_is_moving(door, true):
		_store_last_safe_door_pose(door, record)
		return
	if _door_is_near_obstruction_start_pose(door):
		_log_collision(
			(
				"obstruction_skip door=%s reason=near_closed_pose position=%s rotation=%s"
				% [_door_label(door), door.position, door.rotation_degrees]
			)
		)
		_store_last_safe_door_pose(door, record)
		return

	if _door_has_obstruction(door, record):
		var logical_open := bool(door.get(&"isOpen"))
		_log_collision(
			(
				("blocked door=%s logical_open=%s obstruction=%s position=%s" + " rotation=%s")
				% [
					_door_label(door),
					logical_open,
					record.get("last_obstruction", "unknown"),
					door.position,
					door.rotation_degrees,
				]
			)
		)
		_restore_last_safe_door_pose(door, record)
		door.set(&"isOpen", logical_open)
		door.set(&"animationTime", 0.0)
		record.erase("interaction_only")
		return

	_store_last_safe_door_pose(door, record)


func _door_has_obstruction(door: Node3D, record: Dictionary) -> bool:
	var colliders: Array = record["colliders"]
	_remove_invalid_colliders(colliders)

	if colliders.is_empty():
		colliders.append_array(_door_interactable_colliders(door))

	var collision_objects: Array = record["collision_objects"]
	_remove_invalid_colliders(collision_objects)

	for collision_object in _door_collision_objects(door):
		if not collision_objects.has(collision_object):
			collision_objects.append(collision_object)

	var exclude := _door_query_exclude(collision_objects)
	var space_state := door.get_world_3d().direct_space_state
	var obstruction_shapes := _door_obstruction_shapes(colliders)

	if not bool(record.get("obstruction_debug_logged", false)):
		record["obstruction_debug_logged"] = true
		_log_collision(
			(
				(
					"obstruction_check door=%s colliders=%s collision_objects=%s"
					+ " shapes=%s exclude=%s mask=%s position=%s rotation=%s"
				)
				% [
					_door_label(door),
					_debug_collision_objects(colliders),
					_debug_collision_objects(collision_objects),
					_debug_collision_shapes(obstruction_shapes),
					exclude.size(),
					ENVIRONMENT_OBSTRUCTION_MASK,
					door.position,
					door.rotation_degrees,
				]
			)
		)

	for shape in obstruction_shapes:
		var obstruction := _shape_obstruction(shape, space_state, exclude)
		if not obstruction.is_empty():
			record["last_obstruction"] = obstruction
			return true

	return false


func _shape_obstruction(
	shape: CollisionShape3D, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID]
) -> String:
	if shape.disabled or shape.shape == null:
		_log_collision("skip_shape shape=%s disabled_or_empty=true" % _collision_shape_label(shape))
		return ""

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _obstruction_query_shape(shape)
	query.transform = _obstruction_query_transform(shape)
	query.collision_mask = ENVIRONMENT_OBSTRUCTION_MASK
	query.exclude = exclude
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits := space_state.intersect_shape(query, 16)
	if not hits.is_empty():
		_log_collision(
			(
				(
					"shape_hits shape=%s shape_type=%s source_size=%s"
					+ " query_shape_type=%s query_size=%s scale=%s origin=%s hits=%s"
				)
				% [
					_collision_shape_label(shape),
					shape.shape.get_class(),
					_shape_debug_size(shape.shape),
					query.shape.get_class(),
					_shape_debug_size(query.shape),
					_obstruction_box_scale,
					query.transform.origin,
					hits.size(),
				]
			)
		)

	for hit in hits:
		var collider: Variant = hit.get("collider")
		if collider is CollisionObject3D:
			if _is_ignored_obstruction(collider as CollisionObject3D):
				_log_collision(
					(
						("ignored_hit shape=%s collider=%s" + " layer=%s mask=%s groups=%s")
						% [
							_collision_shape_label(shape),
							_collision_object_label(collider as CollisionObject3D),
							(collider as CollisionObject3D).collision_layer,
							(collider as CollisionObject3D).collision_mask,
							(collider as CollisionObject3D).get_groups(),
						]
					)
				)
				continue
			_log_collision(
				(
					("blocking_hit shape=%s collider=%s layer=%s mask=%s groups=%s")
					% [
						_collision_shape_label(shape),
						_collision_object_label(collider as CollisionObject3D),
						(collider as CollisionObject3D).collision_layer,
						(collider as CollisionObject3D).collision_mask,
						(collider as CollisionObject3D).get_groups(),
					]
				)
			)
			return (
				"%s via %s" % [_collision_object_label(collider as CollisionObject3D), shape.name]
			)
		_log_collision("blocking_hit shape=%s collider=unknown" % _collision_shape_label(shape))
		return "unknown collider via %s" % shape.name

	return ""


func _obstruction_query_shape(shape: CollisionShape3D) -> Shape3D:
	if shape.shape is ConcavePolygonShape3D:
		var box := BoxShape3D.new()
		box.size = (
			(
				_concave_shape_aabb(shape.shape as ConcavePolygonShape3D).size
				* _obstruction_box_scale
			)
			. maxf(MIN_OBSTRUCTION_BOX_SIZE)
		)
		return box

	return shape.shape


func _obstruction_query_transform(shape: CollisionShape3D) -> Transform3D:
	if shape.shape is ConcavePolygonShape3D:
		var aabb := _concave_shape_aabb(shape.shape as ConcavePolygonShape3D)
		var transform := shape.global_transform
		transform.origin += transform.basis * (aabb.position + (aabb.size * 0.5))
		return transform

	return shape.global_transform


func _concave_shape_aabb(shape: ConcavePolygonShape3D) -> AABB:
	var vertices := shape.data
	if vertices.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE * MIN_OBSTRUCTION_BOX_SIZE)

	var min_position: Vector3 = vertices[0]
	var max_position: Vector3 = vertices[0]
	for vertex in vertices:
		min_position = min_position.min(vertex)
		max_position = max_position.max(vertex)

	return AABB(min_position, max_position - min_position)


func _shape_debug_size(shape: Shape3D) -> Vector3:
	if shape is ConcavePolygonShape3D:
		return _concave_shape_aabb(shape as ConcavePolygonShape3D).size
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size
	if shape is SphereShape3D:
		return Vector3.ONE * (shape as SphereShape3D).radius * 2.0
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return Vector3(
			capsule.radius * 2.0, capsule.height + (capsule.radius * 2.0), capsule.radius * 2.0
		)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	return Vector3.ZERO


func _door_query_exclude(collision_objects: Array) -> Array[RID]:
	var exclude: Array[RID] = []

	for collision_object in collision_objects:
		if is_instance_valid(collision_object):
			exclude.append((collision_object as CollisionObject3D).get_rid())

	for player_collider in _resolve_player_colliders():
		if is_instance_valid(player_collider):
			exclude.append(player_collider.get_rid())

	return exclude


func _store_last_safe_door_pose(door: Node3D, record: Dictionary) -> void:
	record["last_safe_position"] = door.position
	record["last_safe_rotation"] = door.rotation_degrees


func _restore_last_safe_door_pose(door: Node3D, record: Dictionary) -> void:
	if not record.has("last_safe_position") or not record.has("last_safe_rotation"):
		return

	door.position = record["last_safe_position"]
	door.rotation_degrees = record["last_safe_rotation"]


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

	_log_collision(
		(
			(
				"mode door=%s state=%s is_open=%s moving=%s colliders=%s"
				+ " opened_collision=%s moving_collision=%s"
			)
			% [
				_door_label(door),
				"interaction_only" if interaction_only else "physical",
				bool(door.get(&"isOpen")),
				_door_is_moving(door, bool(record["has_animation_time"])),
				colliders.size(),
				opened_door_collision_enabled,
				moving_door_collision_enabled,
			]
		)
	)

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
	if _door_is_fully_closed(door, has_animation_time) or _door_is_fully_open(door):
		return false
	if has_animation_time:
		return float(door.get(&"animationTime")) > 0.0
	return not _door_is_fully_closed(door, has_animation_time) and not _door_is_fully_open(door)


func _door_has_animation_time(door: Node3D) -> bool:
	return _has_property(door, &"animationTime")


func _door_animation_time(door: Node3D, has_animation_time: bool) -> float:
	if not has_animation_time:
		return 0.0
	return float(door.get(&"animationTime"))


func _door_is_near_obstruction_start_pose(door: Node3D) -> bool:
	var default_position: Vector3 = door.get(&"defaultPosition")
	var default_rotation: Vector3 = door.get(&"defaultRotation")
	return (
		door.position.distance_to(default_position) <= OBSTRUCTION_START_POSITION_EPSILON
		and (
			door.rotation_degrees.distance_to(default_rotation)
			<= OBSTRUCTION_START_ROTATION_EPSILON
		)
	)


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


func _door_is_fully_open(door: Node3D) -> bool:
	if not bool(door.get(&"isOpen")):
		return false

	var default_position: Vector3 = door.get(&"defaultPosition")
	var default_rotation: Vector3 = door.get(&"defaultRotation")
	var open_angle: Vector3 = door.get(&"openAngle")
	var open_offset := Vector3.ZERO
	if _has_property(door, &"openOffset"):
		open_offset = door.get(&"openOffset")

	return (
		door.position.distance_to(default_position + open_offset) <= CLOSED_POSITION_EPSILON
		and (
			door.rotation_degrees.distance_to(default_rotation + open_angle)
			<= CLOSED_ROTATION_EPSILON
		)
	)


func _door_interactable_colliders(door: Node) -> Array[CollisionObject3D]:
	var colliders: Array[CollisionObject3D] = []
	_collect_door_interactable_colliders(door, colliders)
	return colliders


func _door_collision_objects(door: Node) -> Array[CollisionObject3D]:
	var collision_objects: Array[CollisionObject3D] = []
	_collect_door_collision_objects(door, collision_objects)
	return collision_objects


func _door_obstruction_shapes(colliders: Array) -> Array[CollisionShape3D]:
	var collision_shapes: Array[CollisionShape3D] = []
	for collider in colliders:
		if is_instance_valid(collider):
			_collect_door_collision_shapes(collider as Node, collision_shapes)
	return collision_shapes


func _collect_door_interactable_colliders(node: Node, colliders: Array[CollisionObject3D]) -> void:
	if node is CollisionObject3D and node.is_in_group("Interactable"):
		colliders.append(node as CollisionObject3D)

	for child in node.get_children():
		_collect_door_interactable_colliders(child, colliders)


func _collect_door_collision_objects(
	node: Node, collision_objects: Array[CollisionObject3D]
) -> void:
	if node is CollisionObject3D:
		collision_objects.append(node as CollisionObject3D)

	for child in node.get_children():
		_collect_door_collision_objects(child, collision_objects)


func _collect_door_collision_shapes(node: Node, collision_shapes: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		collision_shapes.append(node as CollisionShape3D)

	for child in node.get_children():
		_collect_door_collision_shapes(child, collision_shapes)


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


func _is_player_collider(collider: CollisionObject3D) -> bool:
	if collider.is_in_group("Player"):
		return true

	for player_collider in _resolve_player_colliders():
		if collider == player_collider:
			return true

	return false


func _is_item_collider(collider: CollisionObject3D) -> bool:
	return collider.is_in_group("Item") or bool(collider.collision_layer & ITEM_COLLISION_LAYER)


func _is_ignored_obstruction(collider: CollisionObject3D) -> bool:
	return _is_player_collider(collider) or _is_item_collider(collider)


func _log_collision(message: String) -> void:
	if not _collision_logging_enabled:
		return

	var line := (
		"[FixedDoors][Collision] %s %s"
		% [
			Time.get_datetime_string_from_system(),
			message,
		]
	)
	print(line)
	_append_log(COLLISION_LOG_PATH, line)


func _append_log(path: String, line: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return

	file.seek_end()
	file.store_line(line)


func _door_label(door: Node3D) -> String:
	return "%s#%s" % [door.name, door.get_instance_id()]


func _collision_object_label(collider: CollisionObject3D) -> String:
	return "%s#%s" % [collider.name, collider.get_instance_id()]


func _collision_shape_label(shape: CollisionShape3D) -> String:
	return "%s#%s" % [shape.name, shape.get_instance_id()]


func _debug_collision_objects(collision_objects: Array) -> String:
	var labels: Array[String] = []
	for collision_object in collision_objects:
		if is_instance_valid(collision_object):
			labels.append(_collision_object_label(collision_object as CollisionObject3D))
	return ", ".join(labels)


func _debug_collision_shapes(collision_shapes: Array[CollisionShape3D]) -> String:
	var labels: Array[String] = []
	for collision_shape in collision_shapes:
		if is_instance_valid(collision_shape):
			labels.append(_collision_shape_label(collision_shape))
	return ", ".join(labels)


func _object_debug_label(object: Object) -> String:
	if object == null:
		return "<null>"
	if object is Node:
		var node := object as Node
		return (
			"%s#%s path=%s groups=%s"
			% [node.name, node.get_instance_id(), node.get_path(), node.get_groups()]
		)
	return "%s#%s" % [object.get_class(), object.get_instance_id()]


func _resolve_interactor() -> RayCast3D:
	if _interactor != null and is_instance_valid(_interactor):
		return _interactor

	for path in INTERACTOR_PATHS:
		var node := get_node_or_null(path)
		if node is RayCast3D:
			_interactor = node as RayCast3D
			_log_collision("resolved_interactor path=%s node=%s" % [path, _interactor.name])
			return _interactor

	var scene := get_tree().current_scene
	if scene == null:
		_log_collision("resolve_interactor_abort reason=no_current_scene")
		return null

	for path in INTERACTOR_PATHS:
		var node := scene.get_node_or_null(path)
		if node is RayCast3D:
			_interactor = node as RayCast3D
			_log_collision("resolved_interactor scene_path=%s node=%s" % [path, _interactor.name])
			return _interactor

	_interactor = _find_interactor(scene)
	if _interactor == null:
		_log_collision("resolve_interactor_abort reason=not_found scene=%s" % scene.name)
	else:
		_log_collision("resolved_interactor fallback node=%s" % _interactor.name)
	return _interactor


func _find_interactor(node: Node) -> RayCast3D:
	if node is RayCast3D and node.name == "Interactor":
		return node as RayCast3D

	for child in node.get_children():
		var found := _find_interactor(child)
		if found != null:
			return found

	return null
