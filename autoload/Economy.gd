extends Node
## Read-only balance tables. Every tunable number lives in res://data/*.json.

const DATA_DIR: String = "res://data/"

var config: Dictionary = {}
var _crops: Array = []
var _buildings: Array = []
var _animals: Array = []
var _iap: Dictionary = {}
var _xp: Dictionary = {}
var _contracts: Dictionary = {}
var _neighbors: Dictionary = {}
var _crop_by_id: Dictionary = {}
var _building_by_id: Dictionary = {}
var _animal_by_id: Dictionary = {}
var _animal_by_product: Dictionary = {}
var _iap_by_sku: Dictionary = {}
var _rewarded_by_id: Dictionary = {}
var _contract_by_id: Dictionary = {}
var _request_by_id: Dictionary = {}


func _ready() -> void:
	config = _load_json("config.json")
	_crops = _array_of(_load_json("crops.json"), "crops")
	_buildings = _array_of(_load_json("buildings.json"), "buildings")
	_animals = _array_of(_load_json("animals.json"), "animals")
	_iap = _load_json("iap.json")
	_xp = _load_json("xp_curve.json")
	_contracts = _load_json("contracts.json")
	_neighbors = _load_json("neighbors.json")
	_build_indexes()


func _build_indexes() -> void:
	_crop_by_id = _index(_crops, "id")
	_building_by_id = _index(_buildings, "id")
	_animal_by_id = _index(_animals, "id")
	_animal_by_product = _index(_animals, "product")
	_iap_by_sku = _index(_array_of(_iap, "products"), "sku")
	_rewarded_by_id = _index(_array_of(_iap, "rewarded"), "id")
	_contract_by_id = _index(_array_of(_contracts, "contracts"), "id")
	_request_by_id = _index(_array_of(_neighbors, "request_types"), "id")


func _load_json(file_name: String) -> Dictionary:
	var path: String = DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("Economy: missing data file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Economy: invalid JSON in %s" % path)
		return {}
	return parsed


func _array_of(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	if value is Array:
		return value
	push_error("Economy: key '%s' is not an array" % key)
	return []


func _index(list: Array, key: String) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in list:
		if entry is Dictionary and (entry as Dictionary).has(key):
			out[str(entry[key])] = entry
	return out


# --- Config ---

func cfg(key: String) -> Variant:
	if not config.has(key):
		push_error("Economy: missing config key '%s'" % key)
	return config.get(key)


func cfg_i(key: String) -> int:
	return int(cfg(key))


func cfg_f(key: String) -> float:
	return float(cfg(key))


func cfg_dict(key: String) -> Dictionary:
	var value: Variant = cfg(key)
	return value if value is Dictionary else {}


func ui_i(key: String) -> int:
	return int(cfg_dict("ui").get(key, 0))


func ui_f(key: String) -> float:
	return float(cfg_dict("ui").get(key, 0.0))


func anim_f(key: String) -> float:
	return float(cfg_dict("anim").get(key, 0.0))


func color(key: String) -> Color:
	return Color.from_string(str(cfg_dict("colors").get(key, "")), Color.MAGENTA)


# --- Crops & items ---

func crops_list() -> Array:
	return _crops


func crop(crop_id: String) -> Dictionary:
	return _crop_by_id.get(crop_id, {})


func is_crop(item_id: String) -> bool:
	return _crop_by_id.has(item_id)


func crop_grow_seconds(crop_id: String) -> float:
	return float(crop(crop_id).get("grow_minutes", 0)) * cfg_f("tick_seconds")


func item_name(item_id: String) -> String:
	if _crop_by_id.has(item_id):
		return str(_crop_by_id[item_id]["name"])
	if _animal_by_product.has(item_id):
		return str(_animal_by_product[item_id]["product_name"])
	return item_id


func item_sell_price(item_id: String) -> int:
	if _crop_by_id.has(item_id):
		return int(_crop_by_id[item_id]["sell_price"])
	if _animal_by_product.has(item_id):
		return int(_animal_by_product[item_id]["sell_price"])
	return 0


# --- Buildings ---

func buildings_list() -> Array:
	return _buildings


func building(building_id: String) -> Dictionary:
	return _building_by_id.get(building_id, {})


func building_cost(building_id: String, current_level: int) -> int:
	var costs: Array = building(building_id).get("costs", [])
	if current_level < 0 or current_level >= costs.size():
		return -1
	return int(costs[current_level])


func building_param(building_id: String, key: String) -> float:
	var params: Dictionary = building(building_id).get("params", {})
	return float(params.get(key, 0.0))


func storage_cap(silo_level: int) -> int:
	return cfg_i("storage_base") + silo_level * int(building_param("silo", "storage_per_level"))


# --- Farm field ---

## Side of the open (square) part of the field at a level; the full grid opens at the last step.
func field_side(at_level: int) -> int:
	var grid: int = cfg_i("grid_size")
	var steps: Array = _array_of(config, "field_sizes")
	if steps.is_empty():
		return grid
	var side: int = int(steps[0].get("side", grid))
	for step: Variant in steps:
		if at_level >= int(step.get("level", 1)):
			side = maxi(side, int(step.get("side", 0)))
	return clampi(side, 1, grid)


## Next field expansion after a level: {"level", "side"}, or {} when the field is already full.
func next_field_step(at_level: int) -> Dictionary:
	var current: int = field_side(at_level)
	for step: Variant in _array_of(config, "field_sizes"):
		if int(step.get("level", 1)) > at_level and int(step.get("side", 0)) > current:
			return {"level": int(step["level"]), "side": mini(int(step["side"]), cfg_i("grid_size"))}
	return {}


# --- Animals ---

func animals_list() -> Array:
	return _animals


func animal(animal_id: String) -> Dictionary:
	return _animal_by_id.get(animal_id, {})


func animal_produce_seconds(animal_id: String) -> float:
	return float(animal(animal_id).get("produce_minutes", 0)) * cfg_f("tick_seconds")


# --- XP curve ---

func max_level() -> int:
	return _array_of(_xp, "thresholds").size()


func xp_for_level(target_level: int) -> int:
	var thresholds: Array = _array_of(_xp, "thresholds")
	if thresholds.is_empty():
		return 0
	return int(thresholds[clampi(target_level - 1, 0, thresholds.size() - 1)])


func level_up_coins() -> int:
	return int(_xp.get("level_up_coins", 0))


# --- Monetization ---

func iap_products() -> Array:
	return _array_of(_iap, "products")


func iap_product(sku: String) -> Dictionary:
	return _iap_by_sku.get(sku, {})


func rewarded_offers() -> Array:
	return _array_of(_iap, "rewarded")


func rewarded_offer(offer_id: String) -> Dictionary:
	return _rewarded_by_id.get(offer_id, {})


# --- Contracts ---

func contract_defs() -> Array:
	return _array_of(_contracts, "contracts")


func contract_def(contract_id: String) -> Dictionary:
	return _contract_by_id.get(contract_id, {})


func contract_duration() -> float:
	return float(_contracts.get("duration_seconds", 0.0))


# --- Neighbors ---

func neighbor_cfg(key: String) -> Variant:
	if not _neighbors.has(key):
		push_error("Economy: missing neighbors key '%s'" % key)
	return _neighbors.get(key)


func neighbor_range(key: String) -> Vector2:
	var pair: Array = neighbor_cfg(key) if neighbor_cfg(key) is Array else []
	if pair.size() < 2:
		push_error("Economy: neighbors key '%s' must be [min, max]" % key)
		return Vector2.ZERO
	return Vector2(float(pair[0]), float(pair[1]))


func request_type(request_id: String) -> Dictionary:
	return _request_by_id.get(request_id, {})


func gift_seeds(trust: int) -> int:
	var amount: int = 0
	for tier: Variant in _array_of(_neighbors, "gift_tiers"):
		if trust >= int(tier["min_trust"]):
			amount = int(tier["seeds"])
	return amount
