class_name ClickFeedback
extends CanvasLayer
## Makes every click noticeable (asked by the player): a ring grows and fades where a mouse button
## was pressed, over the 3D view and over every interface, also in menus and while paused. If the
## click did nothing useful (a failure message right after it), the ring turns red with a cross.
## In the world, the object or floor that was clicked also reacts (flash_node, GameSession).

const LIFE := 0.38 ## Seconds a ring lives.
const START_RADIUS := 5.0
const END_RADIUS := 24.0
const REJECT_WINDOW_MS := 450 ## A failure reported this soon after a click belongs to it.
const FLASH_SECONDS := 0.3

var _canvas: Control
var _rings: Array[Dictionary] = [] ## {"pos": Vector2, "t": float, "color": Color, "bad": bool}
var _last_click_ms: int = -100000
var _flash_material: StandardMaterial3D


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_rings)
	add_child(_canvas)


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if not (button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
		return
	var color := UiStyle.HIGHLIGHT if button.button_index == MOUSE_BUTTON_LEFT else UiStyle.MIST
	_rings.append({"pos": button.position, "t": 0.0, "color": color, "bad": false})
	_last_click_ms = Time.get_ticks_msec()


## The last click did nothing useful: its ring turns red and shows a cross.
func reject() -> void:
	if _rings.is_empty() or Time.get_ticks_msec() - _last_click_ms > REJECT_WINDOW_MS:
		return
	var ring: Dictionary = _rings[_rings.size() - 1]
	ring["color"] = UiStyle.BAD
	ring["bad"] = true
	ring["t"] = minf(float(ring["t"]), LIFE * 0.3) # a little longer, so it is seen


## Number of rings on screen (for the automated walkthrough).
func ring_count() -> int:
	return _rings.size()


func last_ring_rejected() -> bool:
	return not _rings.is_empty() and bool(_rings[_rings.size() - 1]["bad"])


func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	for ring: Dictionary in _rings:
		ring["t"] = float(ring["t"]) + delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["t"]) < LIFE * (1.6 if r["bad"] else 1.0))
	_canvas.queue_redraw()


func _draw_rings() -> void:
	for ring: Dictionary in _rings:
		var life := LIFE * (1.6 if ring["bad"] else 1.0)
		var k := clampf(float(ring["t"]) / life, 0.0, 1.0)
		var radius := lerpf(START_RADIUS, END_RADIUS, 1.0 - pow(1.0 - k, 3.0))
		var color := Color(ring["color"] as Color, 1.0 - k)
		var pos: Vector2 = ring["pos"]
		_canvas.draw_arc(pos, radius, 0.0, TAU, 40, Color(UiStyle.INK, color.a * 0.6), 5.0, true)
		_canvas.draw_arc(pos, radius, 0.0, TAU, 40, color, 2.5, true)
		_canvas.draw_circle(pos, 3.0 * (1.0 - k), color)
		if ring["bad"]:
			var s := 7.0
			_canvas.draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), color, 3.0, true)
			_canvas.draw_line(pos + Vector2(-s, s), pos + Vector2(s, -s), color, 3.0, true)


## Brief glow on an object of the world that was clicked (its meshes get a fading overlay).
func flash_node(node: Node3D) -> void:
	if node == null:
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = Color(UiStyle.HIGHLIGHT, 0.0)
	var material := _flash_material.duplicate() as StandardMaterial3D
	var meshes := ModelUtil.find_meshes_with_prefix(node, "")
	for mesh: MeshInstance3D in meshes:
		if mesh.material_overlay == null:
			mesh.material_overlay = material
	var tween := create_tween()
	tween.tween_method(func(a: float) -> void: material.albedo_color = Color(UiStyle.HIGHLIGHT, a), 0.45, 0.0, FLASH_SECONDS)
	tween.tween_callback(func() -> void:
		for mesh: MeshInstance3D in meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == material:
				mesh.material_overlay = null)
