class_name Hud
extends CanvasLayer
## Main view HUD (GDD §9): credits, level/XP, clock and speed, active mission, inventory,
## contextual hints, toasts and the side panel of close-up views. Reads the world; actions
## are forwarded through signals / callables to the session.

signal inventory_item_pressed(device_id: int)
signal menu_requested
signal toast_shown(ok: bool)

const FLOAT_SECONDS := 2.2

var world: SimWorld
var _root: Control
var _credits: Label
var _income: Label
var _top_panel: PanelContainer
var _cable_panel: PanelContainer
var _cable_title: Label
var _cable_text: Label
var _cable_texts: VBoxContainer
var _cable_cancel: Button
var _cable_cancel_callback: Callable = Callable()
var _level: Label
var _xp_bar: ProgressBar
var _clock: Label
var _skip: Button
var _speed_buttons: Dictionary = {}
var _mission_title: Label
var _mission_list: VBoxContainer
var _inventory_row: HBoxContainer
var _inventory_signature: String = "-" ## Never matches a real list: the first refresh always draws.
var _toast: Label
var _toast_time: float = 0.0
var _hint: Label
var _tool: Label
var _side: PanelContainer
var _side_box: VBoxContainer
var _banner: PanelContainer
var _banner_label: Label


func setup(sim_world: SimWorld) -> void:
	world = sim_world
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	# Top-left: economy, level, time.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UiStyle.panel())
	top.position = Vector2(12, 12)
	_top_panel = top
	root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	top.add_child(top_row)
	var money_box := VBoxContainer.new()
	money_box.add_theme_constant_override("separation", 0)
	_credits = UiStyle.label("", 18, UiStyle.MUSTARD)
	_credits.mouse_filter = Control.MOUSE_FILTER_PASS
	money_box.add_child(_credits)
	_income = UiStyle.label("", 12, UiStyle.OK)
	_income.mouse_filter = Control.MOUSE_FILTER_PASS
	money_box.add_child(_income)
	top_row.add_child(money_box)
	var level_box := VBoxContainer.new()
	_level = UiStyle.label("", 14)
	level_box.add_child(_level)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(130, 8)
	_xp_bar.show_percentage = false
	level_box.add_child(_xp_bar)
	top_row.add_child(level_box)
	_clock = UiStyle.label("", 16)
	top_row.add_child(_clock)
	for spec: Array in [[0.0, "II"], [1.0, "×1"], [2.0, "×2"], [4.0, "×4"]]:
		var b := UiStyle.button(spec[1], _set_speed.bind(spec[0]))
		b.toggle_mode = true
		_speed_buttons[spec[0]] = b
		top_row.add_child(b)
	_skip = UiStyle.button(TranslationServer.translate("Saltar espera"), _skip_wait)
	top_row.add_child(_skip)
	top_row.add_child(UiStyle.button(TranslationServer.translate("Menú (Esc)"), func() -> void: menu_requested.emit()))

	# Top-right: mission.
	var mission := PanelContainer.new()
	mission.add_theme_stylebox_override("panel", UiStyle.panel())
	mission.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mission.position = Vector2(-372, 12)
	mission.custom_minimum_size = Vector2(360, 0)
	root.add_child(mission)
	var mission_box := VBoxContainer.new()
	mission.add_child(mission_box)
	_mission_title = UiStyle.label("", 18, UiStyle.HIGHLIGHT)
	mission_box.add_child(_mission_title)
	_mission_list = VBoxContainer.new()
	mission_box.add_child(_mission_list)

	# Left side: close-up panel (hidden in overview); the mission stays visible on the right.
	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", UiStyle.panel())
	_side.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_side.position = Vector2(12, 84)
	_side.custom_minimum_size = Vector2(360, 0)
	_side.visible = false
	root.add_child(_side)
	_side_box = VBoxContainer.new()
	_side.add_child(_side_box)

	# Bottom: inventory, tool line, hint, toast.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -150
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_bottom = -10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN # taller content (cable guide) grows upwards
	root.add_child(bottom)
	_toast = UiStyle.label("", 17)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_toast)
	# Guide of the cable being laid (CableTool): what to look for, step 1 or 2, and how to cancel.
	_cable_panel = PanelContainer.new()
	var cable_box_style := UiStyle.panel(Color(UiStyle.INK, 0.95), 8, 10)
	cable_box_style.border_color = UiStyle.HIGHLIGHT
	cable_box_style.set_border_width_all(2)
	_cable_panel.add_theme_stylebox_override("panel", cable_box_style)
	_cable_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cable_panel.visible = false
	bottom.add_child(_cable_panel)
	var cable_row := HBoxContainer.new()
	cable_row.add_theme_constant_override("separation", 14)
	_cable_panel.add_child(cable_row)
	_cable_texts = VBoxContainer.new()
	var cable_texts := _cable_texts
	cable_texts.custom_minimum_size = Vector2(620, 0)
	cable_row.add_child(cable_texts)
	_cable_title = UiStyle.label("", 16, UiStyle.HIGHLIGHT)
	cable_texts.add_child(_cable_title)
	_cable_text = UiStyle.label("", 14)
	_cable_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cable_texts.add_child(_cable_text)
	_cable_cancel = UiStyle.button(TranslationServer.translate("Cancelar cable"), _on_cable_cancel)
	_cable_cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cable_row.add_child(_cable_cancel)
	_tool = UiStyle.label("", 15, UiStyle.HIGHLIGHT)
	_tool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long placement previews at 1280 px
	bottom.add_child(_tool)
	var inv_panel := PanelContainer.new()
	inv_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	bottom.add_child(inv_panel)
	var inv_row := HBoxContainer.new()
	inv_panel.add_child(inv_row)
	inv_row.add_child(UiStyle.label(TranslationServer.translate("Inventario:"), 15, UiStyle.MIST))
	_inventory_row = HBoxContainer.new()
	inv_row.add_child(_inventory_row)
	_hint = UiStyle.label("", 13, UiStyle.MIST)
	bottom.add_child(_hint)

	# Centre banner (mission completed).
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UiStyle.panel(Color(INK_DARK(), 0.95), 12, 24))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-260, -110)
	_banner.custom_minimum_size = Vector2(520, 0)
	_banner.visible = false
	root.add_child(_banner)
	var banner_box := VBoxContainer.new()
	_banner.add_child(banner_box)
	_banner_label = UiStyle.label("", 18)
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(_banner_label)
	banner_box.add_child(UiStyle.button(TranslationServer.translate("Seguir jugando"), func() -> void: _banner.visible = false))


static func INK_DARK() -> Color:
	return Color("#141A22")


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func refresh() -> void:
	_credits.text = TranslationServer.translate("%d créditos") % world.credits
	var rate := world.economy.passive_rate(world)
	var left := world.economy.passive_left_today(world.time_minutes)
	if rate <= 0:
		_income.text = ""
	elif left <= 0:
		_income.text = TranslationServer.translate("ingresos pasivos: tope de hoy alcanzado")
	else:
		_income.text = TranslationServer.translate("+%d cr/h en línea") % rate
	_credits.tooltip_text = TranslationServer.translate("Tus créditos. El detalle de ingresos y gastos está en el ordenador: aplicación «Mi cuenta».")
	_income.tooltip_text = TranslationServer.translate("Ingresos pasivos: tus servidores encendidos y accesibles desde el PC pagan %d créditos por hora de juego, hasta %d al día (hoy quedan %d).") % [rate, world.economy.rules.passive_daily_cap, left]
	var progress := world.level_progress()
	_level.text = TranslationServer.translate("Nivel %d · %d/%d XP") % [world.level(), progress[0], progress[1]]
	_xp_bar.max_value = progress[1]
	_xp_bar.value = progress[0]
	_clock.text = world.clock_text()
	for speed: float in _speed_buttons:
		(_speed_buttons[speed] as Button).button_pressed = is_equal_approx(world.speed, speed)
	var wait := world.minutes_to_next_event()
	_skip.disabled = wait < 0.0
	_skip.text = TranslationServer.translate("Saltar espera") if wait < 0.0 else TranslationServer.translate("Saltar espera (%s)") % SimWorld.format_duration(wait)
	_refresh_mission()
	_refresh_inventory()


func _refresh_mission() -> void:
	var tracker := world.mission
	if tracker == null:
		return
	_mission_title.text = TranslationServer.translate("Misión: %s") % tracker.definition.title + ("  ✓" if tracker.completed else "")
	for child: Node in _mission_list.get_children():
		child.queue_free()
	var reqs := tracker.definition.requirements
	for i: int in reqs.size():
		var done := i < tracker.status.size() and tracker.status[i]
		var text := ("✓ " if done else "○ ") + TranslationServer.translate(reqs[i].text)
		if reqs[i].xp > 0:
			text += "  " + (TranslationServer.translate("(+%d XP ganados)") if tracker.rewarded[i] else TranslationServer.translate("(+%d XP)")) % reqs[i].xp
		var line := UiStyle.label(text, 14, UiStyle.OK if done else UiStyle.BONE)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(340, 0)
		_mission_list.add_child(line)
	_mission_list.add_child(UiStyle.label(TranslationServer.translate("Al completarla: %d créditos y %d XP · %d XP en total") % [tracker.definition.reward_credits, tracker.definition.reward_xp, tracker.total_xp()], 13, UiStyle.MUSTARD))


func _refresh_inventory() -> void:
	var items := world.inventory()
	var signature := ",".join(items.map(func(d: SimDevice) -> String: return str(d.id)))
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	for child: Node in _inventory_row.get_children():
		child.queue_free()
	if items.is_empty():
		_inventory_row.add_child(UiStyle.label(TranslationServer.translate("vacío"), 14, UiStyle.MIST))
	for d: SimDevice in items:
		var b := UiStyle.button(d.definition.model if d.definition.category == &"cable" else d.display_name(), _inventory_pressed.bind(d.id))
		b.tooltip_text = d.definition.description
		_inventory_row.add_child(b)


func _inventory_pressed(device_id: int) -> void:
	inventory_item_pressed.emit(device_id)


func _set_speed(speed: float) -> void:
	world.speed = speed
	refresh()


func _skip_wait() -> void:
	var r := world.skip_to_next_event()
	show_toast(r.message, r.ok)
	refresh()


func show_toast(text: String, ok: bool = true) -> void:
	if text == "":
		return
	_toast.text = text
	_toast.add_theme_color_override("font_color", UiStyle.BONE if ok else UiStyle.BAD)
	_toast_time = 5.0
	_toast.modulate.a = 1.0
	toast_shown.emit(ok)


## "+600 cr", "−808 cr", "+10 XP": floats up from the credits and fades, so every change of
## credits or XP is seen with its sign.
func float_delta(text: String, positive: bool) -> void:
	var label := UiStyle.label(text, 18, UiStyle.OK if positive else UiStyle.BAD)
	label.add_theme_color_override("font_outline_color", UiStyle.INK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	var stacked := 0
	for child: Node in _root.get_children():
		if child.has_meta("float_delta"):
			stacked += 1
	label.set_meta("float_delta", true)
	# To the right of the top bar, so it never covers a panel; several stack downwards.
	label.position = Vector2(_top_panel.get_global_rect().end.x + 14.0, 16.0 + 26.0 * stacked)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 22.0, FLOAT_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_SECONDS).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


# ------------------------------------------------------------- cable guide --

## `compact`: in close-ups the panel is narrow and sits at the bottom left, so it never covers
## the sockets in the middle of the screen; in the overview it is wide and centred.
func show_cable_panel(title: String, text: String, cancel: Callable, compact: bool = false) -> void:
	_cable_title.text = title
	_cable_text.text = text
	_cable_cancel_callback = cancel
	_cable_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_SHRINK_CENTER
	_cable_texts.custom_minimum_size = Vector2(250 if compact else 620, 0)
	_cable_panel.visible = true


func hide_cable_panel() -> void:
	_cable_panel.visible = false
	_cable_cancel_callback = Callable()


func cable_panel_visible() -> bool:
	return _cable_panel.visible


func cable_panel_text() -> String:
	return _cable_title.text + " · " + _cable_text.text


func _on_cable_cancel() -> void:
	if _cable_cancel_callback.is_valid():
		_cable_cancel_callback.call()


func set_hint(text: String) -> void:
	_hint.text = text


func set_tool_text(text: String) -> void:
	_tool.text = text


func show_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true


# ---------------------------------------------------------- close-up panel --

func side_clear(title: String) -> void:
	for child: Node in _side_box.get_children():
		child.queue_free()
	_side_box.add_child(UiStyle.label(title, 18, UiStyle.HIGHLIGHT))
	_side.visible = true


func side_label(text: String, color: Color = UiStyle.BONE, size: int = 14) -> void:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	_side_box.add_child(l)


func side_button(text: String, callback: Callable, disabled: bool = false) -> void:
	_side_box.add_child(UiStyle.button(text, callback, disabled))


func side_row(buttons: Array) -> void:
	var row := HBoxContainer.new()
	for spec: Array in buttons:
		row.add_child(UiStyle.button(spec[0], spec[1], spec[2] if spec.size() > 2 else false))
	_side_box.add_child(row)


func side_hide() -> void:
	_side.visible = false
