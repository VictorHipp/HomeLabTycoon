class_name SimHost
extends RefCounted
## Simulated operating system of one device (docs/TERMINAL_DESIGN.md §3).
## Prototype subset: identity and IPv4 networking (interfaces, addresses, default route).
## Files, users, processes, services and packages come in later milestones.

## One network interface bound to a physical port of the device.
class Interface:
	var name: String
	var port_group: StringName
	var port_index: int
	var admin_up: bool = true
	var mac: String
	## Each entry: {"ip": int, "prefix": int, "dynamic": bool}
	var addresses: Array[Dictionary] = []

	func first_address() -> Dictionary:
		return addresses[0] if not addresses.is_empty() else {}


var hostname: String
var os_name: String
var login_user: String
var eth0_mode: StringName
var interfaces: Array[Interface] = []
var default_gateway: int = -1 ## -1 = no default route.
var default_gateway_dynamic: bool = false


func _init(spec: HostSpec, device_id: int, lan_ports: int) -> void:
	hostname = spec.hostname
	os_name = spec.os_name
	login_user = spec.login_user
	eth0_mode = spec.eth0_mode
	for i: int in lan_ports:
		var iface := Interface.new()
		iface.name = "eth%d" % i
		iface.port_group = &"lan"
		iface.port_index = i
		# Locally administered MAC (bit 0x02 of the first octet), deterministic per device.
		iface.mac = "02:00:00:%02x:%02x:%02x" % [(device_id >> 8) & 255, device_id & 255, i + 1]
		interfaces.append(iface)


func find_interface(iface_name: String) -> Interface:
	for iface: Interface in interfaces:
		if iface.name == iface_name:
			return iface
	return null


## Power loss / reboot: runtime configuration made with `ip` is lost (decision 9).
func reset_runtime() -> void:
	for iface: Interface in interfaces:
		iface.addresses.clear()
		iface.admin_up = true
	default_gateway = -1
	default_gateway_dynamic = false
