extends Node
## Yandex Games SDK bridge (Web export only). Loads /sdk.js at runtime (no custom HTML shell
## needed), initialises YaGames and exposes ads, payments and game events to GDScript.
##
## Cloud saves: the Player object's getData / setData (200 KB, at most 100 calls per 5 minutes);
## SaveManager decides what to store and when.
##
## All JS work goes through a small glue object (BRIDGE_JS, window.NFYandex) that talks to the
## SDK and answers through one persistent callback per channel with a JSON string, so GDScript
## only ever handles plain Dictionaries. AdManager and IAP are the only callers.
## Docs: https://yandex.ru/dev/games/doc/ru/sdk/sdk-about

enum State { OFF, LOADING, READY, FAILED }

signal ready_changed(ok: bool)
## Platform pause (ad, purchase window, hidden tab): stop sound and gameplay while true.
signal platform_paused(paused: bool)
## {event: "open" | "close" (shown: bool) | "rewarded" | "error" (error: String)}
signal fullscreen_event(event: Dictionary)
signal rewarded_event(event: Dictionary)
signal payments_ready(ok: bool)
## {ok, products: [{id, title, description, price, priceValue, currency, currencyImage}], error}
signal catalog_loaded(result: Dictionary)
## {ok, id, token, error}
signal purchase_finished(result: Dictionary)
## {ok, purchases: [{id, token}], error}
signal purchases_loaded(result: Dictionary)
## {ok, token, error}
signal consume_finished(result: Dictionary)
## Player data read at start-up or after signing in: {ok, authorized, data: {...}, error}.
## Also emitted with ok = false when the SDK is unavailable, so SaveManager never waits forever.
signal cloud_loaded(result: Dictionary)
## {ok, authorized, data, error} after the Yandex sign-in dialog.
signal auth_finished(result: Dictionary)

const BRIDGE_JS: String = """
window.NFYandex = (function () {
	'use strict';
	var ysdk = null;
	var payments = null;
	var player = null;
	function loadPlayer(cb) {
		ysdk.getPlayer().then(function (p) {
			player = p;
			return p.getData();
		}).then(function (data) {
			send(cb, { ok: true, authorized: player.isAuthorized(), data: data || {} });
		}).catch(function (e) {
			send(cb, { ok: false, authorized: !!(player && player.isAuthorized()), error: errorText(e) });
		});
	}
	function send(cb, data) { cb(JSON.stringify(data)); }
	function errorText(e) {
		if (e && (e.message || e.code)) { return String(e.message || e.code); }
		return String(e);
	}
	return {
		init: function (cb) {
			function start() {
				YaGames.init().then(function (sdk) {
					ysdk = sdk;
					var i18n = sdk.environment && sdk.environment.i18n;
					send(cb, { ok: true, lang: (i18n && i18n.lang) || '' });
				}).catch(function (e) { send(cb, { ok: false, error: errorText(e) }); });
			}
			if (window.YaGames) { start(); return; }
			var script = document.createElement('script');
			script.src = '/sdk.js';
			script.async = true;
			script.onload = start;
			script.onerror = function () { send(cb, { ok: false, error: 'sdk.js not loaded' }); };
			document.head.appendChild(script);
		},
		listenPause: function (cb) {
			ysdk.on('game_api_pause', function () { send(cb, { paused: true }); });
			ysdk.on('game_api_resume', function () { send(cb, { paused: false }); });
		},
		loadingReady: function () {
			var api = ysdk.features && ysdk.features.LoadingAPI;
			if (api) { api.ready(); }
		},
		gameplay: function (running) {
			var api = ysdk.features && ysdk.features.GameplayAPI;
			if (!api) { return; }
			if (running) { api.start(); } else { api.stop(); }
		},
		showFullscreen: function (cb) {
			ysdk.adv.showFullscreenAdv({ callbacks: {
				onOpen: function () { send(cb, { event: 'open' }); },
				onClose: function (shown) { send(cb, { event: 'close', shown: !!shown }); },
				onError: function (e) { send(cb, { event: 'error', error: errorText(e) }); }
			} });
		},
		showRewarded: function (cb) {
			ysdk.adv.showRewardedVideo({ callbacks: {
				onOpen: function () { send(cb, { event: 'open' }); },
				onRewarded: function () { send(cb, { event: 'rewarded' }); },
				onClose: function () { send(cb, { event: 'close' }); },
				onError: function (e) { send(cb, { event: 'error', error: errorText(e) }); }
			} });
		},
		initPayments: function (cb) {
			ysdk.getPayments({ signed: false }).then(function (p) {
				payments = p;
				send(cb, { ok: true });
			}).catch(function (e) { send(cb, { ok: false, error: errorText(e) }); });
		},
		getCatalog: function (cb) {
			payments.getCatalog().then(function (list) {
				send(cb, { ok: true, products: list.map(function (p) {
					var image = '';
					try { image = typeof p.getPriceCurrencyImage === 'function' ? p.getPriceCurrencyImage('medium') : ''; } catch (e) {}
					return { id: p.id, title: p.title, description: p.description, price: p.price,
						priceValue: p.priceValue, currency: p.priceCurrencyCode, currencyImage: image || '' };
				}) });
			}).catch(function (e) { send(cb, { ok: false, error: errorText(e) }); });
		},
		purchase: function (id, cb) {
			payments.purchase({ id: id }).then(function (p) {
				send(cb, { ok: true, id: p.productID, token: p.purchaseToken });
			}).catch(function (e) { send(cb, { ok: false, id: id, error: errorText(e) }); });
		},
		getPurchases: function (cb) {
			payments.getPurchases().then(function (list) {
				send(cb, { ok: true, purchases: list.map(function (p) {
					return { id: p.productID, token: p.purchaseToken };
				}) });
			}).catch(function (e) { send(cb, { ok: false, error: errorText(e) }); });
		},
		initPlayer: function (cb) { loadPlayer(cb); },
		setData: function (json, flush, cb) {
			if (!player) { send(cb, { ok: false, error: 'no player' }); return; }
			player.setData(JSON.parse(json), !!flush).then(function () {
				send(cb, { ok: true });
			}).catch(function (e) { send(cb, { ok: false, error: errorText(e) }); });
		},
		openAuth: function (cb) {
			ysdk.auth.openAuthDialog().then(function () {
				loadPlayer(cb);
			}).catch(function (e) { send(cb, { ok: false, authorized: false, error: errorText(e) }); });
		},
		reload: function () { window.location.reload(); },
		consume: function (token, cb) {
			payments.consumePurchase(token).then(function () {
				send(cb, { ok: true, token: token });
			}).catch(function (e) { send(cb, { ok: false, token: token, error: errorText(e) }); });
		}
	};
})();
"""

var state: int = State.OFF
var payments_available: bool = false
## cloud_loaded already fired (or the SDK failed) and its payload.
var cloud_checked: bool = false
var cloud_result: Dictionary = {}
## Signed in to Yandex (cloud progress follows the player across devices).
var player_authorized: bool = false
## Player object is up and setData() can be used.
var cloud_available: bool = false
## Player language from the SDK environment ("ru", "en", ...); empty until ready.
var lang: String = ""

var _bridge: JavaScriptObject = null
## JS callbacks must stay referenced or the browser side loses them.
var _callbacks: Dictionary = {}
## Current GDScript handler per channel.
var _handlers: Dictionary = {}
var _state_loaded: bool = false
var _loading_reported: bool = false
## Reasons gameplay is currently stopped (GameplayAPI.stop while any is set).
var _gameplay_blocks: Dictionary = {"loading": true}
var _gameplay_running: bool = false


func _ready() -> void:
	Signals.state_loaded.connect(_on_state_loaded)
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(BRIDGE_JS, true)
	_bridge = JavaScriptBridge.get_interface("NFYandex")
	if _bridge == null:
		_fail("bridge not created")
		return
	state = State.LOADING
	_bridge.init(_js("init", _on_init))


func is_ready() -> bool:
	return state == State.READY


## True while the SDK may still come up (Web build, not failed yet).
func is_pending() -> bool:
	return state == State.LOADING


# =====================================================================
# Ads / payments (callers check is_ready() / payments_available first)
# =====================================================================

func show_fullscreen() -> void:
	_bridge.showFullscreen(_js("fullscreen", fullscreen_event.emit))


func show_rewarded() -> void:
	_bridge.showRewarded(_js("rewarded", rewarded_event.emit))


func load_catalog() -> void:
	_bridge.getCatalog(_js("catalog", catalog_loaded.emit))


func purchase(product_id: String) -> void:
	_bridge.purchase(product_id, _js("purchase", purchase_finished.emit))


func load_purchases() -> void:
	_bridge.getPurchases(_js("purchases", purchases_loaded.emit))


func consume(token: String) -> void:
	_bridge.consume(token, _js("consume", consume_finished.emit))


## Stores `data` (a JSON object string) as the player's cloud data. flush = send right away.
func save_cloud(data_json: String, flush: bool) -> void:
	if cloud_available:
		_bridge.setData(data_json, flush, _js("set_data", _on_set_data))


## Yandex sign-in dialog; the result (with fresh cloud data) arrives as auth_finished.
func open_auth() -> void:
	if is_ready():
		_bridge.openAuth(_js("auth", _on_auth))


func reload_page() -> void:
	if is_ready():
		_bridge.reload()


## Stops (blocked) or resumes GameplayAPI for a reason ("ad", "purchase", "focus", ...).
func set_gameplay_blocked(reason: String, blocked: bool) -> void:
	if blocked:
		_gameplay_blocks[reason] = true
	else:
		_gameplay_blocks.erase(reason)
	_sync_gameplay()


# =====================================================================
# Internals
# =====================================================================

func _on_init(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_fail(str(result.get("error", "")))
		return
	state = State.READY
	lang = str(result.get("lang", ""))
	_bridge.listenPause(_js("pause", _on_pause))
	_bridge.initPayments(_js("payments", _on_payments))
	_bridge.initPlayer(_js("player", _on_player))
	ready_changed.emit(true)
	_report_loaded()


func _on_payments(result: Dictionary) -> void:
	payments_available = bool(result.get("ok", false))
	if not payments_available:
		push_warning("YandexSdk: payments unavailable: %s" % str(result.get("error", "")))
	payments_ready.emit(payments_available)


func _on_player(result: Dictionary) -> void:
	cloud_checked = true
	cloud_result = result
	cloud_available = bool(result.get("ok", false))
	player_authorized = bool(result.get("authorized", false))
	if not cloud_available:
		push_warning("YandexSdk: cloud data unavailable: %s" % str(result.get("error", "")))
	cloud_loaded.emit(result)


func _on_auth(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		cloud_available = true
		player_authorized = bool(result.get("authorized", false))
	auth_finished.emit(result)


func _on_set_data(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		push_warning("YandexSdk: cloud save failed: %s" % str(result.get("error", "")))


func _on_pause(result: Dictionary) -> void:
	var paused: bool = bool(result.get("paused", false))
	set_gameplay_blocked("platform", paused)
	platform_paused.emit(paused)


func _on_state_loaded() -> void:
	_state_loaded = true
	_report_loaded()


## LoadingAPI.ready() once both the SDK and the save are up, then gameplay starts.
func _report_loaded() -> void:
	if _loading_reported or not _state_loaded or state != State.READY:
		return
	_loading_reported = true
	_bridge.loadingReady()
	set_gameplay_blocked("loading", false)


func _sync_gameplay() -> void:
	var running: bool = _gameplay_blocks.is_empty()
	if state != State.READY or running == _gameplay_running:
		return
	_gameplay_running = running
	_bridge.gameplay(running)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_gameplay_blocked("focus", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_gameplay_blocked("focus", false)


func _fail(reason: String) -> void:
	state = State.FAILED
	push_warning("YandexSdk: SDK unavailable (%s); ads, purchases and cloud saves are disabled" % reason)
	ready_changed.emit(false)
	cloud_checked = true
	cloud_result = {"ok": false, "error": reason}
	cloud_loaded.emit(cloud_result)


## Persistent JS callback for a channel; `handler` gets the parsed JSON payload.
func _js(channel: String, handler: Callable) -> JavaScriptObject:
	if not _callbacks.has(channel):
		_callbacks[channel] = JavaScriptBridge.create_callback(_on_js.bind(channel))
	_handlers[channel] = handler
	return _callbacks[channel]


func _on_js(args: Array, channel: String) -> void:
	var parsed: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	var handler: Variant = _handlers.get(channel)
	if handler is Callable and (handler as Callable).is_valid():
		(handler as Callable).call(parsed if parsed is Dictionary else {})
