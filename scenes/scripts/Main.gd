extends Control
## Root scene: bootstrap, tab router, top bar, modal stack, toasts, debug hotkeys.

const MODAL_SCENE: PackedScene = preload("res://scenes/components/Modal.tscn")
const ModalScript = preload("res://scenes/components/Modal.gd")
const ModalFactory = preload("res://scenes/scripts/ModalFactory.gd")
const TABS: Array[String] = ["farm", "animals", "market", "neighbors", "shop"]
const NEIGHBORS_TAB_TITLE: String = "Соседи"

var _factory: ModalFactory = ModalFactory.new()
var _modal_stack: Array = []
var _toast_tween: Tween = null

@onready var _bg: ColorRect = $Bg
@onready var _coins: Label = $Root/TopBar/HBox/Coins
@onready var _seeds: Label = $Root/TopBar/HBox/Seeds
@onready var _feed: Label = $Root/TopBar/HBox/Feed
@onready var _level: Label = $Root/TopBar/HBox/LevelBox/Level
@onready var _xp_bar: ProgressBar = $Root/TopBar/HBox/LevelBox/XpBar
@onready var _tab_bar: HBoxContainer = $Root/TabBar
@onready var _neighbors_tab: Button = $Root/TabBar/NeighborsTab
@onready var _modal_layer: Control = $ModalLayer
@onready var _toast: Label = $Toast


func _ready() -> void:
	_bg.color = Economy.color("bg")
	_toast.modulate.a = 0.0
	_connect_signals()
	_setup_tabs()
	var had_save: bool = SaveManager.load_or_create()
	TimeService.start(had_save)
	Signals.tab_requested.emit(TABS[0])


func _connect_signals() -> void:
	Signals.currencies_changed.connect(_on_currencies)
	Signals.xp_changed.connect(_on_xp)
	Signals.neighbors_changed.connect(_on_neighbors)
	Signals.modal_requested.connect(_on_modal_requested)
	Signals.modal_close_requested.connect(_on_modal_close)
	Signals.toast_requested.connect(_show_toast)
	Signals.welcome_back.connect(_on_welcome_back)
	Signals.ad_started.connect(_on_ad_started)
	Signals.ad_rewarded_completed.connect(_show_toast.bind("Награда получена!"))
	Signals.ad_failed.connect(_on_ad_failed)


func _setup_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	var buttons: Array[Node] = _tab_bar.get_children()
	for i: int in mini(buttons.size(), TABS.size()):
		var button: Button = buttons[i]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_on_tab_pressed.bind(TABS[i]))
	(buttons[0] as Button).button_pressed = true


func _on_tab_pressed(tab_id: String) -> void:
	Signals.tab_requested.emit(tab_id)


func _on_currencies(coins: int, seeds: int, feed: int) -> void:
	var cap: int = GameState.storage_cap()
	_coins.text = "Монеты\n%d" % coins
	_seeds.text = "Семена\n%d/%d" % [seeds, cap]
	_feed.text = "Корм\n%d/%d" % [feed, cap]


func _on_xp(level: int, xp_in_level: int, xp_needed: int) -> void:
	_level.text = "Уровень %d" % level
	_xp_bar.max_value = maxf(float(xp_needed), 1.0)
	_xp_bar.value = _xp_bar.max_value if xp_needed <= 0 else float(xp_in_level)


func _on_neighbors() -> void:
	var pending: int = GameState.pending_requests()
	_neighbors_tab.text = NEIGHBORS_TAB_TITLE if pending == 0 else "%s (%d)" % [NEIGHBORS_TAB_TITLE, pending]


func _on_modal_requested(modal_id: String, payload: Dictionary) -> void:
	var spec: Dictionary = _factory.spec(modal_id, payload)
	if spec.is_empty():
		push_error("Main: unknown modal '%s'" % modal_id)
		return
	var modal: ModalScript = MODAL_SCENE.instantiate()
	_modal_layer.add_child(modal)
	_modal_stack.append(modal)
	modal.open(str(spec["title"]), spec["builder"])


func _on_modal_close() -> void:
	if _modal_stack.is_empty():
		return
	var top: Node = _modal_stack.pop_back()
	top.queue_free()


func _on_welcome_back(summary: Dictionary) -> void:
	Signals.modal_requested.emit("welcome_back", summary)


func _on_ad_started(kind: String) -> void:
	_show_toast("Реклама (заглушка): %s" % kind)


func _on_ad_failed(kind: String, reason: String) -> void:
	_show_toast("Реклама недоступна (%s): %s" % [kind, reason])


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(Economy.ui_f("toast_seconds"))
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, Economy.ui_f("toast_fade_seconds"))


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	var debug: Dictionary = Economy.cfg_dict("debug")
	if key.keycode == KEY_F10:
		var seconds: float = float(debug.get("fast_forward_seconds", 0.0))
		TimeService.fast_forward(seconds)
		_show_toast("Отладка: время +%d с" % int(seconds))
	elif key.keycode == KEY_F9:
		GameState.debug_grant()
		_show_toast("Отладка: монеты и опыт")
