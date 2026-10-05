extends Control
## Market tab: sell harvest (1 / all), buy seed packs, workshop crafting (harvest → seeds).

const TAB_ID: String = "market"

var _rebuild_queued: bool = false

@onready var _storage: Label = $Margin/VBox/Storage
@onready var _buy_seeds: Button = $Margin/VBox/Actions/BuySeeds
@onready var _sell_all: Button = $Margin/VBox/Actions/SellAll
@onready var _list: VBoxContainer = $Margin/VBox/Scroll/List


func _ready() -> void:
	_buy_seeds.pressed.connect(GameState.buy_seed_pack)
	_sell_all.pressed.connect(GameState.sell_all_items)
	Signals.tab_requested.connect(_on_tab)
	Signals.inventory_changed.connect(_queue_rebuild)
	Signals.buildings_changed.connect(_queue_rebuild)
	Signals.currencies_changed.connect(_queue_rebuild.unbind(3))


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not visible:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	_refresh_header()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var ids: Array = GameState.inventory.keys()
	ids.sort()
	if ids.is_empty():
		var empty: Label = Label.new()
		empty.text = "Склад пуст — соберите урожай на ферме."
		_list.add_child(empty)
	for id: Variant in ids:
		_list.add_child(_make_row(str(id)))


func _refresh_header() -> void:
	var pack: Dictionary = Economy.cfg_dict("seed_pack")
	_buy_seeds.text = "Семена +%d за %d" % [int(pack.get("seeds", 0)), int(pack.get("cost", 0))]
	var workshop: int = GameState.building_level("workshop")
	var stall: int = GameState.building_level("market_stall")
	_storage.text = "Вместимость склада: %d каждого товара.\nМастерская ур. %d · Прилавок ур. %d" % [
		GameState.storage_cap(), workshop, stall]


func _make_row(item_id: String) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = "%s × %d · цена %d" % [Economy.item_name(item_id), GameState.item_count(item_id), Economy.item_sell_price(item_id)]
	row.add_child(label)
	var buttons: HBoxContainer = HBoxContainer.new()
	row.add_child(buttons)
	_add_button(buttons, "Продать 1", GameState.sell_item.bind(item_id, 1))
	_add_button(buttons, "Продать все", GameState.sell_item.bind(item_id, GameState.item_count(item_id)))
	if Economy.is_crop(item_id) and GameState.building_level("workshop") > 0:
		_add_button(buttons, "В семена", GameState.craft_seeds.bind(item_id))
	row.add_child(HSeparator.new())
	return row


func _add_button(parent: Container, text: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = Economy.ui_i("button_height")
	button.pressed.connect(callback)
	parent.add_child(button)
