class_name ShopSpecs
extends RefCounted
## The specs table and the "in the box" line of a shop page, built only from the catalog data
## (HardwareDefinition and its specs) and the economy rules, so the shop can never disagree with
## what the simulation does.


## [[name, value], ...] for one item.
static func rows(world: SimWorld, def: HardwareDefinition) -> Array:
	var result: Array = [
		[TranslationServer.translate("Marca"), def.brand],
		[TranslationServer.translate("Modelo"), def.model],
		[TranslationServer.translate("Tipo"), _category(def.category)],
	]
	var rack := def.get_spec(RackSpec) as RackSpec
	if rack != null:
		result.append([TranslationServer.translate("Capacidad"), TranslationServer.translate("%dU de 19\" (1U = 44,45 mm)") % rack.capacity_u])
		result.append([TranslationServer.translate("Espacio de trabajo"), TranslationServer.translate("%d cm libres delante y detrás") % roundi(rack.service_clearance_m * 100.0)])
	if def.placement == &"floor" and def.footprint_m != Vector2.ZERO:
		result.append([TranslationServer.translate("Huella en el suelo"), TranslationServer.translate("%s × %s cm") % [_cm(def.footprint_m.x), _cm(def.footprint_m.y)]])
	if def.placement == &"rack":
		result.append([TranslationServer.translate("Montaje"), TranslationServer.translate("En rack de 19\", ocupa %dU") % def.mount_height_u])
		result.append([TranslationServer.translate("Fondo"), TranslationServer.translate("%s cm") % _cm(def.footprint_m.y)])
	var ports: Array[String] = []
	for group: PortDefinition in def.ports:
		ports.append(_ports(group))
	if not ports.is_empty():
		result.append([TranslationServer.translate("Conexiones"), "\n".join(ports)])
	if def.power_max_watts > 0.0:
		result.append([TranslationServer.translate("Consumo"), TranslationServer.translate("%d W en reposo · %d W como máximo") % [roundi(def.power_idle_watts), roundi(def.power_max_watts)]])
	if def.boot_minutes > 0.0:
		result.append([TranslationServer.translate("Encendido"), (TranslationServer.translate("botón de encendido; ") if def.has_power_button else TranslationServer.translate("sin botón: arranca al recibir corriente; ")) + TranslationServer.translate("tarda %s en arrancar") % _minutes(def.boot_minutes)])
	var host := def.get_spec(HostSpec) as HostSpec
	if host != null:
		var network: String = TranslationServer.translate("IP por DHCP") if host.eth0_mode == &"dhcp" else TranslationServer.translate("sin IP: se la asignas tú desde la consola")
		result.append([TranslationServer.translate("Sistema"), TranslationServer.translate("%s · usuario %s · %s") % [host.os_name, host.login_user, network]])
	var cable := def.get_spec(CableSpec) as CableSpec
	if cable != null:
		result.append([TranslationServer.translate("Longitud"), TranslationServer.translate("%s m") % SimWorld.metres(cable.length_m, 0)])
		if cable.media == &"copper":
			result.append([TranslationServer.translate("Tipo de cable"), TranslationServer.translate("red, RJ45 en los dos extremos, hasta %d Mb/s") % cable.max_speed_mbps])
		else:
			result.append([TranslationServer.translate("Tipo de cable"), TranslationServer.translate("corriente: de una toma de la regleta a la entrada de alimentación de un equipo")])
	if def.online_income_per_hour > 0:
		result.append([TranslationServer.translate("Ingresos en línea"), TranslationServer.translate("+%d cr por hora de juego mientras esté encendido y accesible desde tu PC (tope diario de %d cr entre todos los equipos)") % [def.online_income_per_hour, world.economy.rules.passive_daily_cap]])
	result.append([TranslationServer.translate("Reventa"), TranslationServer.translate("Segunda mano: %d cr sin estrenar · %d cr usado") % [def.price * world.economy.rules.resale_unused_percent / 100, def.price * world.economy.rules.resale_used_percent / 100]])
	return result


static func in_the_box(world: SimWorld, def: HardwareDefinition) -> String:
	var parts: Array[String] = ["1 × " + def.display_name()]
	for extra: StringName in def.box_contents:
		var item := world.catalog.get_item(extra)
		if item != null:
			parts.append("1 × " + item.display_name())
	return " · ".join(parts)


static func _ports(group: PortDefinition) -> String:
	var where := {&"front": TranslationServer.translate("delante"), &"rear": TranslationServer.translate("detrás"), &"top": TranslationServer.translate("arriba")}.get(group.face, "") as String
	match group.kind:
		PortDefinition.Kind.POWER_C14:
			return TranslationServer.translate("%d × entrada de alimentación (%s)") % [group.count, where]
		PortDefinition.Kind.POWER_C13:
			return TranslationServer.translate("%d × toma de corriente (%s)") % [group.count, where]
		PortDefinition.Kind.RJ45:
			var speed: String = TranslationServer.translate("%d Gb/s") % (group.speed_mbps / 1000) if group.speed_mbps >= 1000 else TranslationServer.translate("%d Mb/s") % group.speed_mbps
			return TranslationServer.translate("%d × RJ45 %s (%s)") % [group.count, speed, where]
	return "%d × %s" % [group.count, PortDefinition.Kind.keys()[group.kind]]


static func _category(category: StringName) -> String:
	match category:
		&"rack":
			return TranslationServer.translate("Rack")
		&"server":
			return TranslationServer.translate("Servidor")
		&"switch":
			return TranslationServer.translate("Switch")
		&"router":
			return TranslationServer.translate("Router")
		&"cable":
			return TranslationServer.translate("Cable")
		&"power":
			return TranslationServer.translate("Alimentación")
	return String(category)


static func _cm(metres: float) -> String:
	var value := metres * 100.0
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value).replace(".", ",")


static func _minutes(minutes: float) -> String:
	if minutes < 1.0:
		return TranslationServer.translate("%d s") % roundi(minutes * 60.0)
	return TranslationServer.translate("%s min") % ("%.1f" % minutes).replace(".", ",").trim_suffix(",0")
