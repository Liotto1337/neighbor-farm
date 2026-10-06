extends RefCounted
## Procedural textures for farm tiles: grass, plowed furrows, planted soil, dry cracked soil
## and the dirt cross-section used on the block sides. Each texture is generated once per
## (kind, variant, size), cached, and baked at SUPERSAMPLE x the on-screen size with mipmaps
## so it stays crisp on any screen density.

enum Kind { GRASS, PLOWED, PLANTED, WITHERED }

const SUPERSAMPLE: int = 2
const VARIANTS: int = 3
const COARSE_FREQ: float = 0.04
const FINE_FREQ: float = 0.45
const COARSE_AMOUNT: float = 0.32
const FINE_AMOUNT: float = 0.2
const BEVEL_PX: int = 2
const BEVEL_LIGHT: float = 1.16
const BEVEL_DARK: float = 0.82
const FURROWS: int = 4
const FURROW_WOBBLE: float = 0.18
const RIDGE_LIGHT: float = 0.2
const RIDGE_SLOPE: float = 0.14
const TROUGH_DARK: float = 0.25
const STRATA: float = 3.0
const STRATA_AMOUNT: float = 0.1
const BLADE_DENSITY: float = 0.016
const BLADE_MIN: int = 4
const BLADE_MAX: int = 9
const BLADE_LEAN: float = 0.45
const FLOWERS_MAX: int = 2
const FLOWER_COLORS: Array[Color] = [Color("#fff6e0"), Color("#ffd84a"), Color("#f59ac2"), Color("#b9a3ff")]
const FLOWER_CENTER: Color = Color("#f2a521")
const CLODS: int = 7
const PEBBLES: int = 3
const SIDE_PEBBLES: int = 5
const PEBBLE_COLOR: Color = Color("#8e8574")
const BLOB_MIN: int = 2
const BLOB_MAX: int = 4
const CRACKS: int = 6
const CRACK_MIN: int = 8
const CRACK_MAX: int = 22
const SEED_KIND: int = 101
const SEED_VARIANT: int = 7919

static var _cache: Dictionary = {}


## Square texture for the top face; `size_px` is the on-screen edge length.
static func top(kind: int, base: Color, variant: int, size_px: int) -> Texture2D:
	var key: String = "top:%d:%s:%d:%d" % [kind, base.to_html(), variant, size_px]
	if not _cache.has(key):
		_cache[key] = _to_texture(_make_top(kind, base, variant, size_px * SUPERSAMPLE))
	return _cache[key]


## Layered dirt for the block sides (front and flank share it).
static func side(base: Color, width_px: int, height_px: int) -> Texture2D:
	var key: String = "side:%s:%d:%d" % [base.to_html(), width_px, height_px]
	if not _cache.has(key):
		_cache[key] = _to_texture(_make_side(base, width_px * SUPERSAMPLE, height_px * SUPERSAMPLE))
	return _cache[key]


static func _to_texture(img: Image) -> Texture2D:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _make_top(kind: int, base: Color, variant: int, size: int) -> Image:
	var seed_value: int = kind * SEED_KIND + variant * SEED_VARIANT
	var coarse: PackedByteArray = _noise(seed_value, COARSE_FREQ / float(SUPERSAMPLE), size, size)
	var fine: PackedByteArray = _noise(seed_value + 1, FINE_FREQ / float(SUPERSAMPLE), size, size)
	var furrowed: bool = kind == Kind.PLOWED or kind == Kind.PLANTED
	var bevel: int = BEVEL_PX * SUPERSAMPLE
	var data: PackedByteArray = PackedByteArray()
	data.resize(size * size * 3)
	for y: int in size:
		for x: int in size:
			var i: int = y * size + x
			var c: float = float(coarse[i]) / 255.0 - 0.5
			var k: float = 1.0 + c * COARSE_AMOUNT + (float(fine[i]) / 255.0 - 0.5) * FINE_AMOUNT
			if furrowed:
				k *= _ridge((float(y) / float(size) + c * FURROW_WOBBLE / float(FURROWS)) * float(FURROWS))
			if x < bevel or y < bevel:
				k *= BEVEL_LIGHT
			elif x >= size - bevel or y >= size - bevel:
				k *= BEVEL_DARK
			_put(data, i, base, k)
	var img: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	if kind == Kind.GRASS:
		_grass_blades(img, rng, base)
		_flowers(img, rng)
	elif kind == Kind.WITHERED:
		_cracks(img, rng, base)
		_blobs(img, rng, PEBBLES, PEBBLE_COLOR.darkened(0.2))
	else:
		_blobs(img, rng, CLODS, base.lightened(0.1))
		_blobs(img, rng, PEBBLES, PEBBLE_COLOR)
	return img


static func _make_side(base: Color, width: int, height: int) -> Image:
	var coarse: PackedByteArray = _noise(SEED_VARIANT, COARSE_FREQ * 2.0 / float(SUPERSAMPLE), width, height)
	var fine: PackedByteArray = _noise(SEED_KIND, FINE_FREQ / float(SUPERSAMPLE), width, height)
	var data: PackedByteArray = PackedByteArray()
	data.resize(width * height * 3)
	for y: int in height:
		for x: int in width:
			var i: int = y * width + x
			var c: float = float(coarse[i]) / 255.0 - 0.5
			var band: float = sin((float(y) / float(height) * STRATA + c) * PI)
			var k: float = 1.0 + c * COARSE_AMOUNT + (float(fine[i]) / 255.0 - 0.5) * FINE_AMOUNT + band * STRATA_AMOUNT
			_put(data, i, base, k)
	var img: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED_VARIANT
	_blobs(img, rng, SIDE_PEBBLES, PEBBLE_COLOR)
	return img


## Brightness across a furrow: lit crest in the middle of each row, a narrow dark trough
## between rows, and the upper slope a bit brighter than the lower one (light from the top).
static func _ridge(phase: float) -> float:
	var a: float = (phase - 0.5) * TAU
	var trough: float = pow(maxf(-cos(a), 0.0), 3.0)
	return 1.0 + RIDGE_LIGHT * cos(a) - RIDGE_SLOPE * sin(a) - TROUGH_DARK * trough


static func _noise(seed_value: int, frequency: float, width: int, height: int) -> PackedByteArray:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img: Image = noise.get_image(width, height)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _put(data: PackedByteArray, i: int, base: Color, k: float) -> void:
	data[i * 3] = clampi(roundi(base.r8 * k), 0, 255)
	data[i * 3 + 1] = clampi(roundi(base.g8 * k), 0, 255)
	data[i * 3 + 2] = clampi(roundi(base.b8 * k), 0, 255)


static func _grass_blades(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	var size: int = img.get_width()
	var palette: Array[Color] = [base.lightened(0.3), base.lightened(0.15), base.darkened(0.18), base.darkened(0.3), base.lerp(Color("#d9e66b"), 0.4)]
	var root: Color = base.darkened(0.35)
	var count: int = roundi(float(size * size) * BLADE_DENSITY)
	for n: int in count:
		var x: int = rng.randi_range(0, size - 2)
		var y: int = rng.randi_range(BLADE_MAX, size - 2)
		var length: int = rng.randi_range(BLADE_MIN, BLADE_MAX)
		var lean: float = rng.randf_range(-BLADE_LEAN, BLADE_LEAN)
		var color: Color = palette[rng.randi() % palette.size()]
		img.set_pixel(x, y + 1, root)
		img.set_pixel(x + 1, y + 1, root)
		for j: int in length:
			var px: int = clampi(x + roundi(lean * float(j)), 0, size - 2)
			var c: Color = color.lerp(color.lightened(0.25), float(j) / float(length))
			img.set_pixel(px, y - j, c)
			if j < length - 1:
				img.set_pixel(px + 1, y - j, c.darkened(0.15))


static func _flowers(img: Image, rng: RandomNumberGenerator) -> void:
	var size: int = img.get_width()
	for n: int in rng.randi_range(0, FLOWERS_MAX):
		var cx: int = rng.randi_range(3, size - 4)
		var cy: int = rng.randi_range(3, size - 4)
		var petal: Color = FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()]
		img.set_pixel(cx, cy + 2, Color(0.0, 0.0, 0.0, 1.0).lerp(img.get_pixel(cx, cy + 2), 0.6))
		for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			img.set_pixel(cx + d.x, cy + d.y, petal)
		img.set_pixel(cx, cy, FLOWER_CENTER)


## Small rounded lumps (soil clods, pebbles) shaded as if lit from the top-left.
static func _blobs(img: Image, rng: RandomNumberGenerator, count: int, color: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	for n: int in count:
		var r: int = rng.randi_range(BLOB_MIN, BLOB_MAX)
		var cx: int = rng.randi_range(r + 1, w - r - 2)
		var cy: int = rng.randi_range(r + 1, maxi(r + 1, h - r - 2))
		for dy: int in range(-r, r + 2):
			for dx: int in range(-r, r + 2):
				var d: float = Vector2(dx, dy).length()
				if d > float(r) + 0.5:
					# Contact shadow on the lower-right rim.
					if d <= float(r) + 1.5 and dx + dy > 0:
						img.set_pixel(cx + dx, cy + dy, img.get_pixel(cx + dx, cy + dy).darkened(0.3))
					continue
				var light: float = -float(dx + dy) / float(2 * r)
				img.set_pixel(cx + dx, cy + dy, color.lightened(maxf(light, 0.0) * 0.3).darkened(maxf(-light, 0.0) * 0.4))


static func _cracks(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	var size: int = img.get_width()
	var dark: Color = base.darkened(0.45)
	var lit: Color = base.lightened(0.18)
	for n: int in CRACKS:
		var p: Vector2 = Vector2(rng.randf_range(0.0, size), rng.randf_range(0.0, size))
		var dir: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		for j: int in rng.randi_range(CRACK_MIN, CRACK_MAX):
			dir = dir.rotated(rng.randf_range(-0.6, 0.6))
			p += dir
			var x: int = clampi(roundi(p.x), 0, size - 2)
			var y: int = clampi(roundi(p.y), 0, size - 3)
			img.set_pixel(x, y, dark)
			img.set_pixel(x + 1, y, dark)
			img.set_pixel(x, y + 1, dark)
			img.set_pixel(x + 1, y + 1, dark)
			img.set_pixel(x, y + 2, lit)
