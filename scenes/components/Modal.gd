extends Control
## Generic modal: title + body rebuilt by a builder Callable(modal) whenever state changes.

var _builder: Callable = Callable()
var _rebuild_queued: bool = false

@onready var _title: Label = $Panel/Margin/VBox/Header/Title
@onready var _close_button: Button = $Panel/Margin/VBox/Header/Close
@onready var _body: VBoxContainer = $Panel/Margin/VBox/Body


func _ready() -> void:
	_close_button.pressed.connect(close)
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
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _builder.is_valid():
		_builder.call(self)
