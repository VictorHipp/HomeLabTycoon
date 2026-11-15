class_name TerminalView
extends VBoxContainer
## Terminal widget bound to a Shell session on a simulated host (docs/TERMINAL_DESIGN.md).
## Monospace system font (no downloaded fonts, decision 5 still open).

signal exit_requested

var world: SimWorld
var shell: Shell
var output: RichTextLabel
var input: LineEdit
var prompt_label: Label
var _history_index: int = -1


func setup(sim_world: SimWorld, device_id: int, user: String) -> void:
	world = sim_world
	shell = Shell.new(device_id, user)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var font := UiStyle.monospace_font()
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.panel(Color("#0F1216"), 6, 12))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	output = RichTextLabel.new()
	output.bbcode_enabled = false
	output.scroll_following = true
	output.selection_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_override("normal_font", font)
	output.add_theme_font_size_override("normal_font_size", 16)
	output.add_theme_color_override("default_color", UiStyle.MIST)
	column.add_child(output)
	var line := HBoxContainer.new()
	column.add_child(line)
	prompt_label = Label.new()
	prompt_label.add_theme_font_override("font", font)
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", UiStyle.OK)
	line.add_child(prompt_label)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 16)
	input.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	input.caret_blink = true
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_gui)
	line.add_child(input)
	var host := world.get_device(device_id).host
	output.add_text("%s — %s\n" % [host.os_name, host.hostname])
	output.add_text(TranslationServer.translate("Escribe «help» para ver las órdenes disponibles.") + "\n\n")
	_update_prompt()


func focus_input() -> void:
	input.grab_focus()


func run_line(text: String) -> void:
	_on_submit(text)


func _update_prompt() -> void:
	prompt_label.text = shell.prompt(world)


func _on_submit(text: String) -> void:
	output.add_text(shell.prompt(world) + text + "\n")
	input.clear()
	_history_index = -1
	var device := world.get_device(shell.device_id)
	if not device.is_running():
		output.add_text(TranslationServer.translate("El equipo está apagado: no responde.") + "\n")
		return
	var r := shell.run(world, text)
	if r["clear"]:
		output.clear()
	if r["output"] != "":
		output.add_text(r["output"] + "\n")
	_update_prompt()
	if r["exit"]:
		exit_requested.emit()


func _on_input_gui(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or shell.history.is_empty():
		return
	if key.keycode == KEY_UP:
		_history_index = shell.history.size() - 1 if _history_index < 0 else maxi(0, _history_index - 1)
	elif key.keycode == KEY_DOWN:
		if _history_index < 0:
			return
		_history_index += 1
		if _history_index >= shell.history.size():
			_history_index = -1
			input.text = ""
			accept_event()
			return
	else:
		return
	input.text = shell.history[_history_index]
	input.caret_column = input.text.length()
	accept_event()
