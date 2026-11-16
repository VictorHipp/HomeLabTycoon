class_name SimFurniture
extends RefCounted
## One piece of furniture in the room (an instance of a FurnitureDefinition): where it stands.
## Devices standing on it or belonging to it (SimDevice.furniture_id) move with it.

var id: StringName ## Instance id in the room (e.g. &"desk"); stable, used by saves.
var definition: FurnitureDefinition
var position: Vector3 = Vector3.ZERO ## Floor point of its origin (y = 0).
var yaw_degrees: float = 0.0 ## Multiples of 90.


func _init(instance_id: StringName, def: FurnitureDefinition, pos: Vector3, yaw: float) -> void:
	id = instance_id
	definition = def
	position = pos
	yaw_degrees = yaw


func display_name() -> String:
	return definition.display_name()


## A local rect (x, z) of the definition in the room, with the piece at `pos` turned `yaw`.
static func place_rect(local: Rect2, pos: Vector3, yaw: float) -> Rect2:
	var steps := posmod(roundi(yaw / 90.0), 4)
	if steps == 0:
		return Rect2(local.position + Vector2(pos.x, pos.z), local.size)
	var a := Vector3(local.position.x, 0.0, local.position.y).rotated(Vector3.UP, steps * PI / 2.0)
	var b := Vector3(local.end.x, 0.0, local.end.y).rotated(Vector3.UP, steps * PI / 2.0)
	var rect := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z))
	rect.position += Vector2(pos.x, pos.z)
	return rect


## A local point of the definition in the room (y kept: heights do not turn).
static func place_point(local: Vector3, pos: Vector3, yaw: float) -> Vector3:
	return pos + local.rotated(Vector3.UP, deg_to_rad(round(yaw / 90.0) * 90.0))


func rects(local_rects: Array[Rect2], pos: Vector3 = position, yaw: float = yaw_degrees) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for local: Rect2 in local_rects:
		result.append(place_rect(local, pos, yaw))
	return result


func rect(local: Rect2, pos: Vector3 = position, yaw: float = yaw_degrees) -> Rect2:
	return place_rect(local, pos, yaw)


## Where a world point that moves with this piece goes when the piece goes to (pos, yaw).
func carry(world_point: Vector3, pos: Vector3, yaw: float) -> Vector3:
	var local := (world_point - position).rotated(Vector3.UP, -deg_to_rad(yaw_degrees))
	var p := place_point(local, pos, yaw)
	return Vector3(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001))


func save_state() -> Dictionary:
	return {"id": String(id), "position": [position.x, position.y, position.z], "yaw": yaw_degrees}
