class_name PackageView
extends Node3D
## The stack of delivered boxes in the delivery zone (docs/INTERACTION_SYSTEM.md §7): up to
## three boxes are drawn on top of each other and a "×N" counter shows how many are really
## waiting. Each box keeps its own contents in the simulation; a click opens the top one.

const MODEL := "res://assets/models/props/package_box.glb"
const BOX_SIZE := Vector3(0.50, 0.34, 0.40)
const MAX_SHOWN := 3
const TWIST := [0.0, 9.0, -6.0]

var count: int = 0
var label: Label3D
var body: StaticBody3D
var _shape: BoxShape3D
var _boxes: Array[Node3D] = []


func setup() -> void:
	name = "DeliveryStack"
	for i: int in MAX_SHOWN:
		var box := ModelUtil.instance_model(MODEL)
		box.position = Vector3(0.0, i * BOX_SIZE.y, 0.0)
		box.rotation_degrees.y = TWIST[i]
		add_child(box)
		_boxes.append(box)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 40
	label.outline_size = 12
	label.modulate = UiStyle.MUSTARD
	label.outline_modulate = UiStyle.INK
	add_child(label)
	body = StaticBody3D.new()
	body.collision_layer = Layers.DEVICES
	body.collision_mask = 0
	body.set_meta("package_stack", true)
	var shape := CollisionShape3D.new()
	_shape = BoxShape3D.new()
	shape.shape = _shape
	body.add_child(shape)
	add_child(body)
	refresh(0, Vector3.ZERO)


## Shows `waiting` boxes at `spot`. Returns true if something that affects walking changed.
func refresh(waiting: int, spot: Vector3) -> bool:
	var changed := (waiting > 0) != (count > 0) or not global_position.is_equal_approx(spot) \
		or mini(waiting, MAX_SHOWN) != mini(count, MAX_SHOWN)
	count = waiting
	position = spot
	visible = waiting > 0
	body.collision_layer = Layers.DEVICES if waiting > 0 else 0
	var shown := mini(waiting, MAX_SHOWN)
	for i: int in _boxes.size():
		_boxes[i].visible = i < shown
	label.text = "×%d" % waiting
	label.position = Vector3(0.0, shown * BOX_SIZE.y + 0.18, 0.0)
	_shape.size = Vector3(BOX_SIZE.x, maxf(shown, 1) * BOX_SIZE.y, BOX_SIZE.z)
	(body.get_child(0) as CollisionShape3D).position = Vector3(0.0, _shape.size.y / 2.0, 0.0)
	return changed
