class_name RackSpec
extends Resource
## Capability: rack with mounting units (EIA-310, docs/ART_STYLE.md §8).

@export var capacity_u: int = 12
@export var depth_m: float = 0.6
## Height of the bottom of U1 above the floor (matches the RACK_U1 marker of the model).
@export var first_unit_height_m: float = 0.075
