extends Node
## In-app purchases facade.
## Yandex Games: real payments through YandexSdk. Prices, titles and descriptions come from the
## SDK catalog (portal currency name and icon, requirements 1.13.2 / 1.13.4). A consumable is
## granted and saved first and only then consumed; purchases left unprocessed (e.g. the tab was
## closed mid-purchase) are recovered at launch (1.13.1). Product ids in the Developer Console
## must equal the skus in data/iap.json.
## Debug builds without the SDK (editor, desktop) use a stub where every purchase succeeds;
## release builds without the SDK sell nothing.

## Catalog, currency icon or availability changed; the shop re-reads prices.
signal catalog_changed

var currency_icon: Texture2D = null

var _catalog: Dictionary = {}
var _purchasing: String = ""
var _manual_restore: bool = false
var _state_loaded: bool = false
var _synced: bool = false
var _payments_known: bool = false
var _icon_request: HTTPRequest = null


func _ready() -> void:
	Signals.state_loaded.connect(_on_state_loaded)
	YandexSdk.ready_changed.connect(_on_sdk_changed.unbind(1))
	YandexSdk.payments_ready.connect(_on_payments_ready)
	YandexSdk.catalog_loaded.connect(_on_catalog_loaded)
	YandexSdk.purchase_finished.connect(_on_purchase_finished)
	YandexSdk.purchases_loaded.connect(_on_purchases_loaded)
	YandexSdk.consume_finished.connect(_on_consume_finished)


# =====================================================================
# Queries for the UI
# =====================================================================

## "yandex", "stub", "pending" (SDK still starting) or "none".
func provider() -> String:
	if YandexSdk.payments_available:
		return "yandex"
	if YandexSdk.is_pending() or (YandexSdk.is_ready() and not _payments_known):
		return "pending"
	if not YandexSdk.is_ready() and OS.is_debug_build():
		return "stub"
	return "none"


## Whether the product is offered right now (in the platform catalog, or stubbed).
func is_listed(sku: String) -> bool:
	match provider():
		"yandex":
			return _catalog.has(sku)
		"stub", "pending":
			return true
	return false


func can_buy(sku: String) -> bool:
	var p: String = provider()
	return (p == "stub" or (p == "yandex" and _catalog.has(sku))) and not is_owned(sku) and _purchasing.is_empty()


func is_owned(sku: String) -> bool:
	var product: Dictionary = Economy.iap_product(sku)
	return not bool(product.get("consumable", true)) and GameState.is_sku_owned(sku)


## Price as shown to the player: number + portal currency from the SDK (local text in the stub).
func price_text(sku: String) -> String:
	if _catalog.has(sku):
		return str(_catalog[sku].get("price", ""))
	return str(Economy.iap_product(sku).get("price", ""))


func title(sku: String) -> String:
	return _text(sku, "title")


func description(sku: String) -> String:
	return _text(sku, "description", "desc")


func _text(sku: String, catalog_key: String, local_key: String = "") -> String:
	var remote: String = str(_catalog.get(sku, {}).get(catalog_key, ""))
	if not remote.is_empty():
		return remote
	return str(Economy.iap_product(sku).get(local_key if not local_key.is_empty() else catalog_key, ""))


# =====================================================================
# Actions
# =====================================================================

func purchase(sku: String) -> void:
	var product: Dictionary = Economy.iap_product(sku)
	if product.is_empty():
		push_error("IAP: unknown sku '%s'" % sku)
		Signals.purchase_failed.emit(sku, "unknown_sku")
		return
	if is_owned(sku):
		Signals.purchase_failed.emit(sku, "already_owned")
		return
	if not _purchasing.is_empty():
		Signals.purchase_failed.emit(sku, "busy")
		return
	match provider():
		"yandex":
			if not _catalog.has(sku):
				Signals.purchase_failed.emit(sku, "unavailable")
				return
			_purchasing = sku
			Signals.purchase_started.emit(sku)
			YandexSdk.set_gameplay_blocked("purchase", true)
			YandexSdk.purchase(sku)
		"stub":
			Signals.purchase_started.emit(sku)
			_grant.call_deferred(sku, "")
		_:
			Signals.purchase_failed.emit(sku, "unavailable")


## Re-reads the player's purchases from the platform (restores non-consumables).
func restore() -> void:
	if provider() == "yandex":
		_manual_restore = true
		YandexSdk.load_purchases()
	else:
		Signals.restore_completed.emit(GameState.owned_skus.duplicate())


# =====================================================================
# Yandex flow
# =====================================================================

func _on_sdk_changed() -> void:
	catalog_changed.emit()


func _on_payments_ready(ok: bool) -> void:
	_payments_known = true
	if ok:
		YandexSdk.load_catalog()
		_sync_if_ready()
	catalog_changed.emit()


func _on_state_loaded() -> void:
	_state_loaded = true
	_sync_if_ready()


## Unprocessed / owned purchases are applied only once the save is loaded.
func _sync_if_ready() -> void:
	if _synced or not _state_loaded or not YandexSdk.payments_available:
		return
	_synced = true
	YandexSdk.load_purchases()


func _on_catalog_loaded(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		push_warning("IAP: catalog failed: %s" % str(result.get("error", "")))
		return
	_catalog.clear()
	var icon_url: String = ""
	for item: Variant in result.get("products", []):
		if item is Dictionary:
			_catalog[str(item.get("id", ""))] = item
			if icon_url.is_empty():
				icon_url = str(item.get("currencyImage", ""))
	catalog_changed.emit()
	if not icon_url.is_empty() and currency_icon == null:
		_load_icon(icon_url)


func _on_purchase_finished(result: Dictionary) -> void:
	var sku: String = _purchasing
	_purchasing = ""
	YandexSdk.set_gameplay_blocked("purchase", false)
	if not bool(result.get("ok", false)):
		Signals.purchase_failed.emit(sku, "canceled")
		catalog_changed.emit()
		return
	_grant(str(result.get("id", sku)), str(result.get("token", "")))


func _on_purchases_loaded(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		push_warning("IAP: getPurchases failed: %s" % str(result.get("error", "")))
		return
	var restored: Array = []
	for item: Variant in result.get("purchases", []):
		if not item is Dictionary:
			continue
		var sku: String = str(item.get("id", ""))
		var token: String = str(item.get("token", ""))
		var product: Dictionary = Economy.iap_product(sku)
		if product.is_empty():
			push_warning("IAP: purchase of unknown product '%s'" % sku)
			continue
		if bool(product.get("consumable", true)):
			# Paid but never consumed: grant (unless this token was already granted) and consume.
			_grant(sku, token, true)
		elif not GameState.is_sku_owned(sku):
			GameState.apply_purchase(sku, token)
			SaveManager.save_game(true)
			restored.append(sku)
	if _manual_restore or not restored.is_empty():
		Signals.restore_completed.emit(restored)
	_manual_restore = false
	catalog_changed.emit()


func _on_consume_finished(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		# The token stays unconsumed and is retried at the next launch; no double grant.
		push_warning("IAP: consume failed: %s" % str(result.get("error", "")))


## Applies the purchase and saves before consuming it, so a crash never loses a paid item.
func _grant(sku: String, token: String, recovered: bool = false) -> void:
	var product: Dictionary = Economy.iap_product(sku)
	var consumable: bool = bool(product.get("consumable", true))
	var fresh: bool = token.is_empty() or not GameState.has_purchase_token(token)
	if fresh:
		GameState.apply_purchase(sku, token)
		SaveManager.save_game(true)
		if recovered:
			Signals.toast_requested.emit("Покупка восстановлена: %s" % title(sku))
		else:
			Signals.purchase_completed.emit(sku)
	if consumable and not token.is_empty():
		YandexSdk.consume(token)
	catalog_changed.emit()


# =====================================================================
# Currency icon
# =====================================================================

func _load_icon(url: String) -> void:
	if url.begins_with("//"):
		url = "https:" + url
	if _icon_request == null:
		_icon_request = HTTPRequest.new()
		add_child(_icon_request)
		_icon_request.request_completed.connect(_on_icon_loaded)
	if _icon_request.request(url) != OK:
		push_warning("IAP: cannot request currency icon %s" % url)


func _on_icon_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		push_warning("IAP: currency icon download failed (%d / %d)" % [result, code])
		return
	var image: Image = Image.new()
	var head: String = body.slice(0, 64).get_string_from_utf8()
	var err: int = ERR_FILE_UNRECOGNIZED
	if head.contains("<svg") or head.contains("<?xml"):
		err = image.load_svg_from_buffer(body)
	elif body[0] == 0x89:
		err = image.load_png_from_buffer(body)
	elif body[0] == 0xFF:
		err = image.load_jpg_from_buffer(body)
	else:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		push_warning("IAP: currency icon format not supported")
		return
	currency_icon = ImageTexture.create_from_image(image)
	catalog_changed.emit()
