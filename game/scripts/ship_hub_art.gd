extends Node3D
class_name ShipHubArt

## 归航号太空舱 2.0 · 英雄级视觉与物理氛围重构
## 严格遵循《美术制作与AI协作指南》：
## - 全面装配 Blender 4.5 锻造并烘焙 Col 顶点色的英雄 GLB（主龙骨拱架、全息星台、驾驶舱台、地热核心）
## - 绑定 ART-SAMPLE-002 2K PBR 多频贴图库（ArtPbrLib），严守 70/15/10/8/2 功能色板比例
## - gl_compatibility 五层布光（主故事光 + 补光 + 轮廓光 + 舱壁掠射光 + 实用状态光）
## - 接地暗晕 + 悬垂软管 + 克制假光束 + 贴地装甲因果导管 + 舱内物理互动物件（零悬浮 3D 文字）

const RIB_ARCH: PackedScene = preload("res://assets/models/rebuild/hero_ship_rib_arch.glb")
const STAR_TABLE: PackedScene = preload("res://assets/models/rebuild/hero_star_table.glb")
const PILOT_POD: PackedScene = preload("res://assets/models/rebuild/hero_pilot_pod.glb")
const GEO_GEN: PackedScene = preload("res://assets/models/rebuild/hero_geothermal_generator.glb")
const CRATE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_cargo_crate.glb")
const CORE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_thermal_core.glb")
const BOOMBOX_GLB: PackedScene = preload("res://assets/models/rebuild/hero_boombox.glb")
const ORB_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bumper_orb.glb")
const OXYGEN_GLB: PackedScene = preload("res://assets/models/rebuild/hero_oxygen_bottle.glb")
const THERMOS_GLB: PackedScene = preload("res://assets/models/rebuild/hero_thermos.glb")
const HANGING_SIGN_GLB: PackedScene = preload("res://assets/models/rebuild/hero_hanging_sign.glb")
const WALL_PLAQUE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_plaque.glb")
const TRAINING_GATE_GLB: PackedScene = preload("res://assets/ship-hub/kenney/modular-space/gate-door-window.glb")
const LED_SHADER: Shader = preload("res://shaders/led_screen.gdshader")

var _pbr: ArtPbrLib
var _conduit_mats: Array[ShaderMaterial] = []
var _star_ring_node: Node3D
var _clock: float = 0.0

func install(hub: Node3D) -> void:
	if OS.get_environment("SHIP_ART") == "0":
		return
	_pbr = ArtPbrLib.new()
	_upgrade_environment_and_lights(hub)
	_restyle_shell_and_hide_old_toys(hub)
	_build_hero_architecture()
	_build_signboards_and_training_entry()
	_build_conduits_and_atmosphere()
	_build_cabin_physics_toys()
	set_process(true)

func _process(delta: float) -> void:
	_clock += delta
	if _star_ring_node != null:
		_star_ring_node.rotation.y = _clock * 0.32
	for mat: ShaderMaterial in _conduit_mats:
		mat.set_shader_parameter("active_state", 0.72 + 0.20 * sin(_clock * 1.4))

func _upgrade_environment_and_lights(hub: Node3D) -> void:
	# 1. gl_compatibility 安全环境：显式关闭 SSR/SSIL/VolumetricFog，压低环境光底座让主光打立体块
	for child: Node in hub.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			if env != null:
				env.background_mode = Environment.BG_COLOR
				env.background_color = Color("#08111a")
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color("#5d7b92")
				env.ambient_light_energy = 0.24
				env.ssr_enabled = false
				env.ssil_enabled = false
				env.volumetric_fog_enabled = false
				env.fog_enabled = true
				env.fog_light_color = Color("#132433")
				env.fog_density = 0.0085
				env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				env.tonemap_exposure = 1.05
				env.adjustment_enabled = true
				env.adjustment_contrast = 1.12
				env.adjustment_saturation = 1.08
				env.glow_enabled = true
				env.glow_intensity = 0.32
				env.glow_bloom = 0.14
				env.glow_hdr_threshold = 0.92
		elif child is DirectionalLight3D:
			# 光层 1：主故事光 Key（从舰桥极地舷窗斜向掠入，唯一开阴影主光）
			var sun: DirectionalLight3D = child as DirectionalLight3D
			sun.rotation_degrees = Vector3(-28.0, 22.0, 0.0)
			sun.light_color = Color("#ffe5c4")
			sun.light_energy = 0.78
			sun.shadow_enabled = true
		elif child is OmniLight3D:
			# 压暗旧平铺顶灯，杜绝平光糊成一片
			var old_omni: OmniLight3D = child as OmniLight3D
			old_omni.light_energy *= 0.25

	# 光层 2：冷灰补光 Fill（关阴影，保证暗面结构可读）
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "ShipFillLight"
	fill.rotation_degrees = Vector3(-18.0, -145.0, 0.0)
	fill.light_color = Color("#7db4db")
	fill.light_energy = 0.34
	fill.shadow_enabled = false
	add_child(fill)

	# 光层 3：高对比青蓝轮廓光 Rim（从尾部引擎区反打，把控制台与龙骨剪影从暗舱壁剥离）
	var rim: SpotLight3D = SpotLight3D.new()
	rim.name = "ShipRimLight"
	rim.position = Vector3(0.0, 4.1, 13.8)
	rim.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
	rim.light_color = Color("#48d4f0")
	rim.light_energy = 2.6
	rim.spot_range = 30.0
	rim.spot_angle = 52.0
	rim.shadow_enabled = false
	add_child(rim)

	# 光层 4：舱壁掠射光 Graze（15° 贴壁斜擦龙骨与 2K 法线肌理）
	for sx: float in [-1.0, 1.0]:
		var graze: SpotLight3D = SpotLight3D.new()
		graze.name = "ShipWallGraze_%d" % int(sx)
		graze.position = Vector3(sx * 5.2, 4.0, -8.5)
		graze.rotation_degrees = Vector3(-22.0, sx * 12.0, 0.0)
		graze.light_color = Color("#ffd5a6")
		graze.light_energy = 2.1
		graze.spot_range = 24.0
		graze.spot_angle = 38.0
		graze.shadow_enabled = false
		add_child(graze)

	# 光层 5：实用状态光 Practical（直接挂在核心操作台与星图上方）
	_omni("StarTableGlow", Vector3(0.0, 2.2, -0.34), Color("#46d8f2"), 1.65, 8.5)
	_omni("BridgeHeroLight", Vector3(0.0, 3.6, -12.6), Color("#bfe4ff"), 1.55, 11.0)
	_omni("WorkshopTaskLight", Vector3(4.8, 2.8, 2.2), Color("#ffd296"), 1.75, 7.5)
	_omni("RepairTaskLight", Vector3(4.8, 2.8, -2.5), Color("#ffad5c"), 1.45, 6.5)
	_omni("RefillTaskLight", Vector3(-4.8, 2.8, 2.2), Color("#58ebb8"), 1.55, 7.5)
	_omni("StoreTaskLight", Vector3(-4.8, 2.8, -2.5), Color("#70d6f0"), 1.35, 6.5)
	_omni("AirlockWarningLight", Vector3(0.0, 3.1, 13.4), Color("#ff8e42"), 1.75, 8.0)

func _restyle_shell_and_hide_old_toys(hub: Node3D) -> void:
	# 用 ART-SAMPLE-002 2K 材质库（vertex_mask_valid=false）覆盖旧舱壳，彻底消灭 Kenney 塑料玩具感
	var mats_no_vc: Dictionary = _pbr.build_palette("ship", false)
	var deck_mat: Material = mats_no_vc["M_SteelDeep"] as Material
	var wall_mat: Material = mats_no_vc["M_PaintGrey"] as Material
	var ceil_mat: Material = mats_no_vc["M_CastSteel"] as Material

	for node: Node in hub.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var n: String = String(mesh.name)
		var p: String = String(mesh.get_parent().name) if mesh.get_parent() != null else ""
		var gp: String = String(mesh.get_parent().get_parent().name) if mesh.get_parent() != null and mesh.get_parent().get_parent() != null else ""
		var tag: String = n + " " + p + " " + gp
		# 隐藏已被 Blender 英雄 GLB 替代的旧版方块龙骨、旧星图台与旧驾驶台
		if tag.contains("HullRib") or tag.contains("RibWarningBand") or tag.contains("StarChartPedestal") or tag.contains("CentralStarChart") or tag.contains("FlightConsole") or tag.contains("FlightSeat") or tag.contains("NavigationDisplay"):
			mesh.visible = false
			continue
		if tag.contains("panorama_glass") or tag.contains("Decor_plant") or tag.contains("Decor_soil") or tag.contains("ShipDevices") or tag.contains("PromenadeGuide") or tag.contains("WalkwayInsert") or tag.contains("CentralCeilingStrip") or tag.contains("Hero"):
			continue
		# 判断是否属于 KenneyInterior 舱壁/门框/地板（彻底洗掉原包亮黄条纹，统一 ART-SAMPLE-002 工业色板）
		var in_kenney: bool = false
		var cur: Node = mesh
		while cur != null and cur != hub:
			if String(cur.name) == "KenneyInterior":
				in_kenney = true
				break
			cur = cur.get_parent()
		if tag.contains("Deck_") or tag.contains("floor") or tag.contains("BridgePlatform"):
			mesh.material_override = deck_mat
		elif tag.contains("Ceiling") or tag.contains("Shoulder") or tag.contains("RaisedHull") or tag.contains("panel"):
			mesh.material_override = ceil_mat
		elif in_kenney or tag.contains("Wall") or tag.contains("Bulkhead") or tag.contains("Partition") or tag.contains("UpperSide") or tag.contains("UpperCorner") or tag.contains("gate") or tag.contains("pillar"):
			mesh.material_override = wall_mat

func _build_hero_architecture() -> void:
	# 1. 五道 Blender 锻造承压主龙骨拱架（宽 13.5m × 高 4.8m，带工业橙柱靴、奶油白立柱与顶部铜管）
	for z: float in [-11.4, -5.6, 0.2, 6.2, 12.0]:
		var arch: Node3D = _spawn_hero(RIB_ARCH, "ShipRibArch_%.0f" % z, Vector3(0.0, 0.0, z))
		ArtAtmosphereKit.build_ground_skirt(self, Vector3(-6.45, 0.0, z), 1.35, 0.48)
		ArtAtmosphereKit.build_ground_skirt(self, Vector3(6.45, 0.0, z), 1.35, 0.48)
		if absf(z) < 8.0:
			ArtAtmosphereKit.build_godray_cone(self, Vector3(0.0, 4.42, z), 4.2, 1.0, 2.8, Color("#c8e8ff"), 0.09)
		arch.visible = true

	# 2. 中央英雄全息星图台（位于 (0, 0, -0.34)）
	var table: Node3D = _spawn_hero(STAR_TABLE, "HeroStarTable", Vector3(0.0, 0.0, -0.34))
	ArtAtmosphereKit.build_ground_skirt(self, Vector3(0.0, 0.0, -0.34), 2.15, 0.52)
	_star_ring_node = Node3D.new()
	_star_ring_node.name = "OrbitHoloSpinner"
	_star_ring_node.position = Vector3(0.0, 1.62, -0.34)
	add_child(_star_ring_node)
	# 动态旋转的小行星全息微标
	var orb_mat: Material = _pbr.build_palette("ship", false)["M_GlowCyan"] as Material
	for i: int in 3:
		var m: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.065 if i == 0 else 0.042
		sm.height = sm.radius * 2.0
		m.mesh = sm
		m.material_override = orb_mat
		var ang: float = float(i) * TAU / 3.0
		m.position = Vector3(cos(ang) * 0.68, sin(ang * 2.0) * 0.14, sin(ang) * 0.68)
		_star_ring_node.add_child(m)
	table.visible = true

	# 3. 舰桥 4 座英雄驾驶台（与 ShipDevices3D.PILOT_X 完全对齐）
	for index: int in 4:
		var px: float = ShipDevices3D.PILOT_X[index]
		_spawn_hero(PILOT_POD, "HeroPilotPod_%d" % index, Vector3(px, 0.61, -13.55))
		ArtAtmosphereKit.build_ground_skirt(self, Vector3(px, 0.61, -13.55), 1.1, 0.38)

	# 4. 左右尾部引擎核心机组（强化探索飞船的重工压迫感与蒸汽生命力）
	for sx: float in [-1.0, 1.0]:
		var gpos: Vector3 = Vector3(sx * 11.2, 0.0, 12.2)
		var gen: Node3D = _spawn_hero(GEO_GEN, "ShipEngineCore_%d" % int(sx), gpos)
		gen.scale = Vector3.ONE * 0.78
		ArtAtmosphereKit.build_ground_skirt(self, gpos, 2.2, 0.52)
		ArtAtmosphereKit.build_steam_vent(self, gpos + Vector3(0.0, 3.8, 0.0), Color(0.84, 0.94, 1.0, 0.22), 0.65)
		_omni("EngineCoreGlow_%d" % int(sx), gpos + Vector3(0.0, 1.6, -1.6), Color("#ff9842"), 1.4, 8.0)

func _build_conduits_and_atmosphere() -> void:
	# 贴地装甲因果能量导管：从星图台辐射连向 4 座驾驶席与 4 处核心环线站（绕开中央主走道）
	_conduit_mats.clear()
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(-1.3, 0.07, -0.34), Vector3(-4.8, 0.07, -0.34), Vector3(-4.8, 0.07, 2.2)
	], 0.075, Color("#28dbff")))
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(-4.8, 0.07, -0.34), Vector3(-4.8, 0.07, -2.5)
	], 0.075, Color("#28dbff")))
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(1.3, 0.07, -0.34), Vector3(4.8, 0.07, -0.34), Vector3(4.8, 0.07, 2.2)
	], 0.075, Color("#f4a432")))
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(4.8, 0.07, -0.34), Vector3(4.8, 0.07, -2.5)
	], 0.075, Color("#f4a432")))
	# 星图台 → 舰桥四驾驶席主供能管线（紧贴甲板 y=0.05 铺设，遇舰桥台阶垂直攀升，零悬空斜线）
	for px: float in ShipDevices3D.PILOT_X:
		_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
			Vector3(px * 0.20, 0.05, -1.65),
			Vector3(px, 0.05, -5.8),
			Vector3(px, 0.05, -12.78),
			Vector3(px, 0.64, -12.78),
			Vector3(px, 0.64, -13.15)
		], 0.06, Color("#28dbff")))

	# 星图台 → 右舷独立训练舱通道的青色引导导管（直观把训练舱与后方出舱气闸区分开）
	_conduit_mats.append(PhysicalLinkKit.build_conduit_path(self, [
		Vector3(1.3, 0.06, 1.0), Vector3(3.1, 0.06, 6.2), Vector3(3.1, 0.06, 10.18), Vector3(5.8, 0.06, 10.18)
	], 0.065, Color("#3ce8b4")))

	# 顶部悬链线软管（打破呆板横平竖直）
	for sx: float in [-1.0, 1.0]:
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(sx * 5.9, 3.6, -5.6), Vector3(sx * 5.9, 3.6, 0.2), 0.55, 0.045)
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(sx * 5.9, 3.6, 0.2), Vector3(sx * 5.9, 3.6, 6.2), 0.52, 0.042)
		ArtAtmosphereKit.build_catenary_hose(self, Vector3(sx * 5.9, 3.2, 6.2), Vector3(sx * 5.9, 3.2, 12.0), 0.48, 0.040)

	# 气闸泄压微蒸汽
	ArtAtmosphereKit.build_steam_vent(self, Vector3(-1.8, 0.2, 14.6), Color(0.86, 0.94, 1.0, 0.24), 0.55)
	ArtAtmosphereKit.build_steam_vent(self, Vector3(1.8, 0.2, 14.6), Color(0.86, 0.94, 1.0, 0.24), 0.55)

func _build_cabin_physics_toys() -> void:
	# 在主舱休息区放置可踢、可推撞的 Jolt 真实刚体工业箱、复古音响、碰碰球、氧气瓶与热可可壶
	var toy_positions: Array = [
		[CRATE_GLB, Vector3(-2.6, 0.6, 7.6), Vector3(0.75, 0.55, 0.62), 6.0, 0.82, false],
		[CRATE_GLB, Vector3(2.8, 0.6, 7.2), Vector3(0.75, 0.55, 0.62), 6.0, 0.82, false],
		[CORE_GLB, Vector3(-2.8, 0.6, 8.8), Vector3(0.55, 0.85, 0.55), 4.5, 0.82, false],
		[BOOMBOX_GLB, Vector3(2.2, 0.55, 5.4), Vector3(0.68, 0.42, 0.28), 2.5, 1.0, false],
		[ORB_GLB, Vector3(-1.4, 0.75, 6.2), Vector3(0.65, 0.65, 0.65), 1.8, 0.95, true],
		[OXYGEN_GLB, Vector3(-3.6, 0.55, 4.2), Vector3(0.32, 0.70, 0.32), 2.2, 0.95, false],
		[THERMOS_GLB, Vector3(3.2, 0.55, 4.4), Vector3(0.24, 0.48, 0.24), 1.2, 1.05, false],
	]
	for entry: Array in toy_positions:
		var rb: RigidBody3D = RigidBody3D.new()
		rb.name = "CabinPhysicsProp"
		rb.position = entry[1]
		rb.mass = float(entry[3])
		rb.collision_layer = 4
		rb.collision_mask = 2 | 4 | 1
		if bool(entry[5]):
			var pm: PhysicsMaterial = PhysicsMaterial.new()
			pm.bounce = 0.88
			pm.friction = 0.18
			rb.physics_material_override = pm
		var cs: CollisionShape3D = CollisionShape3D.new()
		if bool(entry[5]):
			var sp: SphereShape3D = SphereShape3D.new()
			sp.radius = 0.34
			cs.shape = sp
			cs.position.y = 0.34
		else:
			var bs: BoxShape3D = BoxShape3D.new()
			bs.size = entry[2]
			cs.shape = bs
			cs.position.y = (entry[2] as Vector3).y * 0.5
		rb.add_child(cs)
		var vis: Node3D = (entry[0] as PackedScene).instantiate() as Node3D
		vis.scale = Vector3.ONE * float(entry[4])
		_pbr.bind_glb(vis, "ship", true)
		rb.add_child(vis)
		add_child(rb)

func _build_signboards_and_training_entry() -> void:
	# 1. 天花板/龙骨实体金属吊牌（鸿蒙字体暖白手账风，彻底替代丑陋地板文字）
	_mount_hanging_sign("SignBridge", "res://assets/textures/ship_signs/sign_bridge.png", Vector3(0.0, 3.82, -11.0), 0.0, 0.96)
	_mount_hanging_sign("SignShipName", "res://assets/textures/ship_signs/sign_ship_name.png", Vector3(0.0, 4.02, 5.8), PI, 0.78)
	_mount_hanging_sign("SignAirlockExit", "res://assets/textures/ship_signs/sign_airlock.png", Vector3(0.0, 3.62, 14.55), PI, 1.04)

	# 2. 舱壁/立柱实体壁挂指示牌（挂在对应设备后方舱壁上方，视线平齐清晰好读）
	_mount_wall_plaque("PlaqueStore", "res://assets/textures/ship_signs/sign_store.png", Vector3(-6.24, 2.68, -2.5), PI * 0.5, 1.0)
	_mount_wall_plaque("PlaqueRefill", "res://assets/textures/ship_signs/sign_refill.png", Vector3(-6.24, 2.68, 2.2), PI * 0.5, 1.0)
	_mount_wall_plaque("PlaqueRepair", "res://assets/textures/ship_signs/sign_repair.png", Vector3(6.24, 2.68, -2.5), -PI * 0.5, 1.0)
	_mount_wall_plaque("PlaqueWorkshop", "res://assets/textures/ship_signs/sign_workshop.png", Vector3(6.24, 2.68, 2.2), -PI * 0.5, 1.0)

	# 3. 右舷独立训练舱专用气闸入口（X=+6.55, Z=+10.18，与正后方尾舱星球出舱门呈 90° 彻底分开！）
	var gate_pos: Vector3 = Vector3(6.52, 0.0, 10.18)
	var gate: Node3D = TRAINING_GATE_GLB.instantiate() as Node3D
	gate.name = "TrainingBaySideHatch"
	gate.position = gate_pos
	gate.rotation.y = -PI * 0.5
	gate.scale = Vector3(1.15, 1.15, 1.15)
	# 洗掉原包亮黄门漆，统一绑定 ART-SAMPLE-002 工业暗钢与青绿识别涂装
	var ship_mats: Dictionary = _pbr.build_palette("ship", false)
	var gate_steel: Material = ship_mats["M_SteelDeep"] as Material
	var gate_teal: Material = ship_mats["M_PaintTeal"] as Material
	for child: Node in gate.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi != null:
			mi.material_override = gate_teal if String(mi.name).to_lower().contains("door") else gate_steel
	add_child(gate)
	# 给右舷训练舱入口加上独立青绿门灯与壁挂金属指示牌
	_mount_wall_plaque("PlaqueTrainingBay", "res://assets/textures/ship_signs/sign_training.png", Vector3(6.18, 3.22, 10.18), -PI * 0.5, 1.15)
	_omni("TrainingEntryBeacon", Vector3(5.3, 2.9, 10.18), Color("#46e8b8"), 1.85, 8.0)
	PhysicalLinkKit.build_status_lamp(self, Vector3(6.15, 2.35, 8.85))
	PhysicalLinkKit.build_status_lamp(self, Vector3(6.15, 2.35, 11.50))

func _mount_hanging_sign(node_name: String, tex_path: String, pos: Vector3, yaw: float, sc: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = Vector3.ONE * sc
	add_child(holder)
	var frame: Node3D = HANGING_SIGN_GLB.instantiate() as Node3D
	_pbr.bind_glb(frame, "ship", true)
	holder.add_child(frame)
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex != null:
		# 双面点阵发光 LED 显示屏（带微细点阵与缓慢扫描线）
		for side_z: float in [0.068, -0.068]:
			var face: MeshInstance3D = MeshInstance3D.new()
			var q: QuadMesh = QuadMesh.new()
			q.size = Vector2(2.36, 0.72)
			face.mesh = q
			face.position = Vector3(0.0, 0.0, side_z)
			if side_z < 0.0:
				face.rotation.y = PI
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = LED_SHADER
			mat.set_shader_parameter("screen_tex", tex)
			mat.set_shader_parameter("emit_strength", 1.28)
			face.material_override = mat
			holder.add_child(face)

func _mount_wall_plaque(node_name: String, tex_path: String, pos: Vector3, yaw: float, sc: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = Vector3.ONE * sc
	add_child(holder)
	var frame: Node3D = WALL_PLAQUE_GLB.instantiate() as Node3D
	_pbr.bind_glb(frame, "ship", true)
	holder.add_child(frame)
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex != null:
		var face: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(1.68, 0.56)
		face.mesh = q
		face.position = Vector3(0.0, 0.0, 0.026)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = LED_SHADER
		mat.set_shader_parameter("screen_tex", tex)
		mat.set_shader_parameter("emit_strength", 1.24)
		face.material_override = mat
		holder.add_child(face)

func _spawn_hero(scene: PackedScene, node_name: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var inst: Node3D = scene.instantiate() as Node3D
	inst.name = node_name
	inst.position = pos
	inst.rotation.y = yaw
	_pbr.bind_glb(inst, "ship", true)
	add_child(inst)
	return inst

func _omni(node_name: String, pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
