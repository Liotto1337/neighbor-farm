extends RichTextLabel
## Top-bar chip: a title line and a value line followed by its icon (IconArt), centred.
## Styled by the chip theme variation like the Label it replaces.

const IconArt = preload("res://scenes/components/IconArt.gd")

## IconArt id: "coins", "seeds", "feed" or "level".
@export var icon_id: String = "coins"
## Icon height relative to the font size.
@export var icon_scale: float = 1.3

var _title: String = ""
var _value: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_render()


## Shows `title` on the first line (skipped when empty) and `value` + icon on the second.
func show_value(title: String, value: String) -> void:
	if title == _title and value == _value:
		return
	_title = title
	_value = value
	_render()


func _render() -> void:
	if not is_inside_tree():
		return
	var px: int = roundi(float(get_theme_font_size("normal_font_size")) * icon_scale)
	clear()
	push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	if not _title.is_empty():
		add_text(_title + "\n")
	add_text(_value + " ")
	add_image(IconArt.texture(icon_id), px, px, Color.WHITE, INLINE_ALIGNMENT_CENTER)
	pop()
