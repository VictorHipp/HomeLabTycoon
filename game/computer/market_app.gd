class_name MarketApp
extends VBoxContainer
## Second-hand market (docs/PROGRESSION.md §8; ADR 0010): sells what the player no longer needs
## for less than it cost — the share depends on whether it was ever installed (EconomyRules).
## Only what is in the inventory can be sold; installed things are listed with what to do first.
## Selling asks for a confirmation. Selling is a SimWorld command.

signal message_shown(text: String, ok: bool)

var world: SimWorld
var _confirm_id: int = -1
var _status_text: String = ""
var _status_ok: bool = true


func setup(sim_world: SimWorld) -> void:
	world = sim_world
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_child(UiStyle.label(TranslationServer.translate("Segunda mano — vende lo que no uses"), 22))
	var rules := world.economy.rules
	var intro := UiStyle.label(TranslationServer.translate("Te pagan el %d %% de su precio si está sin estrenar y el %d %% si ya lo instalaste o lo conectaste. Siempre es menos de lo que costó: vender sirve para recuperar parte de una compra que no necesitabas.") % [rules.resale_unused_percent, rules.resale_used_percent], 14, UiStyle.MIST)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	if _status_text != "":
		var status := UiStyle.label(_status_text, 15, UiStyle.OK if _status_ok else UiStyle.BAD)
		status.name = "Status"
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var sellable := world.inventory().filter(func(d: SimDevice) -> bool: return world.economy.resale_price(d) > 0)
	list.add_child(UiStyle.label(TranslationServer.translate("En tu inventario"), 18, UiStyle.MUSTARD))
	if sellable.is_empty():
		list.add_child(UiStyle.label(TranslationServer.translate("No tienes nada en el inventario que se pueda vender."), 14, UiStyle.MIST))
	for d: SimDevice in sellable:
		list.add_child(_row(d))
	var installed: Array[SimDevice] = []
	for d: SimDevice in world.devices.values():
		if d.location in [&"placed", &"mounted", &"cabled"] and world.economy.resale_price(d) > 0:
			installed.append(d)
	if not installed.is_empty():
		list.add_child(UiStyle.label(TranslationServer.translate("Instalado (para venderlo, devuélvelo antes al inventario)"), 18, UiStyle.MUSTARD))
		installed.sort_custom(func(a: SimDevice, b: SimDevice) -> bool: return a.id < b.id)
		for d: SimDevice in installed:
			var how := {&"placed": TranslationServer.translate("recógelo"), &"mounted": TranslationServer.translate("desmóntalo"), &"cabled": TranslationServer.translate("desconéctalo")}.get(d.location, "") as String
			list.add_child(UiStyle.label("%s — %s" % [d.display_name(), how], 14, UiStyle.MIST))


func _row(d: SimDevice) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
	panel.name = "Sell_%d" % d.id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var thumb := TextureRect.new()
	thumb.texture = ShopApp.photo(d.definition.id)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(88, 66)
	row.add_child(thumb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiStyle.label(d.display_name(), 16))
	var state: String = TranslationServer.translate("usado") if d.used else TranslationServer.translate("sin estrenar")
	info.add_child(UiStyle.label(TranslationServer.translate("Estado: %s · costó %d cr") % [state, d.definition.price], 13, UiStyle.MIST))
	var price := world.economy.resale_price(d)
	if _confirm_id == d.id:
		row.add_child(UiStyle.label(TranslationServer.translate("¿Vender por %d cr?") % price, 15, UiStyle.MUSTARD))
		row.add_child(UiStyle.button(TranslationServer.translate("Sí, vender"), _sell.bind(d.id)))
		row.add_child(UiStyle.button(TranslationServer.translate("No"), _ask.bind(-1)))
	else:
		row.add_child(UiStyle.label(TranslationServer.translate("Te dan %d cr") % price, 17, UiStyle.MUSTARD))
		row.add_child(UiStyle.button(TranslationServer.translate("Vender"), _ask.bind(d.id)))
	return panel


func _ask(device_id: int) -> void:
	_confirm_id = device_id
	rebuild()


func _sell(device_id: int) -> void:
	_confirm_id = -1
	var r := world.sell_device(device_id)
	_status_text = r.message
	_status_ok = r.ok
	rebuild()
	message_shown.emit(r.message, r.ok)


## Last message (for the automated walkthrough).
func status_text() -> String:
	return _status_text
