extends Node

const BASE_OPEN_ANGLE_META := &"fixed_doors_base_open_angle"
const INTERACTOR_PATHS := [
	"/root/Map/Core/Interactor",
	"/root/Map/Core/Player/Interactor",
	"Core/Interactor",
	"Core/Player/Interactor",
]
const SIDE_EPSILON := 0.03
const ANGLE_EPSILON := 0.01

var _interactor: RayCast3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		_configure_current_target()


func _physics_process(_delta: float) -> void:
	_configure_current_target()


func _configure_current_target() -> void:
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
	if bool(door.get(&"isOpen")):
		return

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
		and node.has_method(&"UpdateTooltip")
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
