class_name AccountApp
extends VBoxContainer
## "Mi cuenta" (docs/PROGRESSION.md §8, §10.3): balance, level and XP, the passive income right
## now (which equipment earns, how much, what is left today) and every movement of credits and XP
## with its reason, newest first. Reads Economy; changes nothing.

var world: SimWorld


func setup(sim_world: SimWorld) -> void:
	world = sim_world
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var economy := world.economy
	add_child(UiStyle.label(TranslationServer.translate("Mi cuenta"), 22))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	var progress := world.level_progress()
	top.add_child(_tile(TranslationServer.translate("Saldo"), TranslationServer.translate("%d cr") % world.credits, UiStyle.MUSTARD))
	top.add_child(_tile(TranslationServer.translate("Ganado en total"), TranslationServer.translate("%d cr") % economy.earned_total, UiStyle.OK))
	top.add_child(_tile(TranslationServer.translate("Gastado en total"), TranslationServer.translate("%d cr") % economy.spent_total, UiStyle.BAD))
	top.add_child(_tile(TranslationServer.translate("Nivel %d") % world.level(), TranslationServer.translate("%d / %d XP") % [progress[0], progress[1]], UiStyle.HIGHLIGHT))
	# Passive income now.
	var passive := PanelContainer.new()
	passive.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
	add_child(passive)
	var passive_box := VBoxContainer.new()
	passive.add_child(passive_box)
	passive_box.add_child(UiStyle.label(TranslationServer.translate("Ingresos pasivos"), 17, UiStyle.MUSTARD))
	var earners := economy.earners(world)
	var rules := economy.rules
	if earners.is_empty():
		var none := UiStyle.label(TranslationServer.translate("Ahora no ganas nada por hora. Un servidor encendido, con IP en la red de casa y accesible desde tu PC paga unos pocos créditos por hora de juego (hasta %d al día entre todos).") % rules.passive_daily_cap, 14, UiStyle.MIST)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive_box.add_child(none)
	else:
		for d: SimDevice in earners:
			var host_name := d.host.hostname if d.host != null else d.display_name()
			passive_box.add_child(UiStyle.label(TranslationServer.translate("✓ %s (%s) en línea: +%d cr/h") % [host_name, d.display_name(), d.definition.online_income_per_hour], 14, UiStyle.OK))
		var left := economy.passive_left_today(world.time_minutes)
		passive_box.add_child(UiStyle.label(TranslationServer.translate("Hoy: %d de %d cr como máximo (quedan %d). Se cobra a cada hora en punto.") % [rules.passive_daily_cap - left, rules.passive_daily_cap, left], 13, UiStyle.MIST))
	var honest := UiStyle.label(TranslationServer.translate("Es una simplificación del juego: todavía no hay servicios simulados en los servidores; cuenta que el equipo esté encendido y accesible en la red."), 12, UiStyle.MIST)
	honest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive_box.add_child(honest)
	# Ledger.
	add_child(UiStyle.label(TranslationServer.translate("Movimientos (los más recientes primero)"), 17, UiStyle.MUSTARD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Ledger"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for header: String in [TranslationServer.translate("Cuándo"), TranslationServer.translate("Concepto"), TranslationServer.translate("Créditos"), TranslationServer.translate("XP")]:
		grid.add_child(UiStyle.label(header, 13, UiStyle.MIST))
	var lines := economy.ledger.duplicate()
	lines.reverse()
	for line: Dictionary in lines:
		grid.add_child(UiStyle.label(_when(float(line["t"])), 13, UiStyle.MIST))
		var text := String(line["text"])
		if int(line["count"]) > 1:
			text += TranslationServer.translate(" (%d horas)") % int(line["count"])
		var concept := UiStyle.label(text, 14)
		concept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		concept.custom_minimum_size = Vector2(420, 0)
		concept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(concept)
		var credits := int(line["credits"])
		grid.add_child(UiStyle.label("" if credits == 0 else ("%+d cr" % credits), 14, UiStyle.OK if credits > 0 else UiStyle.BAD))
		var xp := int(line["xp"])
		grid.add_child(UiStyle.label("" if xp == 0 else ("+%d XP" % xp), 14, UiStyle.HIGHLIGHT))


func _tile(title: String, value: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
	panel.custom_minimum_size = Vector2(170, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiStyle.label(title, 13, UiStyle.MIST))
	box.add_child(UiStyle.label(value, 20, color))
	return panel


static func _when(minutes: float) -> String:
	var total := int(minutes)
	return TranslationServer.translate("Día %d · %02d:%02d") % [total / 1440 + 1, (total / 60) % 24, total % 60]
