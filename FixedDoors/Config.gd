extends Node

signal settings_changed

const MOD_ID := "FixedDoors"
const MOD_NAME := "Fixed Doors"
const CONFIG_DIR := "user://MCM/%s" % MOD_ID
const CONFIG_FILE := "config.ini"
const MCM_HELPERS_RES := "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"
const OPENED_DOOR_COLLISION_KEY := "opened_door_collision"

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
	return config


func _ensure_config_dir() -> void:
	var root := DirAccess.open("user://")
	if root == null:
		return
	root.make_dir_recursive("MCM/%s" % MOD_ID)


func _config_path() -> String:
	return "%s/%s" % [CONFIG_DIR, CONFIG_FILE]
