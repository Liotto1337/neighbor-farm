extends Node
## Single mutable state owner. Mutate only through methods; each method emits its
## change signals once, after the whole mutation batch.

enum TileState { EMPTY, PLOWED, PLANTED, READY, WITHERED }
enum AnimalStatus { HUNGRY, PRODUCING, READY }

const SECONDS_PER_HOUR: float = 3600.0

var world_seed: int = 0
var coins: int = 0
var seeds: int = 0
var feed: int = 0
var level: int = 1
var xp: int = 0
var inventory: Dictionary = {}
var tiles: Array = []
var buildings: Dictionary = {}
var animals: Array = []
var neighbors: Array = []
var contract: Dictionary = {}
var owned_skus: Array = []
var no_ads: bool = false
var selected_crop: String = ""
var boost_until: float = 0.0
var time_offset: float = 0.0
var last_save: float = 0.0
var last_decay_at: float = 0.0
var last_stall_at: float = 0.0


# =====================================================================
# Lifecycle
# =====================================================================

func new_game(seed_value: int) -> void:
	time_offset = 0.0
	world_seed = seed_value
	var now: float = TimeService.now()
	var start: Dictionary = Economy.cfg_dict("start")
	coins = int(start.get("coins", 0))
	seeds = int(start.get("seeds", 0))
	feed = int(start.get("feed", 0))
	level = int(start.get("level", 1))
	xp = int(start.get("xp", 0))
	selected_crop = str(start.get("crop", ""))
	inventory = {}
	tiles = _make_tiles([])
	buildings = _make_buildings({})
	animals = []
	owned_skus = []
	no_ads = false
	boost_until = 0.0
	contract = {}
	neighbors = NeighborAI.make_states(world_seed, now)
	last_save = now
	last_decay_at = now
	last_stall_at = now
	_update_contract(now)


func to_dict() -> Dictionary:
	return {
		"world_seed": world_seed, "coins": coins, "seeds": seeds, "feed": feed,
		"level": level, "xp": xp, "inventory": inventory.duplicate(),
		"tiles": tiles.duplicate(true), "buildings": buildings.duplicate(),
		"animals": animals.duplicate(true), "neighbors": neighbors.duplicate(true),
		"contract": contract.duplicate(), "owned_skus": owned_skus.duplicate(),
		"no_ads": no_ads, "selected_crop": selected_crop, "boost_until": boost_until,
		"time_offset": time_offset, "last_save": last_save,
		"last_decay_at": last_decay_at, "last_stall_at": last_stall_at,
	}


func from_dict(d: Dictionary) -> void:
	_load_scalars(d)
	inventory = _load_inventory(d.get("inventory", {}))
	tiles = _make_tiles(d.get("tiles", []))
	buildings = _make_buildings(d.get("buildings", {}))
	animals = _load_animals(d.get("animals", []))
	neighbors = _load_neighbors(d.get("neighbors", []))
	contract = _load_contract(d.get("contract", {}))
	owned_skus = []
	var raw_skus: Variant = d.get("owned_skus", [])
	if raw_skus is Array:
		for sku: Variant in raw_skus:
			owned_skus.append(str(sku))


func _load_scalars(d: Dictionary) -> void:
	time_offset = float(d.get("time_offset", 0.0))
	world_seed = int(d.get("world_seed", 0))
	coins = int(d.get("coins", 0))
	seeds = int(d.get("seeds", 0))
	feed = int(d.get("feed", 0))
	level = clampi(int(d.get("level", 1)), 1, Economy.max_level())
	xp = int(d.get("xp", 0))
	no_ads = bool(d.get("no_ads", false))
	selected_crop = str(d.get("selected_crop", ""))
	boost_until = float(d.get("boost_until", 0.0))
	var now: float = TimeService.now()
	last_save = float(d.get("last_save", now))
	last_decay_at = float(d.get("last_decay_at", last_save))
	last_stall_at = float(d.get("last_stall_at", last_save))


func _load_inventory(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			var qty: int = int(raw[key])
			if qty > 0:
				out[str(key)] = qty
	return out


func _make_tiles(raw: Variant) -> Array:
	var side: int = Economy.cfg_i("grid_size")
	var src: Array = raw if raw is Array else []
	var out: Array = []
	for i: int in side * side:
		if i < src.size() and src[i] is Dictionary:
			out.append(_normalize_tile(src[i]))
		else:
			out.append(_empty_tile(TileState.EMPTY))
	return out


func _empty_tile(state: int) -> Dictionary:
	return {"s": state, "c": "", "p": 0.0, "g": 0.0}


func _normalize_tile(t: Dictionary) -> Dictionary:
	return {
		"s": int(t.get("s", TileState.EMPTY)),
		"c": str(t.get("c", "")),
		"p": float(t.get("p", 0.0)),
		"g": float(t.get("g", 0.0)),
	}


func _make_buildings(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var out: Dictionary = {}
	for def: Variant in Economy.buildings_list():
		var id: String = str(def["id"])
		out[id] = int(src.get(id, 0))
	return out


func _load_animals(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for a: Variant in raw:
			if a is Dictionary and not Economy.animal(str(a.get("t", ""))).is_empty():
				out.append({"t": str(a["t"]), "f": float(a.get("f", 0.0))})
	return out


func _load_neighbors(raw: Variant) -> Array:
	var fresh: Array = NeighborAI.make_states(world_seed, TimeService.now())
	var src: Array = raw if raw is Array else []
	for i: int in fresh.size():
		if i < src.size() and src[i] is Dictionary:
			fresh[i] = NeighborAI.normalize_state(src[i], fresh[i])
	return fresh


func _load_contract(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var c: Dictionary = raw
	return {
		"id": str(c.get("id", "")), "week": int(c.get("week", 0)),
		"player": int(c.get("player", 0)), "npc": float(c.get("npc", 0.0)),
		"claimed": bool(c.get("claimed", false)), "last": float(c.get("last", 0.0)),
	}


func emit_all() -> void:
	_emit_currencies()
	_emit_xp()
	Signals.tiles_changed.emit()
	Signals.inventory_changed.emit()
	Signals.animals_changed.emit()
	Signals.buildings_changed.emit()
	Signals.neighbors_changed.emit()
	Signals.contract_changed.emit()
	Signals.boost_changed.emit(boost_until)
	Signals.selected_crop_changed.emit(selected_crop)


func mark_saved(now: float) -> void:
	last_save = now


func add_time_offset(seconds: float) -> void:
	time_offset += seconds


# =====================================================================
# Tick (online + offline progression)
# =====================================================================

func tick(now: float) -> Dictionary:
	if _update_tiles(now):
		Signals.tiles_changed.emit()
	var stall_coins: int = _run_market_stall(now)
	if stall_coins > 0:
		_emit_currencies()
		Signals.inventory_changed.emit()
	var neighbors_dirty: bool = _update_all_neighbors(now)
	var decayed: int = _decay_trust(now)
	if neighbors_dirty or decayed > 0:
		Signals.neighbors_changed.emit()
	if _update_contract(now):
		Signals.contract_changed.emit()
	return {"stall_coins": stall_coins, "trust_decay": decayed}


func snapshot_counts(at_time: float) -> Dictionary:
	return {
		"ready": count_tiles(TileState.READY),
		"withered": count_tiles(TileState.WITHERED),
		"animals_ready": count_ready_animals(at_time),
		"contract": contract_progress(),
	}


# =====================================================================
# Resources, storage, XP
# =====================================================================

func storage_cap() -> int:
	return Economy.storage_cap(building_level("silo"))


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func item_space(item_id: String) -> int:
	return maxi(0, storage_cap() - item_count(item_id))


func _add_item(item_id: String, amount: int) -> int:
	var added: int = mini(amount, item_space(item_id))
	if added > 0:
		inventory[item_id] = item_count(item_id) + added
	return added


func _remove_item(item_id: String, amount: int) -> void:
	var left: int = item_count(item_id) - amount
	if left > 0:
		inventory[item_id] = left
	else:
		inventory.erase(item_id)


func _add_seeds(amount: int) -> int:
	var added: int = clampi(amount, 0, maxi(0, storage_cap() - seeds))
	seeds += added
	return added


func _add_feed(amount: int) -> int:
	var added: int = clampi(amount, 0, maxi(0, storage_cap() - feed))
	feed += added
	return added


func _add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var gained: int = 0
	while level < Economy.max_level() and xp >= Economy.xp_for_level(level + 1):
		level += 1
		gained += 1
	if gained > 0:
		coins += Economy.level_up_coins() * gained
		_emit_currencies()
		_toast("Новый уровень %d! +%d монет" % [level, Economy.level_up_coins() * gained])
		Signals.level_up.emit(level)
	_emit_xp()


func _emit_currencies() -> void:
	Signals.currencies_changed.emit(coins, seeds, feed)


func _emit_xp() -> void:
	var floor_xp: int = Economy.xp_for_level(level)
	var needed: int = 0
	if level < Economy.max_level():
		needed = Economy.xp_for_level(level + 1) - floor_xp
	Signals.xp_changed.emit(level, xp - floor_xp, needed)


func _toast(text: String) -> void:
	Signals.toast_requested.emit(text)


func debug_grant() -> void:
	var grant: Dictionary = Economy.cfg_dict("debug")
	coins += int(grant.get("grant_coins", 0))
	_emit_currencies()
	_add_xp(int(grant.get("grant_xp", 0)))


# =====================================================================
# Farm tiles
# =====================================================================

func tile(index: int) -> Dictionary:
	if index < 0 or index >= tiles.size():
		return {}
	return tiles[index]


func tile_state(index: int) -> int:
	return int(tile(index).get("s", TileState.EMPTY))


func tile_progress(index: int, now: float) -> float:
	var t: Dictionary = tile(index)
	var state: int = int(t.get("s", TileState.EMPTY))
	if state == TileState.READY or state == TileState.WITHERED:
		return 1.0
	if state != TileState.PLANTED or float(t["g"]) <= 0.0:
		return 0.0
	return clampf((now - float(t["p"])) / float(t["g"]), 0.0, 1.0)


func tile_seconds_left(index: int, now: float) -> float:
	var t: Dictionary = tile(index)
	if t.is_empty():
		return 0.0
	return maxf(0.0, float(t["p"]) + float(t["g"]) - now)


func count_tiles(state: int) -> int:
	var count: int = 0
	for t: Variant in tiles:
		if int(t["s"]) == state:
			count += 1
	return count


func select_crop(crop_id: String) -> void:
	if Economy.crop(crop_id).is_empty():
		push_error("GameState: unknown crop '%s'" % crop_id)
		return
	selected_crop = crop_id
	Signals.selected_crop_changed.emit(crop_id)


func plow(index: int) -> bool:
	if tile_state(index) != TileState.EMPTY:
		return false
	tiles[index] = _empty_tile(TileState.PLOWED)
	Signals.tiles_changed.emit()
	return true


func clear_tile(index: int) -> bool:
	if tile_state(index) != TileState.WITHERED:
		return false
	tiles[index] = _empty_tile(TileState.EMPTY)
	Signals.tiles_changed.emit()
	return true


func plant(index: int, crop_id: String) -> bool:
	if tile_state(index) != TileState.PLOWED or not _can_plant(crop_id):
		return false
	_plant_tile(index, crop_id, TimeService.now())
	Signals.tiles_changed.emit()
	_emit_currencies()
	return true


func plant_all(crop_id: String) -> int:
	var now: float = TimeService.now()
	var count: int = 0
	for i: int in tiles.size():
		if tile_state(i) != TileState.PLOWED:
			continue
		if not _can_plant(crop_id):
			break
		_plant_tile(i, crop_id, now)
		count += 1
	if count > 0:
		Signals.tiles_changed.emit()
		_emit_currencies()
	elif count_tiles(TileState.PLOWED) == 0:
		_toast("Нет вспаханных грядок")
	return count


func _can_plant(crop_id: String) -> bool:
	var def: Dictionary = Economy.crop(crop_id)
	if def.is_empty():
		_toast("Выберите культуру")
		return false
	if int(def["unlock_level"]) > level:
		_toast("Откроется на уровне %d" % int(def["unlock_level"]))
		return false
	if seeds < int(def["seed_cost"]):
		_toast("Не хватает семян")
		return false
	return true


func _plant_tile(index: int, crop_id: String, now: float) -> void:
	seeds -= int(Economy.crop(crop_id)["seed_cost"])
	var grow: float = Economy.crop_grow_seconds(crop_id)
	if is_boost_active(now):
		grow *= Economy.cfg_f("boost_growth_multiplier")
	tiles[index] = {"s": TileState.PLANTED, "c": crop_id, "p": now, "g": grow}


func harvest(index: int) -> bool:
	if tile_state(index) != TileState.READY or not _harvest_tile(index):
		return false
	Signals.tiles_changed.emit()
	Signals.inventory_changed.emit()
	return true


func harvest_all() -> int:
	var count: int = 0
	for i: int in tiles.size():
		if tile_state(i) == TileState.READY and _harvest_tile(i):
			count += 1
	if count > 0:
		Signals.tiles_changed.emit()
		Signals.inventory_changed.emit()
	elif count_tiles(TileState.READY) == 0:
		_toast("Пока нечего собирать")
	return count


func _harvest_tile(index: int) -> bool:
	var crop_id: String = str(tiles[index]["c"])
	var def: Dictionary = Economy.crop(crop_id)
	var amount: int = int(def.get("yield", 0))
	if item_space(crop_id) < amount:
		_toast("Склад полон: %s" % Economy.item_name(crop_id))
		return false
	_add_item(crop_id, amount)
	tiles[index] = _empty_tile(TileState.PLOWED)
	_add_xp(int(def.get("xp", 0)))
	return true


func _update_tiles(now: float) -> bool:
	var changed: bool = false
	for t: Variant in tiles:
		var next_state: int = _tile_state_at(t, now)
		if next_state != int(t["s"]):
			t["s"] = next_state
			changed = true
	return changed


func _tile_state_at(t: Dictionary, now: float) -> int:
	var state: int = int(t["s"])
	if state != TileState.PLANTED and state != TileState.READY:
		return state
	var ready_at: float = float(t["p"]) + float(t["g"])
	if now < ready_at:
		return TileState.PLANTED
	var wither_at: float = ready_at + float(t["g"]) * Economy.cfg_f("wither_multiplier")
	return TileState.WITHERED if now >= wither_at else TileState.READY


# =====================================================================
# Animals
# =====================================================================

func max_animals() -> int:
	return building_level("barn") * int(Economy.building_param("barn", "animals_per_level"))


func animal_status(index: int, now: float) -> int:
	if index < 0 or index >= animals.size():
		return AnimalStatus.HUNGRY
	var fed_at: float = float(animals[index]["f"])
	if fed_at <= 0.0:
		return AnimalStatus.HUNGRY
	if now >= fed_at + Economy.animal_produce_seconds(str(animals[index]["t"])):
		return AnimalStatus.READY
	return AnimalStatus.PRODUCING


func animal_seconds_left(index: int, now: float) -> float:
	var a: Dictionary = animals[index]
	return maxf(0.0, float(a["f"]) + Economy.animal_produce_seconds(str(a["t"])) - now)


func count_ready_animals(at_time: float) -> int:
	var count: int = 0
	for i: int in animals.size():
		if animal_status(i, at_time) == AnimalStatus.READY:
			count += 1
	return count


func buy_animal(animal_id: String) -> bool:
	var def: Dictionary = Economy.animal(animal_id)
	if def.is_empty():
		push_error("GameState: unknown animal '%s'" % animal_id)
		return false
	if building_level("barn") <= 0:
		_toast("Сначала постройте амбар")
		return false
	if int(def["unlock_level"]) > level:
		_toast("Откроется на уровне %d" % int(def["unlock_level"]))
		return false
	if animals.size() >= max_animals():
		_toast("Амбар заполнен — улучшите его")
		return false
	if coins < int(def["cost"]):
		_toast("Не хватает монет")
		return false
	coins -= int(def["cost"])
	animals.append({"t": animal_id, "f": 0.0})
	_emit_currencies()
	Signals.animals_changed.emit()
	return true


func feed_animal(index: int) -> bool:
	var now: float = TimeService.now()
	if index < 0 or index >= animals.size() or animal_status(index, now) != AnimalStatus.HUNGRY:
		return false
	var cost: int = int(Economy.animal(str(animals[index]["t"]))["feed_cost"])
	if feed < cost:
		_toast("Не хватает корма — сделайте его из кукурузы")
		return false
	feed -= cost
	animals[index]["f"] = now
	_emit_currencies()
	Signals.animals_changed.emit()
	return true


func collect_animal(index: int) -> bool:
	if animal_status(index, TimeService.now()) != AnimalStatus.READY:
		return false
	var def: Dictionary = Economy.animal(str(animals[index]["t"]))
	var product: String = str(def["product"])
	if _add_item(product, 1) <= 0:
		_toast("Склад полон: %s" % Economy.item_name(product))
		return false
	animals[index]["f"] = 0.0
	Signals.animals_changed.emit()
	Signals.inventory_changed.emit()
	_add_xp(int(def.get("xp", 0)))
	return true


func make_feed() -> bool:
	var source: String = str(Economy.cfg("feed_source_item"))
	if item_count(source) <= 0:
		_toast("Нужна %s" % Economy.item_name(source).to_lower())
		return false
	var gain: int = Economy.cfg_i("feed_per_corn")
	if feed + gain > storage_cap():
		_toast("Склад корма полон")
		return false
	_remove_item(source, 1)
	feed += gain
	_emit_currencies()
	Signals.inventory_changed.emit()
	return true


# =====================================================================
# Market, workshop, buildings
# =====================================================================

func sell_item(item_id: String, qty: int) -> int:
	var amount: int = mini(qty, item_count(item_id))
	if amount <= 0:
		return 0
	var earned: int = amount * Economy.item_sell_price(item_id)
	_remove_item(item_id, amount)
	coins += earned
	_emit_currencies()
	Signals.inventory_changed.emit()
	return earned


func sell_all_items() -> int:
	var earned: int = 0
	for id: Variant in inventory:
		earned += int(inventory[id]) * Economy.item_sell_price(str(id))
	if earned <= 0:
		_toast("Нечего продавать")
		return 0
	inventory.clear()
	coins += earned
	_emit_currencies()
	Signals.inventory_changed.emit()
	_toast("Продано на %d монет" % earned)
	return earned


func buy_seed_pack() -> bool:
	var pack: Dictionary = Economy.cfg_dict("seed_pack")
	var cost: int = int(pack.get("cost", 0))
	var amount: int = int(pack.get("seeds", 0))
	if coins < cost:
		_toast("Не хватает монет")
		return false
	if seeds + amount > storage_cap():
		_toast("Склад семян полон")
		return false
	coins -= cost
	seeds += amount
	_emit_currencies()
	return true


func craft_seeds(item_id: String) -> bool:
	var workshop: int = building_level("workshop")
	if workshop <= 0:
		_toast("Нужна мастерская")
		return false
	if not Economy.is_crop(item_id) or item_count(item_id) <= 0:
		return false
	var gain: int = workshop * int(Economy.building_param("workshop", "seeds_per_item_per_level"))
	if seeds + gain > storage_cap():
		_toast("Склад семян полон")
		return false
	_remove_item(item_id, 1)
	seeds += gain
	_emit_currencies()
	Signals.inventory_changed.emit()
	return true


func building_level(building_id: String) -> int:
	return int(buildings.get(building_id, 0))


func upgrade_building(building_id: String) -> bool:
	var def: Dictionary = Economy.building(building_id)
	if def.is_empty():
		push_error("GameState: unknown building '%s'" % building_id)
		return false
	if int(def["unlock_level"]) > level:
		_toast("Откроется на уровне %d" % int(def["unlock_level"]))
		return false
	var cost: int = Economy.building_cost(building_id, building_level(building_id))
	if cost < 0:
		_toast("Максимальный уровень")
		return false
	if coins < cost:
		_toast("Не хватает монет")
		return false
	coins -= cost
	buildings[building_id] = building_level(building_id) + 1
	Signals.buildings_changed.emit()
	_emit_currencies()
	_toast("%s: уровень %d" % [str(def["name"]), building_level(building_id)])
	_add_xp(int(def.get("xp", 0)))
	return true


func _run_market_stall(now: float) -> int:
	var stall: int = building_level("market_stall")
	var interval: float = Economy.building_param("market_stall", "interval_seconds")
	if stall <= 0 or interval <= 0.0:
		last_stall_at = now
		return 0
	var cycles: int = floori((now - last_stall_at) / interval)
	if cycles <= 0:
		return 0
	last_stall_at += cycles * interval
	var per_cycle: int = stall * int(Economy.building_param("market_stall", "items_per_level"))
	return _stall_sell(cycles * per_cycle)


func _stall_sell(count: int) -> int:
	var mult: float = Economy.building_param("market_stall", "price_multiplier")
	var earned: int = 0
	for k: int in count:
		var id: String = _most_plentiful_item()
		if id.is_empty():
			break
		_remove_item(id, 1)
		earned += maxi(1, roundi(Economy.item_sell_price(id) * mult))
	coins += earned
	return earned


func _most_plentiful_item() -> String:
	var best: String = ""
	var best_qty: int = 0
	for id: Variant in inventory:
		if int(inventory[id]) > best_qty:
			best = str(id)
			best_qty = int(inventory[id])
	return best


# =====================================================================
# Neighbors
# =====================================================================

func neighbor_state(index: int) -> Dictionary:
	if index < 0 or index >= neighbors.size():
		return {}
	return neighbors[index]


func pending_requests() -> int:
	var count: int = 0
	for st: Variant in neighbors:
		if not (st["req"] as Dictionary).is_empty():
			count += 1
	return count


func help_neighbor(index: int) -> bool:
	var st: Dictionary = neighbor_state(index)
	if st.is_empty() or (st["req"] as Dictionary).is_empty():
		_toast("Соседу пока не нужна помощь")
		return false
	var rt: Dictionary = Economy.request_type(str(st["req"]["type"]))
	var cost: int = int(rt.get("cost_feed", 0))
	if feed < cost:
		_toast("Не хватает корма")
		return false
	feed -= cost
	coins += int(rt.get("reward_coins", 0))
	_change_trust(index, int(rt.get("trust", 0)))
	st["req"] = {}
	st["req_next"] = TimeService.now() + NeighborAI.roll_delay(world_seed, index, int(st["n"]), "req")
	_emit_currencies()
	Signals.neighbors_changed.emit()
	_toast("Спасибо! +%d монет, +%d доверия" % [int(rt.get("reward_coins", 0)), int(rt.get("trust", 0))])
	_add_xp(int(rt.get("reward_xp", 0)))
	return true


func claim_gift(index: int) -> bool:
	var st: Dictionary = neighbor_state(index)
	var now: float = TimeService.now()
	if st.is_empty() or now < float(st["gift_at"]):
		_toast("Подарок ещё не готов")
		return false
	var added: int = _add_seeds(Economy.gift_seeds(int(st["trust"])))
	if added <= 0:
		_toast("Склад семян полон")
		return false
	st["gift_at"] = now + float(Economy.neighbor_cfg("gift_interval_seconds"))
	_emit_currencies()
	Signals.neighbors_changed.emit()
	_toast("Подарок: +%d семян" % added)
	return true


func accept_offer(index: int) -> bool:
	var st: Dictionary = neighbor_state(index)
	if st.is_empty() or (st["offer"] as Dictionary).is_empty():
		return false
	var offer: Dictionary = st["offer"]
	var item: String = str(offer["item"])
	var qty: int = mini(int(offer["qty"]), item_count(item))
	if qty <= 0:
		_toast("Нет товара: %s" % Economy.item_name(item))
		return false
	var earned: int = qty * int(offer["price"])
	_remove_item(item, qty)
	coins += earned
	st["offer"] = {}
	st["offer_next"] = TimeService.now() + NeighborAI.roll_delay(world_seed, index, int(st["n"]), "offer")
	_change_trust(index, int(Economy.neighbor_cfg("offer_trust")))
	_emit_currencies()
	Signals.inventory_changed.emit()
	Signals.neighbors_changed.emit()
	_toast("Продано соседу: +%d монет" % earned)
	return true


func add_trust(index: int, amount: int) -> void:
	if neighbor_state(index).is_empty():
		return
	_change_trust(index, amount)
	Signals.neighbors_changed.emit()


func _change_trust(index: int, delta: int) -> void:
	var st: Dictionary = neighbors[index]
	st["trust"] = clampi(int(st["trust"]) + delta, 0, int(Economy.neighbor_cfg("trust_max")))


func _update_all_neighbors(now: float) -> bool:
	var changed: bool = false
	for i: int in neighbors.size():
		if _update_request(i, now):
			changed = true
		if _update_offer(i, now):
			changed = true
	return changed


func _update_request(index: int, now: float) -> bool:
	var st: Dictionary = neighbors[index]
	var req: Dictionary = st["req"]
	if not req.is_empty():
		if now < float(req["exp"]):
			return false
		st["req"] = {}
		st["req_next"] = now + NeighborAI.roll_delay(world_seed, index, int(st["n"]), "req")
		return true
	if now < float(st["req_next"]):
		return false
	st["n"] = int(st["n"]) + 1
	st["req"] = NeighborAI.roll_request(world_seed, index, int(st["n"]), now)
	return true


func _update_offer(index: int, now: float) -> bool:
	var st: Dictionary = neighbors[index]
	var offer: Dictionary = st["offer"]
	if not offer.is_empty():
		if now < float(offer["exp"]):
			return false
		st["offer"] = {}
		st["offer_next"] = now + NeighborAI.roll_delay(world_seed, index, int(st["n"]), "offer")
		return true
	if now < float(st["offer_next"]):
		return false
	st["n"] = int(st["n"]) + 1
	st["offer"] = NeighborAI.roll_offer(world_seed, index, int(st["n"]), now, level)
	return not (st["offer"] as Dictionary).is_empty()


func _decay_trust(now: float) -> int:
	var hours: int = floori((now - last_decay_at) / SECONDS_PER_HOUR)
	if hours <= 0:
		return 0
	last_decay_at += hours * SECONDS_PER_HOUR
	var per_hour: int = int(Economy.neighbor_cfg("trust_decay_per_hour"))
	var total: int = 0
	for i: int in neighbors.size():
		var before: int = int(neighbors[i]["trust"])
		_change_trust(i, -per_hour * hours)
		total += before - int(neighbors[i]["trust"])
	return total


# =====================================================================
# Weekly co-op contract
# =====================================================================

func contract_def() -> Dictionary:
	return Economy.contract_def(str(contract.get("id", "")))


func contract_target() -> int:
	return int(contract_def().get("target", 0))


func contract_progress() -> int:
	if contract.is_empty():
		return 0
	return mini(contract_target(), int(contract["player"]) + int(contract["npc"]))


func contract_player_part() -> int:
	return int(contract.get("player", 0))


func contract_claimed() -> bool:
	return bool(contract.get("claimed", false))


func contract_ends_at() -> float:
	return (float(contract.get("week", 0)) + 1.0) * Economy.contract_duration()


func deliver_to_contract() -> int:
	var def: Dictionary = contract_def()
	if def.is_empty():
		return 0
	var item: String = str(def["item"])
	var amount: int = mini(item_count(item), contract_target() - contract_progress())
	if amount <= 0:
		_toast("Нечего сдавать")
		return 0
	_remove_item(item, amount)
	contract["player"] = int(contract["player"]) + amount
	Signals.inventory_changed.emit()
	Signals.contract_changed.emit()
	_toast("Сдано в контракт: %d" % amount)
	return amount


func claim_contract() -> bool:
	if contract.is_empty() or contract_claimed() or contract_progress() < contract_target():
		return false
	contract["claimed"] = true
	var reward: Dictionary = contract_def().get("reward", {})
	coins += int(reward.get("coins", 0))
	_add_seeds(int(reward.get("seeds", 0)))
	_add_feed(int(reward.get("feed", 0)))
	_emit_currencies()
	Signals.contract_changed.emit()
	_toast("Сундук открыт!")
	_add_xp(int(reward.get("xp", 0)))
	return true


func _update_contract(now: float) -> bool:
	var defs: Array = Economy.contract_defs()
	var duration: float = Economy.contract_duration()
	if defs.is_empty() or duration <= 0.0:
		return false
	var week: int = floori(now / duration)
	if contract.is_empty() or int(contract["week"]) != week:
		var def: Dictionary = defs[week % defs.size()]
		contract = {"id": str(def["id"]), "week": week, "player": 0, "npc": 0.0, "claimed": false, "last": now}
		return true
	var before: int = int(contract["npc"])
	var dt: float = maxf(0.0, now - float(contract["last"]))
	contract["last"] = now
	var gain: float = NeighborAI.contract_rate_total(world_seed) * dt / SECONDS_PER_HOUR
	contract["npc"] = minf(float(contract_target()), float(contract["npc"]) + gain)
	return int(contract["npc"]) != before


# =====================================================================
# Boost, purchases, rewarded ads
# =====================================================================

func is_boost_active(now: float) -> bool:
	return now < boost_until


func is_sku_owned(sku: String) -> bool:
	return owned_skus.has(sku)


func apply_purchase(sku: String) -> void:
	var product: Dictionary = Economy.iap_product(sku)
	if product.is_empty():
		push_error("GameState: unknown sku '%s'" % sku)
		return
	if not bool(product.get("consumable", true)) and not owned_skus.has(sku):
		owned_skus.append(sku)
	_apply_grant(product.get("grant", {}), -1)


func apply_rewarded(offer_id: String, neighbor_index: int) -> void:
	var offer: Dictionary = Economy.rewarded_offer(offer_id)
	if offer.is_empty():
		push_error("GameState: unknown rewarded offer '%s'" % offer_id)
		return
	_apply_grant(offer.get("grant", {}), neighbor_index)


func _apply_grant(grant: Dictionary, neighbor_index: int) -> void:
	coins += int(grant.get("coins", 0))
	_add_seeds(int(grant.get("seeds", 0)))
	_add_feed(int(grant.get("feed", 0)))
	if bool(grant.get("no_ads", false)):
		no_ads = true
	if grant.has("boost_seconds"):
		boost_until = maxf(boost_until, TimeService.now()) + float(grant["boost_seconds"])
		Signals.boost_changed.emit(boost_until)
	if grant.has("trust") and neighbor_index >= 0:
		add_trust(neighbor_index, int(grant["trust"]))
	_emit_currencies()
	if grant.has("time_skip_seconds"):
		TimeService.fast_forward(float(grant["time_skip_seconds"]))
