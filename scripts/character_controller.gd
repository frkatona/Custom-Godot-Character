extends CharacterBody3D
## Camera-relative movement; the authored model faces +Z.

enum Mode { NORMAL, SLIDING, WALL_HOLD, ZIPLINE }

@export_category("Movement")
@export var move_speed := 4.5
@export var acceleration := 22.0
@export var air_acceleration := 9.0
@export var jump_velocity := 6.0
@export var gravity := 18.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var slide_speed := 7.0
@export var slide_duration := 0.85
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
var animation_clip: StringName = &"basis"
var spawn_transform: Transform3D
var move_direction := Vector3.FORWARD
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _jump_age := 100.0
var _land_left := 0.0
var _slide_left := 0.0
var _slide_direction := Vector3.ZERO
var _wall_normal := Vector3.ZERO
var _wall_cooldown := 0.0
var _zipline: Node3D
var _zip_progress := 0.0

func _ready() -> void:
	spawn_transform = global_transform
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
	_jump_age += delta
	_land_left = maxf(0.0, _land_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)

	if mode != Mode.ZIPLINE and Input.is_action_just_pressed("interact"):
		_try_zipline()
	match mode:
		Mode.ZIPLINE:
			_update_zipline(delta)
		Mode.WALL_HOLD:
			_update_wall_hold(delta)
		_:
			_update_movement(desired, delta)

	is_aiming = Input.is_action_pressed("aim") and mode in [Mode.NORMAL, Mode.SLIDING]
	var facing := move_direction
	if is_aiming:
		facing = -camera_yaw.global_basis.z
	elif mode == Mode.WALL_HOLD:
		facing = -_wall_normal
	elif mode == Mode.SLIDING:
		facing = _slide_direction
	if facing.length_squared() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-16.0 * delta))
	_update_animation(delta)
	if global_position.y < -8.0:
		respawn()

func _update_movement(desired: Vector3, delta: float) -> void:
	var grounded := is_on_floor()
	if grounded and Input.is_action_just_pressed("slide") and mode == Mode.NORMAL:
		mode = Mode.SLIDING
		_slide_left = slide_duration
		_slide_direction = move_direction
		_set_crouched(true)
	if mode == Mode.SLIDING:
		_slide_left -= delta
		var speed := lerpf(move_speed, slide_speed, clampf(_slide_left / slide_duration, 0.0, 1.0))
		velocity.x = _slide_direction.x * speed
		velocity.z = _slide_direction.z * speed
		if _slide_left <= 0.0 and _can_stand():
			mode = Mode.NORMAL
			_set_crouched(false)
	else:
		var target := desired * move_speed * (0.75 if Input.is_action_pressed("aim") else 1.0)
		var rate := acceleration if grounded else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, rate * delta)
		velocity.z = move_toward(velocity.z, target.z, rate * delta)
	if grounded:
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and _can_stand():
		_set_crouched(false)
		mode = Mode.NORMAL
		_launch_jump()
	# A shorter jump when Space is released early.
	if Input.is_action_just_released("jump") and velocity.y > 2.0:
		velocity.y *= 0.55
	move_and_slide()
	if not grounded and is_on_floor() and _jump_age > 0.15:
		_land_left = 0.4167
	if not is_on_floor() and mode == Mode.NORMAL and Input.is_action_pressed("interact") and _wall_cooldown <= 0.0:
		var hit := _wall_probe()
		if not hit.is_empty() and (hit.collider as Node).is_in_group("holdable_wall"):
			_wall_normal = hit.normal
			velocity = Vector3.ZERO
			mode = Mode.WALL_HOLD

func _launch_jump() -> void:
	velocity.y = jump_velocity
	_jump_age = 0.0
	_land_left = 0.0
	_jump_buffer_left = 0.0
	_coyote_left = 0.0

func _update_wall_hold(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _jump_buffer_left > 0.0:
		mode = Mode.NORMAL
		_launch_jump()
		velocity += _wall_normal * move_speed * 1.4
		move_direction = _wall_normal
		_wall_cooldown = 0.4
	elif not Input.is_action_pressed("interact") or _wall_probe().is_empty():
		mode = Mode.NORMAL
		_wall_cooldown = 0.25
	move_and_slide()

func _wall_probe() -> Dictionary:
	var direction := -_wall_normal if mode == Mode.WALL_HOLD else move_direction
	var origin := global_position + Vector3.UP * 0.85
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 0.65, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func _try_zipline() -> void:
	for line in get_tree().get_nodes_in_group("ziplines"):
		var start: Vector3 = line.get_start_position()
		if global_position.distance_to(start) < 1.5:
			_zipline = line
			_zip_progress = 0.0
			mode = Mode.ZIPLINE
			_set_crouched(false)
			velocity = Vector3.ZERO
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
		_:
			if not is_on_floor():
				animation_clip = &"jumpStart" if _jump_age < 0.4 else &"falling"
			elif _land_left > 0.0:
				animation_clip = &"jumpLand"
			elif Vector2(velocity.x, velocity.z).length() > 0.15:
				animation_clip = &"run"
			else:
				animation_clip = &"basis"
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
	_set_crouched(false)
	reset_physics_interpolation()
