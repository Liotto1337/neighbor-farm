extends Node
## In-app purchases facade (Yandex Games payments stub).
## Integration point: replace _platform_purchase / _platform_restore with calls to
## ysdk.getPayments() via JavaScriptBridge (Web) or the Android billing plugin and
## route the async result into _on_platform_result.


func purchase(sku: String) -> void:
	var product: Dictionary = Economy.iap_product(sku)
	if product.is_empty():
		push_error("IAP: unknown sku '%s'" % sku)
		Signals.purchase_failed.emit(sku, "unknown_sku")
		return
	if not bool(product.get("consumable", true)) and is_owned(sku):
		Signals.purchase_failed.emit(sku, "already_owned")
		return
	Signals.purchase_started.emit(sku)
	_platform_purchase.call_deferred(sku)


func restore() -> void:
	_platform_restore.call_deferred()


func is_owned(sku: String) -> bool:
	return GameState.is_sku_owned(sku)


func _platform_purchase(sku: String) -> void:
	# Stub: every purchase succeeds immediately.
	_on_platform_result(sku, true, "")


func _platform_restore() -> void:
	# Stub: the platform would return owned non-consumables; we echo local ownership.
	Signals.restore_completed.emit(GameState.owned_skus.duplicate())


func _on_platform_result(sku: String, ok: bool, reason: String) -> void:
	if not ok:
		Signals.purchase_failed.emit(sku, reason)
		return
	GameState.apply_purchase(sku)
	Signals.purchase_completed.emit(sku)
	Signals.save_requested.emit()
