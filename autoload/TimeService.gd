extends Node
## Game clock = unix time + persisted offset (debug fast-forward / IAP speedup).
## Drives GameState.tick() by polling unix time; no Timer nodes for game logic.

const SECONDS_PER_MINUTE: float = 60.0

var _accum: float = 0.0


func _ready() -> void:
	set_process(false)


func now() -> float:
	return Time.get_unix_time_from_system() + GameState.time_offset


func start(had_save: bool) -> void:
	var summary: Dictionary = {}
	if had_save:
		summary = _apply_offline()
	else:
		GameState.tick(now())
	GameState.emit_all()
	Signals.state_loaded.emit()
	if not summary.is_empty():
		Signals.welcome_back.emit(summary)
	set_process(true)


func fast_forward(seconds: float) -> void:
	GameState.add_time_offset(seconds)
	var t: float = now()
	GameState.tick(t)
	Signals.clock_tick.emit(t)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < Economy.cfg_f("ui_refresh_seconds"):
		return
	_accum = 0.0
	var t: float = now()
	GameState.tick(t)
	Signals.clock_tick.emit(t)


func _apply_offline() -> Dictionary:
	var elapsed: float = now() - GameState.last_save
	if elapsed <= 0.0:
		GameState.tick(now())
		return {}
	var cap: float = Economy.cfg_f("offline_cap_seconds")
	var capped: bool = elapsed > cap
	if capped:
		GameState.add_time_offset(cap - elapsed)
		elapsed = cap
	var before: Dictionary = GameState.snapshot_counts(GameState.last_save)
	var result: Dictionary = GameState.tick(now())
	var after: Dictionary = GameState.snapshot_counts(now())
	if elapsed < Economy.cfg_f("welcome_min_seconds"):
		return {}
	return _build_summary(elapsed, capped, before, after, result)


func _build_summary(elapsed: float, capped: bool, before: Dictionary, after: Dictionary, result: Dictionary) -> Dictionary:
	return {
		"seconds": elapsed,
		"capped": capped,
		"crops_ready": int(after["ready"]),
		"withered": maxi(0, int(after["withered"]) - int(before["withered"])),
		"animals_ready": int(after["animals_ready"]),
		"stall_coins": int(result.get("stall_coins", 0)),
		"trust_decay": int(result.get("trust_decay", 0)),
		"contract_gain": maxi(0, int(after["contract"]) - int(before["contract"])),
	}
