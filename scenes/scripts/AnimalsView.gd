extends Control
## Animals tab: barn status, buy and sell animals, make feed from corn, feed and collect products.

const TAB_ID: String = "animals"
const Fmt = preload("res://scenes/scripts/Fmt.gd")
const SELL_BUTTON_WIDTH: int = 130

var _rows: Array = []
var _buy_buttons: Dictionary = {}

@onready var _header: Label = $Margin/VBox/Header
@onready var _feed_info: Label = $Margin/VBox/FeedRow/FeedInfo
@onready var _make_feed: Button = $Margin/VBox/FeedRow/MakeFeed
@onready var _shop: VBoxContainer = $Margin/VBox/Shop
@onready var _list: VBoxContainer = $Margin/VBox/Scroll/List


func _ready() -> void:
	_build_shop()
	_make_feed.pressed.connect(GameState.make_feed)
	Signals.tab_requested.connect(_on_tab)
	Signals.animals_changed.connect(_refresh)
	Signals.buildings_changed.connect(_refresh)
	Signals.inventory_changed.connect(_refresh)
	Signals.currencies_changed.connect(_refresh.unbind(3))
	Signals.level_up.connect(_refresh.unbind(1))
	Signals.clock_tick.connect(_on_clock)


func _build_shop() -> void:
	for def: Variant in Economy.animals_list():
		var id: String = str(def["id"])
		var button: Button = Button.new()
		button.theme_type_variation = &"ButtonBlue"
		button.custom_minimum_size.y = Economy.ui_i("button_height")
		button.pressed.connect(GameState.buy_animal.bind(id))
		_shop.add_child(button)
		_buy_buttons[id] = button


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	_refresh()


func _on_clock(_now: float) -> void:
	if visible:
		_sync_rows()


func _refresh() -> void:
	if not visible:
		return
	_refresh_header()
	_refresh_shop()
	_sync_rows()


func _refresh_header() -> void:
	var barn: int = GameState.building_level("barn")
	if barn <= 0:
		_header.text = "Постройте амбар: вкладка «Ферма», кнопка «Постройки»."
	else:
		_header.text = "Амбар ур. %d · животных %d / %d" % [barn, GameState.animals.size(), GameState.max_animals()]
	var source: String = str(Economy.cfg("feed_source_item"))
	_feed_info.text = "Корм: %d · %s: %d (1 шт. = %d корма)" % [
		GameState.feed, Economy.item_name(source), GameState.item_count(source), Economy.cfg_i("feed_per_corn")]
	_make_feed.disabled = GameState.item_count(source) <= 0


func _refresh_shop() -> void:
	for def: Variant in Economy.animals_list():
		var button: Button = _buy_buttons[str(def["id"])]
		var unlock: int = int(def["unlock_level"])
		if GameState.level < unlock:
			button.text = "%s — откроется на уровне %d" % [str(def["name"]), unlock]
			button.disabled = true
			continue
		button.text = "Купить: %s — %d монет" % [str(def["name"]), int(def["cost"])]
		button.disabled = GameState.building_level("barn") <= 0 or GameState.coins < int(def["cost"])


func _sync_rows() -> void:
	if _rows.size() != GameState.animals.size():
		_rebuild_rows()
	var now: float = TimeService.now()
	for i: int in _rows.size():
		_update_row(i, now)


func _rebuild_rows() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	for i: int in GameState.animals.size():
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(Economy.ui_i("row_button_width"), Economy.ui_i("button_height"))
		button.pressed.connect(_on_row_pressed.bind(i))
		var sell: Button = Button.new()
		sell.text = "Продать"
		sell.theme_type_variation = &"ButtonRed"
		sell.custom_minimum_size = Vector2(SELL_BUTTON_WIDTH, Economy.ui_i("button_height"))
		sell.pressed.connect(_on_sell_pressed.bind(i))
		row.add_child(label)
		row.add_child(button)
		row.add_child(sell)
		_list.add_child(row)
		_rows.append({"label": label, "button": button})


func _update_row(i: int, now: float) -> void:
	var label: Label = _rows[i]["label"]
	var button: Button = _rows[i]["button"]
	var def: Dictionary = Economy.animal(str(GameState.animals[i]["t"]))
	var status: int = GameState.animal_status(i, now)
	if status == GameState.AnimalStatus.HUNGRY:
		label.text = "%s — проголодалась" % str(def["name"])
		button.text = "Покормить (%d)" % int(def["feed_cost"])
		button.disabled = GameState.feed < int(def["feed_cost"])
	elif status == GameState.AnimalStatus.PRODUCING:
		label.text = "%s — %s через %s" % [str(def["name"]), str(def["product_name"]), Fmt.duration(GameState.animal_seconds_left(i, now))]
		button.text = "Ждём…"
		button.disabled = true
	else:
		label.text = "%s — готово: %s!" % [str(def["name"]), str(def["product_name"])]
		button.text = "Собрать"
		button.disabled = false


func _on_sell_pressed(i: int) -> void:
	Signals.modal_requested.emit("sell_animal", {"index": i, "type": str(GameState.animals[i]["t"])})


func _on_row_pressed(i: int) -> void:
	var status: int = GameState.animal_status(i, TimeService.now())
	if status == GameState.AnimalStatus.HUNGRY:
		GameState.feed_animal(i)
	elif status == GameState.AnimalStatus.READY:
		GameState.collect_animal(i)
