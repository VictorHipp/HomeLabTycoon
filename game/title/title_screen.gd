class_name TitleScreen
extends CanvasLayer
## Title screen (game/main/main.gd): continue the most recent game (the player's save or the
## autosave), new game (through the character creator), load the player's save, manual and
## settings (the in-game menu without a game) and quit. "Continuar" and "Cargar partida" say
## what they hold, or why they cannot be used.

var creator: CharacterCreator = null
var menu: GameMenu
var continue_button: Button
var continue_note: Label
var load_button: Button
var load_note: Label
var _root: Control
var _menu: Control


func _ready() -> void:
	# On a canvas layer, so the screen fills the window (the launcher above is a plain Node).
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("#141A22")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_menu = _build_menu()
	_root.add_child(_menu)
	menu = GameMenu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.setup(null)
	var click_fx := ClickFeedback.new() # the same ring under every click as in the game
	click_fx.name = "ClickFeedback"
	add_child(click_fx)


func _build_menu() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#1E2430"), 14, 28))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiStyle.label("HomeLab Tycoon", 40, UiStyle.HIGHLIGHT))
	var tagline := UiStyle.label(TranslationServer.translate("Empieza en tu habitación con un ordenador viejo y monta tu primer laboratorio."), 16, UiStyle.MIST)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tagline)
	box.add_child(HSeparator.new())
	continue_button = UiStyle.button(TranslationServer.translate("Continuar"), _continue)
	continue_button.name = "Continue"
	box.add_child(continue_button)
	continue_note = UiStyle.label("", 14, UiStyle.OK)
	continue_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(continue_note)
	var new_button := UiStyle.button(TranslationServer.translate("Nueva partida"), open_creator)
	new_button.name = "NewGame"
	box.add_child(new_button)
	load_button = UiStyle.button(TranslationServer.translate("Cargar partida"), _load)
	load_button.name = "LoadGame"
	box.add_child(load_button)
	load_note = UiStyle.label("", 14, UiStyle.MIST)
	load_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(load_note)
	var options := UiStyle.button(TranslationServer.translate("Manual y ajustes"), func() -> void: menu.open(&"settings"))
	options.name = "Options"
	box.add_child(options)
	var quit := UiStyle.button(TranslationServer.translate("Salir del juego"), func() -> void: get_tree().quit())
	quit.name = "Quit"
	box.add_child(quit)
	_refresh_load()
	return center


func _refresh_load() -> void:
	# "Continuar": only when there is something to continue (a first-time player does not see it).
	var latest := SaveService.read_latest()
	continue_button.visible = latest["ok"]
	continue_note.visible = latest["ok"]
	if latest["ok"]:
		continue_note.text = (TranslationServer.translate("Autoguardado: %s") if latest["auto"] else TranslationServer.translate("Tu partida guardada: %s")) % SaveService.describe(latest["document"])
	var r := SaveService.read() if SaveService.has_save() else {"ok": false, "message": TranslationServer.translate("No hay ninguna partida guardada."), "from_backup": false}
	load_button.disabled = not r["ok"]
	if not r["ok"]:
		load_note.text = String(r["message"])
		load_note.add_theme_color_override("font_color", UiStyle.MIST)
		return
	load_note.text = TranslationServer.translate("Partida guardada: %s") % SaveService.describe(r["document"])
	if r["from_backup"]:
		load_note.text += "\n" + String(r["message"])
	load_note.add_theme_color_override("font_color", UiStyle.WARN if r["from_backup"] else UiStyle.OK)


## Shows the character creator; "Volver" comes back here.
func open_creator() -> void:
	_menu.visible = false
	creator = CharacterCreator.new()
	creator.name = "Creator"
	_root.add_child(creator)
	creator.back_requested.connect(_close_creator)
	creator.start_requested.connect(func(look: Dictionary) -> void: GameLauncher.start_new_game(get_tree(), look))


func _close_creator() -> void:
	if creator != null:
		creator.queue_free()
		creator = null
	_menu.visible = true


func _continue() -> void:
	var r := GameLauncher.continue_game(get_tree())
	continue_note.text = String(r["message"])


func _load() -> void:
	var r := GameLauncher.load_saved_game(get_tree())
	load_note.text = String(r["message"])
