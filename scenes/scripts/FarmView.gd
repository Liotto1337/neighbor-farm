extends Control
## Farm tab: tile grid, tap = context action (plow / plant / harvest / clear).
## The open part of the field grows with the player's level (config "field_sizes") up to
## grid_size x grid_size; locked tiles stay hidden and new ones pop in when the field expands.

const TAB_ID: String = "farm"
const TILE_SCENE: PackedScene = preload("res://scenes/components/Tile.tscn")
const TileScript = preload("res://scenes/components/Tile.gd")
const Fmt = preload("res://scenes/scripts/Fmt.gd")

var _tiles: Array = []
var _side: int = 0

@onready var _crop_button: Button = $VBox/ToolbarTop/CropButton
@onready var _build_button: Button = $VBox/ToolbarTop/BuildButton
@onready var _plant_all: Button = $VBox/ToolbarBottom/PlantAll
@onready var _harvest_all: Button = $VBox/ToolbarBottom/HarvestAll
@onready var _info: Label = $VBox/Info
@onready var _field: MarginContainer = $VBox/Center/Field
@onready var _grid: GridContainer = $VBox/Center/Field/Plate/Grid


func _ready() -> void:
	_build_grid()
	for button: Button in [_plant_all, _harvest_all]:
		button.set_meta(UiFx.SFX_META, "")
	_crop_button.pressed.connect(_open_modal.bind("plant_picker"))
	_build_button.pressed.connect(_open_modal.bind("build_menu"))
	_plant_all.pressed.connect(_on_plant_all)
	_harvest_all.pressed.connect(_on_harvest_all)
	Signals.tab_requested.connect(_on_tab)
	Signals.tiles_changed.connect(_render_tiles)
	Signals.clock_tick.connect(_on_clock)
	Signals.tile_tapped.connect(_on_tile_tapped)
	Signals.selected_crop_changed.connect(_on_crop_selected)
	Signals.boost_changed.connect(_on_boost_changed)
	Signals.field_expanded.connect(_on_field_expanded.unbind(1))
	Signals.state_loaded.connect(_apply_field.bind(false))


func _build_grid() -> void:
	var side: int = Economy.cfg_i("grid_size")
	var gap: int = Economy.ui_i("tile_gap")
	# Headroom so tall plants in the first row are not drawn over the info label.
	_field.add_theme_constant_override("margin_top", Economy.ui_i("field_top_margin"))
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for i: int in side * side:
		var tile: TileScript = TILE_SCENE.instantiate()
		_grid.add_child(tile)
		tile.setup(i, Economy.ui_i("tile_size"))
		_tiles.append(tile)
	_apply_field(false)


## Shows the open square of the field; with `animate`, newly opened tiles pop in as a
## diagonal wave running away from the old field.
func _apply_field(animate: bool) -> void:
	var grid: int = Economy.cfg_i("grid_size")
	var side: int = GameState.field_side()
	var old_side: int = _side
	_side = side
	_grid.columns = side
	var stagger: float = Economy.anim_f("tile_appear_stagger")
	for i: int in _tiles.size():
		var tile: TileScript = _tiles[i]
		var opened: bool = GameState.is_tile_open(i)
		var was_open: bool = tile.visible
		tile.visible = opened
		if animate and opened and not was_open:
			var wave: int = maxi(floori(float(i) / float(grid)) + i % grid - old_side, 0)
			tile.appear(stagger * float(wave))


func _on_field_expanded() -> void:
	if visible:
		_apply_field(true)


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	if visible:
		if GameState.field_side() != _side:
			_apply_field(true)
		_render_tiles()
		_update_info(TimeService.now())


func _on_clock(now: float) -> void:
	if visible:
		_render_tiles()
		_update_info(now)


func _render_tiles() -> void:
	if not visible:
		return
	var now: float = TimeService.now()
	for i: int in _tiles.size():
		(_tiles[i] as TileScript).render(GameState.tile(i), GameState.tile_progress(i, now))


func _update_info(now: float) -> void:
	var ready: int = GameState.count_tiles(GameState.TileState.READY)
	var growing: int = GameState.count_tiles(GameState.TileState.PLANTED)
	var text: String = "Поле %d×%d · Растёт: %d · Готово: %d" % [_side, _side, growing, ready]
	var next: Dictionary = Economy.next_field_step(GameState.level)
	if not next.is_empty():
		text += "\nПоле %d×%d откроется на уровне %d" % [int(next["side"]), int(next["side"]), int(next["level"])]
	if GameState.is_boost_active(now):
		text += " · Ускорение роста: %s" % Fmt.duration(GameState.boost_until - now)
	_info.text = text


func _on_crop_selected(crop_id: String) -> void:
	var def: Dictionary = Economy.crop(crop_id)
	_crop_button.text = "Сажать: %s" % (str(def["name"]) if not def.is_empty() else "—")


func _on_boost_changed(_until: float) -> void:
	_update_info(TimeService.now())


func _on_plant_all() -> void:
	if GameState.selected_crop.is_empty():
		_open_modal("plant_picker")
		return
	_sound(GameState.plant_all(GameState.selected_crop) > 0, "plant")


func _on_tile_tapped(index: int) -> void:
	var state: int = GameState.tile_state(index)
	if state == GameState.TileState.EMPTY:
		_sound(GameState.plow(index), "plow")
	elif state == GameState.TileState.PLOWED:
		if GameState.selected_crop.is_empty():
			_open_modal("plant_picker")
		else:
			_sound(GameState.plant(index, GameState.selected_crop), "plant")
	elif state == GameState.TileState.PLANTED:
		Audio.play("tock")
		_toast_growing(index)
	elif state == GameState.TileState.READY:
		var crop_id: String = str(GameState.tile(index)["c"])
		if _sound(GameState.harvest(index), "harvest"):
			_float_yield(index, crop_id)
	elif state == GameState.TileState.WITHERED:
		_sound(GameState.clear_tile(index), "clear")


## Plays the action's sound on success, a soft "nope" otherwise; passes `ok` through.
func _sound(ok: bool, sound_id: String) -> bool:
	Audio.play(sound_id if ok else "deny")
	return ok


func _on_harvest_all() -> void:
	var ready: Dictionary = {}
	for i: int in _tiles.size():
		if GameState.tile_state(i) == GameState.TileState.READY and GameState.is_tile_open(i):
			ready[i] = str(GameState.tile(i)["c"])
	var harvested: int = GameState.harvest_all()
	if harvested <= 0:
		Audio.play("deny")
		return
	Audio.play_harvest_many(harvested)
	var shown: int = 0
	for i: int in ready:
		if shown >= int(Economy.anim_f("float_text_limit")):
			break
		if GameState.tile_state(i) != GameState.TileState.READY:
			_float_yield(i, str(ready[i]))
			shown += 1


## "+N Crop" rising from a harvested tile, tinted with the crop colour.
func _float_yield(index: int, crop_id: String) -> void:
	var def: Dictionary = Economy.crop(crop_id)
	var tile: TileScript = _tiles[index]
	var text: String = "+%d %s" % [int(def.get("yield", 1)), Economy.item_name(crop_id)]
	var color: Color = Color.from_string(str(def.get("color", "")), Color.WHITE).lightened(0.2)
	UiFx.float_text(self, text, tile.global_position + tile.size * Vector2(0.5, 0.2), color)


func _toast_growing(index: int) -> void:
	var crop_name: String = Economy.item_name(str(GameState.tile(index)["c"]))
	var left: float = GameState.tile_seconds_left(index, TimeService.now())
	Signals.toast_requested.emit("%s: созреет через %s" % [crop_name, Fmt.duration(left)])


func _open_modal(modal_id: String) -> void:
	Signals.modal_requested.emit(modal_id, {})
