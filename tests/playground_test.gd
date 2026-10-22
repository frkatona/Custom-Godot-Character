extends SceneTree
## Run: godot_console --headless --path . --fixed-fps 60 --script tests/playground_test.gd
## Omit --headless and add -- --screenshots to render verification images in .godot/.

var scene: Node3D
var player: CharacterBody3D
var seen: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/playground.tscn").instantiate()
	player = scene.get_node("Character")
	player.capture_mouse_on_start = false
	root.add_child(scene)
	await step(40)
	check(player.is_on_floor(), "Character settles onto the floor")
	check(player.animation_clip == &"basis", "Basis is the idle pose")
	await screenshot("playground_overview")
	var start := player.global_position
	Input.action_press("move_forward")
	await step(30)
	check(player.global_position.z < start.z - 1.5, "Camera-relative run moves forward")
	check(player.animation_clip == &"run", "Run animation follows movement")
	Input.action_press("aim")
	await step(15)
	check(player.animation_tree.aim_weight > 0.99, "Aim fades in while running")
	await screenshot("playground_run_aim")
	Input.action_press("jump")
	await step(8)
	check(not player.is_on_floor() and player.velocity.y > 0.0, "Jump launches the body")
	check(player.animation_clip == &"jumpStart", "Takeoff plays jumpStart")
	check(player.animation_tree.aim_weight > 0.99, "Aim stays blended during jumpStart")
	await screenshot("playground_jump_aim")
	Input.action_release("move_forward")
	await step(21)
	check(player.animation_clip == &"falling", "Airborne motion reaches falling")
	Input.action_release("jump")
	await step(9)
	check(seen.has(&"jumpLand"), "Ground contact plays jumpLand")
	Input.action_release("aim")
	await step(35)
	check(player.animation_tree.aim_weight < 0.01, "Aim fades out")
	await verify_slide()
	await verify_wall()
	await verify_zipline()
	await verify_buffer_and_coyote()
	await verify_aim_mask()
	player.global_position = Vector3(0, -10, 0)
	await step(3)
	check(player.global_position.distance_to(player.spawn_transform.origin) < 0.2, "Falling off the course resets the character")
	for clip in [&"basis", &"run", &"jumpStart", &"falling", &"jumpLand", &"sliding", &"wallHolding", &"zipping"]:
		check(seen.has(clip), "Played animation: %s" % clip)
	if failures.is_empty():
		print("PASS: movement, jump phases, slide clearance, wall hold/jump, zipline, reset and aim bone isolation")
	else:
		for failure in failures:
			push_error(failure)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func verify_slide() -> void:
	player.respawn()
	player.global_position = Vector3(5.5, 0.02, 5.5)
	await step(5)
	Input.action_press("move_forward")
	await step(7)
	check(player.global_position.z > 4.9, "Standing capsule cannot enter the low tunnel")
	Input.action_press("slide")
	await step(10)
	Input.action_release("slide")
	check(player.animation_clip == &"sliding", "Slide plays sliding")
	check(player.standing_shape.disabled and not player.sliding_shape.disabled, "Slide uses a smaller capsule")
	# Let the timer expire under the ceiling: standing must remain blocked.
	player._slide_left = 0.01
	await step(2)
	check(player.mode == player.Mode.SLIDING, "Slide cannot stand up inside the tunnel")
	await step(55)
	Input.action_release("move_forward")
	check(player.global_position.z < 1.0, "Slide clears the tunnel")
	check(player.mode == player.Mode.NORMAL and not player.standing_shape.disabled, "Standing capsule returns after tunnel exit")

func verify_wall() -> void:
	player.respawn()
	player.global_position = Vector3(0, 0.02, -6.5)
	await step(5)
	Input.action_press("move_forward")
	Input.action_press("jump")
	Input.action_press("interact")
	await step(10)
	Input.action_release("jump")
	check(player.mode == player.Mode.WALL_HOLD, "E catches the wall in midair")
	check(player.animation_clip == &"wallHolding", "Wall hold plays wallHolding")
	var height := player.global_position.y
	await step(10)
	check(absf(player.global_position.y - height) < 0.02, "Wall hold suspends gravity")
	await screenshot("playground_wall_hold")
	Input.action_press("jump")
	await step(1)
	check(player.mode == player.Mode.NORMAL and player.velocity.y > 0.0 and player.velocity.z > 0.0, "Space pushes away from the wall")
	Input.action_release("jump")
	Input.action_release("interact")
	Input.action_release("move_forward")
	await step(50)

func verify_zipline() -> void:
	player.respawn()
	var line := scene.get_node("Zipline")
	player.global_position = line.get_start_position()
	await step(2)
	Input.action_press("interact")
	await step(5)
	Input.action_release("interact")
	check(player.mode == player.Mode.ZIPLINE, "E attaches at the zipline start")
	check(player.animation_clip == &"zipping", "Zipline plays zipping")
	var start := player.global_position
	await step(20)
	check(player.global_position.z > start.z + 1.5, "Zipline carries the character along its cable")
	await screenshot("playground_zipline")
	await step(100)
	check(player.mode == player.Mode.NORMAL, "Zipline releases at its endpoint")
	# Also verify early dismount.
	player.global_position = line.get_start_position()
	await step(2)
	Input.action_press("interact")
	await step(3)
	Input.action_release("interact")
	Input.action_press("jump")
	await step(1)
	check(player.mode == player.Mode.NORMAL and player.velocity.y > 0.0, "Space jumps off the zipline early")
	Input.action_release("jump")

func verify_buffer_and_coyote() -> void:
	player.respawn()
	await step(5)
	player.global_position = Vector3(0, 0.15, 5)
	player.velocity.y = -3.0
	player._coyote_left = 0.0
	await step(1)
	player._coyote_left = 0.0
	Input.action_press("jump")
	await step(4)
	check(player.velocity.y > 0.0, "Buffered jump fires on landing")
	Input.action_release("jump")
	player.respawn()
	await step(5)
	player.global_position = Vector3(16.5, 0.05, 5)
	await step(2)
	Input.action_press("jump")
	await step(1)
	check(player.velocity.y > 0.0, "Coyote jump works after leaving a ledge")
	Input.action_release("jump")

func verify_aim_mask() -> void:
	# Two independent instances sample the same animation time. Aim must change
	# the arm and head without changing hips, legs, torso, or the left arm.
	var neutral: CharacterBody3D = load("res://scenes/character.tscn").instantiate()
	var aimed: CharacterBody3D = load("res://scenes/character.tscn").instantiate()
	neutral.capture_mouse_on_start = false
	aimed.capture_mouse_on_start = false
	root.add_child(neutral)
	root.add_child(aimed)
	neutral.set_physics_process(false)
	aimed.set_physics_process(false)
	neutral.get_node("squirrelLady/rigify_rig/Skeleton3D/bone_spring").active = false
	aimed.get_node("squirrelLady/rigify_rig/Skeleton3D/bone_spring").active = false
	var a: Skeleton3D = neutral.get_node("squirrelLady/rigify_rig/Skeleton3D")
	var b: Skeleton3D = aimed.get_node("squirrelLady/rigify_rig/Skeleton3D")
	for clip in [&"run", &"jumpStart", &"falling", &"jumpLand"]:
		for frame in 25:
			neutral.animation_tree.update_pose(clip, false, 1.0, 1.0 / 60.0)
			aimed.animation_tree.update_pose(clip, true, 1.0, 1.0 / 60.0)
		for bone in [&"DEF-spine", &"DEF-spine.002", &"DEF-thigh.L", &"DEF-shin.R", &"DEF-upper_arm.L"]:
			var index := a.find_bone(bone)
			check(a.get_bone_pose(index).is_equal_approx(b.get_bone_pose(index)), "%s + aim preserves %s" % [clip, bone])
		for bone in [&"DEF-upper_arm.R", &"DEF-spine.006"]:
			var index := a.find_bone(bone)
			check(not a.get_bone_pose_rotation(index).is_equal_approx(b.get_bone_pose_rotation(index)), "%s + aim changes %s" % [clip, bone])
	neutral.queue_free()
	aimed.queue_free()

func step(frames: int) -> void:
	for frame in frames:
		await physics_frame
		await process_frame
		seen[player.animation_clip] = true

func screenshot(title: String) -> void:
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/%s.png" % title)

func check(condition: bool, description: String) -> void:
	print("OK: " if condition else "FAIL: ", description)
	if not condition:
		failures.append(description)
