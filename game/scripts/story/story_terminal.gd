class_name StoryTerminal
extends Node3D

## Damaged maintenance terminal. Reading is optional, diegetic and short; it
## never blocks the mechanical puzzle.

signal log_requested(title: String, lines: Array)
signal read_once()

var player: PlayerController
var area: Area3D
var screen: MeshInstance3D
var read: bool = false
var log_title: String = "维护日志"
var log_lines: Array[String] = []
var kit: WorldKit
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.18, 0.27, 0.29))
	kit.box("TerminalBase", Vector3(1.2, 0.9, 0.6), Vector3(0, 0.75, 0), dark, Vector3.ZERO, true)
	kit.box("TerminalBody", Vector3(1.3, 1.1, 0.4), Vector3(0, 1.4, 0.05), steel, Vector3(deg_to_rad(-12), 0, 0), false)
	screen = kit.box("TerminalScreen", Vector3(1.05, 0.62, 0.03), Vector3(0, 1.45, 0.27), MatLib.energy(Color(0.20, 0.78, 0.85), 0.8, 0.35, 3.0), Vector3(deg_to_rad(-12), 0, 0), false)
	kit.box("TerminalFrame", Vector3(1.18, 0.75, 0.06), Vector3(0, 1.45, 0.235), dark, Vector3(deg_to_rad(-12), 0, 0), false)
	for i in range(4):
		kit.box("Key", Vector3(0.12, 0.03, 0.1), Vector3(-0.36 + float(i) * 0.24, 1.0, 0.42), MatLib.steel(), Vector3.ZERO, false)
	kit.box("StatusLight", Vector3(0.1, 0.06, 0.04), Vector3(0.5, 1.62, 0.42), MatLib.emissive(Color(0.95, 0.6, 0.2), 1.6), Vector3.ZERO, false)
	kit.label3d("矿务终端 · 只读", Vector3(0, 1.92, 0.34), 0.0028, Color(0.7, 0.9, 0.95), 32)
	area = Area3D.new()
	area.name = "TerminalArea"
	area.position = Vector3(0, 1.3, 0.75)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.85
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")


func setup(p_player: PlayerController, title: String, lines: Array[String]) -> void:
	player = p_player
	log_title = title
	log_lines = lines
	if not _built:
		build()


func bind_player(p: PlayerController) -> void:
	player = p


func get_prompt() -> String:
	if read:
		return "日志已读取"
	return "E 读取" + log_title


func interact(_p: PlayerController) -> void:
	if read:
		return
	read = true
	var out: Array = []
	for line in log_lines:
		out.append(line)
	log_requested.emit(log_title, out)
	if screen != null:
		screen.material_override = MatLib.emissive(Color(0.25, 0.9, 0.6), 1.2)
	read_once.emit()


func reset_state() -> void:
	read = false
	if screen != null:
		screen.material_override = MatLib.energy(Color(0.20, 0.78, 0.85), 0.8, 0.35, 3.0)
