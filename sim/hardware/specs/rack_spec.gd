class_name RackSpec
extends Resource
## Capability: rack with mounting units (EIA-310, docs/ART_STYLE.md §8).

@export var capacity_u: int = 12
@export var depth_m: float = 0.6
## Height of the bottom of U1 above the floor (matches the RACK_U1 marker of the model).
@export var first_unit_height_m: float = 0.075
## Free floor needed in front of and behind the rack to work on it (game rule: the player must
## reach the front to mount and the rear to cable; docs/INTERACTION_SYSTEM.md §8.1).
@export var service_clearance_m: float = 0.5
