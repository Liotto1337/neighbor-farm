extends PanelContainer
## Weekly co-op contract summary row. Self-updating from Signals.

const Fmt = preload("res://scenes/scripts/Fmt.gd")

@onready var _title: Label = $VBox/Title
@onready var _bar: ProgressBar = $VBox/Bar
@onready var _info: Label = $VBox/Info
@onready var _details: Button = $VBox/Details


func _ready() -> void:
	_details.pressed.connect(_on_details)
	Signals.contract_changed.connect(_refresh)
	Signals.state_loaded.connect(_refresh)
	Signals.clock_tick.connect(_on_clock)


func _on_clock(_now: float) -> void:
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	var def: Dictionary = GameState.contract_def()
	if def.is_empty():
		_title.text = "Нет активного контракта"
		_info.text = ""
		_bar.value = 0.0
		return
	var progress: int = GameState.contract_progress()
	var target: int = GameState.contract_target()
	_title.text = str(def["title"])
	_bar.max_value = maxf(float(target), 1.0)
	_bar.value = float(progress)
	var status: String = "осталось %s" % Fmt.duration(GameState.contract_ends_at() - TimeService.now())
	if GameState.contract_claimed():
		status = "награда получена"
	elif progress >= target:
		status = "сундук готов!"
	_info.text = "%s: %d / %d · %s" % [Economy.item_name(str(def["item"])), progress, target, status]


func _on_details() -> void:
	Signals.modal_requested.emit("contract_details", {})
