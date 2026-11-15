class_name PowerStripSpec
extends Resource
## Capability: distributes power through its outlet ports (kind POWER_C13).
## Prototype simplification: always plugged into the wall, no capacity limit
## (circuit capacity and UPS come in stage 2, docs/NETWORK_SIMULATION.md §3).

@export var wall_connected: bool = true
