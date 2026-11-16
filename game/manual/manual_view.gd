class_name ManualView
extends VBoxContainer
## The game manual inside the menu: an index of chapters and pages with a picture (screenshot of
## the game) and step-by-step text, with Previous / Index / Next buttons.

var chapters: Array = []
var chapter: int = -1 ## -1 = index
var page: int = 0


func setup() -> void:
	chapters = ManualContent.load_chapters()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	show_index()


func show_index() -> void:
	chapter = -1
	_clear()
	add_child(UiStyle.label(TranslationServer.translate("Manual de HomeLab Tycoon"), 24, UiStyle.HIGHLIGHT))
	var intro := UiStyle.label(TranslationServer.translate("Todo lo que existe en esta versión del juego, paso a paso y con capturas. Elige un capítulo; dentro, usa «Siguiente» y «Anterior»."), 15, UiStyle.MIST)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	for i: int in chapters.size():
		var c: Dictionary = chapters[i]
		var b := UiStyle.button("%d. %s  (%d %s)" % [i + 1, c["title"], (c["pages"] as Array).size(),
			TranslationServer.translate("páginas") if (c["pages"] as Array).size() != 1 else TranslationServer.translate("página")], show_page.bind(i, 0))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)


func show_page(chapter_index: int, page_index: int) -> void:
	chapter = clampi(chapter_index, 0, chapters.size() - 1)
	var pages: Array = chapters[chapter]["pages"]
	page = clampi(page_index, 0, pages.size() - 1)
	var p: Dictionary = pages[page]
	_clear()
	add_child(UiStyle.label("%s %d · %s" % [TranslationServer.translate("Capítulo"), chapter + 1, chapters[chapter]["title"]], 14, UiStyle.MIST))
	add_child(UiStyle.label(p["title"], 22, UiStyle.HIGHLIGHT))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = load(p["image"]) as Texture2D if ResourceLoader.exists(p["image"]) else null
	picture.tooltip_text = p["alt"]
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.size_flags_stretch_ratio = 1.5
	body.add_child(picture)
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.text = p["text"]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_font_override("mono_font", UiStyle.monospace_font())
	text.add_theme_color_override("default_color", UiStyle.BONE)
	body.add_child(text)
	var footer := HBoxContainer.new()
	add_child(footer)
	footer.add_child(UiStyle.button(TranslationServer.translate("◀ Anterior"), previous, chapter == 0 and page == 0))
	footer.add_child(UiStyle.button(TranslationServer.translate("Índice"), show_index))
	footer.add_child(UiStyle.button(TranslationServer.translate("Siguiente ▶"), next, chapter == chapters.size() - 1 and page == pages.size() - 1))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(UiStyle.label(TranslationServer.translate("Página %d de %d") % [page + 1, pages.size()], 14, UiStyle.MIST))


func next() -> void:
	var pages: Array = chapters[chapter]["pages"]
	if page + 1 < pages.size():
		show_page(chapter, page + 1)
	elif chapter + 1 < chapters.size():
		show_page(chapter + 1, 0)


func previous() -> void:
	if page > 0:
		show_page(chapter, page - 1)
	elif chapter > 0:
		show_page(chapter - 1, (chapters[chapter - 1]["pages"] as Array).size() - 1)


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
