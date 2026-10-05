extends Control
## Farm tab: 10x10 tile grid, tap = context action (plow / plant / harvest / clear).

const TAB_ID: String = "farm"
const TILE_SCENE: PackedScene = preload("res://scenes/components/Tile.tscn")
const TileScript = preload("res://scenes/components/Tile.gd")
const Fmt = preload("res://scenes/scripts/Fmt.gd")

var _tiles: Array = []

@onready var _crop_button: Button = $VBox/ToolbarTop/CropButton
@onready var _build_button: Button = $VBox/ToolbarTop/BuildButton
@onready var _plant_all: Button = $VBox/ToolbarBottom/PlantAll
@onready var _harvest_all: Button = $VBox/ToolbarBottom/HarvestAll
@onready var _info: Label = $VBox/Info
@onready var _grid: GridContainer = $VBox/Center/Grid


func _ready() -> void:
	_build_grid()
	_crop_button.pressed.connect(_open_modal.bind("plant_picker"))
	_build_button.pressed.connect(_open_modal.bind("build_menu"))
	_plant_all.pressed.connect(_on_plant_all)
	_harvest_all.pressed.connect(GameState.harvest_all)
	Signals.tab_requested.connect(_on_tab)
	Signals.tiles_changed.connect(_render_tiles)
	Signals.clock_tick.connect(_on_clock)
	Signals.tile_tapped.connect(_on_tile_tapped)
	Signals.selected_crop_changed.connect(_on_crop_selected)
	Signals.boost_changed.connect(_on_boost_changed)


func _build_grid() -> void:
	var side: int = Economy.cfg_i("grid_size")
	var gap: int = Economy.ui_i("tile_gap")
	_grid.columns = side
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for i: int in side * side:
		var tile: TileScript = TILE_SCENE.instantiate()
		_grid.add_child(tile)
		tile.setup(i, Economy.ui_i("tile_size"))
		_tiles.append(tile)


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	if visible:
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
	var text: String = "Растёт: %d · Готово: %d" % [growing, ready]
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
	GameState.plant_all(GameState.selected_crop)


func _on_tile_tapped(index: int) -> void:
	var state: int = GameState.tile_state(index)
	if state == GameState.TileState.EMPTY:
		GameState.plow(index)
	elif state == GameState.TileState.PLOWED:
		if GameState.selected_crop.is_empty():
			_open_modal("plant_picker")
		else:
			GameState.plant(index, GameState.selected_crop)
	elif state == GameState.TileState.PLANTED:
		_toast_growing(index)
	elif state == GameState.TileState.READY:
		GameState.harvest(index)
	elif state == GameState.TileState.WITHERED:
		GameState.clear_tile(index)


func _toast_growing(index: int) -> void:
	var crop_name: String = Economy.item_name(str(GameState.tile(index)["c"]))
	var left: float = GameState.tile_seconds_left(index, TimeService.now())
	Signals.toast_requested.emit("%s: созреет через %s" % [crop_name, Fmt.duration(left)])


func _open_modal(modal_id: String) -> void:
	Signals.modal_requested.emit(modal_id, {})
