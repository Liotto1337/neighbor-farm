extends Node
## Persists GameState to user://save.json. Versioned payload + migration hook.

const SAVE_PATH: String = "user://save.json"

var _accum: float = 0.0
var _active: bool = false


func _ready() -> void:
	set_process(false)
	Signals.save_requested.connect(save_game)


func load_or_create() -> bool:
	var data: Dictionary = _read()
	var had_save: bool = not data.is_empty()
	if had_save:
		data = _migrate(data)
		var state: Variant = data.get("state", {})
		GameState.from_dict(state if state is Dictionary else {})
	else:
		GameState.new_game(randi())
	_active = true
	set_process(true)
	if not had_save:
		save_game()
	return had_save


func save_game() -> void:
	if not _active:
		return
	GameState.mark_saved(TimeService.now())
	var payload: Dictionary = {
		"version": Economy.cfg_i("save_version"),
		"state": GameState.to_dict(),
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(payload, "", false, true))
	file.close()
	Signals.game_saved.emit()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_error("SaveManager: corrupt save at %s, starting a new game" % SAVE_PATH)
		return {}
	return parsed


func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 0))
	var target: int = Economy.cfg_i("save_version")
	if version > target:
		push_error("SaveManager: save version %d is newer than game version %d" % [version, target])
	while version < target:
		data = _migrate_step(data, version)
		version += 1
	data["version"] = target
	return data


func _migrate_step(data: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		0:
			# v0 (prototype) stored the state at the root without a wrapper.
			if not data.has("state"):
				return {"version": from_version + 1, "state": data}
	return data


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= Economy.cfg_f("autosave_seconds"):
		_accum = 0.0
		save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game()
