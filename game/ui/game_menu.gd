class_name GameMenu
extends CanvasLayer
## In-game menu (pauses the game): Continue, Manual, Controls (Settings), Save, Load and back to
## the title screen.
## Opened with Esc in the overview, the "Menú" buttons of the HUD and of the computer screen,
## and F1 for the manual. Works while the game is paused (process mode ALWAYS).

var session: GameSession
var current: StringName = &""
var manual: ManualView
var _content: VBoxContainer
var _status: Label
var _load_button: Button
var _title_button: Button
var _title_armed: bool = false ## The first press warns; the second one leaves.


func setup(game: GameSession) -> void:
	session = game
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.06, 0.08, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		panel.set("offset_" + side, 36 if side in ["left", "top"] else -36)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#18202A"), 12, 18))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(210, 0)
	nav.add_theme_constant_override("separation", 8)
	row.add_child(nav)
	nav.add_child(UiStyle.label("HomeLab Tycoon", 22, UiStyle.HIGHLIGHT))
	nav.add_child(UiStyle.label(TranslationServer.translate("Juego en pausa"), 14, UiStyle.MIST))
	nav.add_child(UiStyle.button(TranslationServer.translate("Continuar (Esc)"), close))
	nav.add_child(UiStyle.button(TranslationServer.translate("Manual (F1)"), show_page.bind(&"manual")))
	nav.add_child(UiStyle.label(TranslationServer.translate("Ajustes"), 14, UiStyle.MIST))
	nav.add_child(UiStyle.button(TranslationServer.translate("Controles"), show_page.bind(&"controls")))
	nav.add_child(UiStyle.label(TranslationServer.translate("Partida"), 14, UiStyle.MIST))
	nav.add_child(UiStyle.button(TranslationServer.translate("Guardar partida"), _save))
	_load_button = UiStyle.button(TranslationServer.translate("Cargar partida"), _load)
	nav.add_child(_load_button)
	_title_button = UiStyle.button(TranslationServer.translate("Volver al menú principal"), _to_title)
	_title_button.name = "ToTitle"
	nav.add_child(_title_button)
	_status = UiStyle.label("", 14, UiStyle.OK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(200, 0)
	nav.add_child(_status)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_content)


func open(page: StringName = &"controls") -> void:
	visible = true
	get_tree().paused = true
	_status.text = ""
	_title_armed = false
	_load_button.disabled = not SaveService.has_save()
	show_page(page)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"open_manual"):
		get_viewport().set_input_as_handled()
		if visible and current == &"manual":
			close()
		elif visible:
			show_page(&"manual")
		else:
			open(&"manual")
	elif visible and event.is_action_pressed(&"close_interaction"):
		get_viewport().set_input_as_handled()
		close()


func show_page(page: StringName) -> void:
	current = page
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match page:
		&"manual":
			manual = ManualView.new()
			_content.add_child(manual)
			manual.setup()
		&"controls":
			_build_controls()


func _build_controls() -> void:
	_content.add_child(UiStyle.label(TranslationServer.translate("Ajustes · Controles"), 24, UiStyle.HIGHLIGHT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for group: Array in ControlsReference.groups():
		list.add_child(UiStyle.label(group[0], 18, UiStyle.MUSTARD))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		list.add_child(grid)
		for row: Array in group[1]:
			var what := UiStyle.label(row[0], 15)
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.custom_minimum_size = Vector2(420, 0)
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(what)
			var keys := RichTextLabel.new()
			keys.bbcode_enabled = true
			keys.fit_content = true
			keys.scroll_active = false
			keys.custom_minimum_size = Vector2(360, 0)
			keys.add_theme_color_override("default_color", UiStyle.HIGHLIGHT)
			keys.text = ("[i]%s[/i]" if row[2] else "[b]%s[/b]") % row[1]
			grid.add_child(keys)
		list.add_child(Control.new())
	var note := UiStyle.label(TranslationServer.translate(ControlsReference.NOT_REMAPPABLE), 13, UiStyle.MIST)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)


func _save() -> void:
	var r := session.save_game()
	_status.text = r["message"]
	_status.add_theme_color_override("font_color", UiStyle.OK if r["ok"] else UiStyle.BAD)
	_load_button.disabled = not SaveService.has_save()


## Back to the title screen. What was not saved is lost: the first press says so.
func _to_title() -> void:
	if not _title_armed:
		_title_armed = true
		_status.text = TranslationServer.translate("Lo que no hayas guardado se perderá. Pulsa otra vez «Volver al menú principal» para salir.")
		_status.add_theme_color_override("font_color", UiStyle.WARN)
		return
	GameLauncher.back_to_title(get_tree())


func _load() -> void:
	var r := session.load_game()
	_status.text = r["message"]
	_status.add_theme_color_override("font_color", UiStyle.OK if r["ok"] else UiStyle.BAD)
