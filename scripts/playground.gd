extends Node3D

@onready var character: CharacterBody3D = $Character
var _status: Label
var _hint: Label
var _reticle: Label

func _ready() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var margin := MarginContainer.new()
	margin.position = Vector2(18, 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	margin.add_child(rows)
	_label(rows, "MOVEMENT PLAYGROUND", 20, Color("f5e9d3"))
	_label(rows, "WASD / arrows  Move    Mouse  Look    Space  Jump    RMB  Aim", 16)
	_label(rows, "Shift / Ctrl  Slide    E  Ride zipline / hold wall    R  Reset    Esc  Free mouse", 16)
	_label(rows, "At the wall: jump + hold E to hang; Space to push off. Click to capture mouse.", 14, Color("bac9cb"))
	_status = _label(rows, "", 16, Color("8ae0ce"))
	_hint = _label(rows, "", 16, Color("ffd697"))
	_reticle = Label.new()
	hud.add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reticle.position = get_viewport().get_visible_rect().size * 0.5 - Vector2(6, 14)
	_reticle.text = "+"
	_reticle.add_theme_font_size_override("font_size", 24)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	_status.text = "%s    %.1f m/s    Aim blend %d%%" % [
		character.animation_clip,
		Vector2(character.velocity.x, character.velocity.z).length(),
		roundi(character.animation_tree.aim_weight * 100.0),
	]
	_reticle.visible = character.is_aiming
	_reticle.position = get_viewport().get_visible_rect().size * 0.5 - Vector2(6, 14)
	_hint.text = ""
	if character.mode == character.Mode.WALL_HOLD:
		_hint.text = "Holding wall  ·  Space to push off  ·  Release E to drop"
	elif character.mode == character.Mode.ZIPLINE:
		_hint.text = "Riding zipline  ·  Space to jump off"
	else:
		for line in get_tree().get_nodes_in_group("ziplines"):
			if character.global_position.distance_to(line.get_start_position()) < 1.5:
				_hint.text = "E  ·  Ride zipline"

func _label(parent: Node, value: String, size: int, tint := Color("e3eceb")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0.03, 0.06, 0.09, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
