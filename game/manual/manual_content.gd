class_name ManualContent
extends RefCounted
## The game manual (how to play), one restricted-Markdown file per chapter in data/manual/es/
## (file names sort the chapters). Format:
##   # Chapter title
##   ## Page title            (starts a page)
##   ![alt text](res://assets/manual/picture.png)   (the page picture, one per page)
##   paragraphs, "- " bullets, "1. " numbered steps, **bold**, `keys or commands`,
##   "> " a tip line
## The pictures are screenshots of the game taken by the walkthrough (scenario "manual").
## tests/unit/test_manual_content.gd checks that every picture exists and every page has text.

const DIR := "res://data/manual/es"


## [{"title", "file", "pages": [{"title", "image", "alt", "text" (BBCode)}]}]
static func load_chapters(dir_path: String = DIR) -> Array:
	var chapters: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return chapters
	var files: Array = Array(dir.get_files()).filter(func(f: String) -> bool: return f.get_extension() == "md")
	files.sort()
	for file: String in files:
		chapters.append(parse(FileAccess.get_file_as_string(dir_path.path_join(file)), file))
	return chapters


static func parse(text: String, file: String = "") -> Dictionary:
	var chapter := {"title": "", "file": file, "pages": []}
	var page: Dictionary = {}
	var lines: Array[String] = []
	for raw: String in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("## "):
			_close_page(chapter, page, lines)
			page = {"title": line.substr(3).strip_edges(), "image": "", "alt": ""}
			lines = []
		elif line.begins_with("# "):
			chapter["title"] = line.substr(2).strip_edges()
		elif line.begins_with("![") and line.contains("](") and line.ends_with(")"):
			page["alt"] = line.substr(2, line.find("](") - 2)
			page["image"] = line.substr(line.find("](") + 2, line.length() - line.find("](") - 3)
		elif not page.is_empty():
			lines.append(line)
	_close_page(chapter, page, lines)
	return chapter


static func _close_page(chapter: Dictionary, page: Dictionary, lines: Array[String]) -> void:
	if page.is_empty():
		return
	page["text"] = to_bbcode(lines)
	(chapter["pages"] as Array).append(page)


static func to_bbcode(lines: Array[String]) -> String:
	var out: Array[String] = []
	var paragraph: Array[String] = []
	for line: String in lines:
		var t := line.strip_edges()
		if t == "":
			_flush(out, paragraph)
			continue
		if t.begins_with("- "):
			_flush(out, paragraph)
			out.append("  •  " + _inline(t.substr(2)))
		elif t.length() > 2 and t[0].is_valid_int() and t.substr(1, 2) == ". ":
			_flush(out, paragraph)
			out.append("[color=#E0B34A][b]%s.[/b][/color] %s" % [t[0], _inline(t.substr(3))])
		elif t.begins_with("> "):
			_flush(out, paragraph)
			out.append("[color=#3CC8D8]%s[/color]" % _inline(t.substr(2)))
		else:
			paragraph.append(_inline(t))
	_flush(out, paragraph)
	return "\n".join(out)


static func _flush(out: Array[String], paragraph: Array[String]) -> void:
	if not paragraph.is_empty():
		out.append(" ".join(paragraph))
		out.append("")
		paragraph.clear()


## **bold** and `code` (keys, commands). Square brackets are escaped for BBCode.
static func _inline(text: String) -> String:
	var t := text.replace("[", "[lb]")
	var result := ""
	var bold := false
	var code := false
	var i := 0
	while i < t.length():
		if t.substr(i, 2) == "**":
			result += "[/b]" if bold else "[b]"
			bold = not bold
			i += 2
			continue
		if t[i] == "`":
			result += "[/code][/color]" if code else "[color=#EFE6D8][code]"
			code = not code
			i += 1
			continue
		result += t[i]
		i += 1
	return result
