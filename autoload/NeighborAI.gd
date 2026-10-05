extends Node
## Deterministic neighbor simulation: pure functions of (world_seed, neighbor index, counter).
## Owns no mutable game state — GameState applies the results.

var _cache_seed: int = -1
var _profiles: Array = []


func profiles(world_seed: int) -> Array:
	if world_seed == _cache_seed and not _profiles.is_empty():
		return _profiles
	_cache_seed = world_seed
	_profiles = []
	var names: Array = (Economy.neighbor_cfg("names") as Array).duplicate()
	_shuffle(names, _rng([world_seed, "names"]))
	var count: int = mini(int(Economy.neighbor_cfg("count")), names.size())
	for i: int in count:
		_profiles.append(_make_profile(world_seed, i, str(names[i])))
	return _profiles


func _make_profile(world_seed: int, index: int, display_name: String) -> Dictionary:
	var rng: RandomNumberGenerator = _rng([world_seed, index, "profile"])
	var palette: Array = Economy.neighbor_cfg("farm_palette")
	var side: int = int(Economy.neighbor_cfg("visit_grid"))
	var cells: Array = []
	for c: int in side * side:
		cells.append(str(palette[rng.randi_range(0, palette.size() - 1)]))
	var rate: Vector2 = Economy.neighbor_range("contract_rate_per_hour")
	return {"name": display_name, "cells": cells, "rate": rng.randf_range(rate.x, rate.y)}


func make_states(world_seed: int, now: float) -> Array:
	var out: Array = []
	var first: Vector2 = Economy.neighbor_range("first_request_seconds")
	for i: int in profiles(world_seed).size():
		var rng: RandomNumberGenerator = _rng([world_seed, i, "first"])
		out.append({
			"trust": int(Economy.neighbor_cfg("trust_start")),
			"req": {},
			"req_next": now + rng.randf_range(first.x, first.y),
			"gift_at": now,
			"offer": {},
			"offer_next": now + roll_delay(world_seed, i, 0, "offer"),
			"n": 0,
		})
	return out


func normalize_state(raw: Dictionary, fallback: Dictionary) -> Dictionary:
	return {
		"trust": int(raw.get("trust", fallback["trust"])),
		"req": _normalize_request(raw.get("req", {})),
		"req_next": float(raw.get("req_next", fallback["req_next"])),
		"gift_at": float(raw.get("gift_at", fallback["gift_at"])),
		"offer": _normalize_offer(raw.get("offer", {})),
		"offer_next": float(raw.get("offer_next", fallback["offer_next"])),
		"n": int(raw.get("n", 0)),
	}


func _normalize_request(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	return {"type": str(raw.get("type", "")), "exp": float(raw.get("exp", 0.0))}


func _normalize_offer(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	return {
		"item": str(raw.get("item", "")),
		"qty": int(raw.get("qty", 0)),
		"price": int(raw.get("price", 0)),
		"exp": float(raw.get("exp", 0.0)),
	}


func roll_delay(world_seed: int, index: int, counter: int, kind: String) -> float:
	var key: String = "request_interval_seconds" if kind == "req" else "offer_interval_seconds"
	var span: Vector2 = Economy.neighbor_range(key)
	return _rng([world_seed, index, counter, kind, "delay"]).randf_range(span.x, span.y)


func roll_request(world_seed: int, index: int, counter: int, now: float) -> Dictionary:
	var types: Array = Economy.neighbor_cfg("request_types")
	if types.is_empty():
		return {}
	var rng: RandomNumberGenerator = _rng([world_seed, index, counter, "req"])
	var picked: Dictionary = types[rng.randi_range(0, types.size() - 1)]
	var lifetime: float = float(Economy.neighbor_cfg("request_lifetime_seconds"))
	return {"type": str(picked["id"]), "exp": now + lifetime}


func roll_offer(world_seed: int, index: int, counter: int, now: float, player_level: int) -> Dictionary:
	var candidates: Array = []
	for def: Variant in Economy.crops_list():
		if int(def["unlock_level"]) <= player_level:
			candidates.append(def)
	if candidates.is_empty():
		return {}
	var rng: RandomNumberGenerator = _rng([world_seed, index, counter, "offer"])
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var qty: Vector2 = Economy.neighbor_range("offer_qty")
	var mult: float = float(Economy.neighbor_cfg("offer_price_multiplier"))
	return {
		"item": str(picked["id"]),
		"qty": rng.randi_range(int(qty.x), int(qty.y)),
		"price": ceili(float(picked["sell_price"]) * mult),
		"exp": now + float(Economy.neighbor_cfg("offer_lifetime_seconds")),
	}


func contract_rate_total(world_seed: int) -> float:
	var total: float = 0.0
	for profile: Variant in profiles(world_seed):
		total += float(profile["rate"])
	return total


func _rng(parts: Array) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(parts)
	return rng


func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(list.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
