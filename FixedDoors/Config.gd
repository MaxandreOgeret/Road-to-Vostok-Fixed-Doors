extends Node

signal settings_changed

const MOD_ID := "FixedDoors"
const MOD_NAME := "Fixed Doors"
const CONFIG_DIR := "user://MCM/%s" % MOD_ID
const CONFIG_FILE := "config.ini"
const MCM_HELPERS_RES := "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"
const OPENED_DOOR_COLLISION_KEY := "opened_door_collision"
const MOVING_DOOR_COLLISION_KEY := "moving_door_collision"
const DOOR_OBSTRUCTION_COLLISION_KEY := "door_obstruction_collision"
const OBSTRUCTION_BOX_SCALE_KEY := "obstruction_box_scale"
const COLLISION_LOGGING_KEY := "collision_logging"

var _config := ConfigFile.new()
var _mcm_helpers: Resource


func _ready() -> void:
	_mcm_helpers = _load_mcm_helpers()
	_ensure_config_dir()

	var defaults := _build_default_config()
	var config_path := _config_path()
	if FileAccess.file_exists(config_path):
		if _mcm_helpers != null and _mcm_helpers.has_method("CheckConfigurationHasUpdated"):
			_mcm_helpers.call("CheckConfigurationHasUpdated", MOD_ID, defaults, config_path)
		if _config.load(config_path) != OK:
			_config = defaults
			_config.save(config_path)
	else:
		_config = defaults
		_config.save(config_path)

	if _mcm_helpers != null and _mcm_helpers.has_method("RegisterConfiguration"):
		_mcm_helpers.call(
			"RegisterConfiguration",
			MOD_ID,
			MOD_NAME,
			CONFIG_DIR,
			"Configure Fixed Doors behavior.",
			{CONFIG_FILE: Callable(self, "_on_config_saved")}
		)


func get_bool(setting_key: String, default_value: bool = false) -> bool:
	var value: Variant = _config.get_value("Bool", setting_key, default_value)
	if value is Dictionary:
		return bool((value as Dictionary).get("value", default_value))
	return bool(value)


func get_float(setting_key: String, default_value: float = 0.0) -> float:
	var value: Variant = _config.get_value("Float", setting_key, default_value)
	if value is Dictionary:
		value = (value as Dictionary).get("value", default_value)
	if value is float or value is int:
		return float(value)
	return default_value


func _on_config_saved(config: ConfigFile) -> void:
	_config = config
	settings_changed.emit()


func _load_mcm_helpers() -> Resource:
	if not ResourceLoader.exists(MCM_HELPERS_RES):
		return null
	return load(MCM_HELPERS_RES) as Resource


func _build_default_config() -> ConfigFile:
	var config := ConfigFile.new()
	(
		config
		. set_value(
			"Bool",
			OPENED_DOOR_COLLISION_KEY,
			{
				"name": "Opened Door Collision (Newly Opened Only)",
				"tooltip":
				(
					"Keep open, opening, and closing doors collidable after this is enabled."
					+ " Doors already made pass-through may stay that way until they are"
					+ " closed or the map is reloaded."
				),
				"default": false,
				"value": false,
				"menu_pos": 10,
			}
		)
	)
	(
		config
		. set_value(
			"Bool",
			MOVING_DOOR_COLLISION_KEY,
			{
				"name": "Opening/Closing Door Collision",
				"tooltip": "Keep doors collidable while they are opening or closing.",
				"default": false,
				"value": false,
				"menu_pos": 20,
			}
		)
	)
	(
		config
		. set_value(
			"Bool",
			DOOR_OBSTRUCTION_COLLISION_KEY,
			{
				"name": "Door Obstruction Collision",
				"tooltip":
				(
					"Stop opening doors when their collision shape intersects"
					+ " environment collision. Loot items are ignored."
				),
				"default": false,
				"value": false,
				"menu_pos": 30,
			}
		)
	)
	(
		config
		. set_value(
			"Float",
			OBSTRUCTION_BOX_SCALE_KEY,
			{
				"name": "Obstruction Box Scale",
				"tooltip":
				(
					"Multiplier for the temporary obstruction proxy used by concave"
					+ " door collision shapes. Lower values are less likely to catch"
					+ " door frames, but may miss narrow obstructions."
				),
				"default": 0.7,
				"value": 0.7,
				"minRange": 0.25,
				"maxRange": 1.0,
				"step": 0.05,
				"menu_pos": 40,
			}
		)
	)
	(
		config
		. set_value(
			"Bool",
			COLLISION_LOGGING_KEY,
			{
				"name": "Door Collision Logging",
				"tooltip":
				(
					"Write Fixed Doors collision mode changes and obstruction stops"
					+ " to user://fixeddoors_collision.log and the Godot log."
				),
				"default": false,
				"value": false,
				"menu_pos": 50,
			}
		)
	)
	return config


func _ensure_config_dir() -> void:
	var root := DirAccess.open("user://")
	if root == null:
		return
	root.make_dir_recursive("MCM/%s" % MOD_ID)


func _config_path() -> String:
	return "%s/%s" % [CONFIG_DIR, CONFIG_FILE]
