extends Control
## Root scene: bootstrap, tab router, top bar, modal stack, toasts, debug hotkeys.

const MODAL_SCENE: PackedScene = preload("res://scenes/components/Modal.tscn")
const ModalScript = preload("res://scenes/components/Modal.gd")
const ModalFactory = preload("res://scenes/scripts/ModalFactory.gd")
const CurrencyChip = preload("res://scenes/components/CurrencyChip.gd")
const TABS: Array[String] = ["farm", "animals", "market", "neighbors", "shop"]
const NEIGHBORS_TAB_TITLE: String = "Соседи"
const BG_GRADIENT_HEIGHT: int = 256

var _factory: ModalFactory = ModalFactory.new()
var _modal_stack: Array = []
var _toast_tween: Tween = null
var _tab_tween: Tween = null
var _xp_tween: Tween = null
var _tab_index: int = 0
var _shown_level: int = 0
## Counter values currently displayed in the top bar (they roll towards the real ones).
var _shown: Dictionary = {}
var _counter_tweens: Dictionary = {}

@onready var _bg: TextureRect = $Bg
@onready var _coins: CurrencyChip = $Root/TopBar/HBox/Coins
@onready var _seeds: CurrencyChip = $Root/TopBar/HBox/Seeds
@onready var _feed: CurrencyChip = $Root/TopBar/HBox/Feed
@onready var _level: CurrencyChip = $Root/TopBar/HBox/LevelBox/Level
@onready var _xp_bar: ProgressBar = $Root/TopBar/HBox/LevelBox/XpBar
@onready var _tab_bar: HBoxContainer = $Root/TabBar
@onready var _neighbors_tab: Button = $Root/TabBar/NeighborsTab
@onready var _content: Control = $Root/Content
@onready var _modal_layer: Control = $ModalLayer
@onready var _toast: Label = $Toast


func _ready() -> void:
	_bg.texture = _make_bg_gradient()
	_toast.modulate.a = 0.0
	_toast.resized.connect(func() -> void: _toast.pivot_offset = _toast.size * 0.5)
	_connect_signals()
	_setup_tabs()
	var had_save: bool = SaveManager.load_or_create()
	TimeService.start(had_save)
	Signals.tab_requested.emit(TABS[0])


## Vertical sky-to-ground gradient behind everything (top/middle/bottom from config colors).
func _make_bg_gradient() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Economy.color("bg_top"), Economy.color("bg"), Economy.color("bg_bottom")])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = BG_GRADIENT_HEIGHT
	return texture


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
	Signals.tab_requested.connect(_on_tab_shown)


func _setup_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	var buttons: Array[Node] = _tab_bar.get_children()
	for i: int in mini(buttons.size(), TABS.size()):
		var button: Button = buttons[i]
		button.toggle_mode = true
		button.set_meta(UiFx.SFX_META, "")
		button.button_group = group
		button.pressed.connect(_on_tab_pressed.bind(TABS[i]))
	(buttons[0] as Button).button_pressed = true


func _on_tab_pressed(tab_id: String) -> void:
	Signals.tab_requested.emit(tab_id)


## Slides the newly shown view in from the side of the tab it came from. Connected after the
## views, so the target view is already visible here.
func _on_tab_shown(tab_id: String) -> void:
	var index: int = TABS.find(tab_id)
	var direction: float = signf(float(index - _tab_index))
	_tab_index = index
	if _tab_tween != null and _tab_tween.is_valid():
		_tab_tween.kill()
	for view: Node in _content.get_children():
		var control: Control = view
		control.position = Vector2.ZERO
		control.modulate.a = 1.0
		if not control.visible or direction == 0.0:
			continue
		var seconds: float = Economy.anim_f("tab_seconds")
		_tab_tween = create_tween().set_parallel()
		control.position.x = direction * Economy.anim_f("tab_slide")
		control.modulate.a = 0.0
		_tab_tween.tween_property(control, "position:x", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tab_tween.tween_property(control, "modulate:a", 1.0, seconds)


func _on_currencies(coins: int, seeds: int, feed: int) -> void:
	_roll_counter("coins", coins)
	_roll_counter("seeds", seeds)
	_roll_counter("feed", feed)


## Rolls the displayed number towards `value`; a gain also flashes the chip.
func _roll_counter(key: String, value: int) -> void:
	if not _shown.has(key):
		_shown[key] = value
		_set_counter(float(value), key)
		return
	var from: int = int(_shown[key])
	if from == value:
		_set_counter(float(value), key)
		return
	var old: Variant = _counter_tweens.get(key, null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tween: Tween = create_tween()
	_counter_tweens[key] = tween
	tween.tween_method(_set_counter.bind(key), float(from), float(value), Economy.anim_f("counter_seconds")) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if value > from:
		UiFx.flash(_counter_label(key))
		if key == "coins":
			Audio.play("coin")


func _set_counter(shown: float, key: String) -> void:
	var value: int = roundi(shown)
	_shown[key] = value
	var cap: int = GameState.storage_cap()
	if key == "coins":
		_coins.show_value("Монеты", str(value))
	elif key == "seeds":
		_seeds.show_value("Семена", "%d/%d" % [value, cap])
	else:
		_feed.show_value("Корм", "%d/%d" % [value, cap])


func _counter_label(key: String) -> CurrencyChip:
	if key == "coins":
		return _coins
	return _seeds if key == "seeds" else _feed


func _on_xp(level: int, xp_in_level: int, xp_needed: int) -> void:
	_level.show_value("", "Уровень %d" % level)
	var target_max: float = maxf(float(xp_needed), 1.0)
	var target: float = target_max if xp_needed <= 0 else float(xp_in_level)
	if _xp_tween != null and _xp_tween.is_valid():
		_xp_tween.kill()
	if _shown_level == 0:
		_xp_bar.max_value = target_max
		_xp_bar.value = target
	else:
		_xp_tween = create_tween()
		if level > _shown_level:
			# Fill the old bar to the end, then start the new level from empty.
			_xp_tween.tween_property(_xp_bar, "value", _xp_bar.max_value, Economy.anim_f("xp_bar_seconds") * 0.5)
			_xp_tween.tween_callback(func() -> void:
				_xp_bar.max_value = target_max
				_xp_bar.value = 0.0)
			UiFx.flash(_level)
		else:
			_xp_bar.max_value = target_max
		_xp_tween.tween_property(_xp_bar, "value", target, Economy.anim_f("xp_bar_seconds")) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shown_level = level


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
	var top: ModalScript = _modal_stack.pop_back()
	top.dismiss()


func _on_welcome_back(summary: Dictionary) -> void:
	Signals.modal_requested.emit("welcome_back", summary)


func _on_ad_started(kind: String) -> void:
	_show_toast("Реклама (заглушка): %s" % kind)


func _on_ad_failed(kind: String, reason: String) -> void:
	_show_toast("Реклама недоступна (%s): %s" % [kind, reason])


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	var seconds: float = Economy.anim_f("toast_in_seconds")
	_toast.scale = Vector2.ONE * Economy.anim_f("modal_from_scale")
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, seconds * 0.6)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
