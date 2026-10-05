extends Button
## One farm tile. Pure view: renders a tile dictionary, reports taps via Signals.

const CENTER: float = 0.5
const SHAPE_POINTS: int = 8

var index: int = -1
var _size_px: float = 0.0

@onready var _soil: ColorRect = $Soil
@onready var _crop: Polygon2D = $Crop
@onready var _letter: Label = $Letter
@onready var _bar: ProgressBar = $Bar


func _ready() -> void:
	pressed.connect(_on_pressed)


func setup(tile_index: int, size_px: int) -> void:
	index = tile_index
	_size_px = float(size_px)
	custom_minimum_size = Vector2(size_px, size_px)


func render(t: Dictionary, progress: float) -> void:
	var state: int = int(t.get("s", GameState.TileState.EMPTY))
	var def: Dictionary = Economy.crop(str(t.get("c", "")))
	_soil.color = _soil_color(state)
	_bar.visible = state == GameState.TileState.PLANTED
	_bar.value = progress
	_crop.visible = state >= GameState.TileState.PLANTED and not def.is_empty()
	_letter.text = ""
	if not _crop.visible:
		return
	var min_f: float = Economy.ui_f("crop_min_fraction")
	var max_f: float = Economy.ui_f("crop_max_fraction")
	_set_crop_shape(lerpf(min_f, max_f, progress))
	_crop.color = Economy.color("withered") if state == GameState.TileState.WITHERED else Color.from_string(str(def["color"]), Color.WHITE)
	_letter.text = str(def["name"]).left(1)
	_letter.modulate = Economy.color("ready_text") if state == GameState.TileState.READY else Economy.color("letter")


func _soil_color(state: int) -> Color:
	if state == GameState.TileState.EMPTY:
		return Economy.color("grass")
	if state == GameState.TileState.PLOWED:
		return Economy.color("plowed")
	if state == GameState.TileState.WITHERED:
		return Economy.color("withered").darkened(CENTER)
	return Economy.color("planted")


func _set_crop_shape(fraction: float) -> void:
	var radius: float = _size_px * fraction * CENTER
	var center: Vector2 = Vector2(_size_px, _size_px) * CENTER
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in SHAPE_POINTS:
		var angle: float = TAU * float(i) / float(SHAPE_POINTS)
		var r: float = radius if i % 2 == 0 else radius * CENTER
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	_crop.polygon = points


func _on_pressed() -> void:
	Signals.tile_tapped.emit(index)
