class_name ShellIp
extends RefCounted
## `ip` (iproute2) subset: address show/add/del, link show/set, route show/add/del default.
## Syntax per ip-address(8) [VERIFICADO: man7.org, 2026-11-15]; error texts imitate iproute2
## [POR VERIFICAR exact wording]. Changes made with `ip` are runtime only (decision 9).

const OBJECTS_ADDRESS: PackedStringArray = ["a", "ad", "add", "addr", "addre", "addres", "address"]
const OBJECTS_LINK: PackedStringArray = ["l", "li", "lin", "link"]
const OBJECTS_ROUTE: PackedStringArray = ["r", "ro", "rou", "rout", "route"]


static func run(world: SimWorld, shell: Shell, args: Array[String]) -> Dictionary:
	var device := world.get_device(shell.device_id)
	if args.is_empty() or args[0] == "help":
		return _out(_usage(), 0 if not args.is_empty() else 255)
	var object := args[0]
	var rest := args.slice(1)
	if OBJECTS_ADDRESS.has(object):
		return _address(world, shell, device, rest)
	if OBJECTS_LINK.has(object):
		return _link(world, shell, device, rest)
	if OBJECTS_ROUTE.has(object):
		return _route(world, shell, device, rest)
	if object in ["n", "neigh", "neighbor", "neighbour"]:
		return _out(TranslationServer.translate("ip neigh: la tabla ARP aún no está implementada en HomeLab Tycoon."), 1)
	return _out("Object \"%s\" is unknown, try \"ip help\"." % object, 1)


static func _usage() -> String:
	return "Usage: ip [ OPTIONS ] OBJECT { COMMAND | help }\nwhere  OBJECT := { address | link | route }\n" \
		+ TranslationServer.translate("(HomeLab Tycoon implementa por ahora address, link y route.)")


# ----------------------------------------------------------------- address --

static func _address(world: SimWorld, shell: Shell, device: SimDevice, args: Array[String]) -> Dictionary:
	var verb := args[0] if not args.is_empty() else "show"
	if verb in ["show", "list", "lst", "s", "sh"]:
		var dev_filter := _arg_after(args, "dev")
		if dev_filter == "" and args.size() >= 2 and args[1] != "dev":
			dev_filter = args[1]
		return _show(world, device, dev_filter, true)
	if verb in ["add", "del", "delete"]:
		if args.size() < 2:
			return _out("Not enough information: \"dev\" argument is required.", 1)
		var dev_name := _arg_after(args, "dev")
		if dev_name == "":
			return _out("Not enough information: \"dev\" argument is required.", 1)
		var cidr := IPv4.parse_cidr(args[1])
		if cidr.is_empty():
			return _out("Error: any valid prefix is expected rather than \"%s\"." % args[1], 1)
		var iface := device.host.find_interface(dev_name)
		if iface == null:
			return _out("Cannot find device \"%s\"" % dev_name, 1)
		if shell.user != "root":
			return _out("RTNETLINK answers: Operation not permitted", 2)
		for addr: Dictionary in iface.addresses:
			if addr["ip"] == cidr[0] and addr["prefix"] == cidr[1]:
				if verb == "add":
					return _out("RTNETLINK answers: File exists", 2)
				iface.addresses.erase(addr)
				world.emit_event(&"host_config_changed", {"device_id": device.id})
				return _out("", 0)
		if verb != "add":
			return _out("RTNETLINK answers: Cannot assign requested address", 2)
		iface.addresses.append({"ip": cidr[0], "prefix": cidr[1], "dynamic": false})
		world.emit_event(&"host_config_changed", {"device_id": device.id})
		return _out("", 0)
	if verb == "flush":
		return _out(TranslationServer.translate("ip address flush: aún no está implementado en HomeLab Tycoon; usa «ip address del»."), 1)
	return _out("Command \"%s\" is unknown, try \"ip address help\"." % verb, 1)


static func _show(world: SimWorld, device: SimDevice, dev_filter: String, with_addresses: bool) -> Dictionary:
	var host := device.host
	var lines: Array[String] = []
	if dev_filter != "" and dev_filter != "lo" and host.find_interface(dev_filter) == null:
		return _out("Device \"%s\" does not exist." % dev_filter, 1)
	if dev_filter == "" or dev_filter == "lo":
		lines.append("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN %sgroup default qlen 1000" % ("" if with_addresses else "mode DEFAULT "))
		lines.append("    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00")
		if with_addresses:
			lines.append("    inet 127.0.0.1/8 scope host lo")
			lines.append("       valid_lft forever preferred_lft forever")
	var n := 2
	for iface: SimHost.Interface in host.interfaces:
		if dev_filter == "" or dev_filter == iface.name:
			var carrier: bool = NetworkEngine.port_link(world, PortRef.make(device.id, iface.port_group, iface.port_index))["up"]
			var flags := "BROADCAST,MULTICAST"
			var state := "DOWN"
			if iface.admin_up:
				flags = "BROADCAST,MULTICAST,UP,LOWER_UP" if carrier else "NO-CARRIER,BROADCAST,MULTICAST,UP"
				state = "UP" if carrier else "DOWN"
			lines.append("%d: %s: <%s> mtu 1500 qdisc fq_codel state %s %sgroup default qlen 1000" % [n, iface.name, flags, state, "" if with_addresses else "mode DEFAULT "])
			lines.append("    link/ether %s brd ff:ff:ff:ff:ff:ff" % iface.mac)
			if with_addresses:
				for addr: Dictionary in iface.addresses:
					if addr["dynamic"]:
						lines.append("    inet %s/%d brd %s scope global dynamic %s" % [IPv4.format(addr["ip"]), addr["prefix"], IPv4.format(IPv4.broadcast(addr["ip"], addr["prefix"])), iface.name])
						lines.append("       valid_lft 86394sec preferred_lft 86394sec")
					else:
						lines.append("    inet %s/%d scope global %s" % [IPv4.format(addr["ip"]), addr["prefix"], iface.name])
						lines.append("       valid_lft forever preferred_lft forever")
		n += 1
	return _out("\n".join(lines), 0)


# -------------------------------------------------------------------- link --

static func _link(world: SimWorld, shell: Shell, device: SimDevice, args: Array[String]) -> Dictionary:
	var verb := args[0] if not args.is_empty() else "show"
	if verb in ["show", "list", "s", "sh"]:
		return _show(world, device, _arg_after(args, "dev") if args.has("dev") else (args[1] if args.size() > 1 else ""), false)
	if verb == "set":
		var rest := args.slice(1)
		if not rest.is_empty() and rest[0] == "dev":
			rest = rest.slice(1)
		if rest.size() < 2 or not (rest[1] in ["up", "down"]):
			return _out(TranslationServer.translate("Uso en HomeLab Tycoon: ip link set [dev] INTERFAZ up|down"), 1)
		var iface := device.host.find_interface(rest[0])
		if iface == null:
			return _out("Cannot find device \"%s\"" % rest[0], 1)
		if shell.user != "root":
			return _out("RTNETLINK answers: Operation not permitted", 2)
		iface.admin_up = rest[1] == "up"
		world.emit_event(&"host_config_changed", {"device_id": device.id})
		return _out("", 0)
	return _out("Command \"%s\" is unknown, try \"ip link help\"." % verb, 1)


# ------------------------------------------------------------------- route --

static func _route(world: SimWorld, shell: Shell, device: SimDevice, args: Array[String]) -> Dictionary:
	var host := device.host
	var verb := args[0] if not args.is_empty() else "show"
	if verb in ["show", "list", "s", "sh"]:
		var lines: Array[String] = []
		if host.default_gateway >= 0:
			var via := NetworkEngine.route_lookup(host, host.default_gateway)
			var dev_name: String = (via["iface"] as SimHost.Interface).name if not via.is_empty() else "?"
			if host.default_gateway_dynamic and not via.is_empty():
				lines.append("default via %s dev %s proto dhcp src %s metric 100" % [IPv4.format(host.default_gateway), dev_name, IPv4.format(via["src_ip"])])
			else:
				lines.append("default via %s dev %s" % [IPv4.format(host.default_gateway), dev_name])
		for iface: SimHost.Interface in host.interfaces:
			if not iface.admin_up:
				continue
			var carrier: bool = NetworkEngine.port_link(world, PortRef.make(device.id, iface.port_group, iface.port_index))["up"]
			for addr: Dictionary in iface.addresses:
				lines.append("%s/%d dev %s proto kernel scope link src %s%s" % [IPv4.format(IPv4.network(addr["ip"], addr["prefix"])), addr["prefix"], iface.name, IPv4.format(addr["ip"]), "" if carrier else " linkdown"])
		return _out("\n".join(lines), 0)
	if verb in ["add", "del", "delete"]:
		if args.size() < 2 or args[1] != "default":
			return _out(TranslationServer.translate("En HomeLab Tycoon, ip route solo admite por ahora la ruta por defecto: ip route add default via IP"), 1)
		if shell.user != "root":
			return _out("RTNETLINK answers: Operation not permitted", 2)
		if verb != "add":
			if host.default_gateway < 0:
				return _out("RTNETLINK answers: No such process", 2)
			host.default_gateway = -1
			host.default_gateway_dynamic = false
			world.emit_event(&"host_config_changed", {"device_id": device.id})
			return _out("", 0)
		var gw_text := _arg_after(args, "via")
		var gw := IPv4.parse(gw_text)
		if gw < 0:
			return _out("Error: inet address is expected rather than \"%s\"." % gw_text, 1)
		if host.default_gateway >= 0:
			return _out("RTNETLINK answers: File exists", 2)
		var saved := host.default_gateway
		host.default_gateway = gw
		if NetworkEngine.route_lookup(host, gw).is_empty():
			host.default_gateway = saved
			return _out("Error: Nexthop has invalid gateway.", 2)
		host.default_gateway_dynamic = false
		world.emit_event(&"host_config_changed", {"device_id": device.id})
		return _out("", 0)
	return _out("Command \"%s\" is unknown, try \"ip route help\"." % verb, 1)


static func _arg_after(args: Array[String], keyword: String) -> String:
	var i := args.find(keyword)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


static func _out(text: String, status: int) -> Dictionary:
	return {"status": status, "output": text}
