extends Control
## Neighbors tab: weekly co-op contract, neighbor list and visit screen (help / gift / trade).

const TAB_ID: String = "neighbors"
const REWARDED_TRUST_ID: String = "trust"
const Fmt = preload("res://scenes/scripts/Fmt.gd")

var _rows: Array = []
var _visit_index: int = -1

@onready var _list_panel: VBoxContainer = $Margin/ListPanel
@onready var _list: VBoxContainer = $Margin/ListPanel/Scroll/List
@onready var _visit_panel: VBoxContainer = $Margin/VisitPanel
@onready var _back: Button = $Margin/VisitPanel/Header/Back
@onready var _visit_name: Label = $Margin/VisitPanel/Header/Name
@onready var _farm_grid: GridContainer = $Margin/VisitPanel/Farm/Grid
@onready var _trust: Label = $Margin/VisitPanel/Trust
@onready var _trust_bar: ProgressBar = $Margin/VisitPanel/TrustBar
@onready var _request: Label = $Margin/VisitPanel/Scroll/Actions/Request
@onready var _help: Button = $Margin/VisitPanel/Scroll/Actions/Help
@onready var _gift: Label = $Margin/VisitPanel/Scroll/Actions/Gift
@onready var _gift_button: Button = $Margin/VisitPanel/Scroll/Actions/GiftButton
@onready var _offer: Label = $Margin/VisitPanel/Scroll/Actions/Offer
@onready var _offer_button: Button = $Margin/VisitPanel/Scroll/Actions/OfferButton
@onready var _ad_trust: Button = $Margin/VisitPanel/Scroll/Actions/AdTrust


func _ready() -> void:
	_back.pressed.connect(_close_visit)
	_help.pressed.connect(func() -> void: GameState.help_neighbor(_visit_index))
	_gift_button.pressed.connect(func() -> void: GameState.claim_gift(_visit_index))
	_offer_button.pressed.connect(func() -> void: GameState.accept_offer(_visit_index))
	_ad_trust.pressed.connect(_on_ad_trust)
	_ad_trust.text = "Реклама: %s" % str(Economy.rewarded_offer(REWARDED_TRUST_ID).get("title", ""))
	Signals.tab_requested.connect(_on_tab)
	Signals.state_loaded.connect(_build_rows)
	Signals.neighbors_changed.connect(_refresh)
	Signals.inventory_changed.connect(_refresh)
	Signals.currencies_changed.connect(_refresh.unbind(3))
	Signals.clock_tick.connect(_refresh.unbind(1))
	Signals.neighbor_visit_requested.connect(_open_visit)


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	_refresh()


func _build_rows() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var profiles: Array = NeighborAI.profiles(GameState.world_seed)
	for i: int in profiles.size():
		_rows.append(_make_row(i, str(profiles[i]["name"])))
	_refresh()


func _make_row(index: int, display_name: String) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	var hbox: HBoxContainer = HBoxContainer.new()
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = Label.new()
	name_label.text = display_name
	var status: Label = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar: ProgressBar = _make_trust_bar()
	var visit: Button = Button.new()
	visit.text = "В гости"
	visit.custom_minimum_size = Vector2(Economy.ui_i("row_button_width"), Economy.ui_i("button_height"))
	visit.pressed.connect(func() -> void: Signals.neighbor_visit_requested.emit(index))
	info.add_child(name_label)
	info.add_child(status)
	info.add_child(bar)
	hbox.add_child(info)
	hbox.add_child(visit)
	panel.add_child(hbox)
	_list.add_child(panel)
	return {"status": status, "bar": bar}


func _make_trust_bar() -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = float(Economy.neighbor_cfg("trust_max"))
	bar.show_percentage = false
	bar.custom_minimum_size.y = Economy.ui_i("trust_bar_height")
	return bar


func _refresh() -> void:
	if not visible:
		return
	var now: float = TimeService.now()
	for i: int in _rows.size():
		_update_row(i, now)
	if _visit_index >= 0:
		_refresh_visit(now)


func _update_row(index: int, now: float) -> void:
	var st: Dictionary = GameState.neighbor_state(index)
	var flags: PackedStringArray = PackedStringArray()
	if not (st["req"] as Dictionary).is_empty():
		flags.append("Нужна помощь!")
	if now >= float(st["gift_at"]):
		flags.append("Есть подарок")
	if not (st["offer"] as Dictionary).is_empty():
		flags.append("Хочет купить")
	(_rows[index]["status"] as Label).text = "Всё спокойно" if flags.is_empty() else " · ".join(flags)
	(_rows[index]["bar"] as ProgressBar).value = float(st["trust"])


func _open_visit(index: int) -> void:
	_visit_index = index
	_build_farm_grid(index)
	_list_panel.visible = false
	_visit_panel.visible = true
	_refresh()


func _close_visit() -> void:
	_visit_index = -1
	_visit_panel.visible = false
	_list_panel.visible = true
	_refresh()


func _build_farm_grid(index: int) -> void:
	for child: Node in _farm_grid.get_children():
		_farm_grid.remove_child(child)
		child.queue_free()
	var profile: Dictionary = NeighborAI.profiles(GameState.world_seed)[index]
	var side: int = int(Economy.neighbor_cfg("visit_grid"))
	var cell: int = Economy.ui_i("visit_cell")
	_farm_grid.columns = side
	_farm_grid.add_theme_constant_override("h_separation", Economy.ui_i("visit_gap"))
	_farm_grid.add_theme_constant_override("v_separation", Economy.ui_i("visit_gap"))
	_visit_name.text = str(profile["name"])
	for color_hex: Variant in profile["cells"]:
		var rect: ColorRect = ColorRect.new()
		rect.custom_minimum_size = Vector2(cell, cell)
		rect.color = Color.from_string(str(color_hex), Color.WHITE)
		_farm_grid.add_child(rect)


func _refresh_visit(now: float) -> void:
	var st: Dictionary = GameState.neighbor_state(_visit_index)
	_trust.text = "Доверие: %d / %d" % [int(st["trust"]), int(Economy.neighbor_cfg("trust_max"))]
	_trust_bar.max_value = float(Economy.neighbor_cfg("trust_max"))
	_trust_bar.value = float(st["trust"])
	_refresh_request(st, now)
	_refresh_gift(st, now)
	_refresh_offer(st)


func _refresh_request(st: Dictionary, now: float) -> void:
	var req: Dictionary = st["req"]
	if req.is_empty():
		_request.text = "Помощь пока не нужна. Загляните позже."
		_help.text = "Помочь"
		_help.disabled = true
		return
	var rt: Dictionary = Economy.request_type(str(req["type"]))
	var cost: int = int(rt.get("cost_feed", 0))
	_request.text = "Просьба: %s.\nНаграда: %d монет, %d опыта, +%d доверия. Осталось %s." % [
		str(rt.get("title", "")), int(rt.get("reward_coins", 0)), int(rt.get("reward_xp", 0)),
		int(rt.get("trust", 0)), Fmt.duration(float(req["exp"]) - now)]
	_help.text = "Помочь" if cost <= 0 else "Помочь (−%d корма)" % cost
	_help.disabled = GameState.feed < cost


func _refresh_gift(st: Dictionary, now: float) -> void:
	var gift_at: float = float(st["gift_at"])
	var amount: int = Economy.gift_seeds(int(st["trust"]))
	if now >= gift_at:
		_gift.text = "Подарок готов: %d семян (больше доверие — щедрее подарки)." % amount
		_gift_button.disabled = false
	else:
		_gift.text = "Следующий подарок через %s." % Fmt.duration(gift_at - now)
		_gift_button.disabled = true


func _refresh_offer(st: Dictionary) -> void:
	var offer: Dictionary = st["offer"]
	if offer.is_empty():
		_offer.text = "Сосед пока ничего не покупает."
		_offer_button.disabled = true
		return
	var item: String = str(offer["item"])
	_offer.text = "Купит: %s × %d по %d монет (у вас %d)." % [
		Economy.item_name(item), int(offer["qty"]), int(offer["price"]), GameState.item_count(item)]
	_offer_button.disabled = GameState.item_count(item) <= 0


func _on_ad_trust() -> void:
	if _visit_index < 0:
		return
	AdManager.show_rewarded(GameState.apply_rewarded.bind(REWARDED_TRUST_ID, _visit_index))
