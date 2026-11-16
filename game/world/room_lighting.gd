class_name RoomLighting
extends RefCounted
## The lighting of the room (docs/ART_STYLE.md §5): environment, warm sun through the window and
## a ceiling lamp. Shared by the game and the character creator preview, so the character looks
## the same in both.


## `with_lamp`: the ceiling lamp. The character creator leaves it out: there it would hang a
## metre from the head and wash the colours out (in the room it is 2.3 m up, over the middle).
static func add_to(parent: Node, with_lamp: bool = true) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.118, 0.141, 0.188)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.92)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 160, 0)
	sun.light_color = Color(1, 0.91, 0.78)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 12.0
	parent.add_child(sun)
	if not with_lamp:
		return
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.2, 2.3, -0.2)
	lamp.light_color = Color(1, 0.85, 0.66)
	lamp.light_energy = 1.1
	lamp.omni_range = 5.5
	lamp.shadow_enabled = true
	parent.add_child(lamp)
