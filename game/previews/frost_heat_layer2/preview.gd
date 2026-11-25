extends "res://previews/frost_open_layer1/preview.gd"

const HEAT_CONTROL: Vector3 = Vector3(17,1.2,33)
const MELT_SECONDS: float = 8.0
var melt: float = 0.0
var heating: bool = false
var heat_operator: int = 0
var ice_parts: Array[Dictionary] = []
var heat_beam: MeshInstance3D
var heat_lamp: OmniLight3D
var heat_gauge: MeshInstance3D
var valve: StaticBody3D
var melt_puddle: MeshInstance3D
var _effect_timer: float = 0.0

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("霜烬星 · 第2层热源融冰")
	print("FROST_HEAT_READY: hold E / persistent thaw / safe outside routes")

func _physics_process(delta: float) -> void:
	# The preview is an offline host. Shared environmental state is mutated
	# only here; formal RPC/snapshot integration remains layer 4.
	if not is_host or walker == null:
		return
	var held: bool = Input.is_action_pressed("interact") and not _settings_visible and not walker.downed
	if not held or not _heat_reachable(1,false) or melt>=1.0:
		_stop_heat()
	elif not heating and _heat_reachable(1,true):
		_start_heat(1)
	if not heating:
		return
	melt = minf(1.0,melt+delta/MELT_SECONDS)
	_apply_thaw()
	_effect_timer += delta
	if _effect_timer>0.14:
		_effect_timer = 0.0
		_drop_meltwater()
	if melt>=1.0:
		trace.append({"event":"ice_open","seconds":elapsed,"distance":distance_walked})
		print("FROST_ICE_OPEN ",elapsed)
		_stop_heat()
		show_notice("薄冰已融开 · 检修口可通行")

func _process(delta: float) -> void:
	super._process(delta)
	if not returned:
		status.text = "霜烬星 · 热源与路线"
	else:
		status.text = "已返回 · 可继续探索"
	if not _settings_visible and _heat_reachable(1,false):
		if melt>=1:
			prompt.text = "薄冰已融开 · 可以松手离开"
		elif heating:
			prompt.text = "供热中 %d%% · 松开 E 暂停" % roundi(melt*100)
		elif _heat_reachable(1,true):
			prompt.text = "按住 E 供热融冰" if melt<=0 else "按住 E 继续供热 · 已融 %d%%" % roundi(melt*100)
		prompt_back.visible = not prompt.text.is_empty()

func handle_action(peer: int, action: String) -> void:
	if action=="interact" and _heat_reachable(peer,true) and melt<1:
		_start_heat(peer)
		return
	super.handle_action(peer,action)

func _heat_reachable(peer: int, require_aim: bool) -> bool:
	var actor: SpacePlayer3D = players.get(peer) as SpacePlayer3D
	if actor==null or actor.downed or actor.position.distance_to(HEAT_CONTROL)>3.3:
		return false
	var eye: Vector3 = actor.global_position+Vector3.UP*SpacePlayer3D.SHIP_EYE_HEIGHT
	return not require_aim or actor.aim_direction().dot((HEAT_CONTROL-eye).normalized())>0.45

func _start_heat(peer: int) -> void:
	if not is_host or _settings_visible or melt>=1 or not _heat_reachable(peer,true):
		return
	if not heating:
		trace.append({"event":"heat_start","seconds":elapsed,"melt":melt})
	heating = true
	heat_operator = peer
	heat_beam.visible = true
	heat_lamp.light_energy = 1.5
	valve.rotation_degrees.z = -35

func _stop_heat() -> void:
	if heating:
		trace.append({"event":"heat_stop","seconds":elapsed,"melt":melt})
	heating = false
	heat_operator = 0
	heat_beam.visible = false
	heat_lamp.light_energy = 0.0
	valve.rotation_degrees.z = 20

func _apply_thaw() -> void:
	for part: Dictionary in ice_parts:
		var body: StaticBody3D = part.body as StaticBody3D
		var fraction: float = clampf((melt-float(part.begin))/float(part.duration),0,1)
		var visual: MeshInstance3D = body.get_child(0) as MeshInstance3D
		var shape: CollisionShape3D = body.get_child(1) as CollisionShape3D
		if fraction>=0.995:
			visual.visible = false
			body.collision_layer = 0
			continue
		var original: Vector3 = part.size
		var next_size: Vector3 = original*Vector3(1.0-fraction*0.5,1.0-fraction,1.0-fraction*0.65)
		(visual.mesh as BoxMesh).size = next_size
		(shape.shape as BoxShape3D).size = next_size
		var initial: Vector3 = part.position
		body.position = initial+Vector3.UP*(original.y-next_size.y)*(-0.5 if part.bottom else 0.5)
		var material: StandardMaterial3D = visual.material_override as StandardMaterial3D
		material.albedo_color = Color("#4b99b3").lerp(Color("#afe6ed"),fraction)
	heat_gauge.scale.y = maxf(0.03,melt)
	melt_puddle.scale = Vector3.ONE*(0.1+melt*0.9)

func _drop_meltwater() -> void:
	var drop: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	drop.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#88cbd9")
	drop.material_override = material
	drop.position = Vector3(11.2+randf()*1.6,1.5+randf()*3.0,29.35)
	add_child(drop)
	var fall: Tween = create_tween()
	fall.tween_property(drop,"position:y",0.03,0.45)
	fall.finished.connect(drop.queue_free)

func _build_buried_ridge() -> void:
	# Two short service passages in one local structure, not a maze network.
	_box("BuriedWestButtress",Vector3(-9,4,20.25),Vector3(10,8,17.5),Color("#7896a6"))
	_box("ServiceDivider",Vector3(6.5,4,20.25),Vector3(5,8,17.5),Color("#7896a6"))
	_box("ServiceEastButtress",Vector3(17.5,4,20.25),Vector3(5,8,17.5),Color("#7896a6"))
	_box("SnowCap",Vector3(3,7.8,21),Vector3(34,1.2,18),Color("#adc5d0"))
	_rock(Vector3(-16,0,23),4,9,Color("#91afbd"))
	_box("TunnelCeiling",Vector3(0,7.6,20),Vector3(8,0.8,20),Color("#425a68"))
	gate = _box("ShortcutDoor",Vector3(0,3.3,28),Vector3(7.8,6.6,0.65),Color("#465563"))
	gate_panel = gate.get_child(0) as MeshInstance3D
	_box("LatchPost",Vector3(2.7,1.25,27.3),Vector3(0.35,2.5,0.5),Color("#304c5a"))
	_box("InsideLatch",Vector3(2.7,1.2,27.05),Vector3(0.65,0.9,0.18),Color("#304c5a"))
	latch_lever = _box("LatchLever",Vector3(2.7,1.2,26.85),Vector3(0.15,0.65,0.18),Color("#edb65e"),true,true)
	latch_lever.rotation_degrees.z = -25
	_wall_arrow(Vector3(2.7,2.3,27.6),false)
	for x: float in [-4.5,4.5,8.6,15.4]:
		_box("PortalFrame",Vector3(x,3.6,30),Vector3(0.55,7.2,0.8),Color("#3e5664"))
	_box("ServiceRoof",Vector3(12,7.2,20.25),Vector3(6,0.5,17.5),Color("#425a68"))
	_add_ice(Vector3(10,3.55,29),Vector3(2,7.1,0.55),0.25,0.75,false)
	_add_ice(Vector3(14,3.55,29),Vector3(2,7.1,0.55),0.25,0.75,false)
	_add_ice(Vector3(12,4.7,29),Vector3(2,4.8,0.55),0.15,0.85,false)
	_add_ice(Vector3(12,1.15,29),Vector3(2,2.3,0.55),0.0,0.65,true)
	var puddle_body: StaticBody3D = _box("Meltwater",Vector3(12,0.015,29.3),Vector3(5.4,0.02,1.8),Color("#4d889d"),false)
	melt_puddle = puddle_body.get_child(0) as MeshInstance3D
	melt_puddle.scale = Vector3.ONE*0.1
	_build_heater()

func _build_ruin() -> void:
	super._build_ruin()
	# The inherited builder creates this child at runtime, outside the TSCN.
	var original_wall: StaticBody3D = find_child("FrontRight",false,false) as StaticBody3D
	if original_wall==null:
		push_error("Heat preview: runtime front wall was not built")
		return
	original_wall.collision_layer = 0
	original_wall.visible = false
	original_wall.queue_free()
	_box("ServiceInnerLeft",Vector3(6.5,2.8,11.5),Vector3(5,5.6,0.6),Color("#405966"))
	_box("ServiceInnerRight",Vector3(17.3,2.8,11.5),Vector3(4.6,5.6,0.6),Color("#405966"))
	_box("ServiceInnerLintel",Vector3(12,5,11.5),Vector3(6,1.6,0.6),Color("#405966"))
	_light(Vector3(12,2.6,14),Color("#a4cad5"),8,0.7)

func _add_ice(p: Vector3, dimensions: Vector3, begin: float, duration: float, bottom: bool) -> void:
	var body: StaticBody3D = _box("ThinIce",p,dimensions,Color("#4b99b3"))
	ice_parts.append({"body":body,"position":p,"size":dimensions,"begin":begin,"duration":duration,"bottom":bottom})

func _build_heater() -> void:
	_box("HeaterBase",Vector3(12,0.35,33),Vector3(2.2,0.7,1.6),Color("#455b68"))
	_box("HeaterNozzle",Vector3(12,1.1,32.8),Vector3(1.5,1.0,0.8),Color("#7c6955"))
	for x: float in [11.6,12,12.4]:
		_box("HeaterGrille",Vector3(x,1.1,32.35),Vector3(0.12,0.65,0.05),Color("#dfad6b"),false,true)
	_box("HeatSupplyPipe",Vector3(14.5,0.6,33),Vector3(5.2,0.2,0.2),Color("#ac8152"))
	_box("HeatControlPost",Vector3(17,1.5,33),Vector3(0.55,3,0.4),Color("#304b59"))
	_box("HeatControlPanel",Vector3(17,1.2,33.25),Vector3(0.9,0.9,0.18),Color("#a77c4b"))
	valve = _box("HeatValve",Vector3(17,1.2,33.4),Vector3(0.15,0.7,0.15),Color("#efc17d"))
	valve.rotation_degrees.z = 20
	_box("GaugeBacking",Vector3(17.35,1.9,33.25),Vector3(0.25,0.75,0.1),Color("#172e39"))
	var gauge: StaticBody3D = _box("ThawGauge",Vector3(17.35,1.9,33.32),Vector3(0.12,0.65,0.04),Color("#f2bd71"),false,true)
	heat_gauge = gauge.get_child(0) as MeshInstance3D
	heat_gauge.scale.y = 0.03
	_box("PictogramBacking",Vector3(17,2.5,33.25),Vector3(1.75,1.12,0.1),Color("#25414d"))
	var sign: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.65,1.03)
	sign.mesh = quad
	var sign_material: StandardMaterial3D = StandardMaterial3D.new()
	sign_material.albedo_texture = preload("res://previews/frost_heat_layer2/assets/heat-ice.svg")
	sign_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sign.material_override = sign_material
	sign.position = Vector3(17,2.5,33.31)
	add_child(sign)
	heat_beam = MeshInstance3D.new()
	var beam: CylinderMesh = CylinderMesh.new()
	beam.top_radius = 0.9
	beam.bottom_radius = 0.3
	beam.height = 3.0
	heat_beam.mesh = beam
	var beam_material: StandardMaterial3D = StandardMaterial3D.new()
	beam_material.albedo_color = Color(1,0.55,0.16,0.14)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heat_beam.material_override = beam_material
	heat_beam.rotation_degrees.x = 90
	heat_beam.position = Vector3(12,1.2,30.8)
	heat_beam.visible = false
	add_child(heat_beam)
	heat_lamp = OmniLight3D.new()
	heat_lamp.position = Vector3(12,2,30)
	heat_lamp.light_color = Color("#f5b36c")
	heat_lamp.omni_range = 8
	heat_lamp.light_energy = 0
	add_child(heat_lamp)
