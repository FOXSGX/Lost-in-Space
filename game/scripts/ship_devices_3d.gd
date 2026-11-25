extends Node3D
class_name ShipDevices3D

## 归航号主舱 2.0 核心交互设施（全 Blender 英雄级 GLB + 零弹窗直操 + 零悬浮文字）
## - 2 座集成图形终端：星图与航志台（hero_star_table 交互锚点）、军械与工坊一体台（hero_workshop_bench）
## - 4 处一键实体直操站：舰体维修总闸（hero_lever_console）、生命与充氧站（hero_refill_pod）、物资快捷存回（hero_lever_console）、气闸出舱拉杆（hero_lever_console）
## - 4 个实体驾驶席（hero_pilot_pod）

const WORKSHOP_GLB: PackedScene = preload("res://assets/models/rebuild/hero_workshop_bench.glb")
const LEVER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_lever_console.glb")
const REFILL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_refill_pod.glb")
const PILOT_X: Array[float] = [-4.8, -1.6, 1.6, 4.8]
const DIRECT_KINDS: Array[String] = ["pilot", "repair", "refill", "store", "surface"]
const WORKSHOP_KINDS: Array[String] = ["craft", "gear", "toy", "skin"]

var devices: Array = []
var screens: Dictionary = {}
var lever_handles: Dictionary = {}
var status_lamps: Dictionary = {}
var session: ShipSession3D
var _pbr: ArtPbrLib

static func catalog() -> Array:
	var entries: Array = []
	for index: int in 4:
		entries.append({"id": "pilot_%d" % index, "kind": "pilot", "item": str(index), "position": Vector3(PILOT_X[index], 0.61, -13.8), "title": "驾驶 %02d" % (index + 1), "existing": true, "radius": 2.35})
	# 核心环线 2 座集成图形终端
	entries.append({"id": "routes", "kind": "route", "item": "", "position": Vector3(0.0, 0.0, 1.75), "title": "星图与航志", "radius": 2.35, "existing": true})
	entries.append({"id": "workshop", "kind": "workshop", "item": "", "position": Vector3(4.8, 0.0, 2.2), "yaw": -PI / 2.0, "title": "工坊与军械台", "radius": 2.25})
	# 核心环线 3 处实体直操站（按 E 立即执行，不弹窗口）
	entries.append({"id": "repair", "kind": "repair", "item": "", "position": Vector3(4.8, 0.0, -2.5), "yaw": -PI / 2.0, "title": "舰体维修总闸", "radius": 2.25, "direct": true})
	entries.append({"id": "refill", "kind": "refill", "item": "", "position": Vector3(-4.8, 0.0, 2.2), "yaw": PI / 2.0, "title": "生命与充氧站", "radius": 2.25, "direct": true})
	entries.append({"id": "store", "kind": "store", "item": "", "position": Vector3(-4.8, 0.0, -2.5), "yaw": PI / 2.0, "title": "物资快捷存回", "radius": 2.25, "direct": true})
	return entries

static func surface_device() -> Dictionary:
	return {"id": "surface", "kind": "surface", "item": "", "position": Vector3(2.2, 0.0, 14.0), "yaw": PI, "title": "星球出舱气闸拉杆", "radius": 2.35, "direct": true}

static func options_for(device: Dictionary, voyage: CampaignNavigation = null) -> Array:
	var kind: String = String(device.get("kind", ""))
	if kind == "workshop":
		var combined: Array = []
		for sub: String in WORKSHOP_KINDS:
			combined.append_array(_options_for_kind(sub, voyage))
		return combined
	return _options_for_kind(kind, voyage)

static func _options_for_kind(kind: String, voyage: CampaignNavigation = null) -> Array:
	var result: Array = []
	var items: Array = []
	match kind:
		"route": items = ["demo", "electromagnetic", "ruin", "earth"] if voyage != null and voyage.enabled else ["demo", "electromagnetic", "ruin"]
		"craft": items = ["medical", "oxygen", "parts"]
		"gear": items = ShipSession3D.GEAR_ITEMS
		"toy": items = ShipSession3D.GOOFY_ITEMS
		"skin":
			for skin: Dictionary in Main3D.SKIN_CATALOG:
				result.append({"id": "skin_" + String(skin.id), "kind": kind, "item": skin.id, "title": String(skin.name).split(" · ")[0]})
			return result
		_: return []
	for value: String in items:
		var title: String = String({"demo": "霜烬星", "electromagnetic": "共振星", "ruin": "腐墟星", "earth": "地球"}.get(value, ShipSession3D.ITEM_NAMES.get(value, ShipSession3D.GEAR_NAMES.get(value, CrewItems3D.NAMES.get(value, value)))))
		result.append({"id": kind + "_" + value, "kind": kind, "item": value, "title": title})
	return result

static func entry_for(id: String) -> Dictionary:
	if id == "surface":
		return surface_device()
	var mapped: String = id
	if id in ["craft", "gear", "toy", "skin"]:
		mapped = "workshop"
	elif id == "mission":
		mapped = "routes"
	for device: Dictionary in catalog():
		if device.id == mapped:
			return device
	return {}

static func point_for(id: String) -> Vector3:
	if id == "surface":
		return surface_device().position
	var mapped: String = id
	if id in ["craft", "gear", "toy", "skin"]:
		mapped = "workshop"
	elif id == "mission":
		mapped = "routes"
	for device: Dictionary in catalog():
		if device.id == mapped:
			return device.position
		for option: Dictionary in options_for(device):
			if option.id == id:
				return device.position
	return Vector3.INF

func _ready() -> void:
	session = get_parent().get_parent() as ShipSession3D
	_pbr = ArtPbrLib.new()
	devices = catalog()
	if session.campaign.enabled:
		devices.append(surface_device())
	for device: Dictionary in devices:
		_build(device)

func nearby(peer_id: int) -> Dictionary:
	var player: SpacePlayer3D = session.controller.players.get(peer_id) as SpacePlayer3D
	if player == null:
		return {}
	var best: Dictionary = {}
	var distance: float = INF
	for device: Dictionary in devices:
		var next_distance: float = session.controller._flat_distance(player.position, device.position)
		if next_distance < distance and session.controller._items.can_reach(player, device.position, float(device.get("radius", 2.1))):
			distance = next_distance
			best = device
	return best

func hint(peer_id: int, device: Dictionary) -> String:
	var kind: String = String(device.kind)
	match kind:
		"pilot":
			var owner: int = int(session.station_owners.get(int(device.item), 0))
			if owner == peer_id:
				return "E 取消就位" if session.launch_remaining < 0 else "出发 %d · E 取消" % ceili(session.launch_remaining)
			return "已占用" if owner != 0 else "E 就位"
		"repair":
			if session.hull >= 100:
				return "舰体完好（100%）"
			return "E 拉闸维修（舰体 %d%% · 零件 ×%d）" % [session.hull, int(session.stock.parts)]
		"refill":
			return "E 补满生命、氧气与随身气瓶"
		"store":
			var held: Dictionary = session.controller._items.selected(peer_id)
			if held.is_empty():
				return "手持补给/道具按 E 快捷存回"
			return "E 存回 · " + session.controller._items.item_name(String(held.get("kind", "")))
		"surface":
			if session.campaign.enabled and session.campaign.grounded and session.campaign.location == "demo" and not session.campaign.home_reached:
				return "E 拉动气闸 · 出舱探索霜烬星"
			return "当前位于航行轨道 · 请前往星图台选星"
	return "E 打开 · " + String(device.title)

func pulse_lever(device_id: String) -> void:
	if lever_handles.has(device_id):
		var handle: Node3D = lever_handles[device_id] as Node3D
		if handle != null:
			var tw: Tween = create_tween()
			tw.tween_property(handle, "rotation_degrees:x", -48.0, 0.14).set_trans(Tween.TRANS_BACK)
			tw.tween_property(handle, "rotation_degrees:x", 24.0, 0.28).set_trans(Tween.TRANS_SINE)
	if status_lamps.has(device_id):
		PhysicalLinkKit.set_lamp_state(status_lamps[device_id], "active")

func _process(_delta: float) -> void:
	if session == null:
		return
	for device: Dictionary in devices:
		if device.kind != "pilot":
			continue
		var owner: int = int(session.station_owners.get(int(device.item), 0))
		if status_lamps.has(device.id):
			PhysicalLinkKit.set_lamp_state(status_lamps[device.id], "active" if owner != 0 else "ready")

func _build(device: Dictionary) -> void:
	var terminal: Node3D = Node3D.new()
	terminal.name = String(device.id)
	terminal.position = device.position
	terminal.rotation.y = float(device.get("yaw", 0.0))
	add_child(terminal)

	# 驾驶席与中央星图台由 ShipHubArt 装配全套 Blender 英雄 GLB，此处只挂实体状态灯（零悬浮 Label3D）
	if String(device.kind) == "pilot":
		status_lamps[device.id] = PhysicalLinkKit.build_status_lamp(terminal, Vector3(0.0, 1.38, -0.58))
		return
	if String(device.kind) == "route":
		status_lamps[device.id] = PhysicalLinkKit.build_status_lamp(terminal, Vector3(0.0, 1.10, -0.95))
		PhysicalLinkKit.set_lamp_state(status_lamps[device.id], "active")
		return

	# 所有独立功能台置于交互锚点后方 0.62m，保持锚点站立区无遮挡
	var body_offset: Vector3 = Vector3(0.0, 0.0, -0.62)
	var scene: PackedScene = LEVER_GLB
	var collider_sz: Vector3 = Vector3(0.95, 1.15, 0.68)
	var icon_pos: Vector3 = body_offset + Vector3(0.0, 0.56, 0.34)
	if String(device.kind) == "workshop":
		scene = WORKSHOP_GLB
		body_offset = Vector3(0.0, 0.0, -0.78)
		collider_sz = Vector3(2.3, 1.15, 0.96)
		icon_pos = body_offset + Vector3(0.0, 1.56, -0.35)
	elif String(device.kind) == "refill":
		scene = REFILL_GLB
		collider_sz = Vector3(1.1, 2.0, 1.1)
		icon_pos = body_offset + Vector3(0.0, 1.12, 0.36)

	var model: Node3D = scene.instantiate() as Node3D
	model.position = body_offset
	_pbr.bind_glb(model, "ship", true)
	terminal.add_child(model)
	ArtAtmosphereKit.build_ground_skirt(terminal, body_offset, 1.25 if String(device.kind) == "workshop" else 0.88, 0.44)
	_add_box_collider(terminal, body_offset + Vector3(0.0, collider_sz.y * 0.5, 0.0), collider_sz)

	# 实体可动工业橙拉杆（安装于 hero_lever_console 顶部闸槽）
	if scene == LEVER_GLB:
		var pivot: Node3D = Node3D.new()
		pivot.position = body_offset + Vector3(0.18, 1.12, 0.0)
		pivot.rotation_degrees.x = 24.0
		terminal.add_child(pivot)
		var bar_mat: Material = _pbr.build_palette("ship", false)["M_BareSteel"] as Material
		var grip_mat: Material = _pbr.build_palette("ship", false)["M_PaintOrange"] as Material
		_add_cyl(pivot, Vector3(0.0, 0.18, 0.0), 0.022, 0.36, bar_mat)
		_add_box(pivot, Vector3(0.0, 0.38, 0.0), Vector3(0.24, 0.065, 0.065), grip_mat)
		lever_handles[String(device.id)] = pivot
		status_lamps[device.id] = PhysicalLinkKit.build_status_lamp(terminal, body_offset + Vector3(-0.34, 1.24, -0.14))
		PhysicalLinkKit.set_lamp_state(status_lamps[device.id], "ready")

	# 贴壳 <= 2cm 纯图铭牌（绝对零悬浮文字）
	var display: MeshInstance3D = MeshInstance3D.new()
	var face: QuadMesh = QuadMesh.new()
	face.size = Vector2(0.38, 0.38)
	display.mesh = face
	var picture: StandardMaterial3D = StandardMaterial3D.new()
	picture.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	picture.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var icon_kind: String = "craft" if device.kind == "workshop" else ("route" if device.kind == "surface" else String(device.kind))
	picture.albedo_texture = load("res://assets/ship-hub/computer-icons/" + icon_kind + ".svg") as Texture2D
	display.material_override = picture
	display.position = icon_pos
	terminal.add_child(display)
	screens[device.id] = display

func _add_cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _add_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _add_box_collider(parent: Node3D, pos: Vector3, sz: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = pos
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = sz
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
