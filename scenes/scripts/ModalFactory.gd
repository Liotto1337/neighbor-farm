extends RefCounted
## Builds modal content by id: BuildMenu, PlantPicker, ContractDetails, IAPConfirm, SellAnimal,
## WelcomeBack.

const ModalScript = preload("res://scenes/components/Modal.gd")
const Fmt = preload("res://scenes/scripts/Fmt.gd")


func spec(modal_id: String, payload: Dictionary) -> Dictionary:
	match modal_id:
		"build_menu":
			return {"title": "Постройки", "builder": _build_menu}
		"plant_picker":
			return {"title": "Что сажаем?", "builder": _plant_picker}
		"contract_details":
			return {"title": "Контракт недели", "builder": _contract_details}
		"iap_confirm":
			return {"title": "Покупка", "builder": _iap_confirm.bind(payload)}
		"sell_animal":
			return {"title": "Продажа животного", "builder": _sell_animal.bind(payload)}
		"welcome_back":
			return {"title": "С возвращением!", "builder": _welcome_back.bind(payload)}
	return {}


func _build_menu(m: ModalScript) -> void:
	m.add_label("Монеты: %d" % GameState.coins)
	for def: Variant in Economy.buildings_list():
		var id: String = str(def["id"])
		var lvl: int = GameState.building_level(id)
		var unlock: int = int(def["unlock_level"])
		var cost: int = Economy.building_cost(id, lvl)
		m.add_separator()
		m.add_label("%s — ур. %d\n%s" % [str(def["name"]), lvl, str(def["desc"])])
		if GameState.level < unlock:
			m.add_button("Откроется на уровне %d" % unlock, Callable(), false)
		elif cost < 0:
			m.add_button("Максимальный уровень", Callable(), false)
		else:
			var verb: String = "Построить" if lvl == 0 else "Улучшить"
			m.add_button("%s за %d монет" % [verb, cost], GameState.upgrade_building.bind(id), GameState.coins >= cost)


func _plant_picker(m: ModalScript) -> void:
	m.add_label("Семян: %d. Тап по вспаханной грядке сажает выбранную культуру, тапы по растущей — ускоряют рост." % GameState.seeds)
	for def: Variant in Economy.crops_list():
		var id: String = str(def["id"])
		var unlock: int = int(def["unlock_level"])
		var marker: String = "» " if id == GameState.selected_crop else ""
		var text: String = "%s%s — %d сем., %s, цена %d" % [
			marker, str(def["name"]), int(def["seed_cost"]),
			Fmt.duration(Economy.crop_grow_seconds(id)), int(def["sell_price"])]
		if GameState.level < unlock:
			text = "%s — с уровня %d" % [str(def["name"]), unlock]
		m.add_button(text, _pick_crop.bind(id), GameState.level >= unlock)


func _pick_crop(crop_id: String) -> void:
	GameState.select_crop(crop_id)
	Signals.modal_close_requested.emit()


func _contract_details(m: ModalScript) -> void:
	var def: Dictionary = GameState.contract_def()
	if def.is_empty():
		m.add_label("Сейчас нет активного контракта.")
		return
	var progress: int = GameState.contract_progress()
	var target: int = GameState.contract_target()
	var item: String = str(def["item"])
	var have: int = GameState.item_count(item)
	m.add_label("%s\n%s" % [str(def["title"]), str(def["desc"])])
	m.add_progress(float(progress), float(target))
	m.add_label("Прогресс: %d / %d (ваш вклад: %d)" % [progress, target, GameState.contract_player_part()])
	m.add_label("До конца недели: %s" % Fmt.duration(GameState.contract_ends_at() - TimeService.now()))
	m.add_label("Награда: %s" % Fmt.reward(def.get("reward", {})))
	m.add_button("Сдать: %s (есть %d)" % [Economy.item_name(item), have], GameState.deliver_to_contract, have > 0 and progress < target)
	var can_claim: bool = progress >= target and not GameState.contract_claimed()
	var claim_text: String = "Награда получена" if GameState.contract_claimed() else "Открыть сундук"
	m.add_button(claim_text, GameState.claim_contract, can_claim)


func _iap_confirm(m: ModalScript, payload: Dictionary) -> void:
	var sku: String = str(payload.get("sku", ""))
	var product: Dictionary = Economy.iap_product(sku)
	if product.is_empty():
		m.add_label("Товар не найден.")
		return
	m.add_label("%s\n%s" % [str(product["title"]), str(product["desc"])])
	m.add_label("Цена: %s" % str(product["price"]))
	if not bool(product.get("consumable", true)) and IAP.is_owned(sku):
		m.add_label("Уже куплено.")
	else:
		m.add_button("Купить за %s" % str(product["price"]), _confirm_purchase.bind(sku))
	m.add_button("Отмена", m.close)


func _confirm_purchase(sku: String) -> void:
	Signals.modal_close_requested.emit()
	IAP.purchase(sku)


func _sell_animal(m: ModalScript, payload: Dictionary) -> void:
	var index: int = int(payload.get("index", -1))
	# The list may have changed since the modal opened: only sell the animal that was picked.
	if index < 0 or index >= GameState.animals.size() or str(GameState.animals[index]["t"]) != str(payload.get("type", "")):
		m.add_label("Это животное уже не в амбаре.")
		m.add_button("Закрыть", m.close)
		return
	var def: Dictionary = Economy.animal(str(payload["type"]))
	var price: int = GameState.animal_sell_price(index)
	m.add_label("Продать «%s» за %d монет? Это %d%% от цены покупки (%d)." % [
		str(def["name"]), price, roundi(Economy.cfg_f("animal_sell_refund") * 100.0), int(def["cost"])])
	if GameState.animal_status(index, TimeService.now()) != GameState.AnimalStatus.HUNGRY:
		m.add_label("Корм уже потрачен, а несобранный продукт (%s) пропадёт." % str(def["product_name"]).to_lower())
	var sell: Button = m.add_button("Продать за %d монет" % price, _confirm_sell.bind(index))
	sell.theme_type_variation = &"ButtonRed"
	m.add_button("Оставить", m.close)


func _confirm_sell(index: int) -> void:
	Signals.modal_close_requested.emit()
	GameState.sell_animal(index)


func _welcome_back(m: ModalScript, summary: Dictionary) -> void:
	m.add_label("Вас не было %s." % Fmt.duration(float(summary.get("seconds", 0.0))))
	if bool(summary.get("capped", false)):
		m.add_label("Ферма работала без вас не дольше %s." % Fmt.duration(Economy.cfg_f("offline_cap_seconds")))
	m.add_label(_summary_text(summary))
	m.add_button("Отлично!", m.close)


func _summary_text(summary: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Созрело грядок: %d" % int(summary.get("crops_ready", 0)))
	lines.append("Завяло грядок: %d" % int(summary.get("withered", 0)))
	lines.append("Животные готовы: %d" % int(summary.get("animals_ready", 0)))
	lines.append("Прилавок заработал: %d монет" % int(summary.get("stall_coins", 0)))
	lines.append("Доверие соседей: -%d" % int(summary.get("trust_decay", 0)))
	lines.append("Соседи продвинули контракт: +%d" % int(summary.get("contract_gain", 0)))
	return "\n".join(lines)
