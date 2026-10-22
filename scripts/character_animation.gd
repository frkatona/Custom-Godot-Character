extends AnimationTree
## Locomotion stays full-body. Aim replaces only the right arm and neck/head.

const MOVEMENT_CLIPS: Array[StringName] = [
	&"idle", &"basis", &"run", &"jumpStart", &"falling", &"jumpLand",
	&"sliding", &"wallHolding", &"zipping",
]
const AIM_ROOTS: Array[StringName] = [
	&"ORG-shoulder.R", &"DEF-spine.004", &"neck", &"head",
]

var current_clip: StringName = &"idle"
var aim_weight := 0.0
var aim_filter_paths: Array[NodePath] = []
var idle_uses_fallback := false
var _restart_pending := false

func _ready() -> void:
	active = false
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var player := get_node(anim_player) as AnimationPlayer
	player.stop()
	_prepare_idle(player)
	# Rebind after adding the local idle library so the tree sees its clips immediately.
	var player_path := anim_player
	anim_player = NodePath()
	anim_player = player_path
	var skeleton := get_node("../squirrelLady/rigify_rig/Skeleton3D") as Skeleton3D
	var graph := AnimationNodeBlendTree.new()
	var movement := AnimationNodeTransition.new()
	movement.input_count = MOVEMENT_CLIPS.size()
	movement.xfade_time = 0.12
	movement.allow_transition_to_self = true
	graph.add_node(&"Movement", movement, Vector2(340, 100))
	for index in MOVEMENT_CLIPS.size():
		var clip := MOVEMENT_CLIPS[index]
		var source_clip: StringName = &"controller/idle" if clip == &"idle" else clip
		assert(player.has_animation(source_clip), "Missing character animation: %s" % source_clip)
		movement.set_input_name(index, clip)
		movement.set_input_reset(index, true)
		var animation := AnimationNodeAnimation.new()
		animation.animation = source_clip
		graph.add_node(clip, animation, Vector2(0, index * 100))
		if clip == &"run":
			graph.add_node(&"RunSpeed", AnimationNodeTimeScale.new(), Vector2(170, 100))
			graph.connect_node(&"RunSpeed", 0, clip)
			graph.connect_node(&"Movement", index, &"RunSpeed")
		else:
			graph.connect_node(&"Movement", index, clip)

	var aim := AnimationNodeAnimation.new()
	aim.animation = &"crossbow_aim"
	graph.add_node(&"AimPose", aim, Vector2(340, 900))
	var overlay := AnimationNodeBlend2.new()
	overlay.filter_enabled = true
	var pose := player.get_animation(&"crossbow_aim")
	for track in pose.get_track_count():
		var path := pose.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone := skeleton.find_bone(path.get_subname(0))
		while bone >= 0:
			if skeleton.get_bone_name(bone) in AIM_ROOTS:
				overlay.set_filter_path(path, true)
				if path not in aim_filter_paths:
					aim_filter_paths.append(path)
				break
			bone = skeleton.get_bone_parent(bone)
	graph.add_node(&"AimOverlay", overlay, Vector2(600, 200))
	graph.connect_node(&"AimOverlay", 0, &"Movement")
	graph.connect_node(&"AimOverlay", 1, &"AimPose")
	graph.connect_node(&"output", 0, &"AimOverlay")
	tree_root = graph
	active = true
	advance(0.0)

func update_pose(clip: StringName, aiming: bool, run_speed: float, delta: float) -> void:
	if clip != current_clip or _restart_pending:
		current_clip = clip
		set("parameters/Movement/transition_request", clip)
		_restart_pending = false
	aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 7.0)
	set("parameters/AimOverlay/blend_amount", aim_weight)
	set("parameters/RunSpeed/scale", clampf(run_speed, 0.55, 1.6))
	advance(delta)

func restart_movement() -> void:
	_restart_pending = true

func _prepare_idle(player: AnimationPlayer) -> void:
	# Prefer an authored idle after the next GLB export. Keep all imported resources intact.
	var source: Animation
	for clip in player.get_animation_list():
		if str(clip).get_file().to_lower() in ["idle", "idle_loop"]:
			source = player.get_animation(clip)
			break
	idle_uses_fallback = source == null
	var idle: Animation = (player.get_animation(&"basis") if source == null else source).duplicate(true)
	idle.loop_mode = Animation.LOOP_LINEAR
	if idle_uses_fallback:
		# A restrained breathing cycle while the exported asset has no idle clip.
		idle.length = 3.0
		for track in idle.get_track_count():
			var path := idle.track_get_path(track)
			if idle.track_get_type(track) != Animation.TYPE_ROTATION_3D or path.get_subname_count() == 0:
				continue
			var bone := str(path.get_subname(0))
			if bone not in ["DEF-spine.002", "DEF-spine.003", "DEF-spine.004"]:
				continue
			var rest: Quaternion = idle.track_get_key_value(track, 0)
			var amount := 0.012 if bone == "DEF-spine.002" else -0.006
			idle.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
			for key in idle.track_get_key_count(track):
				idle.track_remove_key(track, 0)
			for index in 5:
				var breath := sin(index * PI * 0.5) * amount
				idle.rotation_track_insert_key(track, index * 0.75, rest * Quaternion(Vector3.RIGHT, breath))
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", idle)
	player.add_animation_library(&"controller", library)
