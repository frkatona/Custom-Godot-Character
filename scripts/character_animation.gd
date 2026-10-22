extends AnimationTree
## Locomotion stays full-body. Aim replaces only the right arm and neck/head.

const MOVEMENT_CLIPS: Array[StringName] = [
	&"basis", &"run", &"jumpStart", &"falling", &"jumpLand",
	&"sliding", &"wallHolding", &"zipping",
]
const AIM_ROOTS: Array[StringName] = [
	&"ORG-shoulder.R", &"DEF-spine.004", &"neck", &"head",
]

var current_clip: StringName = &"basis"
var aim_weight := 0.0
var aim_filter_paths: Array[NodePath] = []

func _ready() -> void:
	active = false
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var player := get_node(anim_player) as AnimationPlayer
	player.stop()
	var skeleton := get_node("../squirrelLady/rigify_rig/Skeleton3D") as Skeleton3D
	var graph := AnimationNodeBlendTree.new()
	var movement := AnimationNodeTransition.new()
	movement.input_count = MOVEMENT_CLIPS.size()
	movement.xfade_time = 0.12
	graph.add_node(&"Movement", movement, Vector2(340, 100))
	for index in MOVEMENT_CLIPS.size():
		var clip := MOVEMENT_CLIPS[index]
		assert(player.has_animation(clip), "Missing character animation: %s" % clip)
		movement.set_input_name(index, clip)
		movement.set_input_reset(index, true)
		var animation := AnimationNodeAnimation.new()
		animation.animation = clip
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
	if clip != current_clip:
		current_clip = clip
		set("parameters/Movement/transition_request", clip)
	aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 7.0)
	set("parameters/AimOverlay/blend_amount", aim_weight)
	set("parameters/RunSpeed/scale", clampf(run_speed, 0.55, 1.6))
	advance(delta)
