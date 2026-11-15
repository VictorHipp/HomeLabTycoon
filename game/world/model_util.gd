class_name ModelUtil
extends RefCounted
## Helpers to use the imported .glb models: instancing, bounds, markers and box colliders.


static func instance_model(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("ModelUtil: cannot load %s" % path)
		return Node3D.new()
	return packed.instantiate() as Node3D


## Bounding box of all meshes, in the local space of `root` (works before entering the tree).
## The root's own transform is NOT applied (colliders are added as children of `root`).
static func local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for entry: Array in _walk(root, root.transform.affine_inverse()):
		var mesh := entry[0] as MeshInstance3D
		if mesh == null or not mesh.visible:
			continue
		var box: AABB = (entry[1] as Transform3D) * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Transform of a named marker relative to `root` (root transform not applied); found = false if absent.
static func marker_transform(root: Node3D, marker_name: String) -> Dictionary:
	for entry: Array in _walk(root, root.transform.affine_inverse()):
		if (entry[0] as Node).name == marker_name:
			return {"found": true, "transform": entry[1]}
	return {"found": false, "transform": Transform3D.IDENTITY}


static func find_meshes_with_prefix(root: Node, prefix: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry: Array in _walk(root, Transform3D.IDENTITY):
		var mesh := entry[0] as MeshInstance3D
		if mesh != null and String(mesh.name).begins_with(prefix):
			result.append(mesh)
	return result


## Adds a StaticBody3D with one box shape covering `box` (local to `parent`).
static func add_box_body(parent: Node3D, box: AABB, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size.max(Vector3(0.02, 0.02, 0.02))
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	parent.add_child(body)
	return body


## Adds one StaticBody3D with a box per visible mesh of `model` (its parts: desktop, legs,
## drawers...), so the solid shape follows the object instead of one big box around it.
static func add_part_bodies(model: Node3D, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	for entry: Array in _walk(model, model.transform.affine_inverse()):
		var mesh := entry[0] as MeshInstance3D
		if mesh == null or not mesh.visible:
			continue
		var box: AABB = (entry[1] as Transform3D) * mesh.get_aabb()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size.max(Vector3(0.01, 0.01, 0.01))
		shape.shape = box_shape
		shape.position = box.get_center()
		body.add_child(shape)
	model.add_child(body)
	return body


static func _walk(node: Node, parent_xf: Transform3D) -> Array:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var result: Array = [[node, xf]]
	for child: Node in node.get_children():
		result.append_array(_walk(child, xf))
	return result
