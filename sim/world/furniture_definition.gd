class_name FurnitureDefinition
extends Resource
## A piece of furniture of a room (docs/INTERACTION_SYSTEM.md §8.2): the floor it takes, what
## stands on the floor in the way of a cable, its top and the models that show it.
## Every rect is local to the piece origin, (x, z) at yaw 0, and turns with the piece in steps
## of 90°. The player can move it (SimWorld.move_furniture).

@export var id: StringName = &"" ## Stable snake_case id; never renamed once saves exist.
@export var name_text: String = "" ## Shown to the player (translated with tr()).
## Floor nothing else can use: other furniture, devices, boxes. The character walks around it.
@export var blocks: Array[Rect2] = []
## What stands on the floor for a cable (legs, drawers, a chair base...): cables go around it.
@export var cable_parts: Array[Rect2] = []
## Whole outline: it must stay inside the room. A rug has only this (nothing blocks on it).
@export var area: Rect2 = Rect2()
@export_group("Top")
@export var top: Rect2 = Rect2() ## Where small devices can stand (empty = no usable top).
@export var top_height: float = 0.0 ## Metres above the floor.
@export var top_reserved: Array[Rect2] = [] ## Parts of the top already taken (monitor, keyboard).
@export_group("Presentation")
@export var model_path: String = "" ## res:// path of the main model; loaded only by the presentation.
## Extra models that move with it: {"role": String, "model": res:// path, "offset": Vector3,
## "yaw": float}. Roles the presentation knows: chair, monitor, keyboard.
@export var parts: Array[Dictionary] = []


func display_name() -> String:
	return tr(name_text)
