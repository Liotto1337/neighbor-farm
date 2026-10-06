extends Button
## One farm tile. Pure view: renders a tile dictionary, reports taps via Signals.
## Drawn as a raised block seen from above at an angle: a square textured top face lit from
## the top-left, a front side and a left/right side (per ui.tile_side sign) with layered dirt,
## a drop shadow, and an upright crop sprite per crop and growth stage (CropArt) that may
## overlap the row above (later rows draw on top).

const TileArt = preload("res://scenes/components/TileArt.gd")
const CropArt = preload("res://scenes/components/CropArt.gd")

const CENTER: float = 0.5
const FRONT_LIGHT: float = 0.8
const FRONT_DARK: float = 0.5
const FLANK_LIGHT: float = 0.62
const FLANK_DARK: float = 0.4
const LIP_PX: float = 3.0
const LIP_SHADE: float = 0.12
const TOP_LIGHT: Color = Color(1.0, 1.0, 1.0, 0.16)
const TOP_SHADE: Color = Color(0.0, 0.0, 0.0, 0.18)
const TOP_NEUTRAL: Color = Color(0.5, 0.5, 0.5, 0.0)
const EDGE_LIGHT: float = 0.3
const EDGE_WIDTH: float = 2.0
const OUTLINE_COLOR: Color = Color(0.1, 0.06, 0.02, 0.55)
const DROP_OFFSET: Vector2 = Vector2(3.0, 4.0)
const DROP_COLOR: Color = Color(0.0, 0.0, 0.0, 0.32)
const READY_RIM_ALPHA: float = 0.7
const PLANT_BASE_Y: float = 0.55
const SHADOW_SQUASH: float = 0.35
const PLANT_SHADOW: float = 0.2
const READY_GLOW: float = 0.4
## Progress at which a growing crop switches to the YOUNG and UNRIPE sprites.
const STAGE_PROGRESS: Array[float] = [0.25, 0.6]
const SHADOW_ALPHA: float = 0.32
const READY_GLOW_ALPHA: float = 0.45
const CIRCLE_SEGMENTS: int = 20
const BAR_HEIGHT: float = 7.0
const BAR_INSET: float = 3.0

var index: int = -1
var _size_px: float = 0.0
var _depth_px: float = 0.0
var _side_px: float = 0.0
var _left_px: float = 0.0
var _variant: int = 0
var _state: int = -1
var _progress: float = 0.0
var _plant_tex: Texture2D = null
var _top_tex: Texture2D = null
var _side_tex: Texture2D = null

@onready var _bar: ProgressBar = $Bar


func _ready() -> void:
	pressed.connect(_on_pressed)


func setup(tile_index: int, size_px: int) -> void:
	index = tile_index
	_variant = posmod(hash(tile_index), TileArt.VARIANTS)
	_side_px = float(Economy.ui_i("tile_side"))
	# The top face is a square; the side face eats into the cell width so the field keeps its size.
	_size_px = float(size_px) - absf(_side_px)
	_left_px = maxf(-_side_px, 0.0)
	_depth_px = float(Economy.ui_i("tile_depth"))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(float(size_px), _size_px + _depth_px)
	_side_tex = TileArt.side(Economy.color("dirt"), int(_size_px), int(_depth_px))
	_bar.offset_left = _left_px + BAR_INSET
	_bar.offset_right = -(maxf(_side_px, 0.0) + BAR_INSET)
	_bar.offset_top = -(_depth_px + BAR_INSET + BAR_HEIGHT)
	_bar.offset_bottom = -(_depth_px + BAR_INSET)


func render(t: Dictionary, progress: float) -> void:
	var def: Dictionary = Economy.crop(str(t.get("c", "")))
	var state: int = int(t.get("s", GameState.TileState.EMPTY))
	if state != _state:
		_state = state
		_top_tex = TileArt.top(_art_kind(state), _soil_color(state), _variant, int(_size_px))
	_progress = progress
	_plant_tex = _plant_texture(def)
	_bar.visible = _state == GameState.TileState.PLANTED
	_bar.value = progress
	queue_redraw()


func _draw() -> void:
	if _top_tex == null:
		return
	_draw_block()
	if _plant_tex != null:
		_draw_plant()


func _draw_block() -> void:
	var top_color: Color = _soil_color(_state)
	var shift: Vector2 = Vector2(_side_px, _depth_px)
	var lip: Vector2 = shift * (LIP_PX / _depth_px)
	var tl: Vector2 = Vector2(_left_px, 0.0)
	var tr: Vector2 = Vector2(_left_px + _size_px, 0.0)
	var bl: Vector2 = Vector2(_left_px, _size_px)
	var br: Vector2 = Vector2(_left_px + _size_px, _size_px)
	var outline: PackedVector2Array = _silhouette(tl, tr, br, bl, shift)

	var drop: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in outline:
		drop.append(p + DROP_OFFSET)
	draw_colored_polygon(drop, DROP_COLOR)

	# Sides: layered dirt, lit near the top edge and fading into shadow; the top surface
	# wraps over the edge as a thin lip (grass overhang / loose soil).
	_draw_face(PackedVector2Array([bl, br, br + shift, bl + shift]), FRONT_LIGHT, FRONT_DARK)
	draw_colored_polygon(PackedVector2Array([bl, br, br + lip, bl + lip]), top_color.darkened(LIP_SHADE))
	if _side_px > 0.0:
		_draw_face(PackedVector2Array([tr, br, br + shift, tr + shift]), FLANK_LIGHT, FLANK_DARK)
		draw_colored_polygon(PackedVector2Array([tr, br, br + lip, tr + lip]), top_color.darkened(LIP_SHADE * 2.0))
	elif _side_px < 0.0:
		_draw_face(PackedVector2Array([tl, bl, bl + shift, tl + shift]), FLANK_LIGHT, FLANK_DARK)
		draw_colored_polygon(PackedVector2Array([tl, bl, bl + lip, tl + lip]), top_color.darkened(LIP_SHADE * 2.0))

	draw_texture_rect(_top_tex, Rect2(tl, Vector2(_size_px, _size_px)), false)
	draw_polygon(PackedVector2Array([tl, tr, br, bl]), PackedColorArray([TOP_LIGHT, TOP_NEUTRAL, TOP_SHADE, TOP_NEUTRAL]))
	var edge: Color = top_color.lightened(EDGE_LIGHT)
	draw_line(tl + Vector2(0.0, 1.0), tr + Vector2(0.0, 1.0), edge, EDGE_WIDTH, true)
	draw_line(tl + Vector2(1.0, 0.0), bl + Vector2(1.0, 0.0), edge, EDGE_WIDTH * CENTER, true)
	draw_line(bl, br, top_color.lightened(EDGE_LIGHT * CENTER), 1.0, true)
	if _state == GameState.TileState.READY:
		draw_rect(Rect2(tl, Vector2(_size_px, _size_px)).grow(-1.0), _with_alpha(Economy.color("ready_text"), READY_RIM_ALPHA), false, EDGE_WIDTH)
	outline.append(outline[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.0, true)


func _draw_face(quad: PackedVector2Array, light: float, dark: float) -> void:
	var lit: Color = Color(light, light, light)
	var shade: Color = Color(dark, dark, dark)
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	draw_polygon(quad, PackedColorArray([lit, lit, shade, shade]), uvs, _side_tex)


## Outer contour of the block (top face plus the visible sides), clockwise.
func _silhouette(tl: Vector2, tr: Vector2, br: Vector2, bl: Vector2, shift: Vector2) -> PackedVector2Array:
	if _side_px > 0.0:
		return PackedVector2Array([tl, tr, tr + shift, br + shift, bl + shift, bl])
	if _side_px < 0.0:
		return PackedVector2Array([tl, tr, br, br + shift, bl + shift, tl + shift])
	return PackedVector2Array([tl, tr, br + shift, bl + shift])


func _draw_plant() -> void:
	var base: Vector2 = Vector2(_left_px + _size_px * CENTER, _size_px * PLANT_BASE_Y)
	var width: float = _plant_tex.get_width() / float(CropArt.SUPERSAMPLE)
	var height: float = _plant_tex.get_height() / float(CropArt.SUPERSAMPLE)
	if _state == GameState.TileState.READY:
		_draw_ellipse(base, width * READY_GLOW, _with_alpha(Economy.color("ready_text"), READY_GLOW_ALPHA))
	_draw_ellipse(base, width * PLANT_SHADOW, Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	draw_texture_rect(_plant_tex, Rect2(base - CropArt.ANCHOR, Vector2(width, height)), false)


## Growth stage sprite for the crop on this tile (null when nothing grows here).
func _plant_texture(def: Dictionary) -> Texture2D:
	if _state < GameState.TileState.PLANTED or def.is_empty():
		return null
	var stage: int = CropArt.Stage.RIPE
	if _state == GameState.TileState.PLANTED:
		stage = CropArt.Stage.SPROUT
		for threshold: float in STAGE_PROGRESS:
			if _progress >= threshold:
				stage += 1
	var fruit: Color = Color.from_string(str(def.get("color", "")), Color.WHITE)
	var sprite: String = str(def.get("sprite", def.get("id", "")))
	return CropArt.texture(sprite, stage, _state == GameState.TileState.WITHERED, fruit, Economy.color("leaf"), Economy.color("withered"))


func _draw_ellipse(center: Vector2, radius: float, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, SHADOW_SQUASH))
	_fill_circle(Vector2.ZERO, radius, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Filled circle with an antialiased rim (draw_circle has no antialiasing in 4.3).
func _fill_circle(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in CIRCLE_SEGMENTS + 1:
		points.append(center + Vector2.from_angle(TAU * float(i) / float(CIRCLE_SEGMENTS)) * radius)
	draw_colored_polygon(points.slice(0, CIRCLE_SEGMENTS), color)
	draw_polyline(points, color, 1.0, true)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _art_kind(state: int) -> int:
	if state == GameState.TileState.EMPTY:
		return TileArt.Kind.GRASS
	if state == GameState.TileState.PLOWED:
		return TileArt.Kind.PLOWED
	if state == GameState.TileState.WITHERED:
		return TileArt.Kind.WITHERED
	return TileArt.Kind.PLANTED


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
