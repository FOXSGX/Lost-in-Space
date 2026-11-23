class_name Act1RemotePlayer
extends Node3D

var pid := 2
var display_name := "队友"
var body: Node3D
var label: Label3D
var target_position := Vector3.ZERO
var target_yaw := 0.0
var grabbable := false


func setup(p_pid: int, p_name: String) -> void:
	pid = p_pid
	display_name = p_name
	name = "RemotePlayer_%d" % pid
	body = Node3D.new()
	add_child(body)
	var packed := load("res://act1/assets/characters/skin_ranger.glb") as PackedScene
	if packed != null:
		var inst := packed.instantiate() as Node3D
		if inst != null:
			body.add_child(inst)
			inst.rotation.y = PI
			inst.scale = Vector3.ONE * 0.92
	label = Label3D.new()
	label.text = display_name
	label.font_size = 42
	label.pixel_size = 0.0032
	label.outline_size = 12
	label.modulate = Color(0.70, 0.95, 1.0)
	label.no_depth_test = false
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.25, 0)
	add_child(label)


func apply_state(data: Dictionary) -> void:
	target_position = data.get("pos", target_position)
	target_yaw = float(data.get("yaw", target_yaw))
	grabbable = bool(data.get("downed", false))
	if label != null:
		label.modulate = Color(1.0, 0.55, 0.35) if grabbable else Color(0.70, 0.95, 1.0)


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, minf(1.0, delta * 14.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 12.0))