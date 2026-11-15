class_name SimDevice
extends RefCounted
## One concrete piece of hardware owned by the player (an instance of a HardwareDefinition).

## Where the instance is: in_transit | package | inventory | placed | mounted | cabled | fixed
## (fixed = part of the starting scenario, e.g. the PC on the desk).
var location: StringName = &"inventory"
var id: int
var definition: HardwareDefinition
var position: Vector3 = Vector3.ZERO ## World position (metres) when placed / fixed.
var yaw_degrees: float = 0.0 ## Multiples of 90 for floor placement.
var rack_id: int = -1
var rack_u: int = 0 ## First (lowest) unit occupied, 1-based.
var power_switch_on: bool = true ## Only meaningful for devices with a power button.
var state: StringName = &"off" ## off | booting | running
var boot_left_minutes: float = 0.0
var host: SimHost = null


func _init(device_id: int, def: HardwareDefinition) -> void:
	id = device_id
	definition = def
	power_switch_on = not def.has_power_button
	var host_spec := def.get_spec(HostSpec) as HostSpec
	if host_spec != null:
		var lan := def.find_port_group(&"lan")
		host = SimHost.new(host_spec, device_id, lan.count if lan != null else 0)


func is_in_world() -> bool:
	return location in [&"placed", &"mounted", &"fixed"]


func is_running() -> bool:
	return state == &"running"


func display_name() -> String:
	return definition.display_name()


## All port references of this device, in definition order.
func port_refs() -> Array[String]:
	var refs: Array[String] = []
	for group: PortDefinition in definition.ports:
		for i: int in group.count:
			refs.append(PortRef.make(id, group.id, i))
	return refs
