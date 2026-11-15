class_name HardwareDefinition
extends Resource
## Static, data-driven description of one piece of hardware (purchasable or part of the
## starting scenario). One `.tres` per item in res://data/catalog/ (file name = id).
## Optional capabilities live in `specs` (DeviceSpec subclasses): docs/HARDWARE_CATALOG.md §3.2.
## Gameplay code never hard-codes prices, sizes, ports or power figures.

@export var id: StringName = &"" ## Stable snake_case id; never renamed once saves exist.
@export var category: StringName = &"" ## Data category: rack, server, switch, router, computer, cable, power.
@export var brand: String = "" ## Fictional brand.
@export var model: String = ""
@export_multiline var description: String = ""
@export var price: int = 0 ## In-game credits (integer money).
@export var purchasable: bool = true ## false = only exists in starting scenarios.
@export var stage_unlock: int = 1

@export_group("Physical")
@export var placement: StringName = &"none" ## none | floor | desk | rack
@export var footprint_m: Vector2 = Vector2.ZERO ## Floor footprint (x width, z depth) in metres.
@export var mount_height_u: int = 0 ## Rack units occupied when mounted (1U = 44.45 mm).

@export_group("Power")
@export var power_idle_watts: float = 0.0
@export var power_max_watts: float = 0.0
@export var has_power_button: bool = false ## false = runs as soon as it has power.
@export var boot_minutes: float = 0.0 ## Game minutes from power-on to running.

@export_group("Connectivity")
@export var ports: Array[PortDefinition] = []

@export_group("Capabilities")
@export var specs: Array[Resource] = [] ## DeviceSpec subclasses (RackSpec, HostSpec, ...).
@export var box_contents: Array[StringName] = [] ## Extra catalog ids delivered in the same box.

@export_group("Presentation")
@export var model_path: String = "" ## res:// path of the .glb; loaded only by the presentation layer.


func display_name() -> String:
	return "%s %s" % [brand, model]


## Returns the first spec using the given script, or null.
func get_spec(spec_script: Script) -> Resource:
	for spec: Resource in specs:
		if spec != null and spec.get_script() == spec_script:
			return spec
	return null


func find_port_group(group_id: StringName) -> PortDefinition:
	for group: PortDefinition in ports:
		if group.id == group_id:
			return group
	return null
