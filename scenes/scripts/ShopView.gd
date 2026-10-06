extends Control
## Shop tab: rewarded-ad offers and IAP products (all via IAP / AdManager stubs), plus the
## music / sound toggles at the bottom.

const TAB_ID: String = "shop"
const SHOP_PLACEMENT: String = "shop"
const SECTION_FONT_SIZE: int = 26
const Fmt = preload("res://scenes/scripts/Fmt.gd")

var _product_buttons: Dictionary = {}
var _music_toggle: Button = null
var _sfx_toggle: Button = null

@onready var _status: Label = $Margin/Scroll/VBox/Status
@onready var _ads: VBoxContainer = $Margin/Scroll/VBox/Ads
@onready var _products: VBoxContainer = $Margin/Scroll/VBox/Products
@onready var _restore: Button = $Margin/Scroll/VBox/Restore
@onready var _vbox: VBoxContainer = $Margin/Scroll/VBox


func _ready() -> void:
	_build_ads()
	_build_products()
	_build_settings()
	_restore.pressed.connect(IAP.restore)
	Signals.tab_requested.connect(_on_tab)
	Signals.clock_tick.connect(_on_clock)
	Signals.purchase_completed.connect(_on_purchase_completed)
	Signals.purchase_failed.connect(_on_purchase_failed)
	Signals.restore_completed.connect(_on_restore_completed)


func _build_ads() -> void:
	for offer: Variant in Economy.rewarded_offers():
		if str(offer.get("placement", SHOP_PLACEMENT)) != SHOP_PLACEMENT:
			continue
		var button: Button = Button.new()
		button.text = "Смотреть рекламу: %s" % str(offer["title"])
		button.theme_type_variation = &"ButtonPurple"
		button.custom_minimum_size.y = Economy.ui_i("button_height")
		button.pressed.connect(_on_rewarded.bind(str(offer["id"])))
		_ads.add_child(button)


func _build_products() -> void:
	for product: Variant in Economy.iap_products():
		var sku: String = str(product["sku"])
		var button: Button = Button.new()
		button.theme_type_variation = &"ButtonGold"
		button.custom_minimum_size.y = Economy.ui_i("button_height")
		button.pressed.connect(func() -> void: Signals.modal_requested.emit("iap_confirm", {"sku": sku}))
		_products.add_child(button)
		_product_buttons[sku] = button


func _build_settings() -> void:
	_vbox.add_child(HSeparator.new())
	var title: Label = Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_vbox.add_child(title)
	_music_toggle = _add_toggle(Audio.set_music_on)
	_sfx_toggle = _add_toggle(Audio.set_sfx_on)
	Audio.settings_changed.connect(_refresh_settings)
	_refresh_settings()


func _add_toggle(setter: Callable) -> Button:
	var button: Button = Button.new()
	button.toggle_mode = true
	button.theme_type_variation = &"ButtonBlue"
	button.custom_minimum_size.y = Economy.ui_i("button_height")
	button.toggled.connect(setter)
	_vbox.add_child(button)
	return button


func _refresh_settings() -> void:
	_music_toggle.set_pressed_no_signal(Audio.music_on)
	_sfx_toggle.set_pressed_no_signal(Audio.sfx_on)
	_music_toggle.text = "Музыка: %s" % ("вкл" if Audio.music_on else "выкл")
	_sfx_toggle.text = "Звуки: %s" % ("вкл" if Audio.sfx_on else "выкл")


func _on_tab(tab_id: String) -> void:
	visible = tab_id == TAB_ID
	if visible:
		_refresh_products()
		_refresh_status(TimeService.now())


func _on_clock(now: float) -> void:
	if visible:
		_refresh_status(now)


func _refresh_status(now: float) -> void:
	var lines: PackedStringArray = PackedStringArray()
	if GameState.is_boost_active(now):
		lines.append("Ускорение роста: ещё %s" % Fmt.duration(GameState.boost_until - now))
	if GameState.no_ads:
		lines.append("Реклама между уровнями отключена")
	_status.text = "Нет активных бонусов" if lines.is_empty() else "\n".join(lines)


func _refresh_products() -> void:
	for product: Variant in Economy.iap_products():
		var sku: String = str(product["sku"])
		var button: Button = _product_buttons[sku]
		var owned: bool = not bool(product.get("consumable", true)) and IAP.is_owned(sku)
		button.text = "%s — %s" % [str(product["title"]), "куплено" if owned else str(product["price"])]
		button.disabled = owned


func _on_rewarded(offer_id: String) -> void:
	AdManager.show_rewarded(GameState.apply_rewarded.bind(offer_id, -1))


func _on_purchase_completed(sku: String) -> void:
	Signals.toast_requested.emit("Покупка успешна: %s" % str(Economy.iap_product(sku).get("title", sku)))
	_refresh_products()


func _on_purchase_failed(sku: String, reason: String) -> void:
	Signals.toast_requested.emit("Покупка не удалась (%s): %s" % [sku, reason])


func _on_restore_completed(skus: Array) -> void:
	Signals.toast_requested.emit("Восстановлено покупок: %d" % skus.size())
	_refresh_products()
