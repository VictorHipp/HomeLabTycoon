extends TestCase
## Procedural walk of the articulated mannequin (game/character/character_animator.gd): the foot on
## the floor must not slide or sink while the body moves, at any speed, and the legs must stop
## when the body stops.


func _world(n: Node) -> Vector3:
	var xf := Transform3D.IDENTITY
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin


func test_planted_foot_does_not_slide_or_sink() -> void:
	var root := Node3D.new()
	var model := ModelUtil.instance_model(PlayerCharacter.MODEL)
	root.add_child(model)
	var anim := CharacterAnimator.new()
	anim.setup(model)
	assert_true(anim.is_articulated(), "the mannequin has its 10 joints")
	var ankles := {"L": model.find_child("J_ankle_L", true, false), "R": model.find_child("J_ankle_R", true, false)}
	var dt := 1.0 / 60.0
	for speed: float in [1.4, 0.8, 0.45]:
		var drift := 0.0
		var lowest := INF
		var highest := -INF
		var start := {}
		for i: int in 900:
			var step := speed * dt
			root.position.z += step
			anim.update(dt, step, speed)
			if anim.walk_weight < 0.99:
				continue
			for side: String in ["L", "R"]:
				var p := _world(ankles[side])
				if anim.in_stance(side):
					if not start.has(side):
						start[side] = p
					drift = maxf(drift, Vector2(p.x - (start[side] as Vector3).x, p.z - (start[side] as Vector3).z).length())
					lowest = minf(lowest, p.y)
					highest = maxf(highest, p.y)
				else:
					start.erase(side)
		assert_true(drift < 0.01, "speed %.2f: planted foot slides %.4f m" % [speed, drift])
		assert_true(highest - lowest < 0.005, "speed %.2f: planted ankle height varies %.4f m" % [speed, highest - lowest])
	root.free()


func test_legs_stop_when_the_body_stops() -> void:
	var root := Node3D.new()
	var model := ModelUtil.instance_model(PlayerCharacter.MODEL)
	root.add_child(model)
	var anim := CharacterAnimator.new()
	anim.setup(model)
	for i: int in 60:
		anim.update(1.0 / 60.0, 1.4 / 60.0, 1.4)
	assert_true(anim.walk_weight > 0.9, "walking")
	var phase := anim.phase
	for i: int in 60:
		anim.update(1.0 / 60.0, 0.0, 0.0) # blocked: no distance travelled
	assert_eq(anim.phase, phase, "no distance, no step")
	assert_true(anim.walk_weight < 0.05, "blends back to standing")
	anim.sit_weight = 1.0
	anim.update(1.0 / 60.0, 0.0, 0.0)
	assert_true(model.position.y < -0.25, "seated: the body goes down onto the seat")
	root.free()
