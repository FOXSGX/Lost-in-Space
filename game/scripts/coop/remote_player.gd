class_name RemotePlayer
extends Node3D

## Visible teammate avatar for the two-instance slice. It renders the same
## character asset as the local player and is driven by streamed transform /
## grab state; it never simulates gameplay.

var pid: int = 0
var display_name: String = ""
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var grabbing: bool = false
var operating: bool = false
var name_label: Label3D
var grab_ring: MeshInstance3D
var _body: Node3D
var _initialised: bool = false


func setup(p_pid: int, p_name: String) -> void:
	pid = p_pid
	display_name = p_name
	name = "RemotePlayer_%d" % pid
	_build()


func _build() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	var packed: PackedScene = load("res://assets/resonance-characters/skin_ranger.glb") as PackedScene
	if packed != null:
		_body = packed.instantiate() as Node3D
		if _body != null:
			add_child(_body)
			_body.rotation.y = PI
			_body.scale = Vector3.ONE * 0.92
	name_label = Label3D.new()
	name_label.text = "P%d %s" % [pid, display_name]
	name_label.font = font
	name_label.font_size = 44
	name_label.pixel_size = 0.0032
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.modulate = Color(0.55, 0.95, 1.0)
	name_label.outline_size = 6
	name_label.outline_modulate = Color(0, 0, 0, 0.85)
	name_label.position = Vector3(0, 2.15, 0)
	add_child(name_label)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.30
	ring.outer_radius = 0.38
	ring.rings = 16
	ring.ring_segments = 8
	grab_ring = MeshInstance3D.new()
	grab_ring.mesh = ring
	grab_ring.material_override = MatLib.emissive(Color(0.35, 1.0, 0.85), 2.0)
	grab_ring.position = Vector3(0, 0.10, 0)
	grab_ring.visible = false
	add_child(grab_ring)
	_initialised = true


func apply_state(state: Dictionary) -> void:
	var pos: Vector3 = state.get("pos", target_position)
	var yaw: float = float(state.get("yaw", target_yaw))
	grabbing = bool(state.get("grab", false))
	operating = bool(state.get("op", false))
	target_position = pos
	target_yaw = yaw
	if not _initialised:
		global_position = pos
		rotation.y = yaw
	if grab_ring != null:
		grab_ring.visible = grabbing
	if name_label != null:
		var suffix: String = ""
		if grabbing:
			suffix = " · 抓扶"
		elif operating:
			suffix = " · 操作中"
		name_label.text = "P%d %s%s" % [pid, display_name, suffix]


func _process(delta: float) -> void:
	if not _initialised:
		return
	var weight: float = minf(1.0, delta * 14.0)
	global_position = global_position.lerp(target_position, weight)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
