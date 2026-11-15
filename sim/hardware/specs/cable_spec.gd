class_name CableSpec
extends Resource
## Capability: cable. Its two ends plug into ports whose kind matches `media`.

@export var media: StringName = &"copper" ## copper (RJ45 both ends) | power (C13 outlet <-> C14 inlet)
@export var length_m: float = 1.0
@export var max_speed_mbps: int = 1000 ## 0 for power cords.
