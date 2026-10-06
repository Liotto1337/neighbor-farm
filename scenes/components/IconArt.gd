extends RefCounted
## Procedural currency icons (coin, seeds sprout, feed sack, level star) drawn with the crop
## sprite rasteriser (CropArt.Painter), so they share the plants' look. Each icon is designed
## in a DESIGN-px box with a dark outline so it reads on any chip colour; cached per id.

const CropArt = preload("res://scenes/components/CropArt.gd")

const DESIGN: float = 48.0
## Top-left of the design box inside the Painter canvas (CropArt.SPRITE_SIZE).
const ORIGIN: Vector2 = Vector2(4.0, 4.0)
const OUTLINE: Color = Color("#3b2410")
const OUTLINE_PX: float = 2.2
const STAR_POINTS: int = 5

const GOLD: Color = Color("#f6c445")
const GOLD_DARK: Color = Color("#c98a1c")
const GOLD_LIGHT: Color = Color("#ffe08a")
const LEAF: Color = Color("#6cc04a")
const LEAF_LIGHT: Color = Color("#8edb63")
const STEM: Color = Color("#3f7a2c")
const SOIL: Color = Color("#6e4627")
const SOIL_LIGHT: Color = Color("#8a5a33")
const SACK: Color = Color("#e3be86")
const SACK_SHADE: Color = Color("#c39a5e")
const ROPE: Color = Color("#8a5a2a")
const GRAIN: Color = Color("#f2cf4c")
const GRAIN_DARK: Color = Color("#d4a42a")

static var _cache: Dictionary = {}


## Icon texture by id: "coins", "seeds", "feed" or "level".
static func texture(icon_id: String) -> Texture2D:
	if not _cache.has(icon_id):
		var p: CropArt.Painter = CropArt.Painter.new(false, Color.WHITE, LEAF, LEAF)
		match icon_id:
			"coins":
				_coin(p)
			"seeds":
				_sprout(p)
			"feed":
				_sack(p)
			_:
				_star(p)
		_cache[icon_id] = _finish(p)
	return _cache[icon_id]


static func _at(x: float, y: float) -> Vector2:
	return ORIGIN + Vector2(x, y)


static func _coin(p: CropArt.Painter) -> void:
	var c: Vector2 = _at(24, 24)
	p.circle(c, 21.0 + OUTLINE_PX, OUTLINE)
	p.circle(c + Vector2(0.0, 1.5), 21.0, GOLD_DARK)
	p.circle(c, 20.0, GOLD)
	p.circle(c, 14.5, GOLD_DARK)
	p.circle(c + Vector2(0.6, 0.8), 13.5, GOLD)
	_star_shape(p, c + Vector2(0.0, 0.5), 8.5, 3.8, GOLD_DARK)
	_star_shape(p, c + Vector2(-0.4, -0.2), 7.0, 3.0, GOLD_LIGHT)
	p.ellipse(c + Vector2(-9.0, -11.0), 4.5, 2.0, -0.7, GOLD_LIGHT)


static func _sprout(p: CropArt.Painter) -> void:
	var ground: Vector2 = _at(24, 40)
	p.ellipse(ground, 18.0 + OUTLINE_PX, 7.0 + OUTLINE_PX, 0.0, OUTLINE)
	p.ellipse(ground, 18.0, 7.0, 0.0, SOIL)
	p.ellipse(ground + Vector2(-3.0, -2.0), 11.0, 3.5, 0.0, SOIL_LIGHT)
	var root: Vector2 = ground + Vector2(0.0, -2.0)
	var fork: Vector2 = _at(24, 22)
	var left_tip: Vector2 = _at(5, 9)
	var right_tip: Vector2 = _at(44, 5)
	# Outline pass: the same shapes, fatter and dark.
	p.line(root, fork, 3.4 + OUTLINE_PX * 2.0, OUTLINE)
	p.leaf_blade(fork, left_tip + (left_tip - fork).normalized() * OUTLINE_PX, 7.0 + OUTLINE_PX, OUTLINE)
	p.leaf_blade(fork, right_tip + (right_tip - fork).normalized() * OUTLINE_PX, 7.5 + OUTLINE_PX, OUTLINE)
	p.line(root, fork, 3.4, STEM)
	p.leaf_blade(fork, left_tip, 7.0, LEAF)
	p.leaf_blade(fork, right_tip, 7.5, LEAF_LIGHT)


static func _sack(p: CropArt.Painter) -> void:
	var body: PackedVector2Array = PackedVector2Array([
		_at(14, 19), _at(34, 19), _at(41, 28), _at(44, 38), _at(41, 45), _at(7, 45), _at(4, 38), _at(7, 28),
	])
	p.poly(_grow(body, _at(24, 33), OUTLINE_PX), OUTLINE)
	p.poly(body, SACK)
	p.poly(PackedVector2Array([_at(30, 19), _at(34, 19), _at(41, 28), _at(44, 38), _at(41, 45), _at(31, 45), _at(35, 34)]), SACK_SHADE)
	p.line(_at(12, 40), _at(36, 40), 1.0, SACK_SHADE)
	# Open top heaped with grain, tied with a rope.
	p.ellipse(_at(24, 14), 13.0 + OUTLINE_PX, 7.5 + OUTLINE_PX, 0.0, OUTLINE)
	p.ellipse(_at(24, 14), 13.0, 7.5, 0.0, GRAIN_DARK)
	p.ellipse(_at(23, 12.5), 11.0, 5.5, 0.0, GRAIN)
	for k: Vector2 in [Vector2(17, 13), Vector2(22, 10), Vector2(28, 12), Vector2(31, 15), Vector2(20, 16), Vector2(26, 16)]:
		p.ellipse(_at(k.x, k.y), 1.6, 2.4, 0.5, GRAIN_DARK)
	p.line(_at(11, 20.5), _at(37, 20.5), 3.6 + OUTLINE_PX, OUTLINE)
	p.line(_at(11, 20.5), _at(37, 20.5), 3.6, ROPE)


static func _star(p: CropArt.Painter) -> void:
	var c: Vector2 = _at(24, 26)
	_star_shape(p, c, 23.0 + OUTLINE_PX * 1.6, 10.5 + OUTLINE_PX * 0.8, OUTLINE)
	_star_shape(p, c, 23.0, 10.5, GOLD_DARK)
	_star_shape(p, c + Vector2(-0.6, -1.0), 20.5, 9.2, GOLD)
	_star_shape(p, c + Vector2(-2.5, -3.5), 9.0, 4.0, GOLD_LIGHT)


static func _star_shape(p: CropArt.Painter, c: Vector2, outer: float, inner: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in STAR_POINTS * 2:
		var r: float = outer if i % 2 == 0 else inner
		points.append(c + Vector2.UP.rotated(PI * float(i) / float(STAR_POINTS)) * r)
	p.poly(points, color)


## Polygon pushed outwards from `center` by `px` (good enough for convex-ish outlines).
static func _grow(points: PackedVector2Array, center: Vector2, px: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for pt: Vector2 in points:
		out.append(pt + (pt - center).normalized() * px)
	return out


## Crops the design box out of the painter canvas and halves it once (antialiasing + mipmaps).
static func _finish(p: CropArt.Painter) -> Texture2D:
	var k: int = CropArt.RASTER
	var img: Image = p.img.get_region(Rect2i(Vector2i(ORIGIN * k), Vector2i(int(DESIGN) * k, int(DESIGN) * k)))
	img.resize(int(DESIGN) * CropArt.SUPERSAMPLE, int(DESIGN) * CropArt.SUPERSAMPLE, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
