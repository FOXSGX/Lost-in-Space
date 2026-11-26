extends "res://previews/frost_first_playable/items.gd"

## 霜烬星 2.0 物品与创意交互玩具系统
## - 全部基础物品与工具均替换为 Blender 4.5 精细英雄 GLB（零裸方块）
## - 新增 5 件高趣味可交互小玩具：极地弹跳垫、极光信号弹、复古磁力音响、雪地碰碰球、热可可保温壶
## - 扩展物理边界适配 720×920m 极地盆地与全部 11 栋建筑群

const EXTRA: Array[String] = [
	"suction", "chips", "keepsake", "crate",
	"bounce_pad", "flare", "boombox", "bumper_orb", "thermos"
]

const EXTRA_ICONS: Dictionary = {
	"suction": preload("res://assets/items/visor_icons/suction.png"),
	"chips": preload("res://assets/items/visor_icons/chips.png"),
	"keepsake": preload("res://assets/items/visor_icons/keepsake.png"),
	"crate": preload("res://assets/items/visor_icons/crate.png"),
	"bounce_pad": preload("res://assets/items/visor_icons/bounce_pad.png"),
	"flare": preload("res://assets/items/visor_icons/flare.png"),
	"boombox": preload("res://assets/items/visor_icons/boombox.png"),
	"bumper_orb": preload("res://assets/items/visor_icons/bumper_orb.png"),
	"thermos": preload("res://assets/items/visor_icons/thermos.png"),
}

const HERO_ITEM_GLBS: Dictionary = {
	"heater": preload("res://assets/models/rebuild/hero_heat_lance.glb"),
	"cell": preload("res://assets/models/rebuild/hero_battery_pack.glb"),
	"fuel": preload("res://assets/models/rebuild/hero_battery_pack.glb"),
	"suction": preload("res://assets/models/rebuild/hero_suction_gun.glb"),
	"chips": preload("res://assets/models/rebuild/hero_snack_pack.glb"),
	"keepsake": preload("res://assets/models/rebuild/hero_keepsake_mug.glb"),
	"crate": preload("res://assets/models/rebuild/hero_cargo_crate.glb"),
	"bounce_pad": preload("res://assets/models/rebuild/hero_bounce_pad.glb"),
	"flare": preload("res://assets/models/rebuild/hero_flare_stick.glb"),
	"boombox": preload("res://assets/models/rebuild/hero_boombox.glb"),
	"bumper_orb": preload("res://assets/models/rebuild/hero_bumper_orb.glb"),
	"thermos": preload("res://assets/models/rebuild/hero_thermos.glb"),
}

const ITEM_SCALES: Dictionary = {
	"heater": 1.0,
	"cell": 0.90,
	"fuel": 1.0,
	"suction": 1.0,
	"chips": 1.15,
	"keepsake": 1.15,
	"crate": 0.72,
	"bounce_pad": 0.52,
	"flare": 1.0,
	"boombox": 0.95,
	"bumper_orb": 0.92,
	"thermos": 1.05,
}

const ITEM_BOX_SIZES: Dictionary = {
	"heater": Vector3(0.32, 0.38, 0.62),
	"cell": Vector3(0.34, 0.38, 0.26),
	"fuel": Vector3(0.34, 0.40, 0.26),
	"suction": Vector3(0.46, 0.48, 0.85),
	"chips": Vector3(0.34, 0.42, 0.16),
	"keepsake": Vector3(0.32, 0.30, 0.32),
	"crate": Vector3(0.70, 0.56, 0.60),
	"bounce_pad": Vector3(0.90, 0.32, 0.90),
	"flare": Vector3(0.18, 0.58, 0.18),
	"boombox": Vector3(0.66, 0.42, 0.28),
	"bumper_orb": Vector3(0.64, 0.64, 0.64),
	"thermos": Vector3(0.24, 0.48, 0.24),
}

var _pbr: ArtPbrLib

func _ready() -> void:
	super._ready()
	_pbr = ArtPbrLib.new()
	# 写实科幻头盔面罩全息投影物品格（透明深空玻璃 + 冰青发光边框）
	for i: int in _cells.size():
		_cells[i].add_theme_stylebox_override("panel", UIStyleKit.visor_slot(i == 0, false))
	for lb: Label in _slot_levels:
		lb.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
		lb.add_theme_color_override("font_color", UIStyleKit.VISOR_CYAN)

func add_item(id: int, kind: String, reference: int = -1, data: Dictionary = {}, activate: bool = false) -> bool:
	if kind not in EXTRA:
		return super.add_item(id, kind, reference, data, activate)
	var bag: Dictionary = ensure_bag(id)
	for i: int in CAPACITY:
		if bag.slots[i].is_empty():
			bag.slots[i] = data.duplicate(true)
			bag.slots[i].kind = kind
			if kind == "thermos" and not bag.slots[i].has("sips"):
				bag.slots[i]["sips"] = 3
			bag.slots[i].erase("position")
			bag.slots[i].erase("uid")
			if activate:
				bag.equipment_active = false
				bag.selected = i
			return true
	return false

func _physics_process(delta: float) -> void:
	if not controller.game_started:
		return
	if controller.is_host:
		_tick_jet_resources(delta)
	for entry: Dictionary in drops:
		var body: RigidBody3D = _prop_bodies.get(String(entry.uid)) as RigidBody3D
		if body == null:
			continue
		if controller.is_host:
			# 适配 1040×1160m 完整极地盆地与 16 座大型建筑群
			if body.position.y < -18.0 or absf(body.position.x) > 505.0 or body.position.z > 360.0 or body.position.z < -905.0:
				body.position = entry.get("safe_position", Vector3(0, 1, 0))
				body.linear_velocity = Vector3.ZERO
			entry.position = body.position
			entry.rotation = body.rotation
		else:
			body.position = body.position.lerp(Vector3(entry.position), 1.0 - exp(-22.0 * delta))
			body.rotation = entry.get("rotation", Vector3.ZERO)

func item_name(kind: String) -> String:
	return {
		"suction": "手持吸推器",
		"chips": "脆脆薯片",
		"keepsake": "科考纪念杯",
		"crate": "轻型样本箱",
		"bounce_pad": "极地弹跳垫",
		"flare": "极光信号弹",
		"boombox": "复古磁力音响",
		"bumper_orb": "雪地碰碰球",
		"thermos": "热可可保温壶",
	}.get(kind, super.item_name(kind))

func _use_selected(id: int) -> void:
	if ensure_bag(id).equipment_active:
		return
	var slot: Dictionary = selected(id)
	var kind: String = String(slot.get("kind", ""))
	var actor: SpacePlayer3D = controller.players.get(id) as SpacePlayer3D
	var sandbox: Node3D = controller.get("sandbox") as Node3D

	if kind == "chips":
		take_selected(id)
		controller.progress["snacks_eaten"] = int(controller.progress.get("snacks_eaten", 0)) + 1
		if actor != null:
			actor.warmth = minf(1.5, actor.warmth + 0.16)
			actor.set_meta("chips_buff", 20.0)
		controller.tell(id, "咔嚓！吃掉脆脆薯片，获得 20 秒【脆香冲刺】移速加成！")
		publish()
	elif kind == "keepsake":
		controller.tell(id, "科考纪念杯 · 可带回飞船收藏柜，按 E 收藏")
	elif kind == "bounce_pad":
		if actor != null and sandbox != null and sandbox.has_method("deploy_bounce_pad"):
			var fwd: Vector3 = -actor.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3(0, 0, -1)
			var drop_pos: Vector3 = actor.position + fwd * 2.2
			sandbox.deploy_bounce_pad(drop_pos, id)
			take_selected(id)
			controller.tell(id, "弹跳垫已部署！可跃上机甲厂与反应堆的 5m 高空天桥合闸！")
			publish()
	elif kind == "flare":
		if actor != null and sandbox != null and sandbox.has_method("throw_flare"):
			var aim_dir: Vector3 = -actor._camera.global_transform.basis.z if actor._camera != null else -actor.global_transform.basis.z
			sandbox.throw_flare(actor.position + Vector3.UP * 1.4 + aim_dir * 0.8, aim_dir, id)
			take_selected(id)
			controller.tell(id, "极光信号弹已投出！可融解高空热感锁、温室冰封导管，还能诱开无人机！")
			publish()
	elif kind == "boombox":
		if actor != null and sandbox != null and sandbox.has_method("deploy_boombox"):
			var fwd2: Vector3 = -actor.global_transform.basis.z
			fwd2.y = 0.0
			fwd2 = fwd2.normalized() if fwd2.length() > 0.05 else Vector3(0, 0, -1)
			sandbox.deploy_boombox(actor.position + fwd2 * 1.8, id)
			take_selected(id)
			controller.tell(id, "复古音响已开启！靠近声波结晶密柜可共振震碎解锁！")
			publish()
	elif kind == "bumper_orb":
		if actor != null and sandbox != null and sandbox.has_method("launch_bumper_orb"):
			var aim2: Vector3 = -actor._camera.global_transform.basis.z if actor._camera != null else -actor.global_transform.basis.z
			sandbox.launch_bumper_orb(actor.position + Vector3.UP * 1.3 + aim2 * 1.0, aim2, id)
			take_selected(id)
			controller.tell(id, "碰碰球发射！可击亮机甲厂高空动能靶心、撞毁无人机或引爆燃料罐！")
			publish()
	elif kind == "thermos":
		if actor != null:
			var sips: int = int(slot.get("sips", 3))
			actor.warmth = minf(1.5, actor.warmth + 0.55)
			actor.health = mini(5, actor.health + 1)
			actor.set_meta("thermos_buff", 45.0)
			if sandbox != null and sandbox.has_method("drink_thermos"):
				sandbox.drink_thermos(actor)
			sips -= 1
			if sips <= 0:
				take_selected(id)
				controller.tell(id, "吨吨吨！喝完最后一口热可可，获得 45 秒【极地暖流】抗寒+提速！")
			else:
				slot["sips"] = sips
				controller.tell(id, "喝了一口热可可！体温大涨 +1 血 +45 秒极地暖流（还剩 %d 口）" % sips)
			publish()
	elif kind not in ["suction", "crate"]:
		super._use_selected(id)

func _process(delta: float) -> void:
	super._process(delta)
	var id: int = multiplayer.get_unique_id()
	var bag: Dictionary = ensure_bag(id)
	var sel_idx: int = -1 if bool(bag.equipment_active) else int(bag.selected)
	for i: int in CAPACITY:
		var slot: Dictionary = bag.slots[i]
		var kind: String = String(slot.get("kind", ""))
		if kind in EXTRA:
			_icons[i].texture = EXTRA_ICONS[kind]
			if kind == "thermos":
				set_slot_gauge(i, float(slot.get("sips", 3)) / 3.0, UIStyleKit.VISOR_AMBER)
			if i == sel_idx:
				var tip: String = {
					"suction": "左键吸 / F推",
					"chips": "左键吃",
					"keepsake": "可收藏",
					"crate": "可搬运",
					"bounce_pad": "左键放",
					"flare": "左键扔",
					"boombox": "左键开",
					"bumper_orb": "左键射",
					"thermos": "左键喝",
				}.get(kind, "")
				_slot_levels[i].text = tip
				_slot_levels[i].visible = not tip.is_empty()
			else:
				_slot_levels[i].text = ""
				_slot_levels[i].visible = false

func _refresh_world() -> void:
	super._refresh_world()
	for entry: Dictionary in drops:
		var body: RigidBody3D = _prop_bodies.get(String(entry.uid)) as RigidBody3D
		if body == null:
			continue
		var modified: bool = false
		if entry.kind in EXTRA and not body.has_meta("station_model"):
			decorate(body, entry.kind)
			modified = true
		elif entry.kind in ["heater", "cell", "fuel"] and not body.has_meta("sized_collider"):
			body.set_meta("sized_collider", true)
			var col: CollisionShape3D = body.get_child(0) as CollisionShape3D
			if col != null and col.shape is BoxShape3D and ITEM_BOX_SIZES.has(entry.kind):
				(col.shape as BoxShape3D).size = ITEM_BOX_SIZES[entry.kind] as Vector3
			modified = true
		if modified and bool(entry.get("placed", false)) and controller.is_host:
			body.position = Vector3(entry.position)
			body.rotation = Vector3(0.0, float(entry.get("yaw", 0.0)), 0.0)
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true
	for id: int in _held:
		var model: Node3D = _held[id].get("node") as Node3D
		var kind: String = selected(id).get("kind", "")
		if model != null and kind in EXTRA and not model.has_meta("station_model"):
			decorate(model, kind)

# 覆盖父类粗方块热风机与电池外观，全部替换为 Blender 英雄 GLB
func add_heater_model(parent: Node3D) -> void:
	_mount_hero_glb(parent, "heater")

func add_supply_model(parent: Node3D, kind: String) -> void:
	_mount_hero_glb(parent, kind)

func decorate(parent: Node3D, kind: String) -> void:
	parent.set_meta("station_model", true)
	if parent is RigidBody3D:
		var collider: CollisionShape3D = parent.get_child(0) as CollisionShape3D
		if collider != null and collider.shape is BoxShape3D and ITEM_BOX_SIZES.has(kind):
			(collider.shape as BoxShape3D).size = ITEM_BOX_SIZES[kind] as Vector3
	_mount_hero_glb(parent, kind)

func _mount_hero_glb(parent: Node3D, kind: String) -> void:
	for child: Node in parent.get_children():
		if child is Node3D and not (child is CollisionShape3D):
			child.visible = false
	var scene: PackedScene = HERO_ITEM_GLBS.get(kind) as PackedScene
	if scene == null:
		return
	var vis: Node3D = scene.instantiate() as Node3D
	vis.name = "HeroItemVis_" + kind
	var sc: float = float(ITEM_SCALES.get(kind, 1.0))
	vis.scale = Vector3.ONE * sc
	# 让刚体中心与模型底部精确贴合桌面（道具 GLB 底部在 y=0，刚体碰撞体居中）
	var box_sz: Vector3 = ITEM_BOX_SIZES.get(kind, Vector3(0.4, 0.4, 0.4)) as Vector3
	if parent is RigidBody3D:
		vis.position.y = -box_sz.y * 0.50
	if _pbr == null:
		_pbr = ArtPbrLib.new()
	_pbr.bind_glb(vis, "frost", true)
	for m: Node in vis.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(vis)
