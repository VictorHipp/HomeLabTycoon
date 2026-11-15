extends TestCase
## Catalog data rules (docs/HARDWARE_CATALOG.md §9).


func test_catalog_is_valid() -> void:
	var catalog := Catalog.load_default()
	assert_true(catalog.items.size() >= 9, "prototype catalog loaded")
	for problem: String in catalog.validate():
		_fail(problem)


func test_ids_match_file_names() -> void:
	var dir := DirAccess.open(Catalog.CATALOG_DIR)
	for file: String in dir.get_files():
		var res_file := file.trim_suffix(".remap")
		if res_file.get_extension() != "tres":
			continue
		var def := load(Catalog.CATALOG_DIR.path_join(res_file)) as HardwareDefinition
		assert_eq(String(def.id), res_file.get_basename(), "id == file name")


func test_prototype_items_present() -> void:
	var catalog := Catalog.load_default()
	for item_id: StringName in [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_3m", &"power_cord_3m"]:
		var def := catalog.get_item(item_id)
		assert_true(def != null and def.purchasable, "%s purchasable" % item_id)


## The face and height of each port group (used by the cable router in sim/) must match where
## the model really has the sockets.
func test_port_faces_and_heights_match_the_models() -> void:
	var catalog := Catalog.load_default()
	var outward := {&"front": Vector3(0, 0, 1), &"rear": Vector3(0, 0, -1), &"top": Vector3(0, 1, 0)}
	for def: HardwareDefinition in catalog.items.values():
		if def.model_path == "" or def.ports.is_empty():
			continue
		var model := (load(def.model_path) as PackedScene).instantiate() as Node3D
		for group: PortDefinition in def.ports:
			assert_true(outward.has(group.face), "%s.%s: known face" % [def.id, group.id])
			for i: int in group.count:
				var marker := ModelUtil.marker_transform(model, PortRef.marker_name(group.kind, group.id, i))
				if not marker["found"]:
					continue
				var xf: Transform3D = marker["transform"]
				var dir: Vector3 = outward.get(group.face, Vector3.ZERO)
				assert_true(xf.basis.z.normalized().dot(dir) > 0.9, "%s.%s %d faces %s" % [def.id, group.id, i, group.face])
				assert_almost(xf.origin.y, group.height_m, 0.03, "%s.%s %d socket height" % [def.id, group.id, i])
		model.free()


func test_model_markers_match_ports() -> void:
	# The marker names the presentation looks for must follow the port groups of the data.
	assert_eq(PortRef.marker_name(PortDefinition.Kind.RJ45, &"lan", 3), "PORT_lan_3", "rj45 marker")
	assert_eq(PortRef.marker_name(PortDefinition.Kind.POWER_C14, &"psu", 0), "POWER_IN_1", "inlet marker")
	assert_eq(PortRef.marker_name(PortDefinition.Kind.POWER_C13, &"outlet", 1), "POWER_OUT_2", "outlet marker")
