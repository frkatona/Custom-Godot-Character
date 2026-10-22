extends Node3D

@export var speed := 6.0
@export var hang_offset := 1.6

func get_start_position() -> Vector3:
	return $Start.global_position - Vector3.UP * hang_offset

func get_end_position() -> Vector3:
	return $End.global_position - Vector3.UP * hang_offset
