class_name ExitDoor
extends Node3D

## Heavy evacuation blast door. It stays sealed until the navigation data has
## been recovered, then lifts with a visible counterweight and light spill.

signal opened()

var body: StaticBody3D
var open_progress: float = 0.0
var should_open: bool = false
var is_opened: bool = false
var kit: WorldKit
var lamps: Array[MeshInstance3D] = []
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
	var steel: Material = MatLib.painted_steel(Color(0.25, 0.29, 0.27))
	var dark: Material = MatLib.dark_steel()
	kit.box("FrameL", Vector3(0.6, 3.5, 0.6), Vector3(0, 1.75, -2.2), steel, Vector3.ZERO, true)
	kit.box("FrameR", Vector3(0.6, 3.5, 0.6), Vector3(0, 1.75, 2.2), steel, Vector3.ZERO, true)
	kit.box("Lintel", Vector3(0.9, 0.45, 5.0), Vector3(0, 3.55, 0), steel, Vector3.ZERO, true)
	kit.box("DoorHousing", Vector3(0.9, 2.8, 4.6), Vector3(0, 5.05, 0), dark, Vector3.ZERO, false)
	kit.box("HousingTrim", Vector3(1.02, 0.14, 4.7), Vector3(0, 3.72, 0), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("HousingRib", Vector3(0.06, 2.6, 0.16), Vector3(0.46, 5.05, -1.9), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("HousingRib", Vector3(0.06, 2.6, 0.16), Vector3(0.46, 5.05, 1.9), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("GuideL", Vector3(0.2, 3.0, 0.16), Vector3(-0.28, 1.5, -2.05), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("GuideR", Vector3(0.2, 3.0, 0.16), Vector3(-0.28, 1.5, 2.05), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("Threshold", Vector3(0.7, 0.07, 4.1), Vector3(0.1, 0.035, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	body = StaticBody3D.new()
	body.name = "ExitDoorBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.4, 2.9, 3.9)
	col.shape = shape
	col.position = Vector3(0, 1.45, 0)
	body.add_child(col)
	var panel: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(0.34, 2.9, 3.9)
	panel.mesh = pm
	panel.material_override = steel
	panel.position = Vector3(0, 1.45, 0)
	body.add_child(panel)
	for i in range(4):
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rm: BoxMesh = BoxMesh.new()
		rm.size = Vector3(0.06, 2.8, 0.14)
		rib.mesh = rm
		rib.material_override = MatLib.bronze()
		rib.position = Vector3(0.21, 1.45, -1.4 + float(i) * 0.93)
		body.add_child(rib)
	var hazard: MeshInstance3D = MeshInstance3D.new()
	var hm: BoxMesh = BoxMesh.new()
	hm.size = Vector3(0.05, 0.55, 3.7)
	hazard.mesh = hm
	hazard.material_override = MatLib.hazard_material()
	hazard.position = Vector3(0.21, 0.42, 0)
	body.add_child(hazard)
	for i in range(2):
		var lamp: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		sm.radial_segments = 10
		lamp.mesh = sm
		lamp.material_override = MatLib.emissive(Color(0.95, 0.16, 0.1), 2.0)
		lamp.position = Vector3(0.32, 3.32, -1.65 + float(i) * 3.3)
		add_child(lamp)
		lamps.append(lamp)
	# light beyond the door
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(-1.6, 2.4, 0)
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 0.0
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.name = "ExitSpill"
	add_child(light)



func setup(p_audio: AudioDirector) -> void:
	_audio = p_audio


func open_door() -> void:
	if should_open or is_opened:
		return
	should_open = true
	if _audio != null:
		_audio.play_sfx("door_open", global_position, -3.0)
	for lamp in lamps:
		lamp.material_override = MatLib.emissive(Color(0.25, 1.0, 0.55), 2.2)


func _process(delta: float) -> void:
	if not _built:
		return
	if should_open:
		open_progress = move_toward(open_progress, 1.0, delta * 0.38)
		if body != null:
			body.position = Vector3(0, open_progress * 3.0, 0)
		var spill: OmniLight3D = get_node_or_null("ExitSpill") as OmniLight3D
		if spill != null:
			spill.light_energy = open_progress * 2.2
		if open_progress >= 0.999 and not is_opened:
			is_opened = true
			opened.emit()


func reset_state() -> void:
	should_open = false
	is_opened = false
	open_progress = 0.0
	if body != null:
		body.position = Vector3.ZERO
	var spill: OmniLight3D = get_node_or_null("ExitSpill") as OmniLight3D
	if spill != null:
		spill.light_energy = 0.0
	for lamp in lamps:
		lamp.material_override = MatLib.emissive(Color(0.95, 0.16, 0.1), 2.0)

