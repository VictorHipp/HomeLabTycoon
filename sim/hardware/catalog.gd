class_name Catalog
extends RefCounted
## Loads every HardwareDefinition of res://data/catalog/ (docs/HARDWARE_CATALOG.md §3.3)
## and validates the rules of §9.

const CATALOG_DIR := "res://data/catalog"
const KNOWN_CATEGORIES: PackedStringArray = ["rack", "server", "switch", "router", "computer", "cable", "power"]

var items: Dictionary = {} ## StringName -> HardwareDefinition


static func load_default() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_dir(CATALOG_DIR)
	return catalog


func load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Catalog: cannot open %s" % dir_path)
		return
	for file: String in dir.get_files():
		# Exported games list "<name>.tres.remap"; the resource path stays "<name>.tres".
		var res_file := file.trim_suffix(".remap")
		if res_file.get_extension() != "tres":
			continue
		var def := load(dir_path.path_join(res_file)) as HardwareDefinition
		if def == null:
			push_error("Catalog: %s is not a HardwareDefinition" % res_file)
			continue
		items[def.id] = def


func get_item(item_id: StringName) -> HardwareDefinition:
	return items.get(item_id) as HardwareDefinition


func purchasable_items() -> Array[HardwareDefinition]:
	var result: Array[HardwareDefinition] = []
	for def: HardwareDefinition in items.values():
		if def.purchasable:
			result.append(def)
	result.sort_custom(func(a: HardwareDefinition, b: HardwareDefinition) -> bool:
		return [KNOWN_CATEGORIES.find(a.category), a.price] < [KNOWN_CATEGORIES.find(b.category), b.price])
	return result


## Returns human-readable rule violations (empty = valid). File names are checked by the caller.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var id_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for def: HardwareDefinition in items.values():
		var tag := String(def.id)
		if id_pattern.search(String(def.id)) == null:
			problems.append("%s: id must be non-empty snake_case (a-z, 0-9, _)" % tag)
		if not KNOWN_CATEGORIES.has(String(def.category)):
			problems.append("%s: unknown category %s" % [tag, def.category])
		if def.purchasable and def.price <= 0:
			problems.append("%s: purchasable items need price > 0" % tag)
		if def.power_idle_watts > def.power_max_watts:
			problems.append("%s: idle power above max power" % tag)
		if def.placement == &"rack" and def.mount_height_u < 1:
			problems.append("%s: rack-mounted items need mount_height_u >= 1" % tag)
		if def.category == &"rack":
			var rack := def.get_spec(RackSpec) as RackSpec
			if rack == null or rack.capacity_u <= 0:
				problems.append("%s: racks need a RackSpec with capacity_u > 0" % tag)
		if def.category == &"cable" and def.get_spec(CableSpec) == null:
			problems.append("%s: cables need a CableSpec" % tag)
		var seen: Array[StringName] = []
		for group: PortDefinition in def.ports:
			if seen.has(group.id):
				problems.append("%s: duplicated port group %s" % [tag, group.id])
			seen.append(group.id)
			if group.count < 1:
				problems.append("%s: port group %s needs count >= 1" % [tag, group.id])
			var is_power := group.kind in [PortDefinition.Kind.POWER_C13, PortDefinition.Kind.POWER_C14]
			if is_power and group.speed_mbps != 0:
				problems.append("%s: power port group %s must have speed 0" % [tag, group.id])
			if not is_power and group.speed_mbps <= 0:
				problems.append("%s: data port group %s needs speed > 0" % [tag, group.id])
			if group.poe_budget_watts > 0.0 and group.kind != PortDefinition.Kind.RJ45:
				problems.append("%s: PoE only on RJ45 groups" % tag)
		for extra: StringName in def.box_contents:
			if not items.has(extra):
				problems.append("%s: box content %s does not exist" % [tag, extra])
		if def.model_path != "" and not ResourceLoader.exists(def.model_path):
			problems.append("%s: model %s not found" % [tag, def.model_path])
	return problems
