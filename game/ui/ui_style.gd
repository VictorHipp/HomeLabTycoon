class_name UiStyle
extends RefCounted
## Shared look of the game UI ("Taller luminoso", docs/ART_STYLE.md §4 and §9).

const INK := Color("#1E2430")
const GRAPHITE := Color("#2E3440")
const BONE := Color("#EFE6D8")
const MIST := Color("#C9D1D9")
const HIGHLIGHT := Color("#3CC8D8")
const OK := Color("#4ADE80")
const WARN := Color("#F5A524")
const BAD := Color("#EF4444")
const MUSTARD := Color("#E0B34A")


static func panel(bg: Color = Color(INK, 0.92), radius: int = 8, margin: int = 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


static func label(text: String, size: int = 15, color: Color = BONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


static func monospace_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return font
