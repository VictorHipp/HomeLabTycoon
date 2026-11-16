class_name SimDevice
extends RefCounted
## One concrete piece of hardware owned by the player (an instance of a HardwareDefinition).

## Where the instance is: in_transit | package | inventory | placed | mounted | cabled | fixed | sold
## (fixed = part of the starting scenario, e.g. the PC on the desk; sold = sold second hand: kept
## so that old orders and the ledger can still name it).
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
## Installed or plugged in at least once: the second-hand market pays less for it (Economy).
var used: bool = false
## Bought in the shop (with its box). Only these can be sold second hand: what the house came
## with (PC, router, strip and their cables) was never paid for.
var bought: bool = false


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


## Serialisable state (docs/ARCHITECTURE.md §7). The definition is saved by catalog id.
func save_state() -> Dictionary:
	return {
		"id": id,
		"item": String(definition.id),
		"location": String(location),
		"position": [position.x, position.y, position.z],
		"yaw": yaw_degrees,
		"rack_id": rack_id,
		"rack_u": rack_u,
		"power_switch_on": power_switch_on,
		"state": String(state),
		"boot_left_minutes": boot_left_minutes,
		"host": host.save_state() if host != null else null,
		"used": used,
		"bought": bought,
	}


## Rebuilds a device from save_state() output (JSON numbers arrive as floats).
static func from_state(data: Dictionary, catalog: Catalog) -> SimDevice:
	var def := catalog.get_item(StringName(data["item"]))
	if def == null:
		push_error("SimDevice: unknown catalog item %s in save" % data["item"])
		return null
	var d := SimDevice.new(int(data["id"]), def)
	d.location = StringName(data["location"])
	var p: Array = data["position"]
	d.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	d.yaw_degrees = float(data["yaw"])
	d.rack_id = int(data["rack_id"])
	d.rack_u = int(data["rack_u"])
	d.power_switch_on = bool(data["power_switch_on"])
	d.state = StringName(data["state"])
	d.boot_left_minutes = float(data["boot_left_minutes"])
	# Saves of version 1 have no "used": anything in the room had been installed.
	d.used = bool(data.get("used", d.location in [&"placed", &"mounted", &"cabled", &"fixed"]))
	d.bought = bool(data.get("bought", false)) # version 1: SimWorld.load_state rebuilds it from the orders
	if d.host != null and data.get("host") is Dictionary:
		d.host.load_state(data["host"])
	return d


## All port references of this device, in definition order.
func port_refs() -> Array[String]:
	var refs: Array[String] = []
	for group: PortDefinition in definition.ports:
		for i: int in group.count:
			refs.append(PortRef.make(id, group.id, i))
	return refs
