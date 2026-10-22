extends CharacterBody3D
## Camera-relative movement; the authored model faces +Z.

enum Mode { NORMAL, SLIDING, WALL_HOLD, ZIPLINE, DASHING }

@export_category("Movement")
@export var move_speed := 5.5
@export var acceleration := 30.0
@export var air_acceleration := 9.0
@export var ground_friction := 16.0
@export var jump_velocity := 6.5
@export var double_jump_velocity := 6.0
@export_range(0, 4) var extra_jumps := 1
@export var gravity := 20.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export_category("Slide")
@export var slide_min_speed := 6.0
@export var slide_end_speed := 2.5
@export var slide_friction := 3.5
@export var slide_steering := 2.0
@export_category("Dash")
@export var dash_speed := 13.0
@export var dash_duration := 0.2
@export var dash_cooldown := 0.65
@export_range(0, 4) var air_dash_limit := 1
@export_category("Wall Movement")
@export var wall_slide_speed := 1.5
@export_range(0.0, 1.0) var wall_vertical_damping := 0.25
@export_range(0.0, 1.0) var wall_gravity_scale := 0.25
@export var wall_bounce_speed := 8.5
@export var wall_bounce_jump := 6.5
@export var wall_bounce_control_lock := 0.16
@export_category("Camera")
@export var mouse_sensitivity := 0.0025
@export var capture_mouse_on_start := true

@onready var model: Node3D = $squirrelLady
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D
@onready var standing_shape: CollisionShape3D = $StandingShape
@onready var sliding_shape: CollisionShape3D = $SlidingShape

var mode := Mode.NORMAL
var is_aiming := false
var animation_clip: StringName = &"idle"
var spawn_transform: Transform3D
var move_direction := Vector3.FORWARD
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _jump_age := 100.0
var _land_left := 0.0
var _wall_normal := Vector3.ZERO
var _wall_entry_velocity := Vector3.ZERO
var _last_bounce_normal := Vector3.ZERO
var _wall_cooldown := 0.0
var _control_lock_left := 0.0
var _air_jumps_left := 1
var _air_dashes_used := 0
var _dash_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_direction := Vector3.FORWARD
var _zipline: Node3D
var _zip_progress := 0.0

func _ready() -> void:
	spawn_transform = global_transform
	_air_jumps_left = extra_jumps
	spring_arm.add_excluded_object(get_rid())
	if capture_mouse_on_start and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pitch.rotation.x = clampf(camera_pitch.rotation.x - event.relative.y * mouse_sensitivity, -1.05, 0.55)
	elif event.is_action_pressed("respawn"):
		respawn()

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var desired := camera_yaw.global_basis * Vector3(input.x, 0.0, input.y)
	if desired.length_squared() > 0.01:
		move_direction = desired.normalized()
	_wall_cooldown = maxf(0.0, _wall_cooldown - delta)
	_control_lock_left = maxf(0.0, _control_lock_left - delta)
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_jump_age += delta
	_land_left = maxf(0.0, _land_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	if is_on_floor() and mode != Mode.ZIPLINE:
		_coyote_left = coyote_time
		_air_jumps_left = extra_jumps
		_air_dashes_used = 0
		_last_bounce_normal = Vector3.ZERO
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)

	if mode != Mode.ZIPLINE and Input.is_action_just_pressed("interact"):
		_try_zipline()
	if mode != Mode.ZIPLINE and Input.is_action_just_pressed("dash"):
		_try_dash(desired)
	# Holding crouch queues a slide after a dash or on landing, but never creates speed.
	if mode in [Mode.NORMAL, Mode.DASHING] and is_on_floor() and Input.is_action_pressed("slide") and horizontal_speed() >= slide_min_speed:
		mode = Mode.SLIDING
		_land_left = 0.0
		_set_crouched(true)
	match mode:
		Mode.ZIPLINE:
			_update_zipline(delta)
		Mode.WALL_HOLD:
			_update_wall_hold(desired, delta)
		Mode.DASHING:
			_update_dash(desired, delta)
		_:
			_update_movement(desired, delta)

	is_aiming = Input.is_action_pressed("aim") and mode in [Mode.NORMAL, Mode.SLIDING, Mode.DASHING]
	var facing := move_direction
	if is_aiming:
		facing = -camera_yaw.global_basis.z
	elif mode == Mode.WALL_HOLD:
		facing = -_wall_normal
	elif mode == Mode.SLIDING:
		facing = _horizontal_velocity().normalized()
	elif mode == Mode.DASHING:
		facing = _dash_direction
	if facing.length_squared() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-16.0 * delta))
	_update_animation(delta)
	if global_position.y < -8.0:
		respawn()

func _update_movement(desired: Vector3, delta: float) -> void:
	var grounded := is_on_floor()
	if mode == Mode.SLIDING:
		_update_slide(desired, grounded, delta)
	else:
		var speed := move_speed * (0.75 if Input.is_action_pressed("aim") else 1.0)
		if grounded and (desired.is_zero_approx() or horizontal_speed() > speed):
			_set_horizontal_velocity(_horizontal_velocity().move_toward(Vector3.ZERO, ground_friction * delta))
		if _control_lock_left <= 0.0:
			_accelerate(desired, speed, acceleration if grounded else air_acceleration, delta)
	if grounded:
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	_try_jump()
	# A shorter jump when Space is released early.
	if Input.is_action_just_released("jump") and velocity.y > 2.0 and _jump_age < 0.4:
		velocity.y *= 0.55
	_move_body(desired, grounded)

func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func horizontal_speed() -> float:
	return _horizontal_velocity().length()

func _set_horizontal_velocity(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z

func _accelerate(desired: Vector3, speed: float, rate: float, delta: float) -> void:
	if desired.is_zero_approx():
		return
	var direction := desired.normalized()
	# Accelerate along the input axis without discarding dash/bounce momentum.
	var remaining := speed * desired.length() - _horizontal_velocity().dot(direction)
	if remaining > 0.0:
		_set_horizontal_velocity(_horizontal_velocity() + direction * minf(remaining, rate * delta))

func _update_slide(desired: Vector3, grounded: bool, delta: float) -> void:
	if (not grounded or not Input.is_action_pressed("slide") or horizontal_speed() < slide_end_speed) and _can_stand():
		mode = Mode.NORMAL
		_set_crouched(false)
		return
	var horizontal := _horizontal_velocity()
	if grounded:
		var downhill := Vector3.DOWN.slide(get_floor_normal()) * gravity
		horizontal += Vector3(downhill.x, 0.0, downhill.z) * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, slide_friction * delta)
	if not desired.is_zero_approx() and not horizontal.is_zero_approx():
		var steered := horizontal.normalized().lerp(desired.normalized(), minf(slide_steering * delta, 1.0)).normalized()
		horizontal = steered * horizontal.length()
	_set_horizontal_velocity(horizontal)
	if horizontal_speed() < slide_end_speed and not _can_stand():
		# Crawl out if momentum runs out below a ceiling; never stand inside geometry.
		_set_horizontal_velocity(horizontal.move_toward(desired * slide_end_speed, acceleration * delta))

func _try_jump() -> bool:
	if _jump_buffer_left <= 0.0 or not _can_stand():
		return false
	if _coyote_left > 0.0:
		_launch_jump()
	elif _air_jumps_left > 0:
		_air_jumps_left -= 1
		_launch_jump(double_jump_velocity)
	else:
		return false
	mode = Mode.NORMAL
	_set_crouched(false)
	return true

func _launch_jump(speed: float = -1.0) -> void:
	velocity.y = jump_velocity if speed < 0.0 else speed
	_jump_age = 0.0
	_land_left = 0.0
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	animation_tree.restart_movement()

func _update_wall_hold(desired: Vector3, delta: float) -> void:
	# A grip slows ascent/descent but continues to fall instead of hovering forever.
	velocity.y = maxf(velocity.y - gravity * wall_gravity_scale * delta, -wall_slide_speed)
	_set_horizontal_velocity(Vector3.ZERO)
	if _jump_buffer_left > 0.0:
		mode = Mode.NORMAL
		_launch_jump(wall_bounce_jump)
		var tangent := desired.slide(_wall_normal)
		var carried := _wall_entry_velocity.slide(_wall_normal)
		if not tangent.is_zero_approx():
			carried = tangent.normalized() * maxf(carried.length(), move_speed * tangent.length())
		var outward_speed := maxf(wall_bounce_speed, absf(_wall_entry_velocity.dot(_wall_normal)))
		_set_horizontal_velocity(_wall_normal * outward_speed + carried)
		move_direction = _wall_normal
		_last_bounce_normal = _wall_normal
		_wall_cooldown = 0.25
		_control_lock_left = wall_bounce_control_lock
	elif desired.dot(_wall_normal) >= -0.1 or _wall_probe().is_empty():
		mode = Mode.NORMAL
		_wall_cooldown = 0.15
	_move_body(desired, false)

func _move_body(desired: Vector3, was_grounded: bool) -> void:
	var incoming := _horizontal_velocity()
	move_and_slide()
	if is_on_floor():
		if mode == Mode.WALL_HOLD:
			mode = Mode.NORMAL
		_air_jumps_left = extra_jumps
		_air_dashes_used = 0
		_last_bounce_normal = Vector3.ZERO
		if not was_grounded and _jump_age > 0.15:
			_land_left = 0.25
		return
	if mode in [Mode.NORMAL, Mode.DASHING] and _wall_cooldown <= 0.0 and is_on_wall():
		for index in get_slide_collision_count():
			var normal := get_slide_collision(index).get_normal()
			if absf(normal.y) < 0.2 and desired.dot(normal) < -0.1 and normal.dot(_last_bounce_normal) < 0.95:
				_wall_normal = normal
				_wall_entry_velocity = incoming
				velocity.y = clampf(velocity.y * wall_vertical_damping, -wall_slide_speed, wall_slide_speed)
				mode = Mode.WALL_HOLD
				if _jump_buffer_left > 0.0:
					_update_wall_hold(desired, 0.0)
				break

func _wall_probe() -> Dictionary:
	var direction := -_wall_normal
	var origin := global_position + Vector3.UP * 0.85
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 0.45, collision_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func _try_dash(desired: Vector3) -> bool:
	if _dash_cooldown_left > 0.0 or (not is_on_floor() and _air_dashes_used >= air_dash_limit) or not _can_stand():
		return false
	if not is_on_floor():
		_air_dashes_used += 1
		velocity.y = 0.0
	_dash_direction = desired.normalized() if not desired.is_zero_approx() else -camera_yaw.global_basis.z
	_dash_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	_land_left = 0.0
	mode = Mode.DASHING
	_set_crouched(false)
	_set_horizontal_velocity(_dash_direction * maxf(dash_speed, horizontal_speed()))
	return true

func _update_dash(desired: Vector3, delta: float) -> void:
	var grounded := is_on_floor()
	_dash_left -= delta
	_set_horizontal_velocity(_dash_direction * maxf(dash_speed, horizontal_speed()))
	if grounded:
		velocity.y = -0.5
	if _try_jump():
		# Dash-jump carries horizontal momentum into the air.
		_move_body(desired, grounded)
		return
	_move_body(desired, grounded)
	if mode == Mode.DASHING and (_dash_left <= 0.0 or horizontal_speed() < dash_speed * 0.4):
		mode = Mode.NORMAL

func _try_zipline() -> void:
	for line in get_tree().get_nodes_in_group("ziplines"):
		var start: Vector3 = line.get_start_position()
		if global_position.distance_to(start) < 1.5:
			_zipline = line
			_zip_progress = 0.0
			mode = Mode.ZIPLINE
			_set_crouched(false)
			velocity = Vector3.ZERO
			_air_jumps_left = extra_jumps
			_air_dashes_used = 0
			global_position = start
			return

func _update_zipline(delta: float) -> void:
	var start: Vector3 = _zipline.get_start_position()
	var finish: Vector3 = _zipline.get_end_position()
	var direction := (finish - start).normalized()
	velocity = direction * _zipline.speed
	move_direction = direction
	_zip_progress = minf(1.0, _zip_progress + _zipline.speed * delta / start.distance_to(finish))
	# Sweep the capsule so edited courses cannot zip through solid obstacles.
	var target := start.lerp(finish, _zip_progress)
	var collision := move_and_collide(target - global_position)
	if collision != null or _zip_progress >= 1.0 or Input.is_action_just_pressed("jump"):
		mode = Mode.NORMAL
		velocity = direction * _zipline.speed
		_jump_buffer_left = 0.0
		if Input.is_action_just_pressed("jump"):
			_launch_jump()
		else:
			_jump_age = 100.0
		_zipline = null

func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape.shape
	query.transform = standing_shape.global_transform
	# Lift very slightly so the supporting floor is not an obstruction.
	query.transform.origin += Vector3.UP * 0.03
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _set_crouched(crouched: bool) -> void:
	standing_shape.disabled = crouched
	sliding_shape.disabled = not crouched

func _update_animation(delta: float) -> void:
	match mode:
		Mode.SLIDING:
			animation_clip = &"sliding"
		Mode.WALL_HOLD:
			animation_clip = &"wallHolding"
		Mode.ZIPLINE:
			animation_clip = &"zipping"
		Mode.DASHING:
			# Reuse movement clips until an authored dash animation is available.
			animation_clip = &"run" if is_on_floor() else &"falling"
		_:
			if not is_on_floor():
				animation_clip = &"jumpStart" if _jump_age < 0.4 else &"falling"
			elif Vector2(velocity.x, velocity.z).length() > 0.15:
				animation_clip = &"run"
			elif _land_left > 0.0:
				animation_clip = &"jumpLand"
			else:
				animation_clip = &"idle"
	animation_tree.update_pose(animation_clip, is_aiming, Vector2(velocity.x, velocity.z).length() / move_speed, delta)

func respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	mode = Mode.NORMAL
	_zipline = null
	_jump_age = 100.0
	_land_left = 0.0
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_wall_cooldown = 0.0
	_last_bounce_normal = Vector3.ZERO
	_wall_entry_velocity = Vector3.ZERO
	_control_lock_left = 0.0
	_air_jumps_left = extra_jumps
	_air_dashes_used = 0
	_dash_left = 0.0
	_dash_cooldown_left = 0.0
	_set_crouched(false)
	reset_physics_interpolation()
