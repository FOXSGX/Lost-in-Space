extends Node3D
class_name ShipTutorialArt

## 归航号独立训练舱 2.0 · 零重力喷气试飞厅视觉与互动重做
## - 居中对称英雄氧气展示台（彻底解决台子偏歪与挡视线问题，氧气瓶稳坐中央聚光灯下）
## - 3 座高空双层发光飞行穿环（抬高至真实喷气飞行抛物线高度，不再贴地）
## - 科技感点阵 LED 中央吊屏 + 五层 gl_compatibility 机库布光 + 4 道龙骨拱架
## - 底部开放式互动试玩区（可弹飞的极地弹跳垫 + 可踢碰碰球 + 复古音响）

const RIB_ARCH: PackedScene = preload("res://assets/models/rebuild/hero_ship_rib_arch.glb")
const PEDESTAL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_equip_pedestal.glb")
const REFILL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_refill_pod.glb")
const BOUNCE_PAD_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bounce_pad.glb")
const BOOMBOX_GLB: PackedScene = preload("res://assets/models/rebuild/hero_boombox.glb")
const ORB_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bumper_orb.glb")
const CRATE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_cargo_crate.glb")
const HANGING_SIGN_GLB: PackedScene = preload("res://assets/models/rebuild/hero_hanging_sign.glb")
const LED_SHADER: Shader = preload("res://shaders/led_screen.gdshader")

var _pbr: ArtPbrLib
var _rings: Array[Node3D] = []
var _conduit_mats: Array[ShaderMaterial] = []
var _bounce_pad_pos: Vector3 = Vector3(1.6, 0.0, 4.1)
var _bounce_pad_node: Node3D
var _bounce_cd: float = 0.0
var _bounce_squish: float = 0.0
var _clock: float = 0.0

func install(room: Node3D) -> void:
	_pbr = ArtPbrLib.new()
	_upgrade_environment_and_lights(room)
	_restyle_room_and_platforms(room)
	_build_hero_hangar_architecture()
	_build_flight_rings_and_conduits()
	_build_training_playground()
	set_process(true)
	set_physics_process(true)

func _process(delta: float) -> void:
	_clock += delta
	for i: int in _rings.size():
		var r: Node3D = _rings[i]
		r.rotation.z = _clock * (0.48 if i % 2 == 0 else -0.42)
	for mat: ShaderMaterial in _conduit_mats:
		mat.set_shader_parameter("active_state", 0.78 + 0.18 * sin(_clock * 1.8))
	if _bounce_pad_node != null:
		_bounce_squish = maxf(0.0, _bounce_squish - delta * 3.5)
		_bounce_pad_node.scale = Vector3(1.0 + _bounce_squish * 0.20, 1.0 - _bounce_squish * 0.30, 1.0 + _bounce_squish * 0.20)

func _physics_process(delta: float) -> void:
	_bounce_cd = maxf(0.0, _bounce_cd - delta)
	if _bounce_cd > 0.0:
		return
	var root_node: Node = get_tree().root
	for p: Node in root_node.find_children("*", "SpacePlayer3D", true, false):
		var actor: CharacterBody3D = p as CharacterBody3D
		if actor != null:
			var flat_d: float = Vector2(actor.global_position.x - _bounce_pad_pos.x, actor.global_position.z - _bounce_pad_pos.z).length()
			if flat_d < 1.25 and absf(actor.global_position.y - _bounce_pad_pos.y) < 1.3:
				actor.velocity.y = 11.5
				_bounce_cd = 0.55
				_bounce_squish = 1.0

func _upgrade_environment_and_lights(room: Node3D) -> void:
	for child: Node in room.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			if env != null:
				env.background_mode = Environment.BG_COLOR
				env.background_color = Color("#08121d")
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color("#5b7c96")
				env.ambient_light_energy = 0.24
				env.ssr_enabled = false
				env.ssil_enabled = false
				env.volumetric_fog_enabled = false
				env.fog_enabled = true
				env.fog_light_color = Color("#102130")
				env.fog_density = 0.0075
				env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				env.tonemap_exposure = 1.04
				env.adjustment_enabled = true
				env.adjustment_contrast = 1.12
				env.adjustment_saturation = 1.08
				env.glow_enabled = true
				env.glow_intensity = 0.34
				env.glow_bloom = 0.14
				env.glow_hdr_threshold = 0.90

	# 光层 1：斜向机库主故事光（唯一阴影光源）
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "TrainingKeyLight"
	key.rotation_degrees = Vector3(-34.0, -28.0, 0.0)
	key.light_color = Color("#ffe4c2")
	key.light_energy = 0.90
	key.shadow_enabled = true
	add_child(key)

	# 光层 2：冷青补光
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "TrainingFillLight"
	fill.rotation_degrees = Vector3(-16.0, 145.0, 0.0)
	fill.light_color = Color("#74b4de")
	fill.light_energy = 0.34
	fill.shadow_enabled = false
	add_child(fill)

	# 光层 3：工业掠射射灯
	var rim1: SpotLight3D = SpotLight3D.new()
	rim1.position = Vector3(-9.2, 7.6, -5.2)
	rim1.rotation_degrees = Vector3(-35.0, -52.0, 0.0)
	rim1.light_color = Color("#45d8f5")
	rim1.light_energy = 2.6
	rim1.spot_range = 24.0
	rim1.spot_angle = 52.0
	add_child(rim1)

	var rim2: SpotLight3D = SpotLight3D.new()
	rim2.position = Vector3(8.6, 8.2, 4.8)
	rim2.rotation_degrees = Vector3(-42.0, 132.0, 0.0)
	rim2.light_color = Color("#ffbd6b")
	rim2.light_energy = 2.5
	rim2.spot_range = 22.0
	rim2.spot_angle = 48.0
	add_child(rim2)

	# 光层 4：功能点位实用光
	_omni("EquipSpot", Vector3(-7.0, 2.4, 3.8), Color("#58f0e0"), 2.1, 8.5)
	_omni("HopSpot", ShipTutorial3D.HOP_POINT + Vector3(0.0, 2.2, 0.0), Color("#6ad8f0"), 1.5, 8.0)
	_omni("BoostSpot", ShipTutorial3D.BOOST_POINT + Vector3(0.0, 2.2, 0.0), Color("#4ee6c0"), 1.7, 9.0)
	_omni("CrossSpot", ShipTutorial3D.CROSS_POINT + Vector3(0.0, 2.2, 0.0), Color("#78d4f2"), 1.7, 9.0)
	_omni("FinishSpot", ShipTutorial3D.FINISH_POINT + Vector3(0.0, 2.4, 0.0), Color("#ffbc58"), 2.4, 11.0)
	_omni("ExitDoorSpot", Vector3(8.1, 3.2, 5.2), Color("#ff9852"), 1.7, 8.5)

func _restyle_room_and_platforms(room: Node3D) -> void:
	var mats: Dictionary = _pbr.build_palette("ship", false)
	var deck_mat: Material = mats["M_SteelDeep"] as Material
	var wall_mat: Material = mats["M_PaintGrey"] as Material
	var ceil_mat: Material = mats["M_CastSteel"] as Material
	var pad_mat: Material = mats["M_PaintCream"] as Material
	var leg_mat: Material = mats["M_SteelDeep"] as Material
	var finish_mat: Material = mats["M_PaintOrange"] as Material
	var door_teal: Material = mats["M_PaintTeal"] as Material

	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n: String = String(mi.name)
		if n == "LedDisplayFace" or n.contains("Stripe") or n.contains("LandingStripe") or n.contains("CeilingLight") or n.contains("SideTrim"):
			continue
		if n.contains("FinishLandingPad"):
			mi.material_override = finish_mat
		elif n.contains("LandingPad"):
			mi.material_override = pad_mat
		elif n.contains("Platform") or n.contains("Support"):
			mi.material_override = leg_mat
		elif n.contains("Floor") or n.contains("floor"):
			mi.material_override = deck_mat
		elif n.contains("Ceiling"):
			mi.material_override = ceil_mat
		elif n.to_lower().contains("door"):
			mi.material_override = door_teal
		elif n.contains("Wall") or n.contains("Hull") or n.contains("gate"):
			mi.material_override = wall_mat

func _build_hero_hangar_architecture() -> void:
	# 1. 四道横跨机库的 Blender 承压龙骨拱架（宽 13.5m × 高 9.2m）
	for rx: float in [-8.2, -2.8, 2.8, 8.2]:
		var arch: Node3D = RIB_ARCH.instantiate() as Node3D
		arch.name = "TrainingRibArch_%.0f" % rx
		arch.position = Vector3(rx, 0.0, 0.0)
		arch.rotation.y = PI * 0.5
		arch.scale = Vector3(0.96, 1.90, 1.0)
		_pbr.bind_glb(arch, "ship", true)
		add_child(arch)
		ArtAtmosphereKit.build_ground_skirt(self, Vector3(rx, 0.0, -6.3), 1.3, 0.45)
		ArtAtmosphereKit.build_ground_skirt(self, Vector3(rx, 0.0, 6.3), 1.3, 0.45)
	ArtAtmosphereKit.build_godray_cone(self, Vector3(-7.0, 9.0, 3.8), 8.6, 0.9, 2.6, Color("#7ef0ff"), 0.075)
	ArtAtmosphereKit.build_godray_cone(self, Vector3(6.4, 9.0, 2.5), 8.6, 1.2, 3.4, Color("#ffd494"), 0.085)

	# 2. 正中对称的英雄级氧气瓶展示圆台（完全居中对齐 (-7.0, 0, 3.8)，顶面精确落在 y=0.95 托住氧气瓶，绝不偏歪！）
	var ped: Node3D = PEDESTAL_GLB.instantiate() as Node3D
	ped.name = "HeroOxygenPedestal"
	ped.position = Vector3(-7.0, 0.0, 3.8)
	_pbr.bind_glb(ped, "ship", true)
	add_child(ped)
	ArtAtmosphereKit.build_ground_skirt(self, Vector3(-7.0, 0.0, 3.8), 1.35, 0.48)

	# 靠后左角落放一台生命充氧舱作环境叙事装饰
	var pod: Node3D = REFILL_GLB.instantiate() as Node3D
	pod.name = "HeroTrainingRefillPod"
	pod.position = Vector3(-9.3, 0.0, -4.6)
	pod.rotation.y = PI * 0.25
	_pbr.bind_glb(pod, "ship", true)
	add_child(pod)
	ArtAtmosphereKit.build_ground_skirt(self, Vector3(-9.3, 0.0, -4.6), 1.0, 0.45)

	# 3. 顶部悬链线软管 + 返回门边泄压蒸汽
	for sz: float in [-5.8, 5.8]:
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(-8.2, 7.8, sz), Vector3(-2.8, 7.8, sz), 0.68, 0.05)
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(-2.8, 7.8, sz), Vector3(2.8, 7.8, sz), 0.68, 0.05)
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(2.8, 7.8, sz), Vector3(8.2, 7.8, sz), 0.68, 0.05)
	ArtAtmosphereKit.build_steam_vent(self, Vector3(6.2, 0.2, 5.9), Color(0.84, 0.95, 1.0, 0.28), 0.6)

	# 4. 机库顶部中央双面科技感 LED 大屏吊牌
	var sign_holder: Node3D = Node3D.new()
	sign_holder.position = Vector3(0.0, 8.05, 0.0)
	add_child(sign_holder)
	var frame: Node3D = HANGING_SIGN_GLB.instantiate() as Node3D
	frame.scale = Vector3(1.22, 1.22, 1.22)
	_pbr.bind_glb(frame, "ship", true)
	sign_holder.add_child(frame)
	var tex: Texture2D = load("res://assets/textures/ship_signs/sign_training.png") as Texture2D
	if tex != null:
		for side_z: float in [0.084, -0.084]:
			var face: MeshInstance3D = MeshInstance3D.new()
			var q: QuadMesh = QuadMesh.new()
			q.size = Vector2(2.86, 0.86)
			face.mesh = q
			face.position = Vector3(0.0, 0.0, side_z)
			if side_z < 0.0:
				face.rotation.y = PI
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = LED_SHADER
			mat.set_shader_parameter("screen_tex", tex)
			mat.set_shader_parameter("emit_strength", 1.26)
			face.material_override = mat
			sign_holder.add_child(face)

func _build_flight_rings_and_conduits() -> void:
	# 1. 贴地装甲发光导引管（从氧气展示台顺畅串联到四座阶梯高台）
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(-6.2, 0.05, 3.8),
		Vector3(-3.8, 0.05, 3.8),
		Vector3(-4.2, 0.05, -2.3),
		Vector3(2.2, 0.05, -2.3),
		Vector3(6.4, 0.05, 2.5),
	], 0.075, Color("#34e6c6")))

	# 2. 高空双层发光飞行穿环（全部抬高至真实喷气起跳后的空中航线高度，绝不贴地挡人！）
	# Hop(y=0.55) -> Boost(y=2.6): 居中抬高至 y=3.45
	# Boost(y=2.6) -> Cross(y=4.35): 抬高至 y=5.30
	# Cross(y=4.35) -> Finish(y=5.7): 抬高至 y=6.85
	var steel_mat: Material = _pbr.build_palette("ship", false)["M_SteelDeep"] as Material
	var ring_specs: Array = [
		[Vector3(-4.0, 3.45, 0.75), Vector3(0.0, 0.0, 0.0), Color("#38e4ff"), 1.05],
		[Vector3(-1.0, 5.30, -2.3), Vector3(0.0, 90.0, 0.0), Color("#46f0c4"), 1.15],
		[Vector3(4.3, 6.85, 0.1), Vector3(0.0, -45.0, 0.0), Color("#ffba54"), 1.20],
	]
	for spec: Array in ring_specs:
		var pivot: Node3D = Node3D.new()
		pivot.position = spec[0]
		pivot.rotation_degrees = spec[1]
		add_child(pivot)
		var r_rad: float = float(spec[3])
		# 外层深钢导流环壳
		var outer: MeshInstance3D = MeshInstance3D.new()
		var ot: TorusMesh = TorusMesh.new()
		ot.inner_radius = r_rad + 0.05
		ot.outer_radius = r_rad + 0.14
		ot.rings = 24
		ot.ring_segments = 10
		outer.mesh = ot
		outer.rotation_degrees.x = 90.0
		outer.material_override = steel_mat
		pivot.add_child(outer)
		# 内层高亮发光穿越光环
		var inner: MeshInstance3D = MeshInstance3D.new()
		var it: TorusMesh = TorusMesh.new()
		it.inner_radius = r_rad - 0.055
		it.outer_radius = r_rad + 0.045
		it.rings = 24
		it.ring_segments = 10
		inner.mesh = it
		inner.rotation_degrees.x = 90.0
		var rmat: StandardMaterial3D = StandardMaterial3D.new()
		rmat.albedo_color = spec[2]
		rmat.emission_enabled = true
		rmat.emission = spec[2]
		rmat.emission_energy_multiplier = 2.1
		inner.material_override = rmat
		pivot.add_child(inner)
		_rings.append(pivot)

func _build_training_playground() -> void:
	# 训练舱底部宽敞互动区：极地弹跳垫 + 碰碰球 + 复古音响
	_bounce_pad_node = Node3D.new()
	_bounce_pad_node.name = "TrainingBouncePad"
	_bounce_pad_node.position = _bounce_pad_pos
	var pad_vis: Node3D = BOUNCE_PAD_GLB.instantiate() as Node3D
	_pbr.bind_glb(pad_vis, "ship", true)
	_bounce_pad_node.add_child(pad_vis)
	add_child(_bounce_pad_node)
	_omni("TrainingBounceGlow", _bounce_pad_pos + Vector3(0.0, 0.8, 0.0), Color("#48eaff"), 1.4, 6.0)

	var toys: Array = [
		[ORB_GLB, Vector3(-0.4, 0.7, 1.5), 1.8, true],
		[BOOMBOX_GLB, Vector3(3.8, 0.5, 4.8), 2.5, false],
		[CRATE_GLB, Vector3(-8.4, 0.6, -2.0), 5.0, false],
	]
	for t: Array in toys:
		var rb: RigidBody3D = RigidBody3D.new()
		rb.position = t[1]
		rb.mass = float(t[2])
		rb.collision_layer = 4
		rb.collision_mask = 2 | 4 | 1
		var cs: CollisionShape3D = CollisionShape3D.new()
		if bool(t[3]):
			var pm: PhysicsMaterial = PhysicsMaterial.new()
			pm.bounce = 0.90
			pm.friction = 0.16
			rb.physics_material_override = pm
			var sp: SphereShape3D = SphereShape3D.new()
			sp.radius = 0.34
			cs.shape = sp
			cs.position.y = 0.34
		else:
			var bs: BoxShape3D = BoxShape3D.new()
			bs.size = Vector3(0.68, 0.50, 0.52)
			cs.shape = bs
			cs.position.y = 0.25
		rb.add_child(cs)
		var vis: Node3D = (t[0] as PackedScene).instantiate() as Node3D
		vis.scale = Vector3.ONE * 0.92
		_pbr.bind_glb(vis, "ship", true)
		rb.add_child(vis)
		add_child(rb)

func _omni(node_name: String, pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
