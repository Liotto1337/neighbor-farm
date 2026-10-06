extends Node
## Ads facade. On Yandex Games it shows real ads through YandexSdk; in debug builds without
## the SDK (editor, desktop) a stub that always succeeds stands in. Release builds without the
## SDK show no ads.
## Emits Signals.ad_* so Audio mutes the game while an ad is on screen (requirement 4.7) and
## stops GameplayAPI for the duration.

const KIND_REWARDED: String = "rewarded"
const KIND_INTERSTITIAL: String = "interstitial"

var _busy: bool = false
var _rewarded_callback: Callable = Callable()
var _rewarded_earned: bool = false


func _ready() -> void:
	Signals.level_up.connect(_on_level_up)
	YandexSdk.fullscreen_event.connect(_on_fullscreen_event)
	YandexSdk.rewarded_event.connect(_on_rewarded_event)


## Rewarded video; `callback` runs only when the platform confirms the reward.
func show_rewarded(callback: Callable) -> void:
	if _busy:
		Signals.ad_failed.emit(KIND_REWARDED, "busy")
		return
	match _provider():
		"yandex":
			_begin(KIND_REWARDED)
			_rewarded_callback = callback
			_rewarded_earned = false
			YandexSdk.show_rewarded()
		"stub":
			_begin(KIND_REWARDED)
			_stub_rewarded.call_deferred(callback)
		_:
			Signals.ad_failed.emit(KIND_REWARDED, "unavailable")


## Fullscreen ad at a logical pause (level up). The platform throttles how often it shows.
func show_interstitial() -> void:
	if _busy or GameState.no_ads:
		return
	match _provider():
		"yandex":
			_begin(KIND_INTERSTITIAL)
			YandexSdk.show_fullscreen()
		"stub":
			_begin(KIND_INTERSTITIAL)
			_finish_interstitial.call_deferred()


func _provider() -> String:
	if YandexSdk.is_ready():
		return "yandex"
	if OS.is_debug_build() and not YandexSdk.is_pending():
		return "stub"
	return "none"


func _begin(kind: String) -> void:
	_busy = true
	YandexSdk.set_gameplay_blocked("ad", true)
	if kind == KIND_REWARDED:
		Signals.ad_started.emit(kind)


# =====================================================================
# Yandex callbacks
# =====================================================================

func _on_fullscreen_event(event: Dictionary) -> void:
	match str(event.get("event", "")):
		"open":
			# Interstitials announce themselves only when actually shown (often throttled).
			Signals.ad_started.emit(KIND_INTERSTITIAL)
		"close":
			_finish_interstitial()
		"error":
			push_warning("AdManager: fullscreen ad error: %s" % str(event.get("error", "")))
			_finish_interstitial()


func _on_rewarded_event(event: Dictionary) -> void:
	match str(event.get("event", "")):
		"rewarded":
			_rewarded_earned = true
		"close":
			_finish_rewarded(_rewarded_callback, _rewarded_earned)
		"error":
			push_warning("AdManager: rewarded ad error: %s" % str(event.get("error", "")))
			_finish_rewarded(_rewarded_callback, false, "error")


# =====================================================================
# Completion
# =====================================================================

func _stub_rewarded(callback: Callable) -> void:
	_finish_rewarded(callback, true)


func _finish_rewarded(callback: Callable, watched: bool, reason: String = "closed_early") -> void:
	if not _busy:
		return
	_busy = false
	_rewarded_callback = Callable()
	YandexSdk.set_gameplay_blocked("ad", false)
	if not watched:
		Signals.ad_failed.emit(KIND_REWARDED, reason)
		return
	if callback.is_valid():
		callback.call()
	Signals.ad_rewarded_completed.emit()
	Signals.save_requested.emit()


func _finish_interstitial() -> void:
	if not _busy:
		return
	_busy = false
	YandexSdk.set_gameplay_blocked("ad", false)
	Signals.ad_interstitial_closed.emit()


func _on_level_up(_new_level: int) -> void:
	show_interstitial()
