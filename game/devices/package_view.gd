class_name PackageView
extends Node3D
## A delivered cardboard box (one per product). Clicking it walks there and opens it.

const MODEL := "res://assets/models/props/package_box.glb"

var package_id: int = -1


func setup(package: Dictionary) -> void:
	package_id = package["id"]
	name = "Package%d" % package_id
	var model := ModelUtil.instance_model(MODEL)
	add_child(model)
	position = package["position"]
	rotation_degrees.y = float((package_id * 37) % 30 - 15) # a bit of variety
	var body := ModelUtil.add_box_body(self, ModelUtil.local_aabb(model), Layers.DEVICES)
	body.set_meta("package_id", package_id)
