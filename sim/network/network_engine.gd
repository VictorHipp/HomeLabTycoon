class_name NetworkEngine
extends RefCounted
## Analytic network resolution (decision 2, ADR 0008, docs/NETWORK_SIMULATION.md §2):
## the physical/config state lives in SimWorld; this class answers questions about it
## (link state, broadcast domains, DHCP, ping) by walking the topology. No per-packet simulation.
## Stateless: every function receives the world.

const PUBLIC_TEST_IP := "198.51.100.7" ## Documentation range used as "a host on the Internet".


# ------------------------------------------------------------------- links --

## {"has_cable", "power", "up", "speed", "reason", "peer"} for one port.
static func port_link(world: SimWorld, port_ref: String) -> Dictionary:
	var result := {"has_cable": false, "power": false, "up": false, "speed": 0, "reason": "", "peer": ""}
	if not world.port_cable.has(port_ref):
		result["reason"] = TranslationServer.translate("No hay ningún cable conectado.")
		return result
	result["has_cable"] = true
	var cable := world.get_device(world.port_cable[port_ref])
	var spec := cable.definition.get_spec(CableSpec) as CableSpec
	var peer := world.cable_peer(port_ref)
	result["peer"] = peer
	if spec.media == &"power":
		result["power"] = true
		return result
	if peer == "":
		result["reason"] = TranslationServer.translate("El otro extremo del cable está suelto.")
		return result
	var local := world.get_device(PortRef.device_id(port_ref))
	var remote := world.get_device(PortRef.device_id(peer))
	for d: SimDevice in [local, remote]:
		if not d.is_running():
			result["reason"] = TranslationServer.translate("%s está apagado.") % d.display_name() \
				if d.state == &"off" else TranslationServer.translate("%s está arrancando.") % d.display_name()
			return result
	var local_group := local.definition.find_port_group(PortRef.group(port_ref))
	var remote_group := remote.definition.find_port_group(PortRef.group(peer))
	result["up"] = true
	result["speed"] = mini(mini(local_group.speed_mbps, remote_group.speed_mbps), spec.max_speed_mbps)
	return result


# --------------------------------------------------- broadcast domains (L2) --

## Union-find over ports: active copper links join their two ends; a running switch
## (or the LAN side of a router) joins all the ports of its switching group.
static func domains(world: SimWorld) -> Dictionary:
	var parent := {}
	for cable_id: int in world.cable_ends:
		var ends: Dictionary = world.cable_ends[cable_id]
		if ends["b"] == "":
			continue
		var link := port_link(world, ends["a"])
		if link["up"]:
			_union(parent, ends["a"], ends["b"])
	for d: SimDevice in world.devices.values():
		var sw := d.definition.get_spec(SwitchSpec) as SwitchSpec
		if sw == null or not d.is_running():
			continue
		var group := d.definition.find_port_group(sw.port_group)
		var first := ""
		for i: int in group.count:
			var ref := PortRef.make(d.id, group.id, i)
			if not world.port_cable.has(ref):
				continue
			if first == "":
				first = ref
				_find(parent, ref)
			else:
				_union(parent, first, ref)
	return parent


## Domain id of a port with an active link, or "" if the port has no active link.
static func domain_of(world: SimWorld, parent: Dictionary, port_ref: String) -> String:
	if not parent.has(port_ref) or not port_link(world, port_ref)["up"]:
		return ""
	return _find(parent, port_ref)


static func _find(parent: Dictionary, x: String) -> String:
	if not parent.has(x):
		parent[x] = x
	var root := x
	while parent[root] != root:
		root = parent[root]
	while parent[x] != root:
		var next: String = parent[x]
		parent[x] = root
		x = next
	return root


static func _union(parent: Dictionary, a: String, b: String) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


# --------------------------------------------------------------- endpoints --

## Every IPv4 address that can answer on the LAN:
## {"device_id", "ip", "prefix", "iface", "domain", "router"}.
static func endpoints(world: SimWorld, parent: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = world.devices.keys()
	ids.sort()
	for device_id: int in ids:
		var d := world.get_device(device_id)
		if not d.is_running():
			continue
		if d.host != null:
			for iface: SimHost.Interface in d.host.interfaces:
				if not iface.admin_up:
					continue
				var dom := domain_of(world, parent, PortRef.make(d.id, iface.port_group, iface.port_index))
				for addr: Dictionary in iface.addresses:
					result.append({"device_id": d.id, "ip": addr["ip"], "prefix": addr["prefix"],
						"iface": iface.name, "domain": dom, "router": false})
		var router := d.definition.get_spec(RouterSpec) as RouterSpec
		if router != null:
			var cidr := IPv4.parse_cidr(router.lan_address)
			var dom := ""
			var lan := d.definition.find_port_group(&"lan")
			for i: int in lan.count:
				dom = domain_of(world, parent, PortRef.make(d.id, &"lan", i))
				if dom != "":
					break
			result.append({"device_id": d.id, "ip": cidr[0], "prefix": cidr[1], "iface": "br-lan",
				"domain": dom, "router": true})
	return result


static func device_ips(world: SimWorld, d: SimDevice) -> Array[int]:
	var ips: Array[int] = []
	if d.host != null:
		for iface: SimHost.Interface in d.host.interfaces:
			for addr: Dictionary in iface.addresses:
				ips.append(addr["ip"])
	var router := d.definition.get_spec(RouterSpec) as RouterSpec
	if router != null:
		ips.append(IPv4.parse_cidr(router.lan_address)[0])
	return ips


## IPs used by more than one endpoint of the same broadcast domain.
static func ip_conflicts(world: SimWorld) -> Array[int]:
	var parent := domains(world)
	var seen := {}
	var conflicts: Array[int] = []
	for ep: Dictionary in endpoints(world, parent):
		if ep["domain"] == "":
			continue
		var key := "%s|%d" % [ep["domain"], ep["ip"]]
		if seen.has(key) and seen[key] != ep["device_id"] and not conflicts.has(ep["ip"]):
			conflicts.append(ep["ip"])
		seen[key] = ep["device_id"]
	return conflicts


# -------------------------------------------------------------------- DHCP --

## Minimal DHCP (decision 7): a running host whose eth0 is in DHCP mode gets the first free
## address of the router pool when it shares a broadcast domain with the router.
static func update_dhcp(world: SimWorld) -> void:
	var parent := {}
	var eps: Array[Dictionary] = []
	var computed := false
	for d: SimDevice in world.devices.values():
		if d.host == null or not d.is_running() or d.host.eth0_mode != &"dhcp":
			continue
		var eth0 := d.host.find_interface("eth0")
		if eth0 == null or not eth0.admin_up:
			continue
		var has_lease := false
		for addr: Dictionary in eth0.addresses:
			if addr["dynamic"]:
				has_lease = true
		if has_lease:
			continue
		if not computed:
			parent = domains(world)
			eps = endpoints(world, parent)
			computed = true
		var dom := domain_of(world, parent, PortRef.make(d.id, eth0.port_group, eth0.port_index))
		if dom == "":
			continue
		for ep: Dictionary in eps:
			if not ep["router"] or ep["domain"] != dom:
				continue
			var router := world.get_device(ep["device_id"]).definition.get_spec(RouterSpec) as RouterSpec
			var base := IPv4.network(ep["ip"], ep["prefix"])
			for n: int in range(router.dhcp_first_host, router.dhcp_last_host + 1):
				var candidate := base + n
				var used := false
				for other: Dictionary in eps:
					if other["ip"] == candidate and other["domain"] == dom:
						used = true
				if not used:
					eth0.addresses.append({"ip": candidate, "prefix": ep["prefix"], "dynamic": true})
					d.host.default_gateway = ep["ip"]
					d.host.default_gateway_dynamic = true
					eps.append({"device_id": d.id, "ip": candidate, "prefix": ep["prefix"],
						"iface": "eth0", "domain": dom, "router": false})
					world.emit_event(&"dhcp_lease", {"device_id": d.id, "ip": IPv4.format(candidate)})
					break
			break


# ------------------------------------------------------------------ routing --

## Route lookup on a host: {"iface": Interface, "src_ip": int, "next_hop": int} or {} (no route).
static func route_lookup(host: SimHost, dst: int) -> Dictionary:
	var direct := _connected_route(host, dst)
	if not direct.is_empty() or host.default_gateway < 0:
		return direct
	# The gateway itself must be on a connected subnet (no recursion: Linux behaves the same).
	var via := _connected_route(host, host.default_gateway)
	if via.is_empty():
		return {}
	via["next_hop"] = host.default_gateway
	return via


## Longest-prefix match among the host's connected subnets (admin-up interfaces only).
static func _connected_route(host: SimHost, dst: int) -> Dictionary:
	var best := {}
	var best_prefix := -1
	for iface: SimHost.Interface in host.interfaces:
		if not iface.admin_up:
			continue
		for addr: Dictionary in iface.addresses:
			if IPv4.in_subnet(dst, addr["ip"], addr["prefix"]) and addr["prefix"] > best_prefix:
				best = {"iface": iface, "src_ip": addr["ip"], "next_hop": dst}
				best_prefix = addr["prefix"]
	return best


## Whether `responder` (an endpoint) can send a reply back to `src_ip` in its domain.
static func _can_reply(world: SimWorld, responder: Dictionary, src_ip: int, eps: Array[Dictionary]) -> bool:
	if responder["router"]:
		return IPv4.in_subnet(src_ip, responder["ip"], responder["prefix"])
	var host := world.get_device(responder["device_id"]).host
	var back := route_lookup(host, src_ip)
	if back.is_empty():
		return false
	for ep: Dictionary in eps:
		if ep["domain"] == responder["domain"] and ep["ip"] == back["next_hop"]:
			if back["next_hop"] == src_ip:
				return true
			return ep["router"] and IPv4.in_subnet(src_ip, ep["ip"], ep["prefix"])
	return false


# -------------------------------------------------------------------- ping --

## Simulates `ping` from a host. Returns {"output": String, "received": int}.
## Output follows the iputils format; error texts are the real ones [POR VERIFICAR per locale].
static func ping(world: SimWorld, source: SimDevice, target: String, count: int) -> Dictionary:
	var host := source.host
	var lines: Array[String] = []
	var dst := IPv4.parse(target)
	if dst < 0:
		if target == "localhost":
			dst = IPv4.parse("127.0.0.1")
		else:
			return {"received": 0, "output": "ping: %s: %s\n%s" % [target,
				TranslationServer.translate("Fallo temporal en la resolución del nombre"),
				TranslationServer.translate("(Nota del juego: la resolución de nombres por DNS aún no está simulada; usa la dirección IP.)")]}
	lines.append("PING %s (%s) 56(84) bytes of data." % [target, IPv4.format(dst)])
	if IPv4.is_loopback(dst):
		return _replies(lines, target, IPv4.format(dst), count, 64, 0.03)
	var route := route_lookup(host, dst)
	if route.is_empty():
		return {"received": 0, "output": "ping: connect: Network is unreachable"}
	var src_ip: int = route["src_ip"]
	var parent := domains(world)
	var eps := endpoints(world, parent)
	var iface: SimHost.Interface = route["iface"]
	var src_domain := domain_of(world, parent, PortRef.make(source.id, iface.port_group, iface.port_index))
	var hop := _find_endpoint(eps, src_domain, route["next_hop"], source.id)
	if hop.is_empty():
		return _unreachable(lines, target, IPv4.format(src_ip), count, "Destination Host Unreachable")
	if route["next_hop"] == dst:
		if _can_reply(world, hop, src_ip, eps):
			return _replies(lines, target, IPv4.format(dst), count, 64, 0.35)
		return _silence(lines, target, count)
	# Through the gateway.
	if not hop["router"]:
		return _silence(lines, target, count)
	if IPv4.in_subnet(dst, hop["ip"], hop["prefix"]):
		var lan_target := _find_endpoint(eps, hop["domain"], dst, -1)
		if lan_target.is_empty():
			return _unreachable(lines, target, IPv4.format(hop["ip"]), count, "Destination Host Unreachable")
		if _can_reply(world, lan_target, src_ip, eps):
			return _replies(lines, target, IPv4.format(dst), count, 63, 0.7)
		return _silence(lines, target, count)
	var router := world.get_device(hop["device_id"]).definition.get_spec(RouterSpec) as RouterSpec
	if router.has_internet:
		return _replies(lines, target, IPv4.format(dst), count, 117, 14.0)
	return _unreachable(lines, target, IPv4.format(hop["ip"]), count, "Destination Net Unreachable")


static func has_internet(world: SimWorld, source: SimDevice) -> bool:
	return source.host != null and source.is_running() and ping(world, source, PUBLIC_TEST_IP, 1)["received"] > 0


## True if `a` gets replies from at least one address of `b`.
static func reachable(world: SimWorld, a: SimDevice, b: SimDevice) -> bool:
	if a.host == null or not a.is_running():
		return false
	for ip: int in device_ips(world, b):
		if ping(world, a, IPv4.format(ip), 1)["received"] > 0:
			return true
	return false


static func _find_endpoint(eps: Array[Dictionary], dom: String, ip: int, exclude_device: int) -> Dictionary:
	if dom == "":
		return {}
	for ep: Dictionary in eps:
		if ep["domain"] == dom and ep["ip"] == ip and ep["device_id"] != exclude_device:
			return ep
	return {}


static func _replies(lines: Array[String], target: String, from: String, count: int, ttl: int, base_ms: float) -> Dictionary:
	var times: Array[float] = []
	for seq: int in range(1, count + 1):
		var t := base_ms + 0.013 * seq
		times.append(t)
		lines.append("64 bytes from %s: icmp_seq=%d ttl=%d time=%.2f ms" % [from, seq, ttl, t])
	lines.append("")
	lines.append("--- %s ping statistics ---" % target)
	lines.append("%d packets transmitted, %d received, 0%% packet loss, time %dms" % [count, count, maxi(0, (count - 1) * 1001)])
	var avg := 0.0
	for t: float in times:
		avg += t
	avg /= times.size()
	lines.append("rtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms" % [times.min(), avg, times.max(), (times.max() - times.min()) / 2.0])
	return {"received": count, "output": "\n".join(lines)}


static func _unreachable(lines: Array[String], target: String, from: String, count: int, what: String) -> Dictionary:
	for seq: int in range(1, count + 1):
		lines.append("From %s icmp_seq=%d %s" % [from, seq, what])
	lines.append("")
	lines.append("--- %s ping statistics ---" % target)
	lines.append("%d packets transmitted, 0 received, +%d errors, 100%% packet loss, time %dms" % [count, count, maxi(0, (count - 1) * 1001)])
	return {"received": 0, "output": "\n".join(lines)}


static func _silence(lines: Array[String], target: String, count: int) -> Dictionary:
	lines.append("")
	lines.append("--- %s ping statistics ---" % target)
	lines.append("%d packets transmitted, 0 received, 100%% packet loss, time %dms" % [count, maxi(0, (count - 1) * 1001)])
	return {"received": 0, "output": "\n".join(lines)}
