class_name DataPlinth
extends Node3D

## Navigation-data projector. Hidden until the extraction loop is isolated, then
## it rises out of the floor and projects the recovered deep-space route.

signal revealed()
signal data_taken()

var area: Area3D
var holo_root: Node3D
var star_map: Node3D
var shard: Node3D
var beam: MeshInstance3D
var plinth: Node3D
var revealed_flag: bool = false
var session: CoopSession
var taken: bool = false
var reveal_time: float = 0.0
var kit: WorldKit
var _built: bool = false
var _audio: AudioDirector
var _time: float = 0.0


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	plinth = Node3D.new()
	plinth.name = "Plinth"
	plinth.position = Vector3(0, -1.2, 0)
	add_child(plinth)
	var pk: WorldKit = WorldKit.new(plinth)
	pk.cylinder("PlinthBase", 1.15, 0.5, Vector3(0, 0.25, 0), MatLib.dark_steel(), Vector3.ZERO, true, 24)
	pk.cylinder("PlinthTop", 0.85, 0.16, Vector3(0, 0.58, 0), MatLib.bronze(), Vector3.ZERO, false, 24)
	pk.ring_box("DataRing", 0.95, 0.18, 0.06, Vector3(0, 0.68, 0), MatLib.energy(Color(0.3, 0.9, 1.0), 1.2, 0.6, 4.0), Basis(), 32, false)
	# data shard
	shard = Node3D.new()
	shard.name = "NavDataShard"
	shard.position = Vector3(0, 1.35, 0)
	plinth.add_child(shard)
	var sk: WorldKit = WorldKit.new(shard)
	sk.crystal("ShardCrystal", Vector3(0, -0.28, 0), 0.65, 0.16, 6, MatLib.crystal(Color(0.6, 0.95, 1.0), Color(0.6, 0.45, 1.0), 2.4, 1.6), Basis(), 5.5)
	sk.torus("ShardRing", 0.34, 0.015, Vector3.ZERO, MatLib.energy(Color(0.55, 0.9, 1.0), 1.6, 1.2, 5.0), Basis(Vector3.RIGHT, PI * 0.5), 32, 5)
	sk.torus("ShardRing2", 0.42, 0.012, Vector3.ZERO, MatLib.energy(Color(0.7, 0.55, 1.0), 1.4, -1.0, 6.0), Basis(), 32, 5)
	# star map
	holo_root = Node3D.new()
	holo_root.name = "StarMap"
	holo_root.position = Vector3(0, 2.2, 0)
	holo_root.visible = false
	add_child(holo_root)
	var hk: WorldKit = WorldKit.new(holo_root)
	var holo: ShaderMaterial = MatLib.holo(Color(0.45, 0.88, 1.0), 0.36)
	# no opaque hologram base: the star points and route lines carry the visual
	star_map = Node3D.new()
	star_map.name = "Stars"
	holo_root.add_child(star_map)
	var star_mesh: SphereMesh = SphereMesh.new()
	star_mesh.radius = 0.028
	star_mesh.height = 0.056
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 90
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7717
	for i in range(90):
		var a: float = rng.randf() * TAU
		var b: float = acos(1.0 - 2.0 * rng.randf())
		var r: float = 0.75 + rng.randf() * 0.55
		var pos: Vector3 = Vector3(sin(b) * cos(a) * r, cos(b) * r, sin(b) * sin(a) * r)
		if i % 9 == 0:
			pos = Vector3(cos(a) * 0.85, sin(b) * 0.6, sin(a) * 0.85)
		var s: float = 0.7 + rng.randf() * 1.8
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MatLib.emissive(Color(0.65, 0.92, 1.0), 3.2)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_map.add_child(mmi)
	# route lines
	var route_mat: StandardMaterial3D = MatLib.emissive(Color(0.95, 0.8, 0.4), 2.2)
	for i in range(5):
		var a1: float = -2.4 + float(i) * 1.15
		var a2: float = -2.4 + float(i + 1) * 1.15
		var p1: Vector3 = Vector3(cos(a1) * 0.95, 0.2 + 0.18 * sin(float(i) * 1.7), sin(a1) * 0.95)
		var p2: Vector3 = Vector3(cos(a2) * 0.95, 0.2 + 0.18 * sin(float(i + 1) * 1.7), sin(a2) * 0.95)
		var line: MeshInstance3D = MeshInstance3D.new()
		var lm: CylinderMesh = CylinderMesh.new()
		lm.top_radius = 0.008
		lm.bottom_radius = 0.008
		lm.height = p1.distance_to(p2)
		lm.radial_segments = 4
		line.mesh = lm
		line.material_override = route_mat
		line.transform = Transform3D(Basis(Quaternion(Vector3.UP, (p2 - p1).normalized())), (p1 + p2) * 0.5)
		star_map.add_child(line)
	# beam / projector
	beam = MeshInstance3D.new()
	var bm: CylinderMesh = CylinderMesh.new()
	bm.top_radius = 0.95
	bm.bottom_radius = 0.35
	bm.height = 2.0
	bm.radial_segments = 28
	beam.mesh = bm
	beam.material_override = MatLib.holo(Color(0.3, 0.8, 1.0), 0.22)
	beam.position = Vector3(0, 1.0, 0)
	beam.visible = false
	add_child(beam)
	# light
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "DataLight"
	light.position = Vector3(0, 2.0, 0)
	light.light_color = Color(0.45, 0.9, 1.0)
	light.light_energy = 0.0
	light.omni_range = 6.0
	light.shadow_enabled = false
	add_child(light)
	# area, disabled until revealed
	area = Area3D.new()
	area.name = "DataArea"
	area.position = Vector3(0, 1.0, 0.9)
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.95
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")


func setup(p_audio: AudioDirector) -> void:
	_audio = p_audio


func reveal() -> void:
	if revealed_flag:
		return
	revealed_flag = true
	reveal_time = 0.0
	holo_root.visible = true
	beam.visible = true
	area.collision_layer = 8
	if _audio != null:
		_audio.play_sfx("data_reveal", global_position, -2.0)
	revealed.emit()


func get_prompt() -> String:
	if not revealed_flag:
		return ""
	if taken:
		return "航行数据已获取"
	return "E 提取深空航行数据"


func setup_coop(p_session: CoopSession) -> void:
	session = p_session


func interact(_p: PlayerController) -> void:
	if not revealed_flag or taken:
		return
	if session != null and not session.is_authority():
		var net_c: CoopNet = NetLookup.get_net()
		if net_c != null:
			net_c.submit_action("data")
		return
	taken = true
	area.collision_layer = 0
	if _audio != null:
		_audio.play_sfx("data_take", global_position, -2.0)
	data_taken.emit()


func _process(delta: float) -> void:
	_time += delta
	if revealed_flag:
		reveal_time = minf(1.0, reveal_time + delta * 0.8)
		if plinth != null:
			plinth.position.y = lerpf(-1.2, 0.0, ease(reveal_time, 0.35))
		if star_map != null and not taken:
			star_map.rotation.y += delta * 0.22
			star_map.rotation.x = sin(_time * 0.3) * 0.08
		var light: OmniLight3D = get_node_or_null("DataLight") as OmniLight3D
		if light != null:
			light.light_energy = (0.8 + sin(_time * 2.0) * 0.15) if not taken else 0.3
		if shard != null:
			shard.position.y = 1.35 + sin(_time * 1.4) * 0.06
			shard.rotation.y += delta * 0.6
		if taken:
			star_map.visible = false
			beam.visible = false
			shard.visible = false
			if _audio != null:
				pass


func reset_state() -> void:
	revealed_flag = false
	taken = false
	reveal_time = 0.0
	plinth.position.y = -1.2
	holo_root.visible = false
	beam.visible = false
	area.collision_layer = 0
	shard.visible = true
	star_map.visible = true
	var light: OmniLight3D = get_node_or_null("DataLight") as OmniLight3D
	if light != null:
		light.light_energy = 0.0
