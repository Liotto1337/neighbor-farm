extends Button
## One farm tile. Pure view: renders a tile dictionary, reports taps via Signals.
## Drawn as a "top-down at an angle" block: squashed top face + visible front side,
## with upright plants that may overlap the row above (later rows draw on top).

const CENTER: float = 0.5
const SIDE_SHADE: float = 0.35
const EDGE_LIGHT: float = 0.18
const EDGE_WIDTH: float = 2.0
const FURROWS: int = 3
const FURROW_WIDTH: float = 3.0
const TUFTS: int = 4
const TUFT_SIZE: float = 4.0
const PLANT_BASE_Y: float = 0.62
const SHADOW_SQUASH: float = 0.35
const SHADOW_ALPHA: float = 0.3
const STEM_WIDTH: float = 3.0
const LEAF_LEN: float = 0.45
const LEAF_WIDTH: float = 0.18
const FRUIT_FROM_PROGRESS: float = 0.5
const FRUIT_RADIUS: float = 0.22
const FRUIT_OUTLINE: float = 0.3
const HIGHLIGHT_ALPHA: float = 0.6
const READY_GLOW_ALPHA: float = 0.45
const BAR_HEIGHT: float = 7.0
const BAR_INSET: float = 3.0

var index: int = -1
var _size_px: float = 0.0
var _top_px: float = 0.0
var _depth_px: float = 0.0
var _state: int = GameState.TileState.EMPTY
var _progress: float = 0.0
var _crop_color: Color = Color.WHITE
var _has_crop: bool = false
var _tufts: PackedVector2Array = PackedVector2Array()

@onready var _bar: ProgressBar = $Bar


func _ready() -> void:
	pressed.connect(_on_pressed)


func setup(tile_index: int, size_px: int) -> void:
	index = tile_index
	_size_px = float(size_px)
	_top_px = roundf(_size_px * Economy.ui_f("tile_top_ratio"))
	_depth_px = float(Economy.ui_i("tile_depth"))
	custom_minimum_size = Vector2(_size_px, _top_px + _depth_px)
	_bar.offset_top = -(_depth_px + BAR_INSET + BAR_HEIGHT)
	_bar.offset_bottom = -(_depth_px + BAR_INSET)
	_tufts = _make_tufts(tile_index)


func render(t: Dictionary, progress: float) -> void:
	var def: Dictionary = Economy.crop(str(t.get("c", "")))
	_state = int(t.get("s", GameState.TileState.EMPTY))
	_progress = progress
	_has_crop = _state >= GameState.TileState.PLANTED and not def.is_empty()
	_crop_color = Color.from_string(str(def.get("color", "")), Color.WHITE)
	_bar.visible = _state == GameState.TileState.PLANTED
	_bar.value = progress
	queue_redraw()


func _draw() -> void:
	_draw_block()
	if _state == GameState.TileState.EMPTY:
		_draw_tufts()
	else:
		_draw_furrows()
	if _has_crop:
		_draw_plant()


func _draw_block() -> void:
	var top_color: Color = _soil_color(_state)
	draw_rect(Rect2(0.0, _top_px, _size_px, _depth_px), top_color.darkened(SIDE_SHADE))
	draw_rect(Rect2(0.0, 0.0, _size_px, _top_px), top_color)
	draw_line(Vector2(0.0, 1.0), Vector2(_size_px, 1.0), top_color.lightened(EDGE_LIGHT), EDGE_WIDTH)


func _draw_tufts() -> void:
	var color: Color = Economy.color("grass").darkened(EDGE_LIGHT)
	for p: Vector2 in _tufts:
		draw_line(p, p + Vector2(-TUFT_SIZE * CENTER, -TUFT_SIZE), color, EDGE_WIDTH)
		draw_line(p, p + Vector2(TUFT_SIZE * CENTER, -TUFT_SIZE), color, EDGE_WIDTH)


func _draw_furrows() -> void:
	var base: Color = _soil_color(_state)
	var step: float = _top_px / float(FURROWS + 1)
	for i: int in FURROWS:
		var y: float = step * float(i + 1)
		draw_line(Vector2(EDGE_WIDTH, y), Vector2(_size_px - EDGE_WIDTH, y), base.darkened(SIDE_SHADE), FURROW_WIDTH)
		draw_line(Vector2(EDGE_WIDTH, y + FURROW_WIDTH), Vector2(_size_px - EDGE_WIDTH, y + FURROW_WIDTH), base.lightened(EDGE_LIGHT), 1.0)


func _draw_plant() -> void:
	var withered: bool = _state == GameState.TileState.WITHERED
	var min_f: float = Economy.ui_f("crop_min_fraction")
	var max_f: float = Economy.ui_f("crop_max_fraction")
	var height: float = _size_px * lerpf(min_f, max_f, _progress)
	var base: Vector2 = Vector2(_size_px * CENTER, _top_px * PLANT_BASE_Y)
	var top: Vector2 = base + Vector2(0.0, -height)
	var leaf_color: Color = Economy.color("withered") if withered else Economy.color("leaf")

	if _state == GameState.TileState.READY:
		_draw_ellipse(base, height * CENTER, _with_alpha(Economy.color("ready_text"), READY_GLOW_ALPHA))
	_draw_ellipse(base, height * CENTER * CENTER, Color(0.0, 0.0, 0.0, SHADOW_ALPHA))

	var droop: float = 1.0 if withered else -1.0
	draw_line(base, top, leaf_color.darkened(EDGE_LIGHT), STEM_WIDTH)
	var leaf_root: Vector2 = base.lerp(top, CENTER)
	_draw_leaf(leaf_root, Vector2(-1.0, droop * CENTER).normalized(), height, leaf_color)
	_draw_leaf(leaf_root, Vector2(1.0, droop * CENTER).normalized(), height, leaf_color)

	if withered or _progress < FRUIT_FROM_PROGRESS:
		return
	var radius: float = _size_px * FRUIT_RADIUS * inverse_lerp(FRUIT_FROM_PROGRESS, 1.0, _progress)
	draw_circle(top, radius + 1.0, _crop_color.darkened(FRUIT_OUTLINE))
	draw_circle(top, radius, _crop_color)
	draw_circle(top + Vector2(-radius, -radius) * CENTER * CENTER, radius * CENTER * CENTER, _with_alpha(Color.WHITE, HIGHLIGHT_ALPHA))


func _draw_leaf(root: Vector2, dir: Vector2, height: float, color: Color) -> void:
	var tip: Vector2 = root + dir * height * LEAF_LEN
	var side: Vector2 = dir.orthogonal() * height * LEAF_WIDTH
	var mid: Vector2 = root.lerp(tip, CENTER)
	draw_colored_polygon(PackedVector2Array([root, mid + side, tip, mid - side]), color)


func _draw_ellipse(center: Vector2, radius: float, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, SHADOW_SQUASH))
	draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _make_tufts(seed_value: int) -> PackedVector2Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in TUFTS:
		out.append(Vector2(rng.randf_range(TUFT_SIZE, _size_px - TUFT_SIZE), rng.randf_range(TUFT_SIZE * 2.0, _top_px - TUFT_SIZE)))
	return out


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _soil_color(state: int) -> Color:
	if state == GameState.TileState.EMPTY:
		return Economy.color("grass")
	if state == GameState.TileState.PLOWED:
		return Economy.color("plowed")
	if state == GameState.TileState.WITHERED:
		return Economy.color("withered").darkened(CENTER)
	return Economy.color("planted")


func _on_pressed() -> void:
	Signals.tile_tapped.emit(index)
