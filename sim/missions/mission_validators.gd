class_name MissionValidators
extends RefCounted
## Validators: read-only queries on the world (docs/PROGRESSION.md §6). They never look at
## which actions the player took, so any working solution passes.


static func check(world: SimWorld, validator: StringName, params: Dictionary) -> bool:
	match validator:
		&"device_placed":
			return _any(world, params["category"], func(d: SimDevice) -> bool: return d.location == &"placed")
		&"device_mounted":
			return _any(world, params["category"], func(d: SimDevice) -> bool: return d.location == &"mounted")
		&"devices_running":
			for category: String in params["categories"]:
				if not _any(world, StringName(category), func(d: SimDevice) -> bool: return d.is_running()):
					return false
			return true
		&"cabled_to":
			return _cabled_to(world, StringName(params["a"]), StringName(params["b"]))
		&"uplink_to_router":
			return _uplink_to_router(world, StringName(params["category"]))
		&"ip_in_subnet":
			return _ip_in_subnet(world, StringName(params["category"]), String(params["subnet"]))
		&"reachable_both":
			return _reachable_both(world, StringName(params["a"]), StringName(params["b"]))
	push_error("MissionValidators: unknown validator %s" % validator)
	return false


static func _any(world: SimWorld, category: Variant, predicate: Callable) -> bool:
	for d: SimDevice in world.devices_of(StringName(category)):
		if predicate.call(d):
			return true
	return false


static func _cabled_to(world: SimWorld, cat_a: StringName, cat_b: StringName) -> bool:
	for cable_id: int in world.cable_ends:
		var ends: Dictionary = world.cable_ends[cable_id]
		var spec := world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		if ends["b"] == "" or spec.media != &"copper":
			continue
		var ca := world.get_device(PortRef.device_id(ends["a"])).definition.category
		var cb := world.get_device(PortRef.device_id(ends["b"])).definition.category
		if (ca == cat_a and cb == cat_b) or (ca == cat_b and cb == cat_a):
			return true
	return false


static func _uplink_to_router(world: SimWorld, category: StringName) -> bool:
	var parent := NetworkEngine.domains(world)
	var router_domains: Array[String] = []
	for ep: Dictionary in NetworkEngine.endpoints(world, parent):
		if ep["router"] and ep["domain"] != "":
			router_domains.append(ep["domain"])
	for d: SimDevice in world.devices_of(category):
		for ref: String in d.port_refs():
			var dom := NetworkEngine.domain_of(world, parent, ref)
			if dom != "" and router_domains.has(dom):
				return true
	return false


static func _ip_in_subnet(world: SimWorld, category: StringName, subnet: String) -> bool:
	var cidr := IPv4.parse_cidr(subnet)
	var conflicts := NetworkEngine.ip_conflicts(world)
	for d: SimDevice in world.devices_of(category):
		for ip: int in NetworkEngine.device_ips(world, d):
			var is_host_address := ip != IPv4.network(ip, cidr[1]) and ip != IPv4.broadcast(ip, cidr[1])
			if IPv4.in_subnet(ip, cidr[0], cidr[1]) and is_host_address and not conflicts.has(ip):
				return true
	return false


static func _reachable_both(world: SimWorld, cat_a: StringName, cat_b: StringName) -> bool:
	for a: SimDevice in world.devices_of(cat_a):
		for b: SimDevice in world.devices_of(cat_b):
			if NetworkEngine.reachable(world, a, b) and NetworkEngine.reachable(world, b, a):
				return true
	return false
