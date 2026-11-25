extends Node3D
class_name FrostSandboxGameplay

## 霜烬星 2.0 · 高可玩性极寒物理沙盒 & 5件创意玩具互动引擎
## 1. 易爆低温燃料罐（hero_cryo_canister.glb）：吸推抛射/热融引爆 → 炸碎冰障与霜巡无人机
## 2. 地热喷汽间歇泉：周期性高压喷发 → 将玩家或极地运输车抛向高台/捷径
## 3. 主动霜巡哨兵无人机（hero_frost_drone.glb）：巡逻外围地标，会被信号弹吸引、被碰碰球/车/爆炸击毁
## 4. 便携热核供暖球（hero_thermal_core.glb）：暴风雪中为周围提供暖光与恒温护盾
## 5. 五大创意交互玩具：极地弹跳垫、极光信号弹、复古磁力音响、雪地碰碰球、热可可保温壶

const CANISTER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_cryo_canister.glb")
const DRONE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_frost_drone.glb")
const CORE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_thermal_core.glb")
const BOUNCE_PAD_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bounce_pad.glb")
const FLARE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_flare_stick.glb")
const BOOMBOX_GLB: PackedScene = preload("res://assets/models/rebuild/hero_boombox.glb")
const BUMPER_ORB_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bumper_orb.glb")
const BASIN_TERRAIN: Script = preload("res://previews/frost_station/basin_terrain.gd")

var director: Node3D
var world: Node3D
var _pbr: ArtPbrLib
var canisters: Array[Dictionary] = []
var geysers: Array[Dictionary] = []
var drones: Array[Dictionary] = []
var heat_cores: Array[RigidBody3D] = []
var bounce_pads: Array[Dictionary] = []
var flares: Array[Dictionary] = []
var boomboxes: Array[Dictionary] = []
var bumper_orbs: Array[Dictionary] = []
var explosions: Array[Dictionary] = []
var _clock: float = 0.0

func setup(owner_director: Node3D, owner_world: Node3D) -> void:
	name = "FrostSandboxGameplay"
	director = owner_director
	world = owner_world
	_pbr = ArtPbrLib.new()
	_spawn_canisters()
	_spawn_geysers()
	_spawn_drones()
	_spawn_thermal_cores()
	_spawn_preset_toys()

func _spawn_preset_toys() -> void:
	# 预置 3 个可以直接玩到的极地弹跳垫（主楼东侧上屋顶、温室广场旁、南翼特技跳台）
	deploy_bounce_pad(Vector3(-24.0, 0.0, -90.0), 0)
	deploy_bounce_pad(Vector3(-76.0, 0.0, -96.0), 0)
	var sy: float = BASIN_TERRAIN.sample_height(-102.0, 76.0)
	deploy_bounce_pad(Vector3(-102.0, sy, 76.0), 0)
	# 预置 1 台正在开派对的复古音响在主广场，营造一出门就热闹有趣的氛围
	deploy_boombox(Vector3(14.0, 0.0, -44.0), 0)
	# 预置 3 颗可直接踢着玩/吸推的雪地反重力碰碰球
	for orb_pos: Vector3 in [Vector3(-14.0, 1.0, -44.0), Vector3(-86.0, 1.0, -24.0), Vector3(88.0, 1.0, -88.0)]:
		_create_bumper_orb_body(orb_pos, Vector3.ZERO)

func _spawn_canisters() -> void:
	var pts: Array[Vector3] = [
		Vector3(-35.0, 1.0, -16.0),
		Vector3(-54.0, 1.0, -16.0),
		Vector3(38.0, 1.0, -34.0),
		Vector3(44.0, 1.0, -148.0),
		Vector3(-196.0, 2.5, -86.0),
		Vector3(204.0, 15.2, -68.0),
		Vector3(12.0, 1.0, -172.0),
		Vector3(-12.0, 1.0, -172.0),
		Vector3(-88.0, 1.0, -24.0),
		Vector3(88.0, 1.0, -98.0),
	]
	for idx: int in pts.size():
		var rb: RigidBody3D = RigidBody3D.new()
		rb.name = "CryoCanister_%d" % idx
		rb.position = pts[idx]
		rb.mass = 3.2
		rb.collision_layer = 8
		rb.collision_mask = 2 | 8 | 1
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = 0.30
		cyl.height = 1.05
		cs.shape = cyl
		cs.position.y = 0.52
		rb.add_child(cs)
		var vis: Node3D = CANISTER_GLB.instantiate() as Node3D
		_pbr.bind_glb(vis, "frost", true)
		rb.add_child(vis)
		add_child(rb)
		canisters.append({"body": rb, "home": pts[idx], "armed": false, "alive": true, "heat": 0.0, "respawn": 0.0})

func _spawn_geysers() -> void:
	var spots: Array = [
		[Vector3(-76.0, 0.2, -52.0), 15.0],
		[Vector3(-110.0, 0.4, -74.0), 16.5],
		[Vector3(118.0, 4.2, -40.0), 16.0],
		[Vector3(26.0, 0.2, -158.0), 14.5],
		[Vector3(-24.0, 0.2, -168.0), 16.0],
	]
	var ring_mat: Material = _pbr.build_palette("frost", false)["M_CastSteel"] as Material
	var glow_mat: Material = _pbr.build_palette("frost", false)["M_GlowCyan"] as Material
	for idx: int in spots.size():
		var pos: Vector3 = spots[idx][0]
		var power: float = float(spots[idx][1])
		var root: Node3D = Node3D.new()
		root.name = "SteamGeyser_%d" % idx
		root.position = pos
		add_child(root)
		var rim: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = 1.55
		cm.bottom_radius = 2.05
		cm.height = 0.42
		cm.radial_segments = 12
		rim.mesh = cm
		rim.material_override = ring_mat
		root.add_child(rim)
		var core: MeshInstance3D = MeshInstance3D.new()
		var c2: CylinderMesh = CylinderMesh.new()
		c2.top_radius = 1.1
		c2.bottom_radius = 1.1
		c2.height = 0.45
		c2.radial_segments = 12
		core.mesh = c2
		core.material_override = glow_mat
		root.add_child(core)
		ArtAtmosphereKit.build_ground_skirt(root, Vector3.ZERO, 2.6, 0.48)
		var vent: CPUParticles3D = ArtAtmosphereKit.build_steam_vent(root, Vector3(0, 0.35, 0), Color(0.74, 0.94, 1.0, 0.42), 1.65)
		geysers.append({"root": root, "pos": pos, "power": power, "vent": vent, "phase": float(idx) * 1.4, "cooldown": 0.0})

func _spawn_drones() -> void:
	var routes: Array = [
		[Vector3(-188.0, 4.2, -88.0), 14.0],
		[Vector3(198.0, 17.5, -72.0), 13.0],
		[Vector3(-102.0, 5.2, 78.0), 14.0],
		[Vector3(-14.0, 4.5, -198.0), 12.0],
	]
	for idx: int in routes.size():
		var center: Vector3 = routes[idx][0]
		var rad: float = float(routes[idx][1])
		var rb: RigidBody3D = RigidBody3D.new()
		rb.name = "FrostDrone_%d" % idx
		rb.position = center
		rb.mass = 4.0
		rb.gravity_scale = 0.0
		rb.linear_damp = 2.2
		rb.collision_layer = 8
		rb.collision_mask = 2 | 8 | 1
		var cs: CollisionShape3D = CollisionShape3D.new()
		var sp: SphereShape3D = SphereShape3D.new()
		sp.radius = 0.72
		cs.shape = sp
		rb.add_child(cs)
		var vis: Node3D = DRONE_GLB.instantiate() as Node3D
		_pbr.bind_glb(vis, "frost", true)
		rb.add_child(vis)
		var eye_light: OmniLight3D = OmniLight3D.new()
		eye_light.position = Vector3(0, 0, -0.8)
		eye_light.light_color = Color("#ff3b28")
		eye_light.light_energy = 1.6
		eye_light.omni_range = 10.0
		rb.add_child(eye_light)
		add_child(rb)
		drones.append({
			"body": rb, "home": center, "radius": rad, "hp": 100.0,
			"alive": true, "respawn": 0.0, "attack_cd": 0.0, "phase": float(idx) * 1.7
		})

func _spawn_thermal_cores() -> void:
	var pts: Array[Vector3] = [
		Vector3(46.0, 1.2, -104.0),
		Vector3(48.0, 1.2, -152.0),
		Vector3(210.0, 15.2, -72.0),
	]
	for idx: int in pts.size():
		var rb: RigidBody3D = RigidBody3D.new()
		rb.name = "PortableThermalCore_%d" % idx
		rb.position = pts[idx]
		rb.mass = 3.8
		rb.collision_layer = 8
		rb.collision_mask = 2 | 8 | 1
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = 0.36
		cyl.height = 0.96
		cs.shape = cyl
		cs.position.y = 0.48
		rb.add_child(cs)
		var vis: Node3D = CORE_GLB.instantiate() as Node3D
		_pbr.bind_glb(vis, "frost", true)
		rb.add_child(vis)
		var glow: OmniLight3D = OmniLight3D.new()
		glow.position = Vector3(0, 0.55, 0)
		glow.light_color = Color("#ff9c40")
		glow.light_energy = 2.0
		glow.omni_range = 13.0
		rb.add_child(glow)
		add_child(rb)
		heat_cores.append(rb)

# ------------------------------------------------------------------ 5 件创意小玩具接口

func deploy_bounce_pad(pos: Vector3, _owner_id: int) -> void:
	var root: Node3D = Node3D.new()
	root.name = "DeployedBouncePad_%d" % bounce_pads.size()
	root.position = Vector3(pos.x, maxf(pos.y, 0.05), pos.z)
	var vis: Node3D = BOUNCE_PAD_GLB.instantiate() as Node3D
	_pbr.bind_glb(vis, "frost", true)
	root.add_child(vis)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.position = Vector3(0, 0.7, 0)
	glow.light_color = Color("#45e6ff")
	glow.light_energy = 1.4
	glow.omni_range = 7.0
	root.add_child(glow)
	add_child(root)
	bounce_pads.append({"node": root, "pos": root.position, "cooldown": 0.0, "squish": 0.0})
	_spawn_explosion_fx(root.position + Vector3.UP * 0.4, Color("#45e6ff"), 2.4)

func throw_flare(origin: Vector3, dir: Vector3, _owner_id: int) -> void:
	var rb: RigidBody3D = RigidBody3D.new()
	rb.name = "ActiveFlare_%d" % flares.size()
	rb.position = origin
	rb.mass = 0.65
	rb.collision_layer = 8
	rb.collision_mask = 2 | 8 | 1
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.09
	cap.height = 0.55
	cs.shape = cap
	rb.add_child(cs)
	var vis: Node3D = FLARE_GLB.instantiate() as Node3D
	vis.position.y = -0.28
	_pbr.bind_glb(vis, "frost", true)
	rb.add_child(vis)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(0, 0.35, 0)
	light.light_color = Color("#ff7048")
	light.light_energy = 4.2
	light.omni_range = 24.0
	rb.add_child(light)
	ArtAtmosphereKit.build_steam_vent(rb, Vector3(0, 0.3, 0), Color(1.0, 0.48, 0.34, 0.52), 0.75)
	add_child(rb)
	var throw_v: Vector3 = dir.normalized() * 14.5 + Vector3.UP * 4.2
	rb.linear_velocity = throw_v
	rb.angular_velocity = Vector3(5.0, 3.0, -4.0)
	flares.append({"body": rb, "light": light, "life": 28.0})

func deploy_boombox(pos: Vector3, _owner_id: int) -> void:
	var root: Node3D = Node3D.new()
	root.name = "ActiveBoombox_%d" % boomboxes.size()
	root.position = Vector3(pos.x, maxf(pos.y, 0.08), pos.z)
	var vis: Node3D = BOOMBOX_GLB.instantiate() as Node3D
	vis.scale = Vector3.ONE * 1.18
	_pbr.bind_glb(vis, "frost", true)
	root.add_child(vis)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(0, 0.85, 0)
	light.light_color = Color("#4ef0ff")
	light.light_energy = 2.6
	light.omni_range = 14.0
	root.add_child(light)
	add_child(root)
	boomboxes.append({"node": root, "vis": vis, "light": light, "beat_cd": 0.0, "phase": randf() * TAU})
	_spawn_explosion_fx(root.position + Vector3.UP * 0.4, Color("#ff8cd8"), 3.2)

func launch_bumper_orb(origin: Vector3, dir: Vector3, _owner_id: int) -> void:
	_create_bumper_orb_body(origin, dir.normalized() * 19.5 + Vector3.UP * 3.5)

func _create_bumper_orb_body(pos: Vector3, vel: Vector3) -> void:
	var rb: RigidBody3D = RigidBody3D.new()
	rb.name = "BumperOrb_%d" % bumper_orbs.size()
	rb.position = pos
	rb.mass = 2.2
	rb.collision_layer = 8
	rb.collision_mask = 2 | 8 | 1
	var pm: PhysicsMaterial = PhysicsMaterial.new()
	pm.bounce = 0.92
	pm.friction = 0.15
	rb.physics_material_override = pm
	var cs: CollisionShape3D = CollisionShape3D.new()
	var sp: SphereShape3D = SphereShape3D.new()
	sp.radius = 0.36
	cs.shape = sp
	rb.add_child(cs)
	var vis: Node3D = BUMPER_ORB_GLB.instantiate() as Node3D
	vis.position.y = -0.34
	_pbr.bind_glb(vis, "frost", true)
	rb.add_child(vis)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color("#58eaff")
	light.light_energy = 1.2
	light.omni_range = 6.0
	rb.add_child(light)
	add_child(rb)
	rb.linear_velocity = vel
	bumper_orbs.append({"body": rb, "bump_cd": 0.0})

func drink_thermos(actor: SpacePlayer3D) -> void:
	if actor == null:
		return
	_spawn_explosion_fx(actor.position + Vector3.UP * 1.2, Color("#ffb65c"), 2.2)

# ------------------------------------------------------------------ 帧循环

func tick(delta: float) -> void:
	_clock += delta
	_tick_explosions(delta)
	_tick_boombox_visuals(delta)
	if not director.is_host:
		return
	_tick_geysers(delta)
	_tick_bounce_pads(delta)
	_tick_flares(delta)
	_tick_boomboxes(delta)
	_tick_bumper_orbs(delta)
	_tick_canisters(delta)
	_tick_drones(delta)
	_tick_heat_cores(delta)
	_tick_greenhouse_warmth(delta)

func _tick_greenhouse_warmth(delta: float) -> void:
	# 极地玻璃穹顶温室内部自带恒温暖气！
	for actor: Node3D in director.players.values():
		if actor is SpacePlayer3D and not actor.downed:
			var p: Vector3 = actor.position
			if p.distance_to(Vector3(-88.0, 0.0, -108.0)) < 8.5 or p.distance_to(Vector3(-115.0, 2.5, 85.0)) < 8.5:
				actor.warmth = minf(1.5, actor.warmth + delta * 0.35)

func _tick_bounce_pads(delta: float) -> void:
	for bp: Dictionary in bounce_pads:
		bp.cooldown = maxf(0.0, float(bp.cooldown) - delta)
		bp.squish = maxf(0.0, float(bp.squish) - delta * 3.5)
		var root: Node3D = bp.node as Node3D
		if root != null:
			var s: float = float(bp.squish)
			root.scale = Vector3(1.0 + s * 0.22, 1.0 - s * 0.32, 1.0 + s * 0.22)
		if float(bp.cooldown) > 0.0:
			continue
		var p: Vector3 = bp.pos
		for actor: Node3D in director.players.values():
			if actor is CharacterBody3D and not actor.downed:
				var flat_d: float = Vector2(actor.position.x - p.x, actor.position.z - p.z).length()
				if flat_d < 1.35 and absf(actor.position.y - p.y) < 1.6:
					(actor as CharacterBody3D).velocity.y = 15.8
					bp.cooldown = 0.45
					bp.squish = 1.0
					_spawn_explosion_fx(p + Vector3.UP * 0.5, Color("#45e6ff"), 3.2)
		if world.cart != null:
			var cd: float = Vector2(world.cart.position.x - p.x, world.cart.position.z - p.z).length()
			if cd < 2.2 and absf(world.cart.position.y - p.y) < 2.0:
				world.cart.velocity.y = 13.5
				bp.cooldown = 0.75
				bp.squish = 1.0
				_spawn_explosion_fx(p + Vector3.UP * 0.5, Color("#ff9842"), 4.2)
		for ob: Dictionary in bumper_orbs:
			var orb: RigidBody3D = ob.body as RigidBody3D
			if orb != null and orb.position.distance_to(p) < 1.4:
				orb.linear_velocity.y = 16.0
				bp.squish = 0.8

func _tick_flares(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for fl: Dictionary in flares:
		fl.life = float(fl.life) - delta
		var rb: RigidBody3D = fl.body as RigidBody3D
		var lt: OmniLight3D = fl.light as OmniLight3D
		if float(fl.life) <= 0.0 or rb == null:
			if is_instance_valid(rb):
				rb.queue_free()
			continue
		if lt != null:
			lt.light_energy = (3.8 + sin(_clock * 18.0) * 0.55) * clampf(float(fl.life) / 4.0, 0.0, 1.0)
		# 暖光回温 + 缓慢融化附近雪块
		for actor: Node3D in director.players.values():
			if actor is SpacePlayer3D and not actor.downed and actor.position.distance_to(rb.position) < 9.0:
				actor.warmth = minf(1.5, actor.warmth + delta * 0.25)
		if world.get("ice") != null:
			for chunk: Node3D in world.ice:
				if is_instance_valid(chunk) and chunk.position.distance_to(rb.position) < 3.6 and chunk.has_method("melt"):
					chunk.melt(delta * 0.14)
		keep.append(fl)
	flares = keep

func _tick_boombox_visuals(_delta: float) -> void:
	var colors: Array[Color] = [Color("#4ef0ff"), Color("#ff9a42"), Color("#ff6ec7"), Color("#6bff9c")]
	for bb: Dictionary in boomboxes:
		var vis: Node3D = bb.vis as Node3D
		var lt: OmniLight3D = bb.light as OmniLight3D
		var beat: float = absf(sin(_clock * 6.4 + float(bb.phase)))
		if vis != null:
			vis.scale = Vector3(1.18 + beat * 0.10, 1.18 - beat * 0.07, 1.18 + beat * 0.10)
		if lt != null:
			var ci: int = int(floor(_clock * 2.2 + float(bb.phase))) % colors.size()
			lt.light_color = colors[ci]
			lt.light_energy = 1.9 + beat * 1.4

func _tick_boomboxes(delta: float) -> void:
	for bb: Dictionary in boomboxes:
		var root: Node3D = bb.node as Node3D
		if root == null:
			continue
		var p: Vector3 = root.position
		for actor: Node3D in director.players.values():
			if actor is SpacePlayer3D and not actor.downed and actor.position.distance_to(p) < 12.5:
				actor.warmth = minf(1.5, actor.warmth + delta * 0.22)
		bb.beat_cd = float(bb.beat_cd) - delta
		if float(bb.beat_cd) <= 0.0:
			bb.beat_cd = 0.72
			# 让 10m 内的碰碰球、热核和掉落箱子跟着节拍轻跳蹦迪！
			for ob: Dictionary in bumper_orbs:
				var orb: RigidBody3D = ob.body as RigidBody3D
				if orb != null and orb.position.distance_to(p) < 10.5 and orb.linear_velocity.length() < 4.5:
					orb.apply_central_impulse(Vector3(randf_range(-1.2, 1.2), 4.6, randf_range(-1.2, 1.2)))
			for hc: RigidBody3D in heat_cores:
				if is_instance_valid(hc) and hc.position.distance_to(p) < 10.5:
					hc.apply_central_impulse(Vector3(0.0, 3.8, 0.0))

func _tick_bumper_orbs(delta: float) -> void:
	for ob: Dictionary in bumper_orbs:
		var rb: RigidBody3D = ob.body as RigidBody3D
		if rb == null:
			continue
		ob.bump_cd = maxf(0.0, float(ob.bump_cd) - delta)
		var spd: float = rb.linear_velocity.length()
		# 玩家跑近踢球：自动轻踢滚动，超有球类互动手感！
		for actor: Node3D in director.players.values():
			if actor is SpacePlayer3D and not actor.downed:
				var d: float = rb.position.distance_to(actor.position + Vector3.UP * 0.5)
				if d < 1.15 and float(ob.bump_cd) <= 0.0:
					if spd > 10.5:
						# 高速碰碰球趣味撞飞玩家！
						var kb: Vector3 = (actor.position - rb.position).normalized()
						actor.launch_velocity = Vector3(kb.x, 0.0, kb.z) * 7.5
						actor.launch_time = 0.38
						actor.velocity.y = maxf(actor.velocity.y, 4.2)
						ob.bump_cd = 0.55
						_spawn_explosion_fx(rb.position, Color("#58eaff"), 2.4)
					elif actor.velocity.length() > 1.2:
						var kick: Vector3 = (rb.position - actor.position).normalized()
						rb.apply_central_impulse(Vector3(kick.x, 0.25, kick.z) * 14.0)
						ob.bump_cd = 0.30
		if spd < 6.5:
			continue
		# 高速碰碰球一球撞爆霜巡哨兵无人机或引爆燃料罐！
		for d_entry: Dictionary in drones:
			if bool(d_entry.alive) and (d_entry.body as RigidBody3D).position.distance_to(rb.position) < 2.2:
				_destroy_drone(d_entry)
				rb.linear_velocity = -rb.linear_velocity * 0.75 + Vector3.UP * 4.0
		for c_entry: Dictionary in canisters:
			if bool(c_entry.alive) and (c_entry.body as RigidBody3D).position.distance_to(rb.position) < 1.6:
				_detonate(c_entry)

func _tick_geysers(delta: float) -> void:
	for g: Dictionary in geysers:
		g.cooldown = maxf(0.0, float(g.cooldown) - delta)
		var erupting: bool = sin(_clock * 0.95 + float(g.phase)) > -0.15
		var vent: CPUParticles3D = g.vent as CPUParticles3D
		if vent != null:
			vent.emitting = erupting
		if not erupting or float(g.cooldown) > 0.0:
			continue
		var gp: Vector3 = g.pos
		var power: float = float(g.power)
		for actor: Node3D in director.players.values():
			if actor is CharacterBody3D and not actor.downed:
				var flat_d: float = Vector2(actor.position.x - gp.x, actor.position.z - gp.z).length()
				if flat_d < 2.1 and absf(actor.position.y - gp.y) < 2.2:
					(actor as CharacterBody3D).velocity.y = power
					g.cooldown = 0.65
		if world.cart != null:
			var cd: float = Vector2(world.cart.position.x - gp.x, world.cart.position.z - gp.z).length()
			if cd < 2.8 and absf(world.cart.position.y - gp.y) < 2.4:
				world.cart.velocity.y = power * 0.92
				g.cooldown = 0.85

func _tick_canisters(delta: float) -> void:
	for c: Dictionary in canisters:
		var rb: RigidBody3D = c.body as RigidBody3D
		if rb == null:
			continue
		if not bool(c.alive):
			c.respawn = float(c.respawn) - delta
			if float(c.respawn) <= 0.0:
				c.alive = true
				c.armed = false
				c.heat = 0.0
				rb.visible = true
				rb.process_mode = Node.PROCESS_MODE_INHERIT
				rb.position = c.home
				rb.linear_velocity = Vector3.ZERO
				rb.angular_velocity = Vector3.ZERO
			continue
		var spd: float = rb.linear_velocity.length()
		if spd > 10.5:
			c.armed = true
		if bool(c.armed) and spd < 4.5:
			_detonate(c)
			continue
		if world.cart != null and absf(world.cart.speed) > 12.0 and rb.position.distance_to(world.cart.position) < 2.6:
			_detonate(c)

func heat_hit_at(point: Vector3, delta: float) -> void:
	for c: Dictionary in canisters:
		if not bool(c.alive):
			continue
		var rb: RigidBody3D = c.body as RigidBody3D
		if rb != null and rb.position.distance_to(point) < 2.8:
			c.heat = float(c.heat) + delta
			if float(c.heat) >= 0.45:
				_detonate(c)
	for d: Dictionary in drones:
		if not bool(d.alive):
			continue
		var rb: RigidBody3D = d.body as RigidBody3D
		if rb != null and rb.position.distance_to(point) < 3.4:
			d.hp = float(d.hp) - delta * 65.0
			if float(d.hp) <= 0.0:
				_destroy_drone(d)

func _detonate(c: Dictionary) -> void:
	var rb: RigidBody3D = c.body as RigidBody3D
	var center: Vector3 = rb.position
	c.alive = false
	c.respawn = 35.0
	rb.visible = false
	rb.process_mode = Node.PROCESS_MODE_DISABLED
	_spawn_explosion_fx(center, Color("#ff8a34"), 7.5)
	if world.get("ice") != null:
		for chunk: Node3D in world.ice:
			if is_instance_valid(chunk) and chunk.position.distance_to(center) < 8.5:
				if chunk.has_method("melt"):
					chunk.melt(1.2)
				else:
					chunk.set("amount", 1.0)
	for d: Dictionary in drones:
		if bool(d.alive) and (d.body as RigidBody3D).position.distance_to(center) < 9.5:
			_destroy_drone(d)
	for hc: RigidBody3D in heat_cores:
		if hc.position.distance_to(center) < 9.0:
			hc.apply_central_impulse((hc.position - center).normalized() * 14.0 + Vector3.UP * 6.0)
	for actor: Node3D in director.players.values():
		if actor is SpacePlayer3D and not actor.downed and actor.position.distance_to(center) < 7.0:
			var push_dir: Vector3 = (actor.position - center).normalized()
			actor.launch_velocity = push_dir * 9.0
			actor.launch_time = 0.55
			actor.velocity.y = maxf(actor.velocity.y, 5.5)

func _tick_drones(delta: float) -> void:
	for d: Dictionary in drones:
		var rb: RigidBody3D = d.body as RigidBody3D
		if rb == null:
			continue
		if not bool(d.alive):
			d.respawn = float(d.respawn) - delta
			if float(d.respawn) <= 0.0:
				d.alive = true
				d.hp = 100.0
				rb.visible = true
				rb.process_mode = Node.PROCESS_MODE_INHERIT
				rb.position = d.home
				rb.linear_velocity = Vector3.ZERO
			continue
		if world.cart != null and absf(world.cart.speed) > 9.5 and rb.position.distance_to(world.cart.position) < 3.4:
			_destroy_drone(d)
			continue
		if rb.linear_velocity.length() > 13.0:
			_destroy_drone(d)
			continue
		var target_pos: Vector3 = (d.home as Vector3) + Vector3(cos(_clock * 0.55 + float(d.phase)) * float(d.radius), sin(_clock * 1.4 + float(d.phase)) * 0.85, sin(_clock * 0.55 + float(d.phase)) * float(d.radius))
		# 优先被附近燃烧的极光信号弹吸引（战术诱饵！）
		var flare_lure: Node3D = null
		for fl: Dictionary in flares:
			var fb: RigidBody3D = fl.body as RigidBody3D
			if fb != null and fb.position.distance_to(rb.position) < 38.0:
				flare_lure = fb
				break
		if flare_lure != null:
			target_pos = flare_lure.position + Vector3.UP * 2.6
		else:
			var chase_player: SpacePlayer3D = null
			var best_dist: float = 22.0
			for actor: Node3D in director.players.values():
				if actor is SpacePlayer3D and not actor.downed:
					var dist: float = rb.position.distance_to(actor.position + Vector3.UP * 1.5)
					if dist < best_dist and (d.home as Vector3).distance_to(actor.position) < 42.0:
						best_dist = dist
						chase_player = actor as SpacePlayer3D
			if chase_player != null:
				target_pos = chase_player.position + Vector3.UP * 2.4
				d.attack_cd = maxf(0.0, float(d.attack_cd) - delta)
				if best_dist < 4.2 and float(d.attack_cd) <= 0.0:
					d.attack_cd = 2.6
					chase_player.warmth = maxf(0.0, chase_player.warmth - 0.18)
					var kb: Vector3 = (chase_player.position - rb.position).normalized()
					chase_player.launch_velocity = Vector3(kb.x, 0.0, kb.z) * 6.5
					chase_player.launch_time = 0.35
					chase_player.velocity.y = maxf(chase_player.velocity.y, 3.2)
		var to_target: Vector3 = target_pos - rb.position
		rb.apply_central_force(to_target.limit_length(10.0) * 14.0)
		var look_dir: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
		if look_dir.length() > 0.3:
			rb.rotation.y = lerp_angle(rb.rotation.y, atan2(-look_dir.x, -look_dir.z), clampf(delta * 4.0, 0.0, 1.0))

func _destroy_drone(d: Dictionary) -> void:
	var rb: RigidBody3D = d.body as RigidBody3D
	var center: Vector3 = rb.position
	d.alive = false
	d.respawn = 45.0
	rb.visible = false
	rb.process_mode = Node.PROCESS_MODE_DISABLED
	_spawn_explosion_fx(center, Color("#3ce0ff"), 6.2)
	for id: int in director.players.keys():
		director.tell(id, "霜巡哨兵已击毁！外围探索区安全度提升")

func _tick_heat_cores(delta: float) -> void:
	for core: RigidBody3D in heat_cores:
		if not is_instance_valid(core):
			continue
		for actor: Node3D in director.players.values():
			if actor is SpacePlayer3D and not actor.downed and actor.position.distance_to(core.position) < 9.5:
				actor.warmth = minf(1.5, actor.warmth + delta * 0.24)

func _spawn_explosion_fx(pos: Vector3, color: Color, max_r: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sp: SphereMesh = SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	mi.mesh = sp
	mi.position = pos
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = 5.5
	light.omni_range = max_r * 2.5
	add_child(light)
	explosions.append({"mesh": mi, "mat": mat, "light": light, "t": 0.0, "max_r": max_r})

func _tick_explosions(delta: float) -> void:
	var remain: Array[Dictionary] = []
	for fx: Dictionary in explosions:
		fx.t = float(fx.t) + delta * 2.4
		var t: float = float(fx.t)
		var mi: MeshInstance3D = fx.mesh as MeshInstance3D
		var light: OmniLight3D = fx.light as OmniLight3D
		if t >= 1.0:
			if is_instance_valid(mi): mi.queue_free()
			if is_instance_valid(light): light.queue_free()
			continue
		var s: float = lerpf(0.6, float(fx.max_r), sqrt(t))
		mi.scale = Vector3.ONE * s
		(fx.mat as StandardMaterial3D).albedo_color.a = clampf(1.0 - t, 0.0, 1.0)
		light.light_energy = 5.5 * (1.0 - t)
		remain.append(fx)
	explosions = remain
