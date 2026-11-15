extends TestCase
## Overview camera rig (docs/CAMERA_SYSTEM.md §3): limits, smoothing and framing.

var rig: OverviewCameraRig


func before_each() -> void:
	rig = OverviewCameraRig.new()


func test_pose_looks_at_focus() -> void:
	var focus := Vector3(0.1, 0.5, -0.3)
	var pose := OverviewCameraRig.pose_for(focus, 37.4, 30.6, 7.46)
	assert_almost(pose.origin.distance_to(focus), 7.46, 0.001, "distance")
	var look := -pose.basis.z
	assert_almost(look.dot((focus - pose.origin).normalized()), 1.0, 0.0001, "camera looks at the focus")
	assert_true(pose.origin.y > focus.y, "elevated camera")
	rig.free()


func test_limits() -> void:
	rig.tilt_by(500.0)
	assert_almost(rig.target_pitch_deg, rig.pitch_max_deg, 0.001, "pitch max")
	rig.tilt_by(-500.0)
	assert_almost(rig.target_pitch_deg, rig.pitch_min_deg, 0.001, "pitch min")
	for i: int in 50:
		rig.zoom_by(0.5)
	assert_almost(rig.target_distance, rig.distance_min, 0.001, "zoom in limit")
	for i: int in 50:
		rig.zoom_by(2.0)
	assert_almost(rig.target_distance, rig.distance_max, 0.001, "zoom out limit")
	rig.pan_by(Vector2(100.0, 100.0))
	assert_true(rig.bounds.grow(0.001).has_point(rig.target_focus), "focus stays in the room")
	rig.free()


func test_rotation_is_smooth_and_converges() -> void:
	rig.snap()
	var start := rig.target_yaw_deg
	rig.rotate_by(90.0)
	rig.step(0.016)
	var first := rig.current_pose()
	var expected_end := OverviewCameraRig.pose_for(rig.target_focus, start + 90.0, rig.target_pitch_deg, rig.target_distance)
	assert_true(first.origin.distance_to(expected_end.origin) > 0.5, "does not jump in one frame")
	for i: int in 120:
		rig.step(0.016)
	assert_almost(rig.current_pose().origin.distance_to(expected_end.origin), 0.0, 0.01, "reaches the target")
	rig.free()
