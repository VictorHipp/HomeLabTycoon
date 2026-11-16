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
## Cable length = route along the floor + both ends (docs/INTERACTION_SYSTEM.md §9).
const CABLE_SLACK_M := 0.2 ## Extra length for the bends.
const RACK_CABLE_SLACK_M := 0.1 ## Between two devices of the same rack.
const PORT_OUT_M := 0.04 ## The plug sticks out of the socket before the cable bends.
const EXIT_GAP_M := 0.035 ## Gap between a device side and the cable going down to the floor.
const RACK_POST_INSET_M := 0.03 ## Cables go down the rack posts, this far inside the rack sides.
const MAX_STEP_MINUTES := 5.0 ## Long skips are split into steps of at most this size.
const PACKAGE_FOOTPRINT := Vector2(0.5, 0.4)
const DELIVERY_SEARCH_STEP_M := 0.25 ## Grid used to find another spot if the zone is occupied.

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
var obstacles: Array[Rect2] = [] ## Furniture footprints (x, z), rebuilt from `furniture`.
## Pieces of furniture by instance id (StringName -> SimFurniture). The player can move them
## (move_furniture); `obstacles` and `cable_obstacles` are rebuilt from them.
var furniture: Dictionary = {}
## Floor area by the entrance reserved for deliveries: every box waits there in one stack
## and nothing may be placed on it (docs/INTERACTION_SYSTEM.md §7).
var delivery_zone: Rect2 = Rect2()
## Furniture that stands on the floor: cables go around it (a desk on legs only counts its legs).
## Rebuilt from `furniture`.
var cable_obstacles: Array[Rect2] = []
## Floor in front of each door: kept free (nothing is placed there and no cable crosses it).
var door_zones: Array[Rect2] = []
var wall_trim_m: float = 0.0 ## Skirting boards: cables run in front of them.
var mission: MissionTracker = null
var economy: Economy ## Ledger, passive income, second-hand prices.

var _next_id: int = 1
var _router: CableRouter = null
var _state_version: int = 0 ## Grows with every event: invalidates cached cable routes.
var _route_cache: Dictionary = {}
var _route_cache_version: int = -1


func _init(catalog_to_use: Catalog = null) -> void:
	catalog = catalog_to_use if catalog_to_use != null else Catalog.load_default()
	economy = Economy.new()


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
		var income := economy.accrue(self, dt)
		if income > 0:
			grant_rewards(income, 0, &"passive", tr("Ingresos pasivos: equipos en línea en la red de casa"))


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


## Metres with the Spanish decimal comma (`3,1`).
## A length that is needed, rounded up to the decimetre: 3.02 m is "3,1" (never "3,0 m needed,
## the cable is 3 m").
static func metres_needed(value: float) -> String:
	return metres(ceilf(value * 10.0 - 0.0001) / 10.0)


static func metres(value: float, decimals: int = 1) -> String:
	if decimals <= 0:
		return str(roundi(value))
	return ("%.1f" % value).replace(".", ",")


static func format_duration(minutes: float) -> String:
	if minutes >= 60.0:
		var h := int(minutes / 60.0)
		var m := int(minutes) % 60
		return "%d h" % h if m == 0 else "%d h %d min" % [h, m]
	return "%d min" % maxi(1, int(ceil(minutes)))


# ------------------------------------------------------------------ economy --

## Adds credits and XP and writes the reason in the ledger (economy.ledger). Every change of
## credits or XP goes through here or through purchase / sell_device.
func grant_rewards(reward_credits: int, reward_xp: int, kind: StringName = &"reward", text: String = "") -> void:
	var old_level := level()
	credits += reward_credits
	xp += reward_xp
	economy.record(time_minutes, reward_credits, reward_xp, kind, text)
	if reward_credits != 0:
		_emit(&"money_changed", {"credits": credits, "delta": reward_credits, "kind": kind})
	if reward_xp != 0:
		_emit(&"xp_changed", {"xp": xp, "delta": reward_xp, "level": level(), "level_up": level() > old_level, "text": text})


## The value the world's state has now: grows with every event (for caches of derived data).
func state_version() -> int:
	return _state_version


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
	economy.record(time_minutes, -total, 0, &"purchase", tr("Pedido en la tienda (%d productos)") % item_ids.size())
	# One box per piece of hardware (with its accessories); loose cables share one box.
	var groups: Array = []
	var cables_box: Array[int] = []
	for item_id: StringName in item_ids:
		var group: Array[int] = []
		var main := create_device(item_id, &"in_transit")
		main.bought = true
		group.append(main.id)
		for extra: StringName in main.definition.box_contents:
			var accessory := create_device(extra, &"in_transit")
			accessory.bought = true
			group.append(accessory.id)
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
	_emit(&"money_changed", {"credits": credits, "delta": -total, "kind": &"purchase"})
	return CommandResult.success(tr("Pedido realizado: %d créditos. Llegará en %s.") % [total, format_duration(DELIVERY_MINUTES)], order["id"])


## Second-hand market (docs/PROGRESSION.md §8): sells something of the inventory for less than it
## cost (Economy.resale_price). Like the shop, it needs the computer online. The device is kept
## with location "sold", so old orders and the ledger can still name it.
func sell_device(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or d.location == &"sold":
		return CommandResult.failure(tr("Ese objeto ya no es tuyo."))
	if d.location != &"inventory":
		return CommandResult.failure(tr("Solo se vende lo que está en el inventario: recoge, desmonta o desconecta antes %s.") % d.display_name())
	var price := economy.resale_price(d)
	if price <= 0:
		return CommandResult.failure(tr("%s no se puede vender: es parte de la casa.") % d.display_name())
	var seller := _first_running(&"computer")
	if seller == null or not NetworkEngine.has_internet(self, seller):
		return CommandResult.failure(tr("El mercado de segunda mano no responde: el ordenador no tiene conexión a Internet."))
	d.location = &"sold"
	var state := tr("usado") if d.used else tr("sin estrenar")
	grant_rewards(price, 0, &"sale", tr("Venta de segunda mano: %s (%s)") % [d.display_name(), state])
	_emit(&"device_sold", {"device_id": d.id, "price": price})
	return CommandResult.success(tr("Vendido: %s por %d créditos.") % [d.display_name(), price], price)


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
			var package := {"id": _next_id, "device_ids": ids, "position": delivery_spot()}
			_next_id += 1
			packages[package["id"]] = package
		_emit(&"package_delivered", {"order_id": order["id"]})


## Where the stack of boxes goes: the centre of the delivery zone. If something already stands
## there (only possible in a game saved before the zone was reserved), the nearest free spot
## near it, so no object is removed and no delivery is lost.
func delivery_spot() -> Vector3:
	var centre := delivery_zone.get_center()
	if _package_spot_free(centre):
		return Vector3(centre.x, 0.0, centre.y)
	var best := Vector2.INF
	var steps := 12
	for ix: int in range(-steps, steps + 1):
		for iz: int in range(-steps, steps + 1):
			var p := centre + Vector2(ix, iz) * DELIVERY_SEARCH_STEP_M
			if p.distance_to(centre) < best.distance_to(centre) and _package_spot_free(p):
				best = p
	if best == Vector2.INF:
		return Vector3(centre.x, 0.0, centre.y)
	return Vector3(best.x, 0.0, best.y)


## True when the stack is not where it should be (the delivery zone was occupied).
func delivery_zone_blocked() -> bool:
	return not _package_spot_free(delivery_zone.get_center())


func _package_spot_free(p: Vector2) -> bool:
	var rect := Rect2(p - PACKAGE_FOOTPRINT / 2.0, PACKAGE_FOOTPRINT).grow(0.05)
	if not room_bounds.encloses(rect):
		return false
	for obstacle: Rect2 in obstacles:
		if rect.intersects(obstacle):
			return false
	for d: SimDevice in _floor_devices(null):
		if rect.intersects(footprint_rect(d.definition, d.position, d.yaw_degrees)):
			return false
		for zone: Rect2 in service_zones(d.definition, d.position, d.yaw_degrees):
			if rect.intersects(zone):
				return false
	return true


## Puts every waiting box on the current delivery spot (after loading a game).
func _gather_packages() -> void:
	var spot := delivery_spot()
	for package: Dictionary in packages.values():
		package["position"] = spot


## The package opened by a click on the stack: the one on top (the newest).
func top_package_id() -> int:
	var best := -1
	for package_id: int in packages:
		best = maxi(best, package_id)
	return best


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


## Floor areas that must stay free in front of and behind a rack ([front, rear]). The front is
## the local +Z side (where the model's front faces). Empty for devices without clearance.
static func service_zones(def: HardwareDefinition, pos: Vector3, yaw_degrees: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var rack := def.get_spec(RackSpec) as RackSpec
	if rack == null or rack.service_clearance_m <= 0.0:
		return result
	var c := rack.service_clearance_m
	var yaw := deg_to_rad(round(yaw_degrees / 90.0) * 90.0)
	var forward := Vector2(roundf(sin(yaw)), roundf(cos(yaw))) # (x, z)
	var size := Vector2(def.footprint_m.x, c) if absf(forward.y) > 0.5 else Vector2(c, def.footprint_m.x)
	for side: float in [1.0, -1.0]:
		var center := Vector2(pos.x, pos.z) + forward * side * (def.footprint_m.y + c) / 2.0
		result.append(Rect2(center - size / 2.0, size))
	return result


## Read-only placement check: "" if the device fits there, otherwise the reason (for previews).
## Works for devices in the inventory and for moving a device already placed.
func placement_problem(device_id: int, pos: Vector3, yaw_degrees: float) -> String:
	var d := get_device(device_id)
	if d == null or not (d.location in [&"inventory", &"placed"]):
		return tr("Ese objeto no está en tu inventario.")
	if d.definition.placement != &"floor":
		return tr("%s no se coloca en el suelo.") % d.display_name()
	var rect := footprint_rect(d.definition, pos, yaw_degrees)
	if not room_bounds.encloses(rect):
		return tr("No cabe ahí: se sale de la habitación.")
	for obstacle: Rect2 in obstacles:
		if rect.intersects(obstacle):
			return tr("No cabe ahí: choca con un mueble.")
	for other: SimDevice in _floor_devices(d):
		if rect.intersects(footprint_rect(other.definition, other.position, other.yaw_degrees)):
			return tr("No cabe ahí: choca con %s.") % other.display_name()
	if rect.intersects(delivery_zone):
		return tr("Esa zona junto a la puerta está reservada para las entregas.")
	for door: Rect2 in door_zones:
		if rect.intersects(door):
			return tr("No cabe ahí: cerrarías el paso de la puerta.")
	for package: Dictionary in packages.values():
		if rect.intersects(_package_rect(package)):
			return tr("No cabe ahí: hay un paquete en medio.")
	for other: SimDevice in _floor_devices(d):
		for zone: Rect2 in service_zones(other.definition, other.position, other.yaw_degrees):
			if rect.intersects(zone):
				return tr("No cabe ahí: taparía el espacio de trabajo de %s.") % other.display_name()
	var rack := d.definition.get_spec(RackSpec) as RackSpec
	for zone: Rect2 in service_zones(d.definition, pos, yaw_degrees):
		var blocked := not room_bounds.encloses(zone)
		for obstacle: Rect2 in obstacles:
			blocked = blocked or zone.intersects(obstacle)
		for other: SimDevice in _floor_devices(d):
			blocked = blocked or zone.intersects(footprint_rect(other.definition, other.position, other.yaw_degrees))
		blocked = blocked or zone.intersects(delivery_zone)
		if blocked:
			return tr("Deja al menos %d cm libres delante y detrás de %s: hacen falta para trabajar en su frontal y en su trasera.") % [roundi(rack.service_clearance_m * 100.0), d.display_name()]
	return _cable_problem_if_placed(d, pos, yaw_degrees)


## Cables already laid must still have a way and be long enough with `d` at the new spot:
## its own cables when it is moved, and any cable whose route it would cover.
func _cable_problem_if_placed(d: SimDevice, pos: Vector3, yaw_degrees: float) -> String:
	if cable_ends.is_empty():
		return ""
	var rect := footprint_rect(d.definition, pos, yaw_degrees).grow(CableRouter.CLEARANCE)
	var inside: Array[int] = [d.id]
	for m: SimDevice in mounted_in(d):
		inside.append(m.id)
	var affected: Array[int] = []
	for cable_id: int in cable_ends:
		var ends: Dictionary = cable_ends[cable_id]
		if ends["b"] == "":
			continue
		if PortRef.device_id(ends["a"]) in inside or PortRef.device_id(ends["b"]) in inside:
			affected.append(cable_id)
		elif _route_crosses(cable_route(cable_id), rect):
			affected.append(cable_id)
	if affected.is_empty():
		return ""
	var saved := [d.location, d.position, d.yaw_degrees]
	d.location = &"placed"
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.yaw_degrees = yaw_degrees
	var problem := ""
	for cable_id: int in affected:
		var ends: Dictionary = cable_ends[cable_id]
		var route := route_between(ends["a"], ends["b"], _cable_length(cable_id))
		var spec := get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var name := get_device(cable_id).definition.model
		if not route["ok"]:
			problem = tr("Ahí cortaría el paso del cable %s: %s") % [name, route["reason"]]
			break
		if route["length"] > spec.length_m:
			problem = tr("Con %s ahí, el cable %s no llegaría: harían falta unos %s m y mide %s m.") % [d.display_name(), name, metres_needed(route["length"]), metres(spec.length_m, 0)]
			break
	d.location = saved[0]
	d.position = saved[1]
	d.yaw_degrees = saved[2]
	return problem


static func _route_crosses(route: Dictionary, rect: Rect2) -> bool:
	if not route.get("ok", false):
		return false
	var points: PackedVector2Array = route["floor"]
	for i: int in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.02))
		for k: int in steps + 1:
			if rect.has_point(a.lerp(b, float(k) / steps)):
				return true
	return false


func place_device(device_id: int, pos: Vector3, yaw_degrees: float) -> CommandResult:
	var problem := placement_problem(device_id, pos, yaw_degrees)
	if problem != "":
		return CommandResult.failure(problem)
	var d := get_device(device_id)
	var moved := d.location == &"placed"
	d.location = &"placed"
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.yaw_degrees = fposmod(round(yaw_degrees / 90.0) * 90.0, 360.0)
	d.used = true
	_emit(&"device_placed", {"device_id": d.id})
	_refresh()
	return CommandResult.success((tr("%s movido.") if moved else tr("%s colocado.")) % d.display_name())


## Floor devices in the room other than `except`.
func _floor_devices(except: SimDevice) -> Array[SimDevice]:
	var result: Array[SimDevice] = []
	for other: SimDevice in devices.values():
		if other != except and other.location in [&"placed", &"fixed"] and other.definition.placement == &"floor":
			result.append(other)
	return result


func _package_rect(package: Dictionary) -> Rect2:
	var p: Vector3 = package["position"]
	return Rect2(p.x - PACKAGE_FOOTPRINT.x / 2, p.z - PACKAGE_FOOTPRINT.y / 2, PACKAGE_FOOTPRINT.x, PACKAGE_FOOTPRINT.y)


## Placement preview help for a rack: power cable that a device in its top unit would need to
## reach the nearest power strip along the floor (same rule as connect_cable), the cord that
## comes with the equipment and the longest one in the shop. {} for devices that are not racks.
func rack_power_estimate(device_id: int, pos: Vector3, yaw_degrees: float) -> Dictionary:
	var d := get_device(device_id)
	var rack := d.definition.get_spec(RackSpec) as RackSpec if d != null else null
	if rack == null:
		return {}
	var saved := [d.location, d.position, d.yaw_degrees]
	d.location = &"placed"
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.yaw_degrees = yaw_degrees
	var needed := INF
	var height := rack.first_unit_height_m + (rack.capacity_u - 1) * RACK_UNIT_M + 0.022
	for strip: SimDevice in devices_of(&"power"):
		if not strip.is_in_world():
			continue
		var outlet := strip.definition.ports[0]
		var rack_end := _rack_post_end(d, &"rear", height, _center2(strip))
		var strip_end := _cable_end(strip, outlet, rack_end["exit"])
		var path := _cable_router().find_path(rack_end["exit"], strip_end["exit"], _floor_device_rects(), 1.0)
		if not path.is_empty():
			needed = minf(needed, rack_end["drop"] + CableRouter.length_of(path) + strip_end["drop"] + CABLE_SLACK_M)
	d.location = saved[0]
	d.position = saved[1]
	d.yaw_degrees = saved[2]
	var included := INF
	var longest := 0.0
	for item: HardwareDefinition in catalog.items.values():
		var cable := item.get_spec(CableSpec) as CableSpec
		if cable != null and cable.media == &"power":
			longest = maxf(longest, cable.length_m)
		for extra: StringName in item.box_contents:
			var boxed := catalog.get_item(extra)
			var boxed_spec := boxed.get_spec(CableSpec) as CableSpec if boxed != null else null
			if boxed_spec != null and boxed_spec.media == &"power":
				included = minf(included, boxed_spec.length_m)
	return {"needed": needed, "included": included, "longest": longest}


func pick_up_device(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or d.location != &"placed":
		return CommandResult.failure(tr("Solo se pueden recoger objetos colocados en el suelo."))
	if has_cables_inside(d) or not mounted_in(d).is_empty():
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
	d.used = true
	_emit(&"device_mounted", {"device_id": d.id, "rack_id": rack.id, "u": first_u})
	_refresh()
	return CommandResult.success(tr("%s montado en la U%d.") % [d.display_name(), first_u])


func unmount_device(device_id: int) -> CommandResult:
	var d := get_device(device_id)
	if d == null or d.location != &"mounted":
		return CommandResult.failure(tr("Ese equipo no está montado en un rack."))
	if has_cables_inside(d):
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
		return rack_unit_anchor(rack.definition, rack.position, rack.yaw_degrees, d.rack_u)
	return Vector3.ZERO


## Approximate world position of unit `u` of a rack at `rack_pos` / `rack_yaw` (front face).
static func rack_unit_anchor(rack_def: HardwareDefinition, rack_pos: Vector3, rack_yaw: float, u: int) -> Vector3:
	var spec := rack_def.get_spec(RackSpec) as RackSpec
	var local := Vector3(0.0, spec.first_unit_height_m + (u - 0.5) * RACK_UNIT_M, spec.depth_m * 0.5)
	return rack_pos + local.rotated(Vector3.UP, deg_to_rad(rack_yaw))


# ---------------------------------------------------------------- furniture --

## Adds a piece of furniture to the room (scenarios). Returns it.
func add_furniture(instance_id: StringName, def: FurnitureDefinition, pos: Vector3, yaw_degrees: float) -> SimFurniture:
	var piece := SimFurniture.new(instance_id, def, Vector3(pos.x, 0.0, pos.z), yaw_degrees)
	furniture[instance_id] = piece
	_rebuild_furniture_geometry()
	return piece


func get_furniture(instance_id: StringName) -> SimFurniture:
	return furniture.get(instance_id) as SimFurniture


## A flat piece (nothing blocks on it, like a rug) under a floor point, or "".
func flat_furniture_at(point: Vector3) -> StringName:
	for piece: SimFurniture in furniture.values():
		if piece.definition.blocks.is_empty() and piece.rect(piece.definition.area).has_point(Vector2(point.x, point.z)):
			return piece.id
	return &""


## The piece of furniture whose top covers a floor point (x, z), or "".
func furniture_top_at(point: Vector3) -> StringName:
	for piece: SimFurniture in furniture.values():
		if piece.definition.top.has_area() and piece.rect(piece.definition.top).has_point(Vector2(point.x, point.z)):
			return piece.id
	return &""


## Read-only check of putting a small device (placement "desk", like the router) on top of a
## piece of furniture at (x, z) turned `yaw`: "" if it fits, otherwise the reason.
func top_problem(device_id: int, furniture_id: StringName, pos: Vector3, yaw_degrees: float) -> String:
	var d := get_device(device_id)
	if d == null or not d.is_in_world() or d.location == &"mounted":
		return tr("Ese equipo no está en la habitación.")
	if d.definition.placement != &"desk":
		return tr("%s no va encima de los muebles.") % d.display_name()
	var piece := get_furniture(furniture_id)
	if piece == null or not piece.definition.top.has_area():
		return tr("%s va encima de un mueble: el escritorio o la mesilla.") % d.display_name()
	var rect := footprint_rect(d.definition, pos, yaw_degrees)
	if not piece.rect(piece.definition.top).encloses(rect):
		return tr("No cabe ahí: se saldría por el borde.")
	for reserved: Rect2 in piece.rects(piece.definition.top_reserved):
		if rect.intersects(reserved):
			return tr("No cabe ahí: ese sitio ya está ocupado.")
	for other: SimDevice in devices.values():
		if other != d and other.furniture_id == furniture_id and other.position.y > 0.01 and other.is_in_world() \
				and rect.intersects(footprint_rect(other.definition, other.position, other.yaw_degrees)):
			return tr("No cabe ahí: choca con %s.") % other.display_name()
	var saved := [d.position, d.yaw_degrees, d.furniture_id]
	d.position = Vector3(pos.x, piece.definition.top_height, pos.z)
	d.yaw_degrees = fposmod(round(yaw_degrees / 90.0) * 90.0, 360.0)
	d.furniture_id = furniture_id
	var problem := ""
	for cable_id: int in cable_ends:
		var ends: Dictionary = cable_ends[cable_id]
		if ends["b"] == "" or not (PortRef.device_id(ends["a"]) == d.id or PortRef.device_id(ends["b"]) == d.id):
			continue
		var route := route_between(ends["a"], ends["b"], _cable_length(cable_id))
		var spec := get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var name := get_device(cable_id).definition.model
		if not route["ok"]:
			problem = tr("Ahí el cable %s no tendría paso: %s") % [name, route["reason"]]
			break
		if route["length"] > spec.length_m:
			problem = tr("Ahí el cable %s no llegaría: harían falta unos %s m y mide %s m.") % [name, metres_needed(route["length"]), metres(spec.length_m, 0)]
			break
	d.position = saved[0]
	d.yaw_degrees = saved[1]
	d.furniture_id = saved[2]
	return problem


## Puts a small device on top of a piece of furniture (it then moves with that piece).
func place_on_furniture(device_id: int, furniture_id: StringName, pos: Vector3, yaw_degrees: float) -> CommandResult:
	var problem := top_problem(device_id, furniture_id, pos, yaw_degrees)
	if problem != "":
		return CommandResult.failure(problem)
	var d := get_device(device_id)
	var piece := get_furniture(furniture_id)
	d.position = Vector3(pos.x, piece.definition.top_height, pos.z)
	d.yaw_degrees = fposmod(round(yaw_degrees / 90.0) * 90.0, 360.0)
	d.furniture_id = furniture_id
	_emit(&"device_placed", {"device_id": d.id})
	_refresh()
	return CommandResult.success(tr("Hecho: %s está ahora sobre %s.") % [d.display_name(), piece.display_name()])


## Devices that go with a piece of furniture (on its top or belonging to it).
func carried_by(instance_id: StringName) -> Array[SimDevice]:
	var result: Array[SimDevice] = []
	for d: SimDevice in devices.values():
		if d.furniture_id == instance_id and d.is_in_world():
			result.append(d)
	return result


## Read-only check of moving a piece of furniture (with what it carries) to (pos, yaw): "" if
## it fits there, otherwise the reason (for the preview). Cables stay plugged: every cable must
## still have a way and be long enough with the piece at the new spot.
func furniture_problem(instance_id: StringName, pos: Vector3, yaw_degrees: float) -> String:
	var piece := get_furniture(instance_id)
	if piece == null:
		return tr("Ese mueble no está en la habitación.")
	var def := piece.definition
	if not room_bounds.encloses(piece.rect(def.area, pos, yaw_degrees)):
		return tr("No cabe ahí: se sale de la habitación.")
	var carried := carried_by(instance_id)
	var taken: Array[Rect2] = piece.rects(def.blocks, pos, yaw_degrees)
	for d: SimDevice in carried:
		if d.definition.placement == &"floor" and d.position.y < 0.01:
			var rect := footprint_rect(d.definition, piece.carry(d.position, pos, yaw_degrees),
					d.yaw_degrees + yaw_degrees - piece.yaw_degrees)
			if not room_bounds.encloses(rect):
				return tr("No cabe ahí: %s se saldría de la habitación.") % d.display_name()
			taken.append(rect)
	for rect: Rect2 in taken:
		var problem := _furniture_spot_problem(rect, piece, carried)
		if problem != "":
			return problem
	return _cable_problem_if_furniture_moved(piece, pos, yaw_degrees)


## What `rect` (floor a moved piece would take) collides with, or "".
func _furniture_spot_problem(rect: Rect2, piece: SimFurniture, carried: Array[SimDevice]) -> String:
	for other: SimFurniture in furniture.values():
		if other == piece:
			continue
		for block: Rect2 in other.rects(other.definition.blocks):
			if rect.intersects(block):
				return tr("No cabe ahí: choca con %s.") % other.display_name()
	for other: SimDevice in _floor_devices(null):
		if other in carried:
			continue
		if rect.intersects(footprint_rect(other.definition, other.position, other.yaw_degrees)):
			return tr("No cabe ahí: choca con %s.") % other.display_name()
	for package: Dictionary in packages.values():
		if rect.intersects(_package_rect(package)):
			return tr("No cabe ahí: hay un paquete en medio.")
	if rect.intersects(delivery_zone):
		return tr("Esa zona junto a la puerta está reservada para las entregas.")
	for door: Rect2 in door_zones:
		if rect.intersects(door):
			return tr("No cabe ahí: cerrarías el paso de la puerta.")
	for other: SimDevice in _floor_devices(null):
		for zone: Rect2 in service_zones(other.definition, other.position, other.yaw_degrees):
			if rect.intersects(zone):
				return tr("No cabe ahí: taparía el espacio de trabajo de %s.") % other.display_name()
	return ""


## With the piece (and what it carries) at the new spot, every complete cable is routed again.
func _cable_problem_if_furniture_moved(piece: SimFurniture, pos: Vector3, yaw_degrees: float) -> String:
	if cable_ends.is_empty():
		return ""
	var saved := _set_furniture_pose(piece, pos, yaw_degrees)
	var problem := ""
	for cable_id: int in cable_ends:
		var ends: Dictionary = cable_ends[cable_id]
		if ends["b"] == "":
			continue
		var route := route_between(ends["a"], ends["b"], _cable_length(cable_id))
		var spec := get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var name := get_device(cable_id).definition.model
		if not route["ok"]:
			problem = tr("Ahí cortaría el paso del cable %s: %s") % [name, route["reason"]]
			break
		if route["length"] > spec.length_m:
			problem = tr("Con %s ahí, el cable %s no llegaría: harían falta unos %s m y mide %s m.") % [piece.display_name(), name, metres_needed(route["length"]), metres(spec.length_m, 0)]
			break
	_restore_furniture_pose(saved)
	return problem


func move_furniture(instance_id: StringName, pos: Vector3, yaw_degrees: float) -> CommandResult:
	var problem := furniture_problem(instance_id, pos, yaw_degrees)
	if problem != "":
		return CommandResult.failure(problem)
	var piece := get_furniture(instance_id)
	_set_furniture_pose(piece, pos, yaw_degrees)
	_emit(&"furniture_moved", {"furniture_id": instance_id})
	_refresh()
	return CommandResult.success(tr("Hecho: %s está en su nuevo sitio.") % piece.display_name())


## Puts a piece and what it carries at (pos, yaw) and rebuilds the room geometry. Returns what
## _restore_furniture_pose needs to undo it.
func _set_furniture_pose(piece: SimFurniture, pos: Vector3, yaw_degrees: float) -> Array:
	var yaw := fposmod(round(yaw_degrees / 90.0) * 90.0, 360.0)
	var saved: Array = [piece, piece.position, piece.yaw_degrees, []]
	for d: SimDevice in carried_by(piece.id):
		(saved[3] as Array).append([d, d.position, d.yaw_degrees])
		d.position = piece.carry(d.position, pos, yaw)
		d.yaw_degrees = fposmod(d.yaw_degrees + yaw - piece.yaw_degrees, 360.0)
	piece.position = Vector3(pos.x, 0.0, pos.z)
	piece.yaw_degrees = yaw
	_rebuild_furniture_geometry()
	return saved


func _restore_furniture_pose(saved: Array) -> void:
	var piece := saved[0] as SimFurniture
	piece.position = saved[1]
	piece.yaw_degrees = saved[2]
	for entry: Array in saved[3]:
		var d := entry[0] as SimDevice
		d.position = entry[1]
		d.yaw_degrees = entry[2]
	_rebuild_furniture_geometry()


## `obstacles` and `cable_obstacles` from the furniture; cable routes are worked out again.
func _rebuild_furniture_geometry() -> void:
	obstacles.clear()
	cable_obstacles.clear()
	var ids: Array = furniture.keys()
	ids.sort()
	for instance_id: StringName in ids:
		var piece := furniture[instance_id] as SimFurniture
		obstacles.append_array(piece.rects(piece.definition.blocks))
		cable_obstacles.append_array(piece.rects(piece.definition.cable_parts))
	_router = null
	_route_cache.clear()
	_route_cache_version = -1


# ------------------------------------------------------------- cable routes --

## Route of a cable plugged at both ends (cached until the world changes). See route_between.
func cable_route(cable_id: int) -> Dictionary:
	if _route_cache_version != _state_version:
		_route_cache.clear()
		_route_cache_version = _state_version
	if not _route_cache.has(cable_id):
		var ends: Dictionary = cable_ends.get(cable_id, {"a": "", "b": ""})
		_route_cache[cable_id] = route_between(ends["a"], ends["b"], _cable_length(cable_id)) if ends["b"] != "" else {"ok": false, "reason": "", "length": 0.0}
	return _route_cache[cable_id]


## Where a cable between two ports lies and how long it has to be (docs/INTERACTION_SYSTEM.md §9):
##   {"ok", "reason", "length", "same_rack",
##    "floor": PackedVector2Array (x, z) from the floor exit of `a` to that of `b` (empty inside a rack),
##    "a"/"b": {"exit": Vector2, "height": socket height, "face", "side" (rack post: -1 / +1), "drop"}}
## Between two devices of one rack the cable goes through the rack; otherwise each end goes from
## its socket down to the floor next to its device (rack: down a post) and the floor part goes
## around furniture, floor devices and the delivery zone.
## The floor part is the tidy way (CableRouter: along walls and furniture, at right angles). If
## that is longer than `max_length` (the cable), the most compact way is used when it is shorter
## ("compact": true): a person with a short cable takes the shorter way, still tidy and clear.
func route_between(ref_a: String, ref_b: String, max_length: float = INF) -> Dictionary:
	var da := get_device(PortRef.device_id(ref_a))
	var db := get_device(PortRef.device_id(ref_b))
	if da == null or db == null or _floor_object(da) == null or _floor_object(db) == null:
		return {"ok": false, "reason": tr("Ese equipo no está instalado."), "length": 0.0}
	var ga := da.definition.find_port_group(PortRef.group(ref_a))
	var gb := db.definition.find_port_group(PortRef.group(ref_b))
	if da.location == &"mounted" and db.location == &"mounted" and da.rack_id == db.rack_id:
		return _rack_internal_route(get_device(da.rack_id), da, ga, db, gb)
	var end_a := _cable_end(da, ga, _center2(_floor_object(db)))
	var end_b := _cable_end(db, gb, end_a["exit"])
	end_a = _cable_end(da, ga, end_b["exit"])
	var rects := _floor_device_rects()
	var floor_path := _cable_router().find_path(end_a["exit"], end_b["exit"], rects)
	if floor_path.is_empty():
		return {"ok": false, "length": 0.0, "reason": tr("no hay por dónde llevarlo por el suelo entre %s y %s (muebles o equipos cierran el paso).") % [da.display_name(), db.display_name()]}
	var ends: float = end_a["drop"] + end_b["drop"] + CABLE_SLACK_M
	var total: float = ends + CableRouter.length_of(floor_path)
	var compact := false
	if total > max_length:
		var short_path := _cable_router().find_path(end_a["exit"], end_b["exit"], rects, 1.0)
		if not short_path.is_empty() and ends + CableRouter.length_of(short_path) < total - 0.005:
			floor_path = short_path
			total = ends + CableRouter.length_of(short_path)
			compact = true
	return {"ok": true, "reason": "", "length": total, "same_rack": false, "floor": floor_path, "a": end_a, "b": end_b, "compact": compact}


func _cable_length(cable_id: int) -> float:
	var cable := get_device(cable_id)
	var spec := cable.definition.get_spec(CableSpec) as CableSpec if cable != null else null
	return spec.length_m if spec != null else INF


## The shortest length a cable between two ports needs (the compact way), or INF if there is no
## way. For previews and estimates.
func needed_length(ref_a: String, ref_b: String) -> float:
	var route := route_between(ref_a, ref_b, 0.0)
	return route["length"] if route["ok"] else INF


## Two devices of one rack. Same face: the cable runs in front of that face. Front <-> rear: it
## crosses the rack through a free unit between them (or next to them); if every unit in
## between is taken it goes round the outside of the rack side. "cross_height" (or -1 for the
## side) tells the presentation where it crosses.
func _rack_internal_route(rack: SimDevice, da: SimDevice, ga: PortDefinition, db: SimDevice, gb: PortDefinition) -> Dictionary:
	var ea := _rack_post_end(rack, ga.face, _socket_height(da, ga), Vector2.INF)
	var eb := _rack_post_end(rack, gb.face, _socket_height(db, gb), Vector2.INF)
	var rise := absf(float(ea["height"]) - float(eb["height"]))
	var length := 2.0 * PORT_OUT_M + rise + RACK_CABLE_SLACK_M
	var cross := -1.0
	if ga.face != gb.face:
		var spec := rack.definition.get_spec(RackSpec) as RackSpec
		var low := mini(da.rack_u, db.rack_u)
		var high := maxi(da.rack_u + da.definition.mount_height_u - 1, db.rack_u + db.definition.mount_height_u - 1)
		for u: int in range(maxi(1, low - 1), mini(spec.capacity_u, high + 1) + 1):
			if units_free(rack, u, 1):
				var y := spec.first_unit_height_m + (u - 0.5) * RACK_UNIT_M
				if cross < 0.0 or absf(y - (ea["height"] + eb["height"]) / 2.0) < absf(cross - (ea["height"] + eb["height"]) / 2.0):
					cross = y
		length += rack.definition.footprint_m.y
		if cross < 0.0:
			length += rack.definition.footprint_m.x # round the outside of the side
		else:
			length += absf(cross - float(ea["height"])) + absf(cross - float(eb["height"])) - rise
	ea["cross_height"] = cross
	eb["cross_height"] = cross
	return {"ok": true, "reason": "", "length": length, "same_rack": true, "floor": PackedVector2Array(), "a": ea, "b": eb}


func _cable_router() -> CableRouter:
	if _router == null:
		var keepout: Array[Rect2] = []
		keepout.assign(door_zones)
		if delivery_zone.has_area():
			keepout.append(delivery_zone) # kept free for the boxes
		_router = CableRouter.new(room_bounds, cable_obstacles, obstacles, keepout, wall_trim_m)
	return _router


## The rack a mounted device is in, or the device itself if it stands in the room.
func _floor_object(d: SimDevice) -> SimDevice:
	if d.location == &"mounted":
		var rack := get_device(d.rack_id)
		return rack if rack != null and rack.location == &"placed" else null
	return d if d.location in [&"placed", &"fixed"] else null


func _floor_device_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for d: SimDevice in _floor_devices(null):
		rects.append(footprint_rect(d.definition, d.position, d.yaw_degrees))
	return rects


func _socket_height(d: SimDevice, group: PortDefinition) -> float:
	if d.location == &"mounted":
		var rack := get_device(d.rack_id)
		var spec := rack.definition.get_spec(RackSpec) as RackSpec
		return spec.first_unit_height_m + (d.rack_u - 1) * RACK_UNIT_M + group.height_m
	return d.position.y + group.height_m


func _center2(d: SimDevice) -> Vector2:
	return Vector2(d.position.x, d.position.z)


static func _to_world2(d: SimDevice, local: Vector2) -> Vector2:
	var v := Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, deg_to_rad(d.yaw_degrees))
	return Vector2(d.position.x + v.x, d.position.z + v.z)


## End of a cable at one socket: where it reaches the floor and how much cable that takes.
func _cable_end(d: SimDevice, group: PortDefinition, toward: Vector2) -> Dictionary:
	if d.location == &"mounted":
		return _rack_post_end(get_device(d.rack_id), group.face, _socket_height(d, group), toward)
	var fp := d.definition.footprint_m
	var height := _socket_height(d, group)
	if group.face == &"top":
		# Plugged from above (power strip): the cable lies down on the side that saves most cable.
		var best := {}
		for local: Vector2 in [Vector2(0, fp.y / 2 + EXIT_GAP_M), Vector2(0, -fp.y / 2 - EXIT_GAP_M),
				Vector2(fp.x / 2 + EXIT_GAP_M, 0), Vector2(-fp.x / 2 - EXIT_GAP_M, 0)]:
			var exit := _to_world2(d, local)
			var drop := PORT_OUT_M + height + local.length()
			if best.is_empty() or drop + exit.distance_to(toward) < best["drop"] + (best["exit"] as Vector2).distance_to(toward):
				best = {"exit": exit, "drop": drop}
		best["height"] = height
		best["face"] = group.face
		best["side"] = 0.0
		return best
	var sign := 1.0 if group.face == &"front" else -1.0
	var face_point := _to_world2(d, Vector2(0, sign * fp.y / 2))
	var exit := _to_world2(d, Vector2(0, sign * (fp.y / 2 + EXIT_GAP_M)))
	var outward := (exit - face_point).normalized()
	var over := 0.0
	# On top of a piece of furniture (router on the cabinet): over its top to the edge, then down.
	var steps := 0
	while d.position.y > 0.01 and steps < 150 and _over_top(d, exit):
		exit += outward * 0.01
		over += 0.01
		steps += 1
	return {"exit": exit, "drop": PORT_OUT_M + EXIT_GAP_M + over + height, "height": height, "face": group.face, "side": 0.0}


## A cable leaving a rack goes to the nearer post of that face and down it to the floor.
func _rack_post_end(rack: SimDevice, face: StringName, height: float, toward: Vector2) -> Dictionary:
	var fp := rack.definition.footprint_m
	var half_w := fp.x / 2.0 - RACK_POST_INSET_M
	var local_z := (1.0 if face == &"front" else -1.0) * (fp.y / 2.0 + EXIT_GAP_M)
	var best := {}
	for side: float in [1.0, -1.0]:
		var exit := _to_world2(rack, Vector2(side * half_w, local_z))
		if best.is_empty() or (toward != Vector2.INF and exit.distance_to(toward) < (best["exit"] as Vector2).distance_to(toward)):
			best = {"exit": exit, "side": side}
	best["drop"] = PORT_OUT_M + half_w + height + EXIT_GAP_M
	best["height"] = height
	best["face"] = face
	return best


## Over the top a raised device stands on (its piece of furniture), or else over any furniture.
func _over_top(d: SimDevice, p: Vector2) -> bool:
	var piece := get_furniture(d.furniture_id)
	if piece != null and piece.definition.top.has_area():
		return piece.rect(piece.definition.top).grow(CableRouter.CLEARANCE).has_point(p)
	return _over_furniture(p)


func _over_furniture(p: Vector2) -> bool:
	for rect: Rect2 in cable_obstacles:
		if rect.grow(CableRouter.CLEARANCE).has_point(p):
			return true
	return false


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


## Read-only: why the cable cannot go into that socket now ("" if it can, length aside): the
## socket must exist, be free and match the cable (RJ45 for network cables; for power, an outlet
## at one end and a power inlet at the other), and the second end must be on another device.
## The length is checked by cable_reach / connect_cable.
func cable_port_problem(cable_id: int, port_ref: String) -> String:
	var cable := get_device(cable_id)
	var spec := cable.definition.get_spec(CableSpec) as CableSpec if cable != null else null
	if spec == null or not (cable.location in [&"inventory", &"cabled"]):
		return tr("Elige un cable de tu inventario.")
	var ends: Dictionary = cable_ends.get(cable_id, {"a": "", "b": ""})
	if ends["b"] != "":
		return tr("Este cable ya está conectado por los dos extremos.")
	var target := get_device(PortRef.device_id(port_ref))
	var group := target.definition.find_port_group(PortRef.group(port_ref)) if target != null else null
	if group == null or PortRef.index(port_ref) >= group.count or not target.is_in_world():
		return tr("Ese puerto no existe.")
	if port_cable.has(port_ref):
		return tr("Ese puerto ya tiene un cable.")
	var is_power_port := group.kind in [PortDefinition.Kind.POWER_C13, PortDefinition.Kind.POWER_C14]
	if spec.media == &"copper" and group.kind != PortDefinition.Kind.RJ45:
		return tr("Es un cable de red (RJ45) y ese puerto no es RJ45.")
	if spec.media == &"power" and not is_power_port:
		return tr("Es un cable de corriente: une una toma de la regleta con la entrada de alimentación de un equipo.")
	if ends["a"] == "":
		return ""
	var first: String = ends["a"]
	if PortRef.device_id(first) == target.id:
		return tr("Los dos extremos irían al mismo equipo.")
	if spec.media == &"power":
		var first_group := get_device(PortRef.device_id(first)).definition.find_port_group(PortRef.group(first))
		if first_group.kind == group.kind:
			if group.kind == PortDefinition.Kind.POWER_C13:
				return tr("El otro extremo ya está en una toma: este tiene que ir a la entrada de alimentación de un equipo.")
			return tr("El otro extremo ya está en la entrada de un equipo: este tiene que ir a una toma de la regleta.")
	return ""


## Read-only, for the second end of a cable with a loose end: whether it reaches `port_ref`.
## {"ok", "length", "reason"}.
func cable_reach(cable_id: int, port_ref: String) -> Dictionary:
	var ends: Dictionary = cable_ends.get(cable_id, {"a": "", "b": ""})
	if ends["a"] == "" or ends["b"] != "":
		return {"ok": true, "length": 0.0, "reason": ""}
	var length := _cable_length(cable_id)
	var route := route_between(ends["a"], port_ref, length)
	if not route["ok"]:
		return {"ok": false, "length": 0.0, "reason": tr("No se puede conectar: %s") % route["reason"]}
	if route["length"] > length:
		return {"ok": false, "length": route["length"], "reason": tr("El cable no llega: por el suelo hacen falta unos %s m y este mide %s m.") % [metres_needed(route["length"]), metres(length, 0)]}
	return {"ok": true, "length": route["length"], "reason": ""}


## Read-only: free sockets in the room where the cable fits now (cable_port_problem == "").
func compatible_ports(cable_id: int) -> Array[String]:
	var result: Array[String] = []
	for d: SimDevice in devices.values():
		if not d.is_in_world():
			continue
		for ref: String in d.port_refs():
			if not port_cable.has(ref) and cable_port_problem(cable_id, ref) == "":
				result.append(ref)
	return result


## Gives up a cable being laid: its plugged end (if any) is unplugged and it goes back to the
## inventory (ADR 0011). A cable plugged at both ends is not touched.
func cancel_cable(cable_id: int) -> CommandResult:
	var ends: Dictionary = cable_ends.get(cable_id, {})
	if ends.is_empty():
		return CommandResult.success("")
	if ends["b"] != "":
		return CommandResult.failure(tr("Ese cable ya está conectado por los dos extremos."))
	return disconnect_port(ends["a"])


func connect_cable(cable_id: int, port_ref: String) -> CommandResult:
	var problem := cable_port_problem(cable_id, port_ref)
	if problem != "":
		return CommandResult.failure(problem)
	var cable := get_device(cable_id)
	var spec := cable.definition.get_spec(CableSpec) as CableSpec
	var ends: Dictionary = cable_ends.get(cable_id, {"a": "", "b": ""})
	if ends["a"] == "":
		ends["a"] = port_ref
		cable_ends[cable_id] = ends
		port_cable[port_ref] = cable_id
		cable.location = &"cabled"
		_emit(&"cable_plugged", {"cable_id": cable_id, "port": port_ref})
		return CommandResult.success(tr("Extremo conectado. Ahora conecta el otro extremo."))
	var first: String = ends["a"]
	var route := route_between(first, port_ref, spec.length_m)
	if not route["ok"]:
		return CommandResult.failure(tr("No se puede conectar: %s") % route["reason"])
	if route["length"] > spec.length_m:
		return CommandResult.failure(tr("El cable no llega: por el suelo hacen falta unos %s m y este mide %s m.") % [metres_needed(route["length"]), metres(spec.length_m, 0)])
	ends["b"] = port_ref
	port_cable[port_ref] = cable_id
	cable.used = true
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


## True if the device, or anything mounted in it, has a cable plugged in (even a loose end).
func has_cables_inside(d: SimDevice) -> bool:
	var inside: Array[SimDevice] = [d]
	inside.append_array(mounted_in(d))
	for device: SimDevice in inside:
		for ref: String in device.port_refs():
			if port_cable.has(ref):
				return true
	return false


# -------------------------------------------------------------- save / load --

## Everything that changes while playing (docs/ARCHITECTURE.md §7). The room itself (bounds,
## furniture, delivery zone) belongs to the scenario and is rebuilt by it, not saved.
## Lists are sorted by id so the same state always produces the same text.
func save_state() -> Dictionary:
	var device_list: Array = []
	var ids: Array = devices.keys()
	ids.sort()
	for device_id: int in ids:
		device_list.append((devices[device_id] as SimDevice).save_state())
	var package_list: Array = []
	var package_ids: Array = packages.keys()
	package_ids.sort()
	for package_id: int in package_ids:
		var p: Dictionary = packages[package_id]
		var pos: Vector3 = p["position"]
		package_list.append({"id": p["id"], "device_ids": Array(p["device_ids"]), "position": [pos.x, pos.y, pos.z]})
	var order_list: Array = []
	for order: Dictionary in orders:
		order_list.append({"id": order["id"], "eta": order["eta"], "groups": order["groups"].duplicate(true),
			"total": order["total"], "delivered": order["delivered"]})
	var cable_list: Array = []
	var cable_ids: Array = cable_ends.keys()
	cable_ids.sort()
	for cable_id: int in cable_ids:
		cable_list.append({"cable": cable_id, "a": cable_ends[cable_id]["a"], "b": cable_ends[cable_id]["b"]})
	return {
		"time_minutes": time_minutes,
		"speed": speed,
		"credits": credits,
		"xp": xp,
		"next_id": _next_id,
		"devices": device_list,
		"packages": package_list,
		"orders": order_list,
		"cables": cable_list,
		"mission": mission.save_state() if mission != null else {},
		"economy": economy.save_state(),
		"furniture": _furniture_state(),
	}


func _furniture_state() -> Array:
	var result: Array = []
	var ids: Array = furniture.keys()
	ids.sort()
	for instance_id: StringName in ids:
		result.append((furniture[instance_id] as SimFurniture).save_state())
	return result


## Replaces the dynamic state with a save_state() dictionary (also after a JSON round trip,
## where every number is a float and dictionary keys are strings).
func load_state(data: Dictionary) -> void:
	devices.clear()
	packages.clear()
	orders.clear()
	cable_ends.clear()
	port_cable.clear()
	time_minutes = float(data["time_minutes"])
	speed = float(data["speed"])
	credits = int(data["credits"])
	xp = int(data["xp"])
	_next_id = int(data["next_id"])
	for saved: Dictionary in data["devices"]:
		var d := SimDevice.from_state(saved, catalog)
		if d != null:
			devices[d.id] = d
	for saved: Dictionary in data["packages"]:
		var ids: Array[int] = []
		for device_id: Variant in saved["device_ids"]:
			ids.append(int(device_id))
		var p: Array = saved["position"]
		packages[int(saved["id"])] = {"id": int(saved["id"]), "device_ids": ids,
			"position": Vector3(float(p[0]), float(p[1]), float(p[2]))}
	for saved: Dictionary in data["orders"]:
		var groups: Array = []
		for group: Array in saved["groups"]:
			var ids: Array[int] = []
			for device_id: Variant in group:
				ids.append(int(device_id))
			groups.append(ids)
		orders.append({"id": int(saved["id"]), "eta": float(saved["eta"]), "groups": groups,
			"total": int(saved["total"]), "delivered": bool(saved["delivered"])})
	# Saves of version 1 do not say what was bought: everything in an order was.
	var saved_devices: Array = data["devices"]
	if not saved_devices.is_empty() and not (saved_devices[0] as Dictionary).has("bought"):
		for order: Dictionary in orders:
			for group: Array in order["groups"]:
				for device_id: int in group:
					if devices.has(device_id):
						(devices[device_id] as SimDevice).bought = true
	for saved: Dictionary in data["cables"]:
		var cable_id := int(saved["cable"])
		var ends := {"a": String(saved["a"]), "b": String(saved["b"])}
		cable_ends[cable_id] = ends
		port_cable[ends["a"]] = cable_id
		if ends["b"] != "":
			port_cable[ends["b"]] = cable_id
	var saved_mission: Dictionary = data.get("mission", {})
	mission = MissionTracker.from_state(saved_mission) if not saved_mission.is_empty() else null
	economy = Economy.new(economy.rules)
	economy.load_state(data.get("economy", {}))
	# Where each piece of furniture stands (saves before version 3: the starting layout).
	for saved: Dictionary in data.get("furniture", []):
		var piece := get_furniture(StringName(saved["id"]))
		if piece != null:
			var p: Array = saved["position"]
			piece.position = Vector3(float(p[0]), 0.0, float(p[2]))
			piece.yaw_degrees = float(saved["yaw"])
	_rebuild_furniture_geometry()
	_gather_packages() # boxes always wait in one stack at the (current) delivery spot
	_emit(&"state_loaded", {})


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
	_state_version += 1
	event_emitted.emit(type, data)
