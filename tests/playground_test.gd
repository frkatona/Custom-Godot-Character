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
	check(player.animation_clip == &"idle", "Stationary character plays idle")
	var idle: Animation = player.get_node("squirrelLady/AnimationPlayer").get_animation("controller/idle")
	check(idle.loop_mode == Animation.LOOP_LINEAR and idle.length > 0.1, "Idle is a looping animation, not a frozen basis pose")
	var skeleton: Skeleton3D = player.get_node("squirrelLady/rigify_rig/Skeleton3D")
	var before_idle := skeleton.get_bone_pose_rotation(skeleton.find_bone("DEF-spine.002"))
	await step(20)
	check(not before_idle.is_equal_approx(skeleton.get_bone_pose_rotation(skeleton.find_bone("DEF-spine.002"))), "Idle advances over time")
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
	await step(12)
	check(seen.has(&"jumpLand"), "Ground contact plays jumpLand")
	Input.action_release("aim")
	await step(35)
	check(player.animation_tree.aim_weight < 0.01, "Aim fades out")
	await verify_double_jump()
	await verify_dash()
	await verify_slide()
	await verify_wall()
	await verify_zipline()
	await verify_buffer_and_coyote()
	await verify_aim_mask()
	player.global_position = Vector3(0, -10, 0)
	await step(3)
	check(player.global_position.distance_to(player.spawn_transform.origin) < 0.2, "Falling off the course resets the character")
	for clip in [&"idle", &"run", &"jumpStart", &"falling", &"jumpLand", &"sliding", &"wallHolding", &"zipping"]:
		check(seen.has(clip), "Played animation: %s" % clip)
	if failures.is_empty():
		print("PASS: idle, double jump, dashes, momentum slides, automatic wall grip/bounce, zipline, reset and aim isolation")
	else:
		for failure in failures:
			push_error(failure)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func verify_double_jump() -> void:
	await reset_at()
	Input.action_press("jump")
	await step(10)
	check(player._air_jumps_left == 1, "First jump preserves the extra air jump")
	Input.action_release("jump")
	await step(2)
	Input.action_press("jump")
	await step(1)
	check(player.velocity.y > 5.0 and player._air_jumps_left == 0, "Second press launches a double jump")
	check(player.animation_clip == &"jumpStart" and player._jump_age < 0.05, "Double jump restarts the takeoff animation")
	Input.action_release("jump")
	await step(2)
	var vertical := player.velocity.y
	Input.action_press("jump")
	await step(1)
	check(player.velocity.y < vertical and player._air_jumps_left == 0, "A third jump is rejected")
	Input.action_release("jump")
	await step(65)
	check(player.is_on_floor() and player._air_jumps_left == player.extra_jumps, "Landing restores the extra jump")

func verify_dash() -> void:
	await reset_at()
	Input.action_press("move_right")
	Input.action_press("dash")
	var start := player.global_position
	await step(4)
	check(player.mode == player.Mode.DASHING and player.horizontal_speed() > 12.0, "Shift starts a directional ground dash")
	check(player.global_position.x > start.x + 0.5, "Ground dash moves the collision body")
	await screenshot("playground_dash")
	Input.action_release("dash")
	await step(12)
	Input.action_press("dash")
	await step(1)
	check(player.mode != player.Mode.DASHING, "Dash cooldown rejects immediate reuse")
	await reset_at()
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(3)
	Input.action_press("jump")
	await step(2)
	check(not player.is_on_floor() and player.horizontal_speed() > 10.0, "Dash-jump preserves horizontal momentum")
	await reset_at(Vector3(0, 5.0, 5.5))
	Input.action_press("move_right")
	Input.action_press("dash")
	await step(3)
	check(player.mode == player.Mode.DASHING and player._air_dashes_used == 1, "Dash is available in midair")
	Input.action_release("dash")
	Input.action_release("move_right")
	await step(42)
	Input.action_press("dash")
	await step(1)
	check(not player.is_on_floor() and player.mode != player.Mode.DASHING, "Only one air dash is allowed per airtime even after cooldown")
	Input.action_release("dash")
	await step(40)
	check(player.is_on_floor() and player._air_dashes_used == 0, "Landing restores the air dash")
	await reset_at()
	player.camera_yaw.rotation.y = PI * 0.5
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(1)
	check(player.velocity.x < -12.0 and absf(player.velocity.z) < 0.1, "Dash direction follows the camera")
	player.camera_yaw.rotation.y = 0.0
	await reset_at(Vector3(0, 0.02, -6.85))
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(6)
	check(player.global_position.z > -7.0 and player.mode == player.Mode.NORMAL, "Dash stops at solid walls without entering an airborne grip from the floor")

func verify_slide() -> void:
	await reset_at()
	Input.action_press("slide")
	await step(2)
	check(player.mode == player.Mode.NORMAL and player.horizontal_speed() < 0.1, "Slide from rest is rejected without adding speed")
	Input.action_release("slide")
	Input.action_press("move_forward")
	await step(20)
	Input.action_press("slide")
	await step(2)
	check(player.mode == player.Mode.NORMAL and player.horizontal_speed() < player.slide_min_speed, "Normal running below the threshold cannot slide")
	await reset_at(Vector3(5.5, 0.02, 7.5))
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(4)
	Input.action_release("dash")
	var entry_speed: float = player.horizontal_speed()
	Input.action_press("slide")
	await step(1)
	check(player.mode == player.Mode.SLIDING and player.horizontal_speed() <= entry_speed + 0.1, "Dash can cancel into a slide without an artificial speed boost")
	await step(10)
	check(player.animation_clip == &"sliding", "Slide plays sliding")
	check(player.standing_shape.disabled and not player.sliding_shape.disabled, "Slide uses a smaller capsule")
	await screenshot("playground_slide")
	Input.action_release("slide")
	await step(2)
	check(player.mode == player.Mode.SLIDING, "Slide cannot stand up inside the tunnel")
	await step(35)
	Input.action_release("move_forward")
	check(player.global_position.z < 1.0, "Slide clears the tunnel")
	check(player.mode == player.Mode.NORMAL and not player.standing_shape.disabled, "Standing capsule returns after tunnel exit")
	await reset_at()
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(2)
	Input.action_press("slide")
	await step(2)
	Input.action_press("jump")
	await step(1)
	check(player.mode == player.Mode.NORMAL and player.velocity.y > 0.0 and player.horizontal_speed() > 10.0, "Jumping out of a slide carries momentum")
	Input.action_release("jump")
	await step(40)
	check(player.mode == player.Mode.SLIDING, "Holding slide in the air queues a slide when landing above the speed threshold")

func verify_wall() -> void:
	await reset_at(Vector3(0, 2.8, -6.85))
	player.velocity.y = -8.0
	player._air_jumps_left = 0
	Input.action_press("move_forward")
	await step(12)
	check(player.mode == player.Mode.WALL_HOLD, "Pressing into an airborne wall grips automatically without E")
	check(player.animation_clip == &"wallHolding", "Wall hold plays wallHolding")
	check(player.velocity.y < 0.0 and player.velocity.y >= -player.wall_slide_speed - 0.01, "Wall grip reduces downward velocity")
	var height := player.global_position.y
	await step(10)
	check(player.global_position.y < height - 0.05 and player.global_position.y > height - 0.3, "Wall grip slides down slowly instead of suspending gravity")
	await screenshot("playground_wall_hold")
	Input.action_press("jump")
	await step(1)
	check(player.mode == player.Mode.NORMAL and player.velocity.y > 0.0 and player.velocity.z > 8.0, "Space bounces up and away from the wall")
	check(player._air_jumps_left == 0, "Wall bounce works independently without replenishing the double jump")
	Input.action_release("jump")
	await step(5)
	check(player.velocity.z > 7.5, "Brief air-control lock preserves the bounce impulse")
	Input.action_release("move_forward")
	await step(50)
	await reset_at(Vector3(0, 1.0, -6.85))
	Input.action_press("move_forward")
	await step(8)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await step(2)
	check(player.mode == player.Mode.NORMAL, "Moving away releases the wall grip")
	await reset_at(Vector3(0, 0.4, -6.85))
	Input.action_press("move_forward")
	await step(60)
	check(player.is_on_floor() and player.mode == player.Mode.NORMAL, "Reaching the floor exits the wall-grip state")
	await reset_at(Vector3(0, 2.0, -6.5))
	Input.action_press("move_forward")
	Input.action_press("dash")
	await step(4)
	check(player.mode == player.Mode.WALL_HOLD, "Air dashing into a wall catches the wall")
	Input.action_press("jump")
	await step(1)
	check(player.velocity.z >= player.dash_speed - 0.1, "Wall bounce preserves the incoming dash speed")

func verify_zipline() -> void:
	await reset_at()
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
	await reset_at()
	player.global_position = Vector3(0, 0.15, 5)
	player.velocity.y = -3.0
	player._coyote_left = 0.0
	await step(1)
	player._coyote_left = 0.0
	player._air_jumps_left = 0
	Input.action_press("jump")
	await step(4)
	check(player.velocity.y > 0.0, "Buffered jump fires on landing")
	Input.action_release("jump")
	await reset_at()
	player.global_position = Vector3(16.5, 0.05, 5)
	await step(2)
	Input.action_press("jump")
	await step(1)
	check(player.velocity.y > 0.0 and player._air_jumps_left == player.extra_jumps, "Coyote jump works without spending the air jump")
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

func reset_at(position := Vector3(0, 0.05, 5.5)) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "aim", "slide", "dash", "interact"]:
		Input.action_release(action)
	player.respawn()
	player.global_position = position
	await step(5)

func screenshot(title: String) -> void:
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/%s.png" % title)

func check(condition: bool, description: String) -> void:
	print("OK: " if condition else "FAIL: ", description)
	if not condition:
		failures.append(description)
