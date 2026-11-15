class_name SimWorld
extends RefCounted
## The whole simulated state of a game (docs/ARCHITECTURE.md §4). Pure logic: no Node, no scenes.
## Every change goes through a command method that returns a CommandResult (ok, or rejected with
## a reason the player can read). Observers listen to `event_emitted`.
## Time runs in game minutes (decision 13: 1 real second = 1 game minute at x1).

signal event_emitted(type: StringName, data: Dictionary)

const MINUTES_PER_REAL_SECOND := 1.0
const DELIVERY_MINUTES := 120.0 ## Standard shipping (simplified, docs/HARDWARE_CATALOG.md §5.1).
const RACK_UNIT_M := 0.04445 ## 1U [VERIFICADO: EIA-310 via Wikipedia, 2026-11-15]
const CABLE_ROUTING_FACTOR := 1.2 ## Straight distance x factor + slack (docs/INTERACTION_SYSTEM.md §9).
const CABLE_SLACK_M := 0.3
const MAX_STEP_MINUTES := 5.0 ## Long skips are split into steps of at most this size.
const PACKAGE_FOOTPRINT := Vector2(0.5, 0.4)
const PACKAGE_SPACING_M := 0.6

var catalog: Catalog
var time_minutes: float = 8.0 * 60.0 ## Day 1, 08:00.
var speed: float = 1.0 ## 0 = paused; 1, 2, 4.
var credits: int = 0
var xp: int = 0
var devices: Dictionary = {} ## int -> SimDevice
var packages: Dictionary = {} ## int -> {"id": int, "device_ids": Array[int], "position": Vector3}
var orders: Array[Dictionary] = [] ## {"id", "eta", "groups", "total", "delivered"}
var cable_ends: Dictionary = {} ## cable device id -> {"a": port_ref, "b": port_ref}
var port_cable: Dictionary = {} ## port_ref -> cable device id
var room_bounds: Rect2 = Rect2() ## Floor area (x, z) where things can be placed.
var obstacles: Array[Rect2] = [] ## Furniture footprints (x, z).
var delivery_point: Vector3 = Vector3.ZERO
var mission: MissionTracker = null

var _next_id: int = 1


func _init(catalog_to_use: Catalog = null) -> void:
	catalog = catalog_to_use if catalog_to_use != null else Catalog.load_default()


# ------------------------------------------------------------------ devices --

func create_device(item_id: StringName, location: StringName) -> SimDevice:
	var def := catalog.get_item(item_id)
	if def == null:
		push_error("SimWorld: unknown catalog item %s" % item_id)
		return null
	var device := SimDevice.new(_next_id, def)
	_next_id += 1
	device.location = location
	devices[device.id] = device
	return device


func get_device(device_id: int) -> SimDevice:
	return devices.get(device_id) as SimDevice


func devices_of(category: StringName) -> Array[SimDevice]:
	var result: Array[SimDevice] = []
	for d: SimDevice in devices.values():
		if d.definition.category == category:
			result.append(d)
	return result


func inventory() -> Array[SimDevice]:
	var result: Array[SimDevice] = []
	for d: SimDevice in devices.values():
		if d.location == &"inventory":
			result.append(d)
	result.sort_custom(func(a: SimDevice, b: SimDevice) -> bool: return a.id < b.id)
	return result


func mounted_in(rack: SimDevice) -> Array[SimDevice]:
	var result: Array[SimDevice] = []
	for d: SimDevice in devices.values():
		if d.location == &"mounted" and d.rack_id == rack.id:
			result.append(d)
	return result


# --------------------------------------------------------------------- time --

func advance(real_seconds: float) -> void:
	if speed > 0.0:
		step_minutes(real_seconds * MINUTES_PER_REAL_SECOND * speed)


func step_minutes(minutes: float) -> void:
	var left := minutes
	while left > 0.0:
		var dt := minf(left, MAX_STEP_MINUTES)
		left -= dt
		time_minutes += dt
		_process_orders()
		_process_power(dt)
		NetworkEngine.update_dhcp(self)
		if mission != null:
			mission.evaluate(self)


## Minutes until the next scheduled thing (delivery or end of a boot), or -1 if none.
func minutes_to_next_event() -> float:
	var best := -1.0
	for order: Dictionary in orders:
		if not order["delivered"]:
			var wait: float = order["eta"] - time_minutes
			best = wait if best < 0.0 else minf(best, wait)
	for d: SimDevice in devices.values():
		if d.state == &"booting":
			best = d.boot_left_minutes if best < 0.0 else minf(best, d.boot_left_minutes)
	return best


func skip_to_next_event() -> CommandResult:
	var wait := minutes_to_next_event()
	if wait < 0.0:
		return CommandResult.failure(tr("No hay nada pendiente que esperar."))
	step_minutes(maxf(wait, 0.0) + 0.01)
	return CommandResult.success(tr("Han pasado %s.") % format_duration(wait))


func clock_text() -> String:
	var total := int(time_minutes)
	return tr("Día %d · %02d:%02d") % [total / 1440 + 1, (total / 60) % 24, total % 60]


static func format_duration(minutes: float) -> String:
	if minutes >= 60.0:
		var h := int(minutes / 60.0)
		var m := int(minutes) % 60
		return "%d h" % h if m == 0 else "%d h %d min" % [h, m]
	return "%d min" % maxi(1, int(ceil(minutes)))


# ------------------------------------------------------------------ economy --

func grant_rewards(reward_credits: int, reward_xp: int) -> void:
	var old_level := level()
	credits += reward_credits
	xp += reward_xp
	_emit(&"money_changed", {"credits": credits})
	_emit(&"xp_changed", {"xp": xp, "level": level(), "level_up": level() > old_level})


func level() -> int:
	return level_for_xp(xp)


## XP needed to go from level n to n+1 ≈ 100 × n^1.5 (docs/PROGRESSION.md §10.4).
static func level_for_xp(total_xp: int) -> int:
	var lvl := 1
	var threshold := 0.0
	while true:
		threshold += 100.0 * pow(lvl, 1.5)
		if total_xp < threshold:
			return lvl
		lvl += 1
	return lvl


## [xp inside the current level, xp needed for the next level]
func level_progress() -> Array[int]:
	var lvl := 1
	var floor_xp := 0.0
	while true:
		var need := 100.0 * pow(lvl, 1.5)
		if xp < floor_xp + need:
			return [xp - int(floor_xp), int(need)]
		floor_xp += need
		lvl += 1
	return [0, 1]


# ----------------------------------------------------------- shop & orders --

func purchase(item_ids: Array[StringName]) -> CommandResult:
	if item_ids.is_empty():
		return CommandResult.failure(tr("El carrito está vacío."))
	var total := 0
	for item_id: StringName in item_ids:
		var def := catalog.get_item(item_id)
		if def == null or not def.purchasable:
			return CommandResult.failure(tr("Producto no disponible: %s") % item_id)
		total += def.price
	if total > credits:
		return CommandResult.failure(tr("No tienes créditos suficientes: el pedido cuesta %d y tienes %d.") % [total, credits])
	var buyer := _first_running(&"computer")
	if buyer == null or not NetworkEngine.has_internet(self, buyer):
		return CommandResult.failure(tr("La tienda no responde: el ordenador no tiene conexión a Internet."))
	credits -= total
	# One box per piece of hardware (with its accessories); loose cables share one box.
	var groups: Array = []
	var cables_box: Array[int] = []
	for item_id: StringName in item_ids:
		var group: Array[int] = []
		var main := create_device(item_id, &"in_transit")
		group.append(main.id)
		for extra: StringName in main.definition.box_contents:
			group.append(create_device(extra, &"in_transit").id)
		if main.definition.category == &"cable":
			cables_box.append_array(group)
		else:
			groups.append(group)
	if not cables_box.is_empty():
		groups.append(cables_box)
	var order := {"id": _next_id, "eta": time_minutes + DELIVERY_MINUTES, "groups": groups,
		"total": total, "delivered": false}
	_next_id += 1
	orders.append(order)
	_emit(&"order_placed", {"order_id": order["id"], "eta": order["eta"]})
	_emit(&"money_changed", {"credits": credits})
	return CommandResult.success(tr("Pedido realizado: %d créditos. Llegará en %s.") % [total, format_duration(DELIVERY_MINUTES)], order["id"])


func _process_orders() -> void:
	for order: Dictionary in orders:
		if order["delivered"] or time_minutes < order["eta"]:
			continue
		order["delivered"] = true
		for group: Array in order["groups"]:
			var ids: Array[int] = []
			for device_id: int in group:
				ids.append(device_id)
				get_device(device_id).location = &"package"
			var package := {"id": _next_id, "device_ids": ids, "position": _free_package_spot()}
			_next_id += 1
			packages[package["id"]] = package
		_emit(&"package_delivered", {"order_id": order["id"]})


func _free_package_spot() -> Vector3:
	for i: int in 12:
		var spot := delivery_point + Vector3(PACKAGE_SPACING_M * (i % 4), 0.0, -PACKAGE_SPACING_M * (i / 4))
		var rect := Rect2(spot.x - PACKAGE_FOOTPRINT.x / 2, spot.z - PACKAGE_FOOTPRINT.y / 2, PACKAGE_FOOTPRINT.x, PACKAGE_FOOTPRINT.y)
		var taken := false
		for other: Dictionary in packages.values():
			if (other["position"] as Vector3).distance_to(spot) < 0.3:
				taken = true
		for d: SimDevice in devices.values():
			if d.location == &"placed" and footprint_rect(d.definition, d.position, d.yaw_degrees).intersects(rect):
				taken = true
		if not taken:
			return spot
	return delivery_point


func open_package(package_id: int) -> CommandResult:
	if not packages.has(package_id):
		return CommandResult.failure(tr("Ese paquete ya no existe."))
	var names: Array[String] = []
	for device_id: int in packages[package_id]["device_ids"]:
		var d := get_device(device_id)
		d.location = &"inventory"
		names.append(d.display_name())
	packages.erase(package_id)
	_emit(&"package_opened", {"package_id": package_id})
	return CommandResult.success(tr("Paquete abierto: %s. Ya está en tu inventario.") % ", ".join(names))


# ---------------------------------------------------------- placement --------

static func footprint_rect(def: HardwareDefinition, pos: Vector3, yaw_degrees: float) -> Rect2:
	var size := def.footprint_m
	if int(round(yaw_degrees / 90.0)) % 2 != 0:
		size = Vector2(size.y, size.x)
	return Rect2(pos.x - size.x / 2.0, pos.z - size.y / 2.0, size.x, size.y)


## Read-only placement check: "" if the device fits there, otherwise the reason (for previews).
func placement_problem(device_id: int, pos: Vector3, yaw_degrees: float) -> String:
	var d := get_device(device_id)
	if d == null or not (d.location in [&"inventory", &"placed"]):
		return tr("Ese objeto no está en tu inventario.")
	if d.definition.placement != &"floor":
		return tr("%s no se coloca en el suelo.") % d.display_name()
	if d.location == &"placed" and _has_cables_inside(d):
		return tr("Desconecta antes los cables de %s.") % d.display_name()
	var rect := footprint_rect(d.definition, pos, yaw_degrees)
	if not room_bounds.encloses(rect):
		return tr("No cabe ahí: se sale de la habitación.")
	for obstacle: Rect2 in obstacles:
		if rect.intersects(obstacle):
			return tr("No cabe ahí: choca con un mueble.")
	for other: SimDevice in devices.values():
		if other != d and other.location in [&"placed", &"fixed"] and other.definition.placement == &"floor":
			if rect.intersects(footprint_rect(other.definition, other.position, other.yaw_degrees)):
				return tr("No cabe ahí: choca con %s.") % other.display_name()
	for package: Dictionary in packages.values():
		var p: Vector3 = package["position"]
		if rect.intersects(Rect2(p.x - PACKAGE_FOOTPRINT.x / 2, p.z - PACKAGE_FOOTPRINT.y / 2, PACKAGE_FOOTPRINT.x, PACKAGE_FOOTPRINT.y)):
			return tr("No cabe ahí: hay un paquete en medio.")
	return ""


func place_device(device_id: int, pos: Vector3, yaw_degrees: float) -> CommandResult:
	var problem := placement_problem(device_id, pos, yaw_degrees)
	if problem != "":
		return CommandResult.failure(problem)
	var d := get_device(device_id)
	d.location = &"placed"
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.yaw_degrees = fposmod(round(yaw_degrees / 90.0) * 90.0, 360.0)
	_emit(&"device_placed", {"device_id": d.id})
	_refresh()
	return CommandResult.success(tr("%s colocado.") % d.display_name())


func pick_up_device(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or d.location != &"placed":
		return CommandResult.failure(tr("Solo se pueden recoger objetos colocados en el suelo."))
	if _has_cables_inside(d) or not mounted_in(d).is_empty():
		return CommandResult.failure(tr("Vacía antes %s y desconecta sus cables.") % d.display_name())
	d.location = &"inventory"
	_emit(&"device_removed", {"device_id": d.id})
	_refresh()
	return CommandResult.success(tr("%s vuelve al inventario.") % d.display_name())


# ----------------------------------------------------------------- racks -----

func units_free(rack: SimDevice, first_u: int, height_u: int, ignore_id: int = -1) -> bool:
	var spec := rack.definition.get_spec(RackSpec) as RackSpec
	if spec == null or first_u < 1 or first_u + height_u - 1 > spec.capacity_u:
		return false
	for m: SimDevice in mounted_in(rack):
		if m.id == ignore_id:
			continue
		var m_top := m.rack_u + m.definition.mount_height_u - 1
		if first_u <= m_top and m.rack_u <= first_u + height_u - 1:
			return false
	return true


func mount_device(device_id: int, rack_id: int, first_u: int) -> CommandResult:
	var d := get_device(device_id)
	var rack := get_device(rack_id)
	if d == null or d.location != &"inventory":
		return CommandResult.failure(tr("Ese equipo no está en tu inventario."))
	if rack == null or rack.location != &"placed" or rack.definition.get_spec(RackSpec) == null:
		return CommandResult.failure(tr("Primero coloca el rack en la habitación."))
	if d.definition.placement != &"rack":
		return CommandResult.failure(tr("%s no se monta en rack.") % d.display_name())
	var h := d.definition.mount_height_u
	if not units_free(rack, first_u, h):
		return CommandResult.failure(tr("No hay %dU libres a partir de la U%d.") % [h, first_u])
	d.location = &"mounted"
	d.rack_id = rack.id
	d.rack_u = first_u
	_emit(&"device_mounted", {"device_id": d.id, "rack_id": rack.id, "u": first_u})
	_refresh()
	return CommandResult.success(tr("%s montado en la U%d.") % [d.display_name(), first_u])


func unmount_device(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or d.location != &"mounted":
		return CommandResult.failure(tr("Ese equipo no está montado en un rack."))
	if _has_cables_inside(d):
		return CommandResult.failure(tr("Desconecta antes los cables de %s.") % d.display_name())
	d.location = &"inventory"
	d.rack_id = -1
	d.rack_u = 0
	_emit(&"device_removed", {"device_id": d.id})
	_refresh()
	return CommandResult.success(tr("%s desmontado y devuelto al inventario.") % d.display_name())


## Approximate world position of a device (used for cable lengths).
func device_anchor(d: SimDevice) -> Vector3:
	if d.location in [&"placed", &"fixed"]:
		return d.position
	if d.location == &"mounted":
		var rack := get_device(d.rack_id)
		var spec := rack.definition.get_spec(RackSpec) as RackSpec
		var local := Vector3(0.0, spec.first_unit_height_m + (d.rack_u - 0.5) * RACK_UNIT_M, spec.depth_m * 0.5)
		return rack.position + local.rotated(Vector3.UP, deg_to_rad(rack.yaw_degrees))
	return Vector3.ZERO


# ---------------------------------------------------------------- power ------

func press_power(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or not d.is_in_world():
		return CommandResult.failure(tr("Ese equipo no está instalado."))
	if not d.definition.has_power_button:
		return CommandResult.failure(tr("%s no tiene botón de encendido: arranca en cuanto recibe corriente.") % d.display_name())
	d.power_switch_on = not d.power_switch_on
	_refresh()
	_emit(&"power_button", {"device_id": d.id, "on": d.power_switch_on})
	if not d.power_switch_on:
		return CommandResult.success(tr("Apagando %s.") % d.display_name())
	if not is_powered(d):
		return CommandResult.success(tr("%s no arranca: no le llega corriente. Conecta su cable de alimentación a la regleta.") % d.display_name())
	return CommandResult.success(tr("Encendiendo %s…") % d.display_name())


func is_powered(d: SimDevice) -> bool:
	if not d.is_in_world():
		return false
	var strip := d.definition.get_spec(PowerStripSpec) as PowerStripSpec
	if strip != null:
		return strip.wall_connected
	for group: PortDefinition in d.definition.ports:
		if group.kind != PortDefinition.Kind.POWER_C14:
			continue
		var ref := PortRef.make(d.id, group.id, 0)
		var peer := cable_peer(ref)
		if peer == "":
			return false
		var source := get_device(PortRef.device_id(peer))
		var source_strip := source.definition.get_spec(PowerStripSpec) as PowerStripSpec
		return source.is_in_world() and source_strip != null and source_strip.wall_connected
	return false


func _process_power(dt: float) -> void:
	for d: SimDevice in devices.values():
		if d.definition.get_spec(PowerStripSpec) != null:
			continue
		var wants_on := is_powered(d) and d.power_switch_on
		if wants_on:
			if d.state == &"off":
				d.state = &"booting"
				d.boot_left_minutes = d.definition.boot_minutes
				_emit(&"device_booting", {"device_id": d.id})
			if d.state == &"booting":
				d.boot_left_minutes -= dt
				if d.boot_left_minutes <= 0.0:
					d.state = &"running"
					d.boot_left_minutes = 0.0
					_emit(&"device_running", {"device_id": d.id})
		elif d.state != &"off":
			d.state = &"off"
			if d.host != null:
				d.host.reset_runtime()
			_emit(&"device_off", {"device_id": d.id})


# --------------------------------------------------------------- cabling -----

func cable_peer(port_ref: String) -> String:
	if not port_cable.has(port_ref):
		return ""
	var ends: Dictionary = cable_ends[port_cable[port_ref]]
	return ends["b"] if ends["a"] == port_ref else ends["a"]


## A cable that has one end plugged and the other loose (decision 12), or -1.
func pending_cable() -> int:
	for cable_id: int in cable_ends:
		var ends: Dictionary = cable_ends[cable_id]
		if ends["b"] == "":
			return cable_id
	return -1


func connect_cable(cable_id: int, port_ref: String) -> CommandResult:
	var cable := get_device(cable_id)
	var spec := cable.definition.get_spec(CableSpec) as CableSpec if cable != null else null
	if spec == null or not (cable.location in [&"inventory", &"cabled"]):
		return CommandResult.failure(tr("Elige un cable de tu inventario."))
	var ends: Dictionary = cable_ends.get(cable_id, {"a": "", "b": ""})
	if ends["b"] != "":
		return CommandResult.failure(tr("Este cable ya está conectado por los dos extremos."))
	var target := get_device(PortRef.device_id(port_ref))
	var group := target.definition.find_port_group(PortRef.group(port_ref)) if target != null else null
	if group == null or PortRef.index(port_ref) >= group.count or not target.is_in_world():
		return CommandResult.failure(tr("Ese puerto no existe."))
	if port_cable.has(port_ref):
		return CommandResult.failure(tr("Ese puerto ya tiene un cable."))
	var is_power_port := group.kind in [PortDefinition.Kind.POWER_C13, PortDefinition.Kind.POWER_C14]
	if spec.media == &"copper" and group.kind != PortDefinition.Kind.RJ45:
		return CommandResult.failure(tr("Es un cable de red (RJ45) y ese puerto no es RJ45."))
	if spec.media == &"power" and not is_power_port:
		return CommandResult.failure(tr("Es un cable de corriente: une una toma de la regleta con la entrada de alimentación de un equipo."))
	if ends["a"] == "":
		ends["a"] = port_ref
		cable_ends[cable_id] = ends
		port_cable[port_ref] = cable_id
		cable.location = &"cabled"
		_emit(&"cable_plugged", {"cable_id": cable_id, "port": port_ref})
		return CommandResult.success(tr("Extremo conectado. Ahora conecta el otro extremo."))
	var first: String = ends["a"]
	if PortRef.device_id(first) == target.id:
		return CommandResult.failure(tr("Los dos extremos irían al mismo equipo."))
	if spec.media == &"power":
		var first_group := get_device(PortRef.device_id(first)).definition.find_port_group(PortRef.group(first))
		if first_group.kind == group.kind:
			return CommandResult.failure(tr("Un cable de corriente une una toma de la regleta con la entrada de alimentación de un equipo."))
	var needed := device_anchor(get_device(PortRef.device_id(first))).distance_to(device_anchor(target)) * CABLE_ROUTING_FACTOR + CABLE_SLACK_M
	if needed > spec.length_m:
		return CommandResult.failure(tr("El cable no llega: hacen falta unos %.1f m y este mide %.0f m.") % [needed, spec.length_m])
	ends["b"] = port_ref
	port_cable[port_ref] = cable_id
	_refresh()
	_emit(&"cable_connected", {"cable_id": cable_id})
	if spec.media == &"power":
		return CommandResult.success(tr("Cable de corriente conectado."))
	var link := NetworkEngine.port_link(self, port_ref)
	if link["up"]:
		return CommandResult.success(tr("Cable conectado. Enlace activo a %d Mb/s.") % link["speed"])
	return CommandResult.success(tr("Cable conectado. Sin enlace todavía: %s") % link["reason"])


func disconnect_port(port_ref: String) -> CommandResult:
	if not port_cable.has(port_ref):
		return CommandResult.failure(tr("Ese puerto no tiene cable."))
	var cable_id: int = port_cable[port_ref]
	var ends: Dictionary = cable_ends[cable_id]
	port_cable.erase(ends["a"])
	if ends["b"] != "":
		port_cable.erase(ends["b"])
	cable_ends.erase(cable_id)
	get_device(cable_id).location = &"inventory"
	_refresh()
	_emit(&"cable_removed", {"cable_id": cable_id})
	return CommandResult.success(tr("Cable desconectado y devuelto al inventario."))


func _has_cables_inside(d: SimDevice) -> bool:
	var inside: Array[SimDevice] = [d]
	inside.append_array(mounted_in(d))
	for device: SimDevice in inside:
		for ref: String in device.port_refs():
			if port_cable.has(ref):
				return true
	return false


# ----------------------------------------------------------------- helpers ---

func _first_running(category: StringName) -> SimDevice:
	for d: SimDevice in devices_of(category):
		if d.is_running():
			return d
	return null


## Re-evaluates derived state right after a command (power, DHCP, mission).
func _refresh() -> void:
	_process_power(0.0)
	NetworkEngine.update_dhcp(self)
	if mission != null:
		mission.evaluate(self)


func emit_event(type: StringName, data: Dictionary = {}) -> void:
	_emit(type, data)


func _emit(type: StringName, data: Dictionary) -> void:
	event_emitted.emit(type, data)
