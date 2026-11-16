class_name GameSettings
extends RefCounted
## The player's settings (ADR 0015): display, camera feel and autosave. They belong to the
## machine, not to a game, so they live in user://settings.cfg and never in the save file.
## One table (SPECS) drives the file, the defaults and the "Ajustes" page of the menu.
## The walkthrough and the tests point `path` somewhere else, so the player's file is never
## touched, and the window is left alone when there is no real window to change.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"

## id, label, kind ("bool" | "choice"), default, [choices: [value, label]...], note.
const SPECS: Array[Dictionary] = [
	{"id": "fullscreen", "group": "Pantalla", "label": "Pantalla completa", "kind": "bool", "default": false,
		"note": "Sin bordes, a la resolución del escritorio."},
	{"id": "vsync", "group": "Pantalla", "label": "Sincronización vertical", "kind": "bool", "default": true,
		"note": "Evita los cortes en la imagen; limita los fotogramas a los del monitor."},
	{"id": "msaa", "group": "Pantalla", "label": "Suavizado de bordes", "kind": "choice", "default": 2,
		"choices": [[0, "Desactivado"], [1, "×2"], [2, "×4"], [3, "×8"]],
		"note": "Más suavizado = bordes más limpios y más trabajo para la tarjeta gráfica."},
	{"id": "show_fps", "group": "Pantalla", "label": "Mostrar fotogramas por segundo", "kind": "bool", "default": false,
		"note": "Un contador pequeño en la esquina inferior derecha."},
	{"id": "camera_sensitivity", "group": "Cámara", "label": "Sensibilidad al girar con el ratón", "kind": "choice", "default": 1.0,
		"choices": [[0.5, "Baja"], [0.75, "Media-baja"], [1.0, "Normal"], [1.5, "Alta"], [2.0, "Muy alta"]],
		"note": ""},
	{"id": "invert_x", "group": "Cámara", "label": "Invertir el giro horizontal", "kind": "bool", "default": false, "note": ""},
	{"id": "invert_y", "group": "Cámara", "label": "Invertir la inclinación", "kind": "bool", "default": false, "note": ""},
	{"id": "autosave_minutes", "group": "Partida", "label": "Autoguardado", "kind": "choice", "default": 5,
		"choices": [[0, "Desactivado"], [2, "Cada 2 minutos"], [5, "Cada 5 minutos"], [10, "Cada 10 minutos"]],
		"note": "Minutos reales de juego. Además se guarda al llegar un pedido, al completar una misión y al salir. Nunca sustituye a tu partida guardada."},
]

static var path: String = DEFAULT_PATH
## False where there is no real window to change (headless, walkthrough): the values are still
## kept and shown, but fullscreen and vsync are not applied.
static var apply_to_window: bool = true

static var _values: Dictionary = {}
static var _loaded: bool = false


static func spec(id: String) -> Dictionary:
	for s: Dictionary in SPECS:
		if s["id"] == id:
			return s
	return {}


static func value(id: String) -> Variant:
	_ensure_loaded()
	return _values.get(id, spec(id).get("default"))


## Sets, saves and returns the value really kept (an unknown id or value is refused).
static func set_value(id: String, new_value: Variant) -> Variant:
	_ensure_loaded()
	var s := spec(id)
	if s.is_empty():
		return null
	_values[id] = _valid(s, new_value)
	save()
	return _values[id]


## Next choice of a "choice" setting (wraps round), or the other value of a "bool".
static func cycle(id: String, step: int = 1) -> Variant:
	var s := spec(id)
	if s.is_empty():
		return null
	if s["kind"] == "bool":
		return set_value(id, not bool(value(id)))
	var choices: Array = s["choices"]
	var index := 0
	for i: int in choices.size():
		if is_equal_approx(float(choices[i][0]), float(value(id))):
			index = i
	return set_value(id, choices[posmod(index + step, choices.size())][0])


## The text of the current value ("Sí", "×4", "Cada 5 minutos").
static func value_label(id: String) -> String:
	var s := spec(id)
	if s.is_empty():
		return ""
	if s["kind"] == "bool":
		return TranslationServer.translate("Sí") if bool(value(id)) else TranslationServer.translate("No")
	for choice: Array in s["choices"]:
		if is_equal_approx(float(choice[0]), float(value(id))):
			return TranslationServer.translate(String(choice[1]))
	return str(value(id))


## Forgets what is in memory and reads `path` again (used when `path` changes).
static func read_file() -> void:
	_loaded = false
	_values = {}
	_ensure_loaded()


static func save() -> bool:
	var config := ConfigFile.new()
	for s: Dictionary in SPECS:
		config.set_value(SECTION, s["id"], _values.get(s["id"], s["default"]))
	return config.save(path) == OK


## Fullscreen and vsync (the window), where there is one to change.
static func apply_window() -> void:
	if not apply_to_window or DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value("fullscreen")) else DisplayServer.WINDOW_MODE_WINDOWED
	var current := DisplayServer.window_get_mode()
	var is_full := current in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if is_full != bool(value("fullscreen")):
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value("vsync")) else DisplayServer.VSYNC_DISABLED)


## Antialiasing of a 3D viewport (the game's and the character creator's preview).
static func apply_viewport(viewport: Viewport) -> void:
	viewport.msaa_3d = int(value("msaa")) as Viewport.MSAA


static func apply_camera(rig: OverviewCameraRig) -> void:
	rig.drag_sensitivity_deg = OverviewCameraRig.DEFAULT_DRAG_SENSITIVITY_DEG * float(value("camera_sensitivity"))
	rig.invert_drag_x = bool(value("invert_x"))
	rig.invert_drag_y = bool(value("invert_y"))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_values = {}
	var config := ConfigFile.new()
	var found := config.load(path) == OK
	for s: Dictionary in SPECS:
		var stored: Variant = config.get_value(SECTION, s["id"], s["default"]) if found else s["default"]
		_values[s["id"]] = _valid(s, stored)


## A value of the right kind and among the choices, or the default (a file edited by hand).
static func _valid(s: Dictionary, candidate: Variant) -> Variant:
	if s["kind"] == "bool":
		return candidate if candidate is bool else s["default"]
	if not (candidate is int or candidate is float):
		return s["default"]
	for choice: Array in s["choices"]:
		if is_equal_approx(float(choice[0]), float(candidate)):
			return choice[0]
	return s["default"]
