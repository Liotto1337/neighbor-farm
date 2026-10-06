extends Node
## UI motion: press feedback for every button in the tree, plus small tween helpers
## (floating "+N" text, colour flash). Timings live in config.json "anim".

## Buttons with this meta set animate themselves (e.g. farm tiles draw their own squash).
const SKIP_META: StringName = &"fx_skip"
const FLOAT_FONT_SIZE: int = 24
const FLOAT_OUTLINE: int = 6
const FLOAT_OUTLINE_COLOR: Color = Color(0.16, 0.1, 0.04, 0.9)
const FLOAT_Z: int = 10
const FLASH_COLOR: Color = Color(1.35, 1.3, 1.0)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(SKIP_META):
		var button: BaseButton = node
		button.button_down.connect(_on_button_down.bind(button))
		button.button_up.connect(_on_button_up.bind(button))


func _on_button_down(button: BaseButton) -> void:
	button.pivot_offset = button.size * 0.5
	var tween: Tween = _restart(button, &"fx_press_tween")
	tween.tween_property(button, "scale", Vector2.ONE * Economy.anim_f("press_scale"), Economy.anim_f("press_seconds")) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up(button: BaseButton) -> void:
	var tween: Tween = _restart(button, &"fx_press_tween")
	tween.tween_property(button, "scale", Vector2.ONE, Economy.anim_f("release_seconds")) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Text that rises from a point (global coordinates) and fades out, drawn above `host`'s children.
func float_text(host: Control, text: String, global_pos: Vector2, color: Color = Color.WHITE) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = FLOAT_Z
	label.add_theme_font_size_override("font_size", FLOAT_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", FLOAT_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", FLOAT_OUTLINE)
	host.add_child(label)
	label.reset_size()
	var start: Vector2 = global_pos - host.global_position - label.size * 0.5
	label.position = start
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * Economy.anim_f("plant_pop_from")
	var seconds: float = Economy.anim_f("float_text_seconds")
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "scale", Vector2.ONE, seconds * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", start.y - Economy.anim_f("float_text_rise"), seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, seconds * 0.5).set_delay(seconds * 0.5)
	tween.chain().tween_callback(label.queue_free)


## Brief bright tint that fades back to normal (counters, level label).
func flash(item: CanvasItem) -> void:
	var tween: Tween = _restart(item, &"fx_flash_tween")
	item.modulate = FLASH_COLOR
	tween.tween_property(item, "modulate", Color.WHITE, Economy.anim_f("flash_seconds"))


## Kills the tween stored under `key` on the node and starts a fresh one bound to it.
func _restart(node: Node, key: StringName) -> Tween:
	var old: Variant = node.get_meta(key) if node.has_meta(key) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tween: Tween = node.create_tween()
	node.set_meta(key, tween)
	return tween
