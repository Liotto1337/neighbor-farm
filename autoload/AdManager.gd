extends Node
## Ads facade (Yandex Games ads stub).
## Integration point: replace _platform_* with ysdk.adv.showRewardedVideo /
## showFullscreenAdv via JavaScriptBridge and call the _finish_* methods from callbacks.

var _busy: bool = false


func _ready() -> void:
	Signals.level_up.connect(_on_level_up)


func show_rewarded(callback: Callable) -> void:
	if _busy:
		Signals.ad_failed.emit("rewarded", "busy")
		return
	_busy = true
	Signals.ad_started.emit("rewarded")
	_platform_rewarded.call_deferred(callback)


func show_interstitial() -> void:
	if _busy or GameState.no_ads:
		return
	_busy = true
	Signals.ad_started.emit("interstitial")
	_platform_interstitial.call_deferred()


func _platform_rewarded(callback: Callable) -> void:
	# Stub: the user always watches to the end.
	_finish_rewarded(callback, true)


func _platform_interstitial() -> void:
	_finish_interstitial()


func _finish_rewarded(callback: Callable, watched: bool) -> void:
	_busy = false
	if not watched:
		Signals.ad_failed.emit("rewarded", "closed_early")
		return
	if callback.is_valid():
		callback.call()
	Signals.ad_rewarded_completed.emit()
	Signals.save_requested.emit()


func _finish_interstitial() -> void:
	_busy = false
	Signals.ad_interstitial_closed.emit()


func _on_level_up(_new_level: int) -> void:
	show_interstitial()
