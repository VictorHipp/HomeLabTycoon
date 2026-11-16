class_name HoverTip
extends CanvasLayer
## Small label by the cursor in the overview: the name of what is under it and what each mouse
## button does there (InteractionManager decides the text). It hides by itself when the cursor
## goes over the interface, when the game is paused or when `still_valid` says no.

const OFFSET := Vector2(18, 20)

var still_valid: Callable = Callable()
var title_text: String = "" ## What is shown now ("" = hidden); read by the walkthrough.
var _panel: PanelContainer
var _title: Label
var _actions: Label


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var style := UiStyle.panel(Color(UiStyle.INK, 0.94), 6, 8)
	style.border_color = Color(UiStyle.HIGHLIGHT, 0.55)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_title = UiStyle.label("", 15, UiStyle.BONE)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)
	_actions = UiStyle.label("", 13, UiStyle.MIST)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_actions)


## Shows `title` and one line per action next to `screen_pos`, kept inside the window.
func show_tip(screen_pos: Vector2, title: String, actions: PackedStringArray) -> void:
	title_text = title
	_title.text = title
	_actions.text = "\n".join(actions)
	_actions.visible = not actions.is_empty()
	_panel.visible = true
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	var window := _panel.get_viewport_rect().size
	var pos := screen_pos + OFFSET
	if pos.x + size.x > window.x - 4.0:
		pos.x = screen_pos.x - OFFSET.x - size.x
	if pos.y + size.y > window.y - 4.0:
		pos.y = screen_pos.y - OFFSET.y - size.y
	_panel.position = pos.max(Vector2(4.0, 4.0))


func hide_tip() -> void:
	title_text = ""
	if _panel != null:
		_panel.visible = false


func is_shown() -> bool:
	return _panel != null and _panel.visible


func _process(_delta: float) -> void:
	if not is_shown():
		return
	if get_tree().paused or get_viewport().gui_get_hovered_control() != null \
			or (still_valid.is_valid() and not still_valid.call()):
		hide_tip()
