extends Node3D
## Temporary entry point (replaced by the first-mission game scene during Hito 1).

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	print("HomeLabTycoon boot OK | Godot %s" % Engine.get_version_info()["string"])
