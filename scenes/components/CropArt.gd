extends RefCounted
## Procedural crop sprites: one drawing per crop "sprite" id (crops.json), four growth stages
## (sprout, young, unripe, ripe) plus a withered look. Sprites are rasterised on the CPU at
## RASTER x the on-screen size, halved to SUPERSAMPLE x (antialiasing) and cached with mipmaps.
## Coordinates below are in on-screen pixels with the plant base at ANCHOR; "up" is -y.

enum Stage { SPROUT, YOUNG, UNRIPE, RIPE }

const SPRITE_SIZE: Vector2i = Vector2i(56, 60)
const ANCHOR: Vector2 = Vector2(28.0, 54.0)
const SUPERSAMPLE: int = 2
const RASTER: int = SUPERSAMPLE * 2
const ELLIPSE_SEGMENTS: int = 24
const BEZIER_STEPS: int = 10
const GROWTH: Array[float] = [0.35, 0.62, 0.86, 1.0]
const WITHER_MIX: float = 0.65
const WITHER_SQUASH: float = 0.82
const SOIL: Color = Color("#4a2f19")
const STALK_DRY: Color = Color("#d9b25c")
const TASSEL: Color = Color("#c99a45")
const SILK: Color = Color("#e8c873")
const SEED_DISC: Color = Color("#6b3e1a")
const STEM_BROWN: Color = Color("#6d5a2a")

static var _cache: Dictionary = {}


static func texture(sprite_id: String, stage: int, withered: bool, fruit: Color, leaf: Color, dry: Color) -> Texture2D:
	var key: String = "%s:%d:%s:%s" % [sprite_id, stage, withered, fruit.to_html()]
	if not _cache.has(key):
		var p: Painter = Painter.new(withered, fruit, leaf, dry)
		_paint(p, sprite_id, stage)
		_cache[key] = p.finish()
	return _cache[key]


static func _paint(p: Painter, sprite_id: String, stage: int) -> void:
	if stage == Stage.SPROUT:
		_sprout(p)
		return
	match sprite_id:
		"wheat":
			_wheat(p, stage)
		"carrot":
			_carrot(p, stage)
		"corn":
			_corn(p, stage)
		"pumpkin":
			_pumpkin(p, stage)
		"sunflower":
			_sunflower(p, stage)
		_:
			_tomato(p, stage)


# --- Plants ---

static func _sprout(p: Painter) -> void:
	p.line(p.at(0, 0), p.at(0, 9), 1.6, p.leaf_dark)
	p.leaf_blade(p.at(0, 8), p.at(-7, 12), 3.2, p.leaf)
	p.leaf_blade(p.at(0, 8), p.at(7, 13), 3.2, p.leaf_light)


static func _wheat(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	var ripe: float = 1.0 if stage == Stage.RIPE else (0.45 if stage == Stage.UNRIPE else 0.0)
	var stalk: Color = p.leaf.lerp(STALK_DRY if not p.withered else p.leaf, ripe)
	var grain: Color = p.leaf_light.lerp(p.fruit, ripe)
	p.leaf_blade(p.at(0, 2), p.at(-13, 16 * f), 2.6, p.leaf_dark)
	p.leaf_blade(p.at(0, 2), p.at(12, 18 * f), 2.6, p.leaf)
	for i: int in 5:
		var angle: float = deg_to_rad(-16.0 + 8.0 * float(i))
		var length: float = 42.0 * f * (0.9 + 0.1 * float(i % 2))
		var dir: Vector2 = Vector2.UP.rotated(angle)
		var base: Vector2 = p.at(0, 0) + Vector2(float(i - 2), 0.0)
		var tip: Vector2 = base + dir * length
		p.line(base, tip, 1.4, stalk.darkened(0.1 if i % 2 == 0 else 0.0))
		if stage < Stage.UNRIPE:
			continue
		# Ear: alternating kernels along the top third, awns fanning from the tip.
		var side: Vector2 = dir.orthogonal()
		for k: int in 5:
			var c: Vector2 = tip - dir * (2.0 + 2.6 * float(k))
			var s: float = 1.0 if k % 2 == 0 else -1.0
			p.ellipse(c + side * s * 1.2 + Vector2(0.5, 0.5), 1.5, 2.5, angle + s * 0.4, grain.darkened(0.35))
			p.ellipse(c + side * s * 1.2, 1.5, 2.5, angle + s * 0.4, grain)
		for a: int in 3:
			p.line(tip, tip + dir.rotated(0.25 * float(a - 1)) * 5.0, 0.6, grain.lightened(0.3))


static func _carrot(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	if stage >= Stage.UNRIPE:
		# Carrot shoulder poking out of a soil mound.
		var w: float = 7.0 if stage == Stage.RIPE else 5.0
		var top: float = 10.0 if stage == Stage.RIPE else 7.0
		var root: Color = p.fruit if stage == Stage.RIPE else p.fruit.lerp(Color("#f6c27a"), 0.4)
		p.ellipse(p.at(0, -1), w + 4.0, 3.2, 0.0, SOIL)
		p.ellipse(p.at(0, 0), w + 2.5, 2.0, 0.0, SOIL.lightened(0.15))
		p.poly(PackedVector2Array([p.at(-w, 0), p.at(w, 0), p.at(w * 0.85, top * 0.7), p.at(w * 0.4, top), p.at(-w * 0.4, top), p.at(-w * 0.85, top * 0.7)]), root.darkened(0.15))
		p.poly(PackedVector2Array([p.at(-w * 0.85, 0), p.at(w * 0.5, 0), p.at(w * 0.4, top * 0.95), p.at(-w * 0.4, top * 0.95), p.at(-w * 0.75, top * 0.7)]), root)
		p.ellipse(p.at(-w * 0.35, top * 0.6), w * 0.18, top * 0.25, 0.0, root.lightened(0.35))
		for k: int in 3:
			var y: float = top * (0.2 + 0.25 * float(k))
			p.line(p.at(w * (0.1 + 0.2 * float(k % 2)), y), p.at(w * (0.55 + 0.2 * float(k % 2)), y), 0.7, root.darkened(0.35))
	# Feathery fronds: stems with paired leaflets.
	for i: int in 4:
		var angle: float = deg_to_rad(-36.0 + 24.0 * float(i))
		var dir: Vector2 = Vector2.UP.rotated(angle)
		var base: Vector2 = p.at(0, (10 if stage == Stage.RIPE else 7) if stage >= Stage.UNRIPE else 0)
		var length: float = 26.0 * f
		p.line(base, base + dir * length, 1.0, p.leaf_dark)
		for k: int in 4:
			var c: Vector2 = base + dir * length * (0.35 + 0.2 * float(k))
			var size: float = 3.2 - 0.5 * float(k)
			var color: Color = p.leaf_light if k % 2 == 0 else p.leaf
			p.ellipse(c + dir.orthogonal() * size, size, size * 0.45, angle + 1.1, color)
			p.ellipse(c - dir.orthogonal() * size, size, size * 0.45, angle - 1.1, color.darkened(0.1))


static func _corn(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	var height: float = 43.0 * f
	var stalk: Color = p.leaf.lerp(STALK_DRY, 0.25)
	p.line(p.at(0, 0), p.at(0, height), 3.0, stalk)
	p.line(p.at(-0.8, 0), p.at(-0.8, height), 0.8, stalk.lightened(0.25))
	var leaf_heights: Array[float] = [0.2, 0.42, 0.62, 0.8]
	for i: int in leaf_heights.size():
		var s: float = -1.0 if i % 2 == 0 else 1.0
		var root: Vector2 = p.at(0, height * leaf_heights[i])
		var reach: float = (20.0 - 3.0 * float(i)) * f + 4.0
		p.strap(root, root + Vector2(s * reach * 0.7, -reach * 0.7), root + Vector2(s * reach, reach * 0.15), 2.6, p.leaf if i % 2 == 0 else p.leaf_light)
	if stage < Stage.UNRIPE:
		return
	for a: int in 5:
		var top: Vector2 = p.at(0, height)
		p.line(top, top + Vector2.UP.rotated(deg_to_rad(-40.0 + 20.0 * float(a))) * 7.0, 0.9, TASSEL)
	# Cob on the right side of the stalk, wrapped in husk; ripe cobs show their kernels.
	var cob: Vector2 = p.at(5, height * 0.5)
	var tilt: float = deg_to_rad(18.0)
	var ripe: bool = stage == Stage.RIPE
	var cob_color: Color = p.fruit if ripe else p.fruit.lerp(p.leaf_light, 0.5)
	p.ellipse(cob + Vector2(0.6, 0.6), 3.4, 8.0, tilt, cob_color.darkened(0.4))
	p.ellipse(cob, 3.4, 8.0, tilt, cob_color)
	if ripe:
		for row: int in 5:
			for col: int in 2:
				var d: Vector2 = Vector2(-1.0 + 2.0 * float(col), -6.0 + 3.0 * float(row)).rotated(tilt)
				p.ellipse(cob + d, 0.9, 1.1, tilt, cob_color.lightened(0.25))
	else:
		p.line(cob + Vector2(0, -8).rotated(tilt), cob + Vector2(2, -12).rotated(tilt), 0.8, SILK)
	p.leaf_blade(cob + Vector2(0, 7).rotated(tilt), cob + Vector2(-3.5, -4 if ripe else -7).rotated(tilt), 2.6, p.leaf_dark)
	p.leaf_blade(cob + Vector2(0, 7).rotated(tilt), cob + Vector2(3.5, -3 if ripe else -7).rotated(tilt), 2.4, p.leaf)


static func _tomato(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	var h: float = 36.0 * f
	p.line(p.at(0, 0), p.at(0, h), 2.0, p.leaf_dark)
	p.line(p.at(0, h * 0.4), p.at(-9 * f, h * 0.75), 1.4, p.leaf_dark)
	p.line(p.at(0, h * 0.5), p.at(9 * f, h * 0.85), 1.4, p.leaf_dark)
	# Bush: layered clusters, dark at the back, light in front.
	var clusters: Array[Vector2] = [Vector2(-9, 0.75), Vector2(9, 0.85), Vector2(0, 1.0), Vector2(-5, 0.45), Vector2(6, 0.5)]
	for c: Vector2 in clusters:
		var center: Vector2 = p.at(c.x * f, h * c.y)
		var r: float = 6.5 * f + 1.0
		p.circle(center + Vector2(1, 1), r, p.leaf_dark)
		p.circle(center + Vector2(-r * 0.4, 0), r * 0.75, p.leaf)
		p.circle(center + Vector2(r * 0.4, -r * 0.2), r * 0.7, p.leaf)
		p.circle(center + Vector2(-r * 0.2, -r * 0.4), r * 0.45, p.leaf_light)
	if stage < Stage.UNRIPE:
		return
	var ripe: bool = stage == Stage.RIPE
	var r_fruit: float = 4.4 if ripe else 3.2
	var color: Color = p.fruit if ripe else p.leaf_light.lerp(p.fruit, 0.25)
	for c: Vector2 in [Vector2(-7, 0.55), Vector2(6, 0.68), Vector2(-1, 0.32)]:
		_round_fruit(p, p.at(c.x, h * c.y), r_fruit, color)
		var top: Vector2 = p.at(c.x, h * c.y) + Vector2(0, -r_fruit)
		for a: int in 5:
			p.line(top, top + Vector2.UP.rotated(TAU * float(a) / 5.0) * 2.2, 0.8, p.leaf_dark)


static func _pumpkin(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	# Low vine: big lobed leaves with veins.
	var leaves: Array[Vector3] = [Vector3(-12, 9, 1.0), Vector3(12, 11, 0.9), Vector3(-2, 17, 1.1)]
	for l: Vector3 in leaves:
		var c: Vector2 = p.at(l.x * f, l.y * f)
		var r: float = 6.5 * f * l.z + 1.0
		p.line(p.at(0, 0), c, 1.4, p.leaf_dark)
		p.circle(c + Vector2(1, 1), r, p.leaf_dark.darkened(0.2))
		p.circle(c + Vector2(-r * 0.5, 0), r * 0.7, p.leaf)
		p.circle(c + Vector2(r * 0.5, 0), r * 0.7, p.leaf)
		p.circle(c + Vector2(0, -r * 0.45), r * 0.7, p.leaf_light)
		for a: int in 3:
			p.line(c + Vector2(0, r * 0.3), c + Vector2(0, -r * 0.7).rotated(0.7 * float(a - 1)), 0.6, p.leaf_dark)
	if stage < Stage.UNRIPE:
		return
	var ripe: bool = stage == Stage.RIPE
	var w: float = 10.0 if ripe else 6.5
	var h: float = 7.5 if ripe else 5.0
	var body: Color = p.fruit if ripe else p.fruit.lerp(p.leaf, 0.55)
	var c0: Vector2 = p.at(0, h * 0.85)
	p.ellipse(c0 + Vector2(0, h * 0.9), w * 1.05, 2.2, 0.0, Color(0.0, 0.0, 0.0, 1.0).lerp(SOIL, 0.6))
	p.ellipse(c0 + Vector2(-w * 0.45, 0), w * 0.6, h, 0.0, body.darkened(0.2))
	p.ellipse(c0 + Vector2(w * 0.45, 0), w * 0.6, h, 0.0, body.darkened(0.28))
	p.ellipse(c0, w * 0.55, h * 1.02, 0.0, body)
	p.ellipse(c0 + Vector2(-w * 0.2, -h * 0.45), w * 0.18, h * 0.25, -0.4, body.lightened(0.35))
	p.line(c0 + Vector2(-w * 0.55, -h * 0.7), c0 + Vector2(-w * 0.55, h * 0.7), 0.7, body.darkened(0.4))
	p.line(c0 + Vector2(w * 0.55, -h * 0.7), c0 + Vector2(w * 0.55, h * 0.7), 0.7, body.darkened(0.45))
	p.line(c0 + Vector2(0, -h * 0.9), c0 + Vector2(1.5, -h - 3.0), 2.0, STEM_BROWN)


static func _sunflower(p: Painter, stage: int) -> void:
	var f: float = GROWTH[stage]
	var h: float = 38.0 * f
	p.line(p.at(0, 0), p.at(0, h), 2.6, p.leaf_dark)
	p.line(p.at(-0.7, 0), p.at(-0.7, h), 0.7, p.leaf_light)
	p.leaf_blade(p.at(0, h * 0.3), p.at(-13 * f - 3, h * 0.42), 5.0 * f + 1.0, p.leaf)
	p.leaf_blade(p.at(0, h * 0.55), p.at(12 * f + 3, h * 0.66), 4.5 * f + 1.0, p.leaf_light)
	if stage == Stage.YOUNG:
		p.leaf_blade(p.at(0, h), p.at(-4, h + 4), 2.4, p.leaf)
		p.leaf_blade(p.at(0, h), p.at(4, h + 5), 2.4, p.leaf_light)
		return
	var head: Vector2 = p.at(0, h)
	if stage == Stage.UNRIPE:
		# Closed bud: green sepals with yellow petal tips peeking out.
		for a: int in 8:
			var d: Vector2 = Vector2.UP.rotated(TAU * float(a) / 8.0)
			p.ellipse(head + d * 4.5, 1.4, 2.8, d.angle() + PI * 0.5, p.fruit)
		p.circle(head, 4.6, p.leaf_dark)
		p.circle(head + Vector2(-1, -1), 3.2, p.leaf)
		return
	for a: int in 14:
		var d: Vector2 = Vector2.UP.rotated(TAU * (float(a) + 0.5) / 14.0)
		p.ellipse(head + d * 7.5, 1.9, 4.2, d.angle() + PI * 0.5, p.fruit.darkened(0.2))
	for a: int in 14:
		var d: Vector2 = Vector2.UP.rotated(TAU * float(a) / 14.0)
		p.ellipse(head + d * 7.0, 1.9, 4.0, d.angle() + PI * 0.5, p.fruit)
	p.circle(head, 5.4, SEED_DISC.darkened(0.25))
	p.circle(head + Vector2(-0.6, -0.6), 4.6, SEED_DISC)
	for ring: int in 2:
		for a: int in 8:
			var d: Vector2 = Vector2.UP.rotated(TAU * (float(a) + 0.5 * float(ring)) / 8.0) * (1.6 + 1.6 * float(ring))
			p.circle(head + d, 0.55, SEED_DISC.lightened(0.25))


static func _round_fruit(p: Painter, c: Vector2, r: float, color: Color) -> void:
	p.circle(c + Vector2(0.5, 0.5), r + 0.6, color.darkened(0.45))
	p.circle(c, r, color.darkened(0.2))
	p.circle(c + Vector2(-r, -r) * 0.15, r * 0.8, color)
	p.circle(c + Vector2(-r, -r) * 0.4, r * 0.25, color.lightened(0.6))


## Tiny CPU rasteriser: even-odd scanline polygons drawn into an Image at RASTER x scale.
class Painter:
	var img: Image
	var withered: bool
	var fruit: Color
	var leaf: Color
	var leaf_dark: Color
	var leaf_light: Color

	func _init(is_withered: bool, fruit_color: Color, leaf_color: Color, dry_color: Color) -> void:
		withered = is_withered
		img = Image.create(SPRITE_SIZE.x * RASTER, SPRITE_SIZE.y * RASTER, false, Image.FORMAT_RGBA8)
		fruit = fruit_color.lerp(dry_color, WITHER_MIX).darkened(0.15) if withered else fruit_color
		leaf = dry_color if withered else leaf_color
		leaf_dark = leaf.darkened(0.3)
		leaf_light = leaf.lightened(0.18)

	## Point `up` px above and `dx` px right of the plant base (withered plants slump).
	func at(dx: float, up: float) -> Vector2:
		return ANCHOR + Vector2(dx, -up * (WITHER_SQUASH if withered else 1.0))

	func finish() -> Texture2D:
		img.resize(SPRITE_SIZE.x * SUPERSAMPLE, SPRITE_SIZE.y * SUPERSAMPLE, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)

	func poly(points: PackedVector2Array, color: Color) -> void:
		var k: float = float(RASTER)
		var y0: int = maxi(0, floori(_min_y(points) * k))
		var y1: int = mini(img.get_height() - 1, ceili(_max_y(points) * k))
		var n: int = points.size()
		for y: int in range(y0, y1 + 1):
			var sy: float = (float(y) + 0.5) / k
			var xs: Array[float] = []
			for i: int in n:
				var a: Vector2 = points[i]
				var b: Vector2 = points[(i + 1) % n]
				if (a.y <= sy) != (b.y <= sy):
					xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			for j: int in range(0, xs.size() - 1, 2):
				var x0: int = maxi(0, ceili(xs[j] * k - 0.5))
				var x1: int = mini(img.get_width() - 1, floori(xs[j + 1] * k - 0.5))
				if x1 >= x0:
					img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), color)

	func ellipse(c: Vector2, rx: float, ry: float, angle: float, color: Color) -> void:
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in ELLIPSE_SEGMENTS:
			var a: float = TAU * float(i) / float(ELLIPSE_SEGMENTS)
			points.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
		poly(points, color)

	func circle(c: Vector2, r: float, color: Color) -> void:
		ellipse(c, r, r, 0.0, color)

	func line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
		var side: Vector2 = (b - a).normalized().orthogonal() * width * 0.5
		poly(PackedVector2Array([a + side, b + side, b - side, a - side]), color)
		circle(b, width * 0.5, color)

	func polyline(points: PackedVector2Array, width: float, color: Color) -> void:
		for i: int in points.size() - 1:
			line(points[i], points[i + 1], width, color)

	## Pointed leaf from `root` to `tip`, widest at a third of its length, with a midrib.
	func leaf_blade(root: Vector2, tip: Vector2, width: float, color: Color) -> void:
		var side: Vector2 = (tip - root).normalized().orthogonal() * width
		var mid: Vector2 = root.lerp(tip, 0.4)
		poly(PackedVector2Array([root, mid + side, tip, mid - side]), color)
		poly(PackedVector2Array([root, mid + side, tip]), color.darkened(0.12))
		line(root, root.lerp(tip, 0.85), 0.5, color.darkened(0.3))

	## Long arching leaf (corn) along a quadratic Bezier, tapering to a point.
	func strap(root: Vector2, control: Vector2, tip: Vector2, width: float, color: Color) -> void:
		var left: PackedVector2Array = PackedVector2Array()
		var right: PackedVector2Array = PackedVector2Array()
		for i: int in BEZIER_STEPS + 1:
			var t: float = float(i) / float(BEZIER_STEPS)
			var pt: Vector2 = root.lerp(control, t).lerp(control.lerp(tip, t), t)
			var tangent: Vector2 = (control - root).lerp(tip - control, t).normalized()
			var w: float = width * (1.0 - t) * minf(1.0, t * 4.0 + 0.4)
			left.append(pt + tangent.orthogonal() * w)
			right.append(pt - tangent.orthogonal() * w)
		right.reverse()
		poly(left + right, color)
		var rib: PackedVector2Array = PackedVector2Array()
		for i: int in BEZIER_STEPS:
			var t: float = float(i) / float(BEZIER_STEPS)
			rib.append(root.lerp(control, t).lerp(control.lerp(tip, t), t))
		polyline(rib, 0.5, color.darkened(0.25))

	func _min_y(points: PackedVector2Array) -> float:
		var m: float = INF
		for pt: Vector2 in points:
			m = minf(m, pt.y)
		return m

	func _max_y(points: PackedVector2Array) -> float:
		var m: float = -INF
		for pt: Vector2 in points:
			m = maxf(m, pt.y)
		return m
