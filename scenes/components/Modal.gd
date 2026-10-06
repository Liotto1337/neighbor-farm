extends Control
## Generic modal: title + body rebuilt by a builder Callable(modal) whenever state changes.
## Fades/scales in on open; dismiss() plays the reverse and frees the modal.

var _builder: Callable = Callable()
var _rebuild_queued: bool = false
var _tween: Tween = null

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel

@onready var _title: Label = $Panel/Margin/VBox/Header/Title
@onready var _close_button: Button = $Panel/Margin/VBox/Header/Close
@onready var _body: VBoxContainer = $Panel/Margin/VBox/Body


func _ready() -> void:
	_close_button.pressed.connect(close)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)
	Signals.currencies_changed.connect(_queue_rebuild.unbind(3))
	Signals.inventory_changed.connect(_queue_rebuild)
	Signals.buildings_changed.connect(_queue_rebuild)
	Signals.contract_changed.connect(_queue_rebuild)
	Signals.selected_crop_changed.connect(_queue_rebuild.unbind(1))
	Signals.level_up.connect(_queue_rebuild.unbind(1))


func open(title: String, builder: Callable) -> void:
	_title.text = title
	_builder = builder
	_rebuild()
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE * Economy.anim_f("modal_from_scale")
	var seconds: float = Economy.anim_f("modal_in_seconds")
	_tween = create_tween().set_parallel()
	_tween.tween_property(_dim, "modulate:a", 1.0, seconds)
	_tween.tween_property(_panel, "modulate:a", 1.0, seconds * 0.6)
	_tween.tween_property(_panel, "scale", Vector2.ONE, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Plays the closing animation, then frees the modal. Input is blocked meanwhile.
func dismiss() -> void:
	_builder = Callable()
	var blocker: Control = Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var seconds: float = Economy.anim_f("modal_out_seconds")
	_tween = create_tween().set_parallel()
	_tween.tween_property(_dim, "modulate:a", 0.0, seconds)
	_tween.tween_property(_panel, "modulate:a", 0.0, seconds)
	_tween.tween_property(_panel, "scale", Vector2.ONE * Economy.anim_f("modal_from_scale"), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)


func close() -> void:
	Signals.modal_close_requested.emit()


func add_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = Economy.ui_i("modal_content_width")
	_body.add_child(label)
	return label


func add_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size.y = Economy.ui_i("button_height")
	if callback.is_valid():
		button.pressed.connect(callback)
	_body.add_child(button)
	return button


func add_progress(value: float, max_value: float) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = maxf(max_value, 1.0)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = Economy.ui_i("trust_bar_height")
	_body.add_child(bar)
	return bar


func add_separator() -> void:
	_body.add_child(HSeparator.new())


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not _builder.is_valid():
		return
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_builder.call(self)
