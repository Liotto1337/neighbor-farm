extends Control
## Shop tab: rewarded-ad offers (AdManager) and in-app products (IAP), plus the music / sound
## toggles at the bottom. Product titles, descriptions and prices come from the platform
## catalog when available; the buy button opens the platform payment window directly.

const TAB_ID: String = "shop"
const SHOP_PLACEMENT: String = "shop"
const SECTION_FONT_SIZE: int = 26
const CARD_TITLE_FONT_SIZE: int = 24
const CARD_DESC_FONT_SIZE: int = 19
const Fmt = preload("res://scenes/scripts/Fmt.gd")
const CURRENCY_ICON_PX: int = 28
const PURCHASE_FAIL_TEXT: Dictionary = {
	"already_owned": "Уже куплено",
	"busy": "Покупка уже оформляется",
	"unavailable": "Покупки сейчас недоступны",
	"canceled": "Покупка отменена",
}

## sku -> {card, title, desc, button}
var _product_cards: Dictionary = {}
var _iap_note: Label = null
var _auth_button: Button = null
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
	IAP.catalog_changed.connect(_refresh_products)
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
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = &"Card"
		var box: VBoxContainer = VBoxContainer.new()
		var title: Label = Label.new()
		title.add_theme_font_size_override("font_size", CARD_TITLE_FONT_SIZE)
		var desc: Label = Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", CARD_DESC_FONT_SIZE)
		var button: Button = Button.new()
		button.theme_type_variation = &"ButtonGold"
		button.custom_minimum_size.y = Economy.ui_i("button_height")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_theme_constant_override("icon_max_width", CURRENCY_ICON_PX)
		button.pressed.connect(IAP.purchase.bind(sku))
		box.add_child(title)
		box.add_child(desc)
		box.add_child(button)
		card.add_child(box)
		_products.add_child(card)
		_product_cards[sku] = {"card": card, "title": title, "desc": desc, "button": button}
	_iap_note = Label.new()
	_iap_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_products.add_child(_iap_note)


func _build_settings() -> void:
	_vbox.add_child(HSeparator.new())
	var title: Label = Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_vbox.add_child(title)
	_music_toggle = _add_toggle(Audio.set_music_on)
	_sfx_toggle = _add_toggle(Audio.set_sfx_on)
	# Guests keep cloud progress only on this device; signing in carries it to any device.
	_auth_button = Button.new()
	_auth_button.text = "Войти в Яндекс — прогресс будет на всех устройствах"
	_auth_button.theme_type_variation = &"ButtonGold"
	_auth_button.custom_minimum_size.y = Economy.ui_i("button_height")
	_auth_button.clip_text = true
	_auth_button.pressed.connect(YandexSdk.open_auth)
	_vbox.add_child(_auth_button)
	Audio.settings_changed.connect(_refresh_settings)
	YandexSdk.cloud_loaded.connect(_refresh_settings.unbind(1))
	YandexSdk.auth_finished.connect(_refresh_settings.unbind(1))
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
	_auth_button.visible = YandexSdk.is_ready() and YandexSdk.cloud_available and not YandexSdk.player_authorized


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
	var provider: String = IAP.provider()
	var listed: int = 0
	for sku: String in _product_cards:
		var parts: Dictionary = _product_cards[sku]
		var button: Button = parts["button"]
		(parts["card"] as Control).visible = IAP.is_listed(sku)
		if not IAP.is_listed(sku):
			continue
		listed += 1
		(parts["title"] as Label).text = IAP.title(sku)
		(parts["desc"] as Label).text = IAP.description(sku)
		button.icon = null
		if IAP.is_owned(sku):
			button.text = "Куплено"
		elif provider == "pending":
			button.text = "Загрузка…"
		else:
			button.text = "Купить за %s" % IAP.price_text(sku)
			button.icon = IAP.currency_icon
		button.disabled = not IAP.can_buy(sku)
	_iap_note.visible = listed == 0
	_iap_note.text = "Покупки сейчас недоступны."
	_restore.visible = provider == "yandex" or provider == "stub"


func _on_rewarded(offer_id: String) -> void:
	AdManager.show_rewarded(GameState.apply_rewarded.bind(offer_id, -1))


func _on_purchase_completed(sku: String) -> void:
	Signals.toast_requested.emit("Покупка успешна: %s" % IAP.title(sku))
	_refresh_products()


func _on_purchase_failed(_sku: String, reason: String) -> void:
	Signals.toast_requested.emit(str(PURCHASE_FAIL_TEXT.get(reason, "Покупка не удалась")))
	_refresh_products()


func _on_restore_completed(skus: Array) -> void:
	Signals.toast_requested.emit("Восстановлено покупок: %d" % skus.size())
	_refresh_products()
