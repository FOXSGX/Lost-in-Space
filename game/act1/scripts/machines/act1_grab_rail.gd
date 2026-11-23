class_name Act1GrabRail
extends Act1Interactable

## A real handhold for Act 01. The body is anchored and the player is attached
## to it while held; wind no longer moves the player and releasing is always
## possible.

var anchor_points: Array[Vector3] = []


func setup_rail(p_id: String, p_pos: Vector3, length: float, horizontal_yaw: float = 0.0) -> void:
	var size := Vector3(0.12, 0.18, length)
	if absf(sin(horizontal_yaw)) > 0.5:
		size = Vector3(length, 0.18, 0.12)
	setup(p_id, "E 抓住扶手", size)
	position = p_pos
	prompt_text = "E 抓住扶手 · 风场中不会被吹走"
	interaction_id = p_id
	add_focus_marker(0.18)


func _ready() -> void:
	pass