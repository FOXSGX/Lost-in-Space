class_name MemoryShard
extends Node3D

## Resonance memory crystal: touching it projects a small holographic diorama of
## the miners cutting the rail. The player keeps full control of the camera and
## movement; the memory is an environmental projection, not a cutscene.

signal memory_started()
signal memory_finished()

var player: PlayerController
var area: Area3D
var holo_root: Node3D
var crystal: Node3D
var figs: Array[Node3D] = []
var cutter_spark: MeshInstance3D
var played: bool = false
var playing: bool = false
var play_time: float = 0.0
var kit: WorldKit
var _built: bool = false
var _audio: AudioDirector


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	kit.cylinder("PedestalBase", 1.5, 0.35, Vector3(0, 0.17, 0), MatLib.dark_steel(), Vector3.ZERO, true, 24)
	kit.cylinder("PedestalTop", 1.15, 0.45, Vector3(0, 0.58, 0), MatLib.rock(Color(0.24, 0.24, 0.26), Color(0.12, 0.5, 0.62), 0.45), Vector3.ZERO, true, 24)
	kit.ring_box("PedestalRing", 1.18, 0.2, 0.08, Vector3(0, 0.82, 0), MatLib.bronze(), Basis(), 32, false)
	crystal = kit.crystal_cluster("MemoryCrystal", Vector3(0, 0.82, 0), 20.0, 0.85, MatLib.crystal(Color(0.35, 0.85, 1.0), Color(0.55, 0.35, 1.0), 1.1, 0.8), false)
	kit.omni(Vector3(0, 1.5, 0), Color(0.3, 0.75, 1.0), 1.3, 4.5, false, "MemoryLight")
	# holographic diorama
	holo_root = Node3D.new()
	holo_root.name = "MemoryDiorama"
	holo_root.position = Vector3(0, 1.9, 0)
	holo_root.visible = false
	add_child(holo_root)
	var hk: WorldKit = WorldKit.new(holo_root)
	var holo: ShaderMaterial = MatLib.holo(Color(0.45, 0.9, 1.0), 0.42)
	var holo_strong: ShaderMaterial = MatLib.holo(Color(0.65, 0.95, 1.0), 0.72)
	hk.cylinder("HoloBase", 1.5, 0.03, Vector3.ZERO, holo, Vector3.ZERO, false, 28)
	# rail and ties
	hk.box("RailA", Vector3(2.4, 0.05, 0.07), Vector3(0, 0.12, -0.25), holo_strong, Vector3.ZERO, false)
	hk.box("RailB", Vector3(2.4, 0.05, 0.07), Vector3(0, 0.12, 0.25), holo_strong, Vector3.ZERO, false)
	for i in range(5):
		hk.box("Tie", Vector3(0.1, 0.04, 0.7), Vector3(-0.9 + float(i) * 0.45, 0.09, 0), holo, Vector3.ZERO, false)
	# two miners: torso, head, arms, tool
	for i in range(2):
		var fig: Node3D = Node3D.new()
		fig.name = "HoloMiner_%d" % i
		fig.position = Vector3(-0.65 + float(i) * 1.25, 0.55, 0.5 - float(i) * 0.2)
		holo_root.add_child(fig)
		var fk: WorldKit = WorldKit.new(fig)
		fk.cylinder("Torso", 0.19, 0.72, Vector3(0, 0, 0), holo_strong, Vector3.ZERO, false, 8)
		fk.sphere("Head", 0.16, Vector3(0, 0.53, 0), holo_strong, 8)
		fk.cylinder("LegL", 0.06, 0.6, Vector3(-0.09, -0.62, 0), holo, Vector3.ZERO, false, 6)
		fk.cylinder("LegR", 0.06, 0.6, Vector3(0.09, -0.62, 0), holo, Vector3.ZERO, false, 6)
		var arm: Node3D = Node3D.new()
		arm.name = "Arm"
		arm.position = Vector3(0.2, 0.2, 0)
		fig.add_child(arm)
		var ak: WorldKit = WorldKit.new(arm)
		ak.beam("ArmCyl", Vector3.ZERO, Vector3(0.45, -0.18, -0.5), 0.055, holo_strong, false, 6)
		if i == 0:
			ak.beam("Cutter", Vector3(0.45, -0.18, -0.5), Vector3(0.7, -0.3, -1.1), 0.035, holo_strong, false, 6)
		figs.append(fig)
	cutter_spark = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 8
	cutter_spark.mesh = sm
	cutter_spark.material_override = MatLib.emissive(Color(1.0, 0.75, 0.35), 3.0)
	cutter_spark.position = Vector3(0.1, 0.15, -0.9)
	holo_root.add_child(cutter_spark)
	# read area
	area = Area3D.new()
	area.name = "MemoryArea"
	area.position = Vector3(0, 1.0, 1.15)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.95
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")


func setup(p_player: PlayerController, p_audio: AudioDirector) -> void:
	_audio = p_audio
	player = p_player


func get_prompt() -> String:
	if played:
		return "记忆已回放"
	return "E 触碰记忆晶体"


func interact(_p: PlayerController) -> void:
	if played:
		return
	played = true
	playing = true
	play_time = 0.0
	holo_root.visible = true
	if _audio != null:
		_audio.play_sfx("memory", global_position, -4.0)
	memory_started.emit()


func _process(delta: float) -> void:
	if not playing:
		return
	play_time += delta
	var t: float = play_time
	for i in range(figs.size()):
		var fig: Node3D = figs[i]
		fig.position.y = 0.55 + sin(t * 1.4 + float(i) * 1.7) * 0.03
		fig.rotation.y = sin(t * 0.6 + float(i)) * 0.12
	if cutter_spark != null:
		cutter_spark.position = Vector3(0.1 + sin(t * 13.0) * 0.03, 0.15 + sin(t * 17.0) * 0.03, -0.9 + cos(t * 11.0) * 0.03)
		cutter_spark.material_override = MatLib.emissive(Color(1.0, 0.7, 0.3), 2.4 + 1.4 * absf(sin(t * 9.0)))
	if play_time > 15.0:
		playing = false
		holo_root.visible = false
		memory_finished.emit()


func reset_state() -> void:
	played = false
	playing = false
	play_time = 0.0
	holo_root.visible = false
