extends Node
## Persists GameState to user://save.json and, on Yandex Games, to the player's cloud data
## (YandexSdk getData / setData) so progress follows a signed-in player across devices.
## Versioned payload + migration hook. At start-up the newer of the local and cloud saves wins
## (by real-time "saved_at"); the cloud copy is refreshed at most every cloud_save_seconds, and
## right away for important saves (purchases, leaving the tab).

## Emitted once the save is chosen and GameState is filled; Main starts the game on it.
signal loaded(had_save: bool)

const SAVE_PATH: String = "user://save.json"
## Cloud data stays well under the 200 KB per-player limit; bigger saves are skipped.
const CLOUD_LIMIT_BYTES: int = 190000

var _accum: float = 0.0
var _active: bool = false
var _booted: bool = false
var _saved_at: float = 0.0
var _cloud_accum: float = 0.0
var _cloud_pending: String = ""


func _ready() -> void:
	set_process(false)
	Signals.save_requested.connect(save_game)
	YandexSdk.auth_finished.connect(_on_auth_finished)


## Loads the game. On Web it first waits (briefly) for the cloud save; emits `loaded`.
func boot() -> void:
	if YandexSdk.cloud_checked or not (YandexSdk.is_pending() or YandexSdk.is_ready()):
		_finish_boot(YandexSdk.cloud_result)
		return
	YandexSdk.cloud_loaded.connect(_finish_boot, CONNECT_ONE_SHOT)
	get_tree().create_timer(Economy.cfg_f("cloud_boot_timeout_seconds")).timeout.connect(
		_finish_boot.bind({"ok": false, "error": "timeout"}))


func _finish_boot(cloud_result: Dictionary) -> void:
	if _booted:
		return
	_booted = true
	var local: Dictionary = _read()
	if not local.is_empty():
		local = _migrate(local)
	var cloud: Dictionary = _cloud_payload(cloud_result)
	var data: Dictionary = local if _saved_time(local) >= _saved_time(cloud) else cloud
	var had_save: bool = not data.is_empty()
	if had_save:
		var state: Variant = data.get("state", {})
		GameState.from_dict(state if state is Dictionary else {})
	else:
		GameState.new_game(randi())
	_saved_at = maxf(_saved_time(data), 0.0)
	_active = true
	set_process(true)
	loaded.emit(had_save)
	# Align both copies (newer cloud written locally, newer local uploaded). Deferred until the
	# clock has applied offline progress: saving stamps last_save.
	if _saved_time(local) != _saved_time(cloud) or not had_save:
		save_game.call_deferred(true)


## Writes the local save; `important` also sends it to the cloud immediately.
func save_game(important: bool = false) -> void:
	if not _active:
		return
	GameState.mark_saved(TimeService.now())
	_saved_at = Time.get_unix_time_from_system()
	var payload: Dictionary = {
		"version": Economy.cfg_i("save_version"),
		"saved_at": _saved_at,
		"state": GameState.to_dict(),
	}
	_queue_cloud(payload, important)
	if _write_local(payload):
		Signals.game_saved.emit()


func _write_local(payload: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "", false, true))
	file.close()
	return true


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
	_cloud_accum += delta
	if not _cloud_pending.is_empty() and _cloud_accum >= Economy.cfg_f("cloud_save_seconds"):
		_flush_cloud(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game(true)


# =====================================================================
# Cloud (Yandex player data)
# =====================================================================

func _queue_cloud(payload: Dictionary, important: bool) -> void:
	if not YandexSdk.cloud_available:
		return
	var data: String = JSON.stringify({"save": JSON.stringify(payload, "", false, true), "saved_at": _saved_at})
	if data.to_utf8_buffer().size() > CLOUD_LIMIT_BYTES:
		push_warning("SaveManager: save too big for the cloud (%d bytes)" % data.to_utf8_buffer().size())
		return
	_cloud_pending = data
	if important:
		_flush_cloud(true)


## setData is limited to 100 calls per 5 minutes: routine saves go out every
## cloud_save_seconds, important ones immediately with flush.
func _flush_cloud(flush: bool) -> void:
	if _cloud_pending.is_empty():
		return
	YandexSdk.save_cloud(_cloud_pending, flush)
	_cloud_pending = ""
	_cloud_accum = 0.0


## Save payload inside a getData() result, migrated; {} when there is none.
func _cloud_payload(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return {}
	var data: Variant = result.get("data", {})
	if not data is Dictionary or not (data as Dictionary).has("save"):
		return {}
	var parsed: Variant = JSON.parse_string(str(data["save"]))
	if not parsed is Dictionary:
		push_warning("SaveManager: corrupt cloud save ignored")
		return {}
	return _migrate(parsed)


func _saved_time(payload: Dictionary) -> float:
	return float(payload.get("saved_at", 0.0)) if not payload.is_empty() else -1.0


## After signing in: a newer cloud save replaces this device's progress (page reload);
## otherwise this progress is uploaded to the account.
func _on_auth_finished(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		Signals.toast_requested.emit("Вход не выполнен")
		return
	var cloud: Dictionary = _cloud_payload(result)
	if not cloud.is_empty() and _saved_time(cloud) > _saved_at:
		_active = false
		_write_local(cloud)
		Signals.toast_requested.emit("Загружаем прогресс из аккаунта…")
		YandexSdk.reload_page()
		return
	save_game(true)
	Signals.toast_requested.emit("Готово! Прогресс сохраняется в аккаунте Яндекса")
