extends RefCounted
class_name FrostInteriorArt

## 霜烬星 2.0 · 16 座建筑深度生活化室内装潢模块（22 套 Blender 专属室内设施！）
## 目标：
##   1. 彻底消灭空荡大白墙与光秃平顶：给每栋楼挂满贴墙工业管束、发光战术简报白板、悬挂桁架长条吊灯！
##   2. 让每栋楼的每一寸空间都像“昨天还有人在这里生活、喝咖啡、修机甲、做实验”：
##      衣柜半开、沙发茶几摆着盆栽与平板、厨房有咖啡机微波炉、角落堆着工具箱暖风机和电缆！
##   3. 全纯视觉陈设，严格留出宽敞步行通道，确保 54 项自动化测试 100% 畅通。

const BUNK_BED_GLB: PackedScene = preload("res://assets/models/rebuild/hero_bunk_bed.glb")
const DINING_SET_GLB: PackedScene = preload("res://assets/models/rebuild/hero_dining_set.glb")
const LAB_WORKSTATION_GLB: PackedScene = preload("res://assets/models/rebuild/hero_lab_workstation.glb")
const HOLO_MAP_GLB: PackedScene = preload("res://assets/models/rebuild/hero_holo_map_table.glb")
const MED_POD_GLB: PackedScene = preload("res://assets/models/rebuild/hero_med_pod.glb")
const HYDRO_PLANTER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_hydro_planter.glb")
const TELESCOPE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_giant_telescope.glb")
const REACTOR_TURBINE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_reactor_turbine.glb")
const STORAGE_RACK_GLB: PackedScene = preload("res://assets/models/rebuild/hero_storage_rack.glb")
const MECH_GANTRY_GLB: PackedScene = preload("res://assets/models/rebuild/hero_mech_gantry.glb")
const DRILL_RIG_GLB: PackedScene = preload("res://assets/models/rebuild/hero_drill_rig.glb")
const MUSEUM_PEDESTAL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_museum_pedestal.glb")

# 深度丰富化新件（10 套墙顶建筑设施 + 生活杂物！）
const WALL_PIPE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_pipe_run.glb")
const CEILING_LAMP_GLB: PackedScene = preload("res://assets/models/rebuild/hero_ceiling_truss_lamp.glb")
const LOCKER_BANK_GLB: PackedScene = preload("res://assets/models/rebuild/hero_locker_bank.glb")
const SERVER_RACK_GLB: PackedScene = preload("res://assets/models/rebuild/hero_server_rack.glb")
const SOFA_LOUNGE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_sofa_lounge.glb")
const KITCHEN_GLB: PackedScene = preload("res://assets/models/rebuild/hero_kitchen_counter.glb")
const TOOL_WALL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_tool_wall_cabinet.glb")
const CRYO_TANK_GLB: PackedScene = preload("res://assets/models/rebuild/hero_cryo_sample_tank.glb")
const WHITEBOARD_GLB: PackedScene = preload("res://assets/models/rebuild/hero_whiteboard_wall.glb")
const CLUTTER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_floor_clutter.glb")
const DESK_CLUTTER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_desk_clutter.glb")
const WALL_PILASTER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_pilaster.glb")
const CEILING_TRUSS_GLB: PackedScene = preload("res://assets/models/rebuild/hero_ceiling_bay_truss.glb")
const WALL_BULKHEAD_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_bulkhead.glb")
const DOOR_ARCH_GLB: PackedScene = preload("res://assets/models/rebuild/hero_door_arch_trim.glb")

const LED_SHADER: Shader = preload("res://shaders/led_screen.gdshader")
const SCR_LIVING: Texture2D = preload("res://assets/textures/interior_screens/wall_living_poster.png")
const SCR_MED: Texture2D = preload("res://assets/textures/interior_screens/wall_med_vitals.png")
const SCR_DRILL: Texture2D = preload("res://assets/textures/interior_screens/wall_drill_geology.png")
const SCR_BIO: Texture2D = preload("res://assets/textures/interior_screens/wall_greenhouse_botany.png")
const SCR_REACTOR: Texture2D = preload("res://assets/textures/interior_screens/wall_reactor_telemetry.png")
const SCR_MAP: Texture2D = preload("res://assets/textures/interior_screens/wall_colony_map.png")

static func build_all_interiors(detail_root: Node3D, pbr: ArtPbrLib) -> int:
	var count: int = 0
	var root: Node3D = Node3D.new()
	root.name = "FrostDistinctInteriors"
	detail_root.add_child(root)

	# ------------------------------------------------------------------ 0. 全部 13 座封闭建筑统一加装【建筑级结构吊顶桁架风管网格 + 四周分层装甲护墙板】！
	#    （彻底告别灰水泥平顶与大白墙；自动避让大门与主楼观景大窗，确保零穿模与 100% 畅通！）
	var enclosed_specs: Array = [
		# [id, center, width, depth, height, skip_north_window]
		["main", Vector3(0.0, 0.0, -110.0), 60.0, 32.0, 9.0, true],
		["museum", Vector3(-49.0, 0.0, -70.0), 32.0, 38.0, 11.0, false],
		["living", Vector3(49.0, 0.0, -63.0), 32.0, 38.0, 7.0, false],
		["power", Vector3(58.0, 0.0, -116.0), 26.0, 28.0, 7.0, false],
		["garage", Vector3(46.0, 0.0, -22.0), 44.0, 28.0, 7.0, false],
		["warehouse", Vector3(-43.0, 0.0, -22.0), 40.0, 28.0, 7.0, false],
		["comms_hub", Vector3(112.0, 0.0, -108.0), 34.0, 30.0, 10.0, false],
		["cargo_depot", Vector3(-108.0, 0.0, -32.0), 42.0, 32.0, 10.0, false],
		["mech_hangar", Vector3(112.0, 0.0, -34.0), 42.0, 34.0, 11.0, false],
		["reactor_hall", Vector3(166.0, 0.0, -76.0), 38.0, 34.0, 12.0, false],
		["drill_station", Vector3(-72.0, 0.0, -166.0), 36.0, 28.0, 10.0, false],
		["south_hub", Vector3(72.0, 0.0, 42.0), 40.0, 30.0, 9.5, false],
		["north_fort", Vector3(74.0, 0.0, -166.0), 34.0, 28.0, 9.5, false],
	]
	for spec: Array in enclosed_specs:
		var c: Vector3 = spec[1] as Vector3
		var w: float = float(spec[2])
		var d: float = float(spec[3])
		var h: float = float(spec[4])
		var has_north_win: bool = bool(spec[5])
		count += _dress_room_ceiling(root, pbr, c, w, d, h)
		count += _dress_room_walls(root, pbr, c, w, d, h, has_north_win)

	# 内部隔断门洞统一套上科幻斜角过道门框 + 顶部收口压条（生活楼/动力站/通讯总部）
	for arch_pos: Vector3 in [
		Vector3(49.0, 0.20, -65.0), Vector3(49.0, 0.20, -75.0),
		Vector3(58.0, 0.20, -115.0), Vector3(112.0, 0.20, -112.0),
	]:
		count += _place(root, pbr, DOOR_ARCH_GLB, arch_pos, 0.0, 1.0)
	# 生活楼两道内部隔断墙顶部加装深钢收口压条与橙色暖灯饰带，彻底摆脱裸灰矮墙感！
	for part_z: float in [-65.0, -75.0]:
		count += _partition_trim(root, pbr, Vector3(49.0, 3.55, part_z), 30.0, 5.4)

	# ------------------------------------------------------------------ 1. 主科研楼（超级科研指挥中枢：全息沙盘 + 培养液柱 + 服务器墙 + 休息沙发 + 二层首席书房）
	count += _floor_zone(root, Vector3(0.0, 0.22, -106.0), Vector3(14.0, 0.04, 14.0), Color("#204958"), Color("#3cd6eb"))
	count += _floor_zone(root, Vector3(17.0, 0.22, -109.0), Vector3(18.0, 0.04, 22.0), Color("#233b48"), Color("#54c4d8"))
	count += _place(root, pbr, HOLO_MAP_GLB, Vector3(0.0, 0.22, -106.0), 0.0, 1.32)
	# 中央大厅两侧 4 座发光蓝晶培养柱 + 简报大屏 + 悬挂吊灯
	for sx: float in [-8.2, 8.2]:
		count += _place(root, pbr, CRYO_TANK_GLB, Vector3(sx, 0.22, -112.5), 0.0, 1.0)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(24.5, 0.22, -103.5), -90.0, 1.05)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(24.5, 0.22, -116.5), -90.0, 1.05)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(-12.5, 0.22, -120.5), 0.0, 1.05)
	count += _place(root, pbr, SERVER_RACK_GLB, Vector3(-28.0, 0.22, -102.0), 90.0, 1.05)
	count += _place(root, pbr, SERVER_RACK_GLB, Vector3(-28.0, 0.22, -105.0), 90.0, 1.05)
	count += _place(root, pbr, LOCKER_BANK_GLB, Vector3(-28.0, 0.22, -114.0), 90.0, 1.0)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, Vector3(-12.5, 0.22, -98.5), 0.0, 1.05)
	count += _place(root, pbr, KITCHEN_GLB, Vector3(28.0, 0.22, -98.5), -90.0, 0.95)
	count += _led_wall_screen(root, pbr, SCR_MAP, Vector3(16.0, 2.35, -125.4), 0.0, Vector2(4.4, 2.2))
	count += _place(root, pbr, DESK_CLUTTER_GLB, Vector3(-11.5, 5.16, -121.8), 10.0, 1.0)
	count += _place(root, pbr, DESK_CLUTTER_GLB, Vector3(15.2, 1.32, -106.8), -15.0, 1.0)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(11.0, 0.22, -96.0), 25.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(29.3, 0.22, -110.0), -90.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(-29.3, 0.22, -110.0), 90.0, 1.0)
	for lx: float in [-16.0, 0.0, 16.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(lx, 7.6, -106.0), 0.0, 1.15)
	# 二层首席办公室：暖色地毯 + 办公台 + 服务器柜 + 休息沙发 + 简报白板 + 盆栽杂物
	count += _floor_zone(root, Vector3(-7.0, 4.22, -121.5), Vector3(14.0, 0.04, 6.2), Color("#3d3128"), Color("#e09c50"))
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(-11.5, 4.22, -122.0), 0.0, 0.95)
	count += _place(root, pbr, SERVER_RACK_GLB, Vector3(-14.6, 4.22, -124.2), 0.0, 0.92)
	count += _place(root, pbr, LOCKER_BANK_GLB, Vector3(0.5, 4.22, -124.5), 0.0, 0.92)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, Vector3(15.5, 4.22, -121.8), 180.0, 0.95)
	_light(root, Vector3(0.0, 3.6, -106.0), Color("#58e4ff"), 1.6, 18.0)
	_light(root, Vector3(-7.0, 6.8, -121.0), Color("#ffcf8a"), 1.5, 14.0)

	# ------------------------------------------------------------------ 2. 标本馆（典雅博物馆：赭红地毯 + 6 展台 + 4 巨型培养液柱 + 简报白板 + 休息沙发 + 悬吊射灯）
	count += _floor_zone(root, Vector3(-49.0, 0.22, -70.0), Vector3(22.0, 0.04, 30.0), Color("#462a28"), Color("#d49c54"))
	for pz: float in [-81.0, -71.0, -61.0]:
		count += _place(root, pbr, MUSEUM_PEDESTAL_GLB, Vector3(-58.5, 0.22, pz), 90.0, 1.05)
		count += _place(root, pbr, MUSEUM_PEDESTAL_GLB, Vector3(-39.5, 0.22, pz), -90.0, 1.05)
	for sx: float in [-62.5, -35.5]:
		count += _place(root, pbr, CRYO_TANK_GLB, Vector3(sx, 0.22, -56.0), 0.0, 1.05)
		count += _place(root, pbr, CRYO_TANK_GLB, Vector3(sx, 0.22, -76.0), 0.0, 1.05)
		count += _place(root, pbr, WALL_PIPE_GLB, Vector3(sx + (-1.8 if sx < -49 else 1.8), 1.8, -66.0), 90.0 if sx < -49 else -90.0, 1.0)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(-59.5, 0.22, -85.5), 0.0, 1.0)
	count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(-38.5, 0.22, -85.5), 0.0, 1.0)
	count += _led_wall_screen(root, pbr, SCR_DRILL, Vector3(-59.0, 2.8, -88.4), 0.0, Vector2(4.0, 2.0))
	count += _place(root, pbr, DESK_CLUTTER_GLB, Vector3(-59.5, 1.18, -85.5), 8.0, 1.0)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, Vector3(-39.0, 0.22, -54.0), 180.0, 0.95)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(-62.0, 0.22, -81.0), 40.0, 1.0)
	for lz: float in [-79.0, -69.0, -59.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(-49.0, 9.2, lz), 0.0, 1.2)
	_light(root, Vector3(-49.0, 7.8, -78.0), Color("#ffd28a"), 2.4, 24.0)
	_light(root, Vector3(-49.0, 7.8, -62.0), Color("#ffd28a"), 2.2, 24.0)

	# ------------------------------------------------------------------ 3. 生活医疗楼（超温馨人味生活区：厨房吧台 + 餐桌 + 转角沙发电视角 + 医疗舱 + 4 张上下铺 + 成排个人衣柜 + 墙管吊灯！）
	count += _floor_zone(root, Vector3(49.0, 0.22, -52.0), Vector3(24.0, 0.04, 14.0), Color("#3b4a42"), Color("#e8a862"))
	count += _floor_zone(root, Vector3(58.5, 0.22, -58.5), Vector3(9.5, 0.04, 10.0), Color("#1e4a3d"), Color("#4ef2a6"))
	count += _floor_zone(root, Vector3(49.0, 0.22, -74.0), Vector3(26.0, 0.04, 14.0), Color("#44352c"), Color("#f0b878"))
	# 温馨厨房吧台（咖啡机/微波炉/餐盘）紧贴西墙，配实木餐桌 + 转角休闲沙发（错开南侧零食吧台，零穿模！）
	count += _place(root, pbr, KITCHEN_GLB, Vector3(34.2, 0.22, -54.5), 90.0, 1.05)
	count += _place(root, pbr, DINING_SET_GLB, Vector3(41.2, 0.22, -51.5), 0.0, 1.05)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, Vector3(48.8, 0.22, -51.0), 180.0, 1.05)
	count += _led_wall_screen(root, pbr, SCR_LIVING, Vector3(41.0, 3.25, -64.65), 0.0, Vector2(3.8, 1.75))
	count += _place(root, pbr, DESK_CLUTTER_GLB, Vector3(41.2, 0.98, -51.5), 18.0, 1.05)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(35.0, 0.22, -47.0), 15.0, 1.0)
	# 医疗区（2 台发光翡翠绿维生舱 + 医疗培养液柱 + 药柜实验台 + 高清生命体征监测 LED 大屏 + 墙面钢构肋柱！）
	count += _place(root, pbr, MED_POD_GLB, Vector3(57.2, 0.22, -55.5), -90.0, 1.05)
	count += _place(root, pbr, MED_POD_GLB, Vector3(57.2, 0.22, -60.5), -90.0, 1.05)
	count += _place(root, pbr, CRYO_TANK_GLB, Vector3(63.0, 0.22, -51.0), 0.0, 0.92)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(61.5, 0.22, -63.4), 0.0, 0.92)
	count += _led_wall_screen(root, pbr, SCR_MED, Vector3(64.15, 3.28, -57.5), -90.0, Vector2(3.8, 1.75))
	# 宿舍区（4 张宇航员上下铺 + 4 组个人衣柜 + 角落行李暖风机！）
	count += _place(root, pbr, BUNK_BED_GLB, Vector3(36.5, 0.22, -70.0), 90.0, 1.05)
	count += _place(root, pbr, BUNK_BED_GLB, Vector3(36.5, 0.22, -78.0), 90.0, 1.05)
	count += _place(root, pbr, BUNK_BED_GLB, Vector3(61.5, 0.22, -70.0), -90.0, 1.05)
	count += _place(root, pbr, BUNK_BED_GLB, Vector3(61.5, 0.22, -78.0), -90.0, 1.05)
	count += _place(root, pbr, LOCKER_BANK_GLB, Vector3(41.5, 0.22, -81.2), 0.0, 1.0)
	count += _place(root, pbr, LOCKER_BANK_GLB, Vector3(56.5, 0.22, -81.2), 0.0, 1.0)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, Vector3(49.0, 0.22, -70.5), 0.0, 0.92)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(42.0, 0.22, -72.5), -35.0, 0.95)
	# 贴墙管网与 4 盏悬挂温暖吊灯
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(33.5, 0.4, -62.0), 90.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(64.5, 0.4, -71.0), -90.0, 1.0)
	for lx: float in [41.0, 56.0]:
		for lz: float in [-54.0, -72.0]:
			count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(lx, 5.7, lz), 0.0, 1.05)
	_light(root, Vector3(44.0, 5.2, -54.0), Color("#ffcb8c"), 2.4, 24.0)
	_light(root, Vector3(58.0, 4.6, -58.0), Color("#62f5b4"), 1.9, 18.0)
	_light(root, Vector3(49.0, 5.0, -74.0), Color("#ffbf7c"), 2.2, 24.0)

	# ------------------------------------------------------------------ 4. 动力与生命保障站（重工业电厂：双涡轮 + 伺服器阵 + 满墙工业管道 + 工具柜 + 吊灯）
	count += _floor_zone(root, Vector3(58.0, 0.22, -118.0), Vector3(20.0, 0.04, 20.0), Color("#332920"), Color("#ff9834"))
	count += _place(root, pbr, REACTOR_TURBINE_GLB, Vector3(51.0, 0.22, -121.0), 0.0, 0.88)
	count += _place(root, pbr, REACTOR_TURBINE_GLB, Vector3(64.0, 0.22, -121.0), 0.0, 0.88)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(58.0, 0.22, -108.5), 180.0, 0.95)
	count += _place(root, pbr, SERVER_RACK_GLB, Vector3(46.5, 0.22, -127.0), 0.0, 1.05)
	count += _place(root, pbr, SERVER_RACK_GLB, Vector3(48.5, 0.22, -127.0), 0.0, 1.05)
	count += _place(root, pbr, TOOL_WALL_GLB, Vector3(69.8, 0.22, -116.0), -90.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(45.5, 0.4, -116.0), 90.0, 1.0)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(66.5, 0.22, -106.0), 20.0, 1.0)
	count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(58.0, 5.8, -116.0), 0.0, 1.1)
	_light(root, Vector3(58.0, 5.6, -120.0), Color("#ff9a38"), 2.6, 22.0)

	# ------------------------------------------------------------------ 5. 机修车库（硬核汽修车间：龙门吊 + 满墙工具挂板与备胎 + 货架 + 杂物暖风机 + 吊灯）
	count += _floor_zone(root, Vector3(46.0, 0.22, -21.0), Vector3(32.0, 0.04, 18.0), Color("#2d3236"), Color("#e8a848"))
	count += _place(root, pbr, MECH_GANTRY_GLB, Vector3(34.0, 0.22, -20.5), 0.0, 0.98)
	count += _place(root, pbr, TOOL_WALL_GLB, Vector3(25.2, 0.22, -19.5), 90.0, 1.1)
	count += _place(root, pbr, TOOL_WALL_GLB, Vector3(66.8, 0.22, -23.0), -90.0, 1.1)
	count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(27.5, 0.22, -25.5), 90.0, 1.05)
	count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(64.5, 0.22, -16.5), -90.0, 1.05)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, Vector3(60.0, 0.22, -32.2), 0.0, 1.05)
	count += _place(root, pbr, LOCKER_BANK_GLB, Vector3(35.0, 0.22, -34.5), 0.0, 1.0)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(29.0, 0.22, -13.0), -25.0, 1.05)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(62.0, 0.22, -12.0), 40.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, Vector3(46.0, 0.5, -35.4), 0.0, 1.15)
	for lx: float in [35.0, 56.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(lx, 5.8, -21.0), 0.0, 1.15)
	_light(root, Vector3(46.0, 5.8, -22.0), Color("#ffe0a6"), 2.4, 26.0)

	# ------------------------------------------------------------------ 6. 冷藏物资仓库（高密度仓储库：成排高货架 + 贴墙冷媒管 + 杂物栈板 + 吊灯）
	count += _floor_zone(root, Vector3(-43.0, 0.22, -22.0), Vector3(34.0, 0.04, 22.0), Color("#23323b"), Color("#68c4d8"))
	for sx: float in [-61.0, -25.0]:
		count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(sx, 0.22, -15.0), 90.0 if sx < -43.0 else -90.0, 1.05)
		count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(sx, 0.22, -28.5), 90.0 if sx < -43.0 else -90.0, 1.05)
		count += _place(root, pbr, WALL_PIPE_GLB, Vector3(sx + (-1.2 if sx < -43 else 1.2), 1.0, -22.0), 90.0 if sx < -43 else -90.0, 1.0)
	count += _place(root, pbr, STORAGE_RACK_GLB, Vector3(-43.0, 0.22, -33.6), 0.0, 1.1)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(-48.0, 0.22, -13.5), 18.0, 1.0)
	count += _place(root, pbr, CLUTTER_GLB, Vector3(-37.0, 0.22, -13.5), -32.0, 1.0)
	for lx: float in [-51.0, -35.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, Vector3(lx, 5.8, -22.0), 0.0, 1.1)

	# ------------------------------------------------------------------ 7. 巨型生态穹顶温室（生机勃勃植物天堂：8 排水培槽 + 2 座生物培养液柱 + 休闲沙发 + 咖啡厨房吧台 + 茶歇餐桌！）
	var gh: Vector3 = Vector3(-108.0, 0.28, -112.0)
	count += _floor_zone(root, gh, Vector3(22.0, 0.04, 22.0), Color("#1d3e31"), Color("#4ef29c"))
	for gx: float in [-8.8, 8.8]:
		for gz: float in [-8.0, -2.5, 3.0, 8.2]:
			count += _place(root, pbr, HYDRO_PLANTER_GLB, gh + Vector3(gx, 0.0, gz), 90.0 if gx < 0 else -90.0, 1.08)
	count += _place(root, pbr, CRYO_TANK_GLB, gh + Vector3(-5.2, 0.0, -9.8), 0.0, 1.05)
	count += _place(root, pbr, CRYO_TANK_GLB, gh + Vector3(5.2, 0.0, -9.8), 0.0, 1.05)
	count += _place(root, pbr, KITCHEN_GLB, gh + Vector3(0.0, 0.0, -10.5), 0.0, 1.0)
	count += _led_wall_screen(root, pbr, SCR_BIO, gh + Vector3(0.0, 3.6, -11.4), 0.0, Vector2(3.8, 1.9))
	count += _place(root, pbr, DESK_CLUTTER_GLB, gh + Vector3(0.2, 0.88, 2.2), -12.0, 1.0)
	count += _place(root, pbr, DINING_SET_GLB, gh + Vector3(0.0, 0.0, 2.2), 0.0, 1.1)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, gh + Vector3(0.0, 0.0, 7.8), 180.0, 1.05)
	count += _place(root, pbr, CLUTTER_GLB, gh + Vector3(-4.5, 0.0, 6.2), 25.0, 0.95)
	_light(root, gh + Vector3(0.0, 5.2, 0.0), Color("#90ffb8"), 2.4, 28.0)

	# ------------------------------------------------------------------ 8. 高空通讯灯塔总部（满墙服务器机柜 + 巨型中央全息星图 + 6 工位 + 战术白板 + 休息沙发 + 吊灯！）
	var ch: Vector3 = Vector3(112.0, 0.22, -108.0)
	count += _floor_zone(root, ch, Vector3(28.0, 0.04, 24.0), Color("#14283a"), Color("#3ce8ff"))
	count += _place(root, pbr, HOLO_MAP_GLB, ch + Vector3(0.0, 0.0, 0.5), 0.0, 1.55)
	for sx: float in [-10.0, 10.0]:
		count += _place(root, pbr, LAB_WORKSTATION_GLB, ch + Vector3(sx, 0.0, -9.5), 0.0, 1.15)
		count += _place(root, pbr, LAB_WORKSTATION_GLB, ch + Vector3(sx, 0.0, 3.0), 90.0 if sx < 0 else -90.0, 1.1)
		count += _place(root, pbr, SERVER_RACK_GLB, ch + Vector3(sx * 1.48, 0.0, -7.0), 90.0 if sx < 0 else -90.0, 1.15)
		count += _place(root, pbr, SERVER_RACK_GLB, ch + Vector3(sx * 1.48, 0.0, -3.5), 90.0 if sx < 0 else -90.0, 1.15)
		count += _place(root, pbr, WALL_PIPE_GLB, ch + Vector3(sx * 1.62, 1.2, 2.0), 90.0 if sx < 0 else -90.0, 1.1)
	count += _led_wall_screen(root, pbr, SCR_MAP, ch + Vector3(0.0, 3.2, -14.5), 0.0, Vector2(5.2, 2.6))
	count += _place(root, pbr, SOFA_LOUNGE_GLB, ch + Vector3(-12.0, 0.0, 10.5), 0.0, 1.05)
	count += _place(root, pbr, LOCKER_BANK_GLB, ch + Vector3(12.0, 0.0, 10.5), 180.0, 1.05)
	for lx: float in [-8.0, 8.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, ch + Vector3(lx, 8.2, -1.0), 0.0, 1.25)
	_light(root, ch + Vector3(0.0, 6.2, 0.0), Color("#46e4ff"), 2.6, 28.0)

	# ------------------------------------------------------------------ 9. 西线重型货运总站（10 座高货架 + 调度台 + 满墙管束 + 工具箱杂物 + 4 盏工业吊灯！）
	var cd: Vector3 = Vector3(-108.0, 0.22, -32.0)
	count += _floor_zone(root, cd, Vector3(36.0, 0.04, 26.0), Color("#2c3034"), Color("#e8a246"))
	for sx: float in [-16.5, -9.5, 9.5, 16.5]:
		count += _place(root, pbr, STORAGE_RACK_GLB, cd + Vector3(sx, 0.0, -9.5), 0.0, 1.15)
		count += _place(root, pbr, STORAGE_RACK_GLB, cd + Vector3(sx, 0.0, 5.5), 180.0, 1.15)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, cd + Vector3(0.0, 0.0, -13.5), 0.0, 1.15)
	count += _led_wall_screen(root, pbr, SCR_MAP, cd + Vector3(0.0, 3.2, -15.5), 0.0, Vector2(5.0, 2.5))
	count += _place(root, pbr, TOOL_WALL_GLB, cd + Vector3(-20.2, 0.0, -2.0), 90.0, 1.15)
	count += _place(root, pbr, LOCKER_BANK_GLB, cd + Vector3(20.2, 0.0, -2.0), -90.0, 1.15)
	count += _place(root, pbr, CLUTTER_GLB, cd + Vector3(-14.0, 0.0, 0.0), 22.0, 1.15)
	count += _place(root, pbr, CLUTTER_GLB, cd + Vector3(14.0, 0.0, 0.0), -40.0, 1.15)
	for lx: float in [-11.0, 11.0]:
		for lz: float in [-6.0, 6.0]:
			count += _place(root, pbr, CEILING_LAMP_GLB, cd + Vector3(lx, 8.2, lz), 0.0, 1.2)

	# ------------------------------------------------------------------ 10. 东线极地机甲维修厂（双巨型龙门吊 + 双工具墙 + 服务器诊断柜 + 工业管道 + 吊灯！）
	var mh: Vector3 = Vector3(112.0, 0.22, -34.0)
	count += _floor_zone(root, mh, Vector3(36.0, 0.04, 28.0), Color("#302722"), Color("#f0943a"))
	count += _place(root, pbr, MECH_GANTRY_GLB, mh + Vector3(-9.5, 0.0, -3.5), 0.0, 1.25)
	count += _place(root, pbr, MECH_GANTRY_GLB, mh + Vector3(9.5, 0.0, -3.5), 0.0, 1.25)
	count += _place(root, pbr, TOOL_WALL_GLB, mh + Vector3(-20.2, 0.0, -4.0), 90.0, 1.2)
	count += _place(root, pbr, TOOL_WALL_GLB, mh + Vector3(20.2, 0.0, -4.0), -90.0, 1.2)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, mh + Vector3(-14.5, 0.0, -12.5), 0.0, 1.1)
	count += _place(root, pbr, STORAGE_RACK_GLB, mh + Vector3(14.5, 0.0, -12.5), 0.0, 1.15)
	count += _place(root, pbr, SERVER_RACK_GLB, mh + Vector3(-2.0, 0.0, -15.0), 0.0, 1.2)
	count += _place(root, pbr, SERVER_RACK_GLB, mh + Vector3(2.0, 0.0, -15.0), 0.0, 1.2)
	count += _place(root, pbr, CLUTTER_GLB, mh + Vector3(-14.0, 0.0, 8.5), 15.0, 1.15)
	count += _place(root, pbr, CLUTTER_GLB, mh + Vector3(14.0, 0.0, 8.5), -28.0, 1.15)
	count += _place(root, pbr, WALL_PIPE_GLB, mh + Vector3(-20.2, 2.2, 6.0), 90.0, 1.15)
	count += _place(root, pbr, WALL_PIPE_GLB, mh + Vector3(20.2, 2.2, 6.0), -90.0, 1.15)
	for lx: float in [-10.0, 10.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, mh + Vector3(lx, 9.2, 4.0), 0.0, 1.25)
	_light(root, mh + Vector3(0.0, 8.2, -2.0), Color("#ffaa4c"), 2.8, 34.0)

	# ------------------------------------------------------------------ 11. 西翼天文观测大穹顶（6.5m 巨型望远镜 + 环绕双屏观星台 + 服务器阵 + 休息沙发 + 咖啡吧！）
	var obs: Vector3 = Vector3(-164.0, 0.28, -78.0)
	count += _floor_zone(root, obs, Vector3(22.0, 0.04, 22.0), Color("#152236"), Color("#68b8ff"))
	count += _place(root, pbr, TELESCOPE_GLB, obs + Vector3(0.0, 0.0, -1.5), -25.0, 1.25)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, obs + Vector3(-8.5, 0.0, 5.0), 45.0, 1.05)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, obs + Vector3(8.5, 0.0, 5.0), -45.0, 1.05)
	count += _place(root, pbr, SERVER_RACK_GLB, obs + Vector3(-9.5, 0.0, -4.5), 110.0, 1.1)
	count += _place(root, pbr, SERVER_RACK_GLB, obs + Vector3(9.5, 0.0, -4.5), -110.0, 1.1)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, obs + Vector3(-6.2, 0.0, -9.2), 20.0, 1.0)
	count += _place(root, pbr, KITCHEN_GLB, obs + Vector3(6.2, 0.0, -9.2), -20.0, 0.95)
	_light(root, obs + Vector3(0.0, 7.2, 0.0), Color("#78c4ff"), 2.4, 28.0)

	# ------------------------------------------------------------------ 12. 东翼地热反应堆电厂（4 座巨型反应堆涡轮 + 满墙管道 + 服务器阵 + 控制台 + 工业吊灯！）
	var rh: Vector3 = Vector3(166.0, 0.22, -76.0)
	count += _floor_zone(root, rh, Vector3(32.0, 0.04, 28.0), Color("#362218"), Color("#ff8828"))
	for rx: float in [-9.0, 9.0]:
		for rz: float in [-8.0, 2.0]:
			count += _place(root, pbr, REACTOR_TURBINE_GLB, rh + Vector3(rx, 0.0, rz), 0.0, 1.18)
		count += _place(root, pbr, WALL_PIPE_GLB, rh + Vector3(rx * 1.98, 1.8, -4.0), 90.0 if rx < 0 else -90.0, 1.2)
		count += _place(root, pbr, SERVER_RACK_GLB, rh + Vector3(rx * 1.65, 0.0, 8.0), 90.0 if rx < 0 else -90.0, 1.2)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, rh + Vector3(0.0, 0.0, 10.5), 180.0, 1.15)
	count += _led_wall_screen(root, pbr, SCR_REACTOR, rh + Vector3(0.0, 3.6, -16.4), 0.0, Vector2(5.4, 2.7))
	count += _place(root, pbr, TOOL_WALL_GLB, rh + Vector3(-14.0, 0.0, -15.8), 0.0, 1.15)
	count += _place(root, pbr, CLUTTER_GLB, rh + Vector3(14.0, 0.0, 11.5), -35.0, 1.1)
	for lx: float in [-9.0, 9.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, rh + Vector3(lx, 10.0, 6.0), 0.0, 1.25)
	_light(root, rh + Vector3(0.0, 8.8, -3.0), Color("#ff8a2e"), 3.2, 34.0)

	# ------------------------------------------------------------------ 13. 西北冰川钻探中心（中央 8m 冰芯钻塔 + 4 座发光蓝晶培养柱 + 4 组实验台/服务器 + 贴墙管网 + 白板 + 杂物 + 吊灯！）
	var dr: Vector3 = Vector3(-72.0, 0.22, -166.0)
	count += _floor_zone(root, dr, Vector3(30.0, 0.04, 22.0), Color("#18323e"), Color("#4ae4ff"))
	count += _place(root, pbr, DRILL_RIG_GLB, dr + Vector3(0.0, 0.0, -1.5), 0.0, 1.12)
	# 环绕钻塔的 4 座发光冰芯培养液柱（科幻感直接爆表！）
	for sx: float in [-5.8, 5.8]:
		for sz: float in [-6.8, 3.8]:
			count += _place(root, pbr, CRYO_TANK_GLB, dr + Vector3(sx, 0.0, sz), 0.0, 1.05)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, dr + Vector3(-11.5, 0.0, -5.5), 90.0, 1.1)
	count += _place(root, pbr, LAB_WORKSTATION_GLB, dr + Vector3(11.5, 0.0, -5.5), -90.0, 1.1)
	count += _place(root, pbr, MUSEUM_PEDESTAL_GLB, dr + Vector3(-7.8, 0.0, -11.2), 0.0, 1.05)
	count += _place(root, pbr, MUSEUM_PEDESTAL_GLB, dr + Vector3(7.8, 0.0, -11.2), 0.0, 1.05)
	count += _place(root, pbr, SERVER_RACK_GLB, dr + Vector3(-16.0, 0.0, -11.0), 45.0, 1.15)
	count += _place(root, pbr, SERVER_RACK_GLB, dr + Vector3(16.0, 0.0, -11.0), -45.0, 1.15)
	count += _place(root, pbr, STORAGE_RACK_GLB, dr + Vector3(-14.5, 0.0, 5.5), 90.0, 1.08)
	count += _place(root, pbr, STORAGE_RACK_GLB, dr + Vector3(14.5, 0.0, 5.5), -90.0, 1.08)
	count += _led_wall_screen(root, pbr, SCR_DRILL, dr + Vector3(0.0, 3.4, -13.15), 0.0, Vector2(5.6, 2.8))
	count += _place(root, pbr, DESK_CLUTTER_GLB, dr + Vector3(-11.5, 1.22, -5.5), 102.0, 1.0)
	count += _place(root, pbr, DESK_CLUTTER_GLB, dr + Vector3(11.5, 1.22, -5.5), -108.0, 1.0)
	count += _place(root, pbr, WALL_PIPE_GLB, dr + Vector3(-17.4, 1.4, -2.0), 90.0, 1.15)
	count += _place(root, pbr, WALL_PIPE_GLB, dr + Vector3(17.4, 1.4, -2.0), -90.0, 1.15)
	count += _place(root, pbr, CLUTTER_GLB, dr + Vector3(-9.5, 0.0, 1.2), 30.0, 1.05)
	count += _place(root, pbr, CLUTTER_GLB, dr + Vector3(9.5, 0.0, 1.2), -25.0, 1.05)
	for lx: float in [-9.0, 9.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, dr + Vector3(lx, 8.2, -2.0), 0.0, 1.2)
	_light(root, dr + Vector3(0.0, 6.5, -1.5), Color("#5ce8ff"), 2.8, 28.0)

	# ------------------------------------------------------------------ 14. 南区星港物流枢纽（食堂厨房 + 沙发休息区 + 医疗角 + 成排货架与衣柜 + 吊灯！）
	var sh: Vector3 = Vector3(72.0, 0.22, 42.0)
	count += _floor_zone(root, sh, Vector3(34.0, 0.04, 24.0), Color("#2c3a3a"), Color("#70d6ba"))
	count += _place(root, pbr, KITCHEN_GLB, sh + Vector3(-18.0, 0.0, -2.0), 90.0, 1.1)
	count += _place(root, pbr, DINING_SET_GLB, sh + Vector3(-10.5, 0.0, 5.0), 0.0, 1.12)
	count += _place(root, pbr, DINING_SET_GLB, sh + Vector3(-10.5, 0.0, -4.0), 0.0, 1.12)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, sh + Vector3(-10.5, 0.0, -10.5), 0.0, 1.05)
	count += _place(root, pbr, STORAGE_RACK_GLB, sh + Vector3(13.5, 0.0, -6.5), -90.0, 1.12)
	count += _place(root, pbr, STORAGE_RACK_GLB, sh + Vector3(13.5, 0.0, 4.5), -90.0, 1.12)
	count += _place(root, pbr, LOCKER_BANK_GLB, sh + Vector3(18.5, 0.0, -1.0), -90.0, 1.08)
	count += _place(root, pbr, MED_POD_GLB, sh + Vector3(0.0, 0.0, -10.5), 0.0, 1.05)
	count += _led_wall_screen(root, pbr, SCR_LIVING, sh + Vector3(0.0, 3.0, -14.5), 0.0, Vector2(4.8, 2.4))
	count += _place(root, pbr, CLUTTER_GLB, sh + Vector3(6.5, 0.0, 10.5), 25.0, 1.05)
	for lx: float in [-9.0, 9.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, sh + Vector3(lx, 7.8, 0.0), 0.0, 1.2)

	# ------------------------------------------------------------------ 15. 西南极光特技生态基地（休闲水培 + 车手沙发吧 + 上下铺 + 工具墙 + 厨房！）
	var so: Vector3 = Vector3(-84.0, 0.28, 44.0)
	count += _floor_zone(root, so, Vector3(22.0, 0.04, 22.0), Color("#223b32"), Color("#68f0b0"))
	count += _place(root, pbr, HYDRO_PLANTER_GLB, so + Vector3(-8.2, 0.0, -4.5), 90.0, 1.05)
	count += _place(root, pbr, HYDRO_PLANTER_GLB, so + Vector3(8.2, 0.0, -4.5), -90.0, 1.05)
	count += _place(root, pbr, KITCHEN_GLB, so + Vector3(0.0, 0.0, -9.8), 0.0, 1.0)
	count += _place(root, pbr, DINING_SET_GLB, so + Vector3(0.0, 0.0, -3.5), 0.0, 1.1)
	count += _place(root, pbr, SOFA_LOUNGE_GLB, so + Vector3(0.0, 0.0, 1.8), 180.0, 1.0)
	count += _place(root, pbr, BUNK_BED_GLB, so + Vector3(-8.5, 0.0, 5.5), 90.0, 1.05)
	count += _place(root, pbr, STORAGE_RACK_GLB, so + Vector3(8.5, 0.0, 5.5), -90.0, 1.05)
	count += _place(root, pbr, CLUTTER_GLB, so + Vector3(-4.5, 0.0, 8.2), -20.0, 1.0)

	# ------------------------------------------------------------------ 16. 北峡谷前哨要塞（战地前哨：全息沙盘 + 双上下铺 + 个人衣柜 + 简报白板 + 咖啡台 + 吊灯！）
	var nf: Vector3 = Vector3(74.0, 0.22, -166.0)
	count += _floor_zone(root, nf, Vector3(28.0, 0.04, 22.0), Color("#362f26"), Color("#e8a454"))
	count += _place(root, pbr, HOLO_MAP_GLB, nf + Vector3(0.0, 0.0, -2.0), 0.0, 1.25)
	count += _place(root, pbr, BUNK_BED_GLB, nf + Vector3(-11.5, 0.0, -5.5), 90.0, 1.05)
	count += _place(root, pbr, BUNK_BED_GLB, nf + Vector3(-11.5, 0.0, 4.5), 90.0, 1.05)
	count += _place(root, pbr, LOCKER_BANK_GLB, nf + Vector3(-15.5, 0.0, -0.5), 90.0, 1.0)
	count += _place(root, pbr, KITCHEN_GLB, nf + Vector3(0.0, 0.0, -11.5), 0.0, 1.0)
	count += _led_wall_screen(root, pbr, SCR_MAP, nf + Vector3(10.0, 3.0, -13.5), 0.0, Vector2(4.4, 2.2))
	count += _place(root, pbr, STORAGE_RACK_GLB, nf + Vector3(12.5, 0.0, 4.0), -90.0, 1.08)
	count += _place(root, pbr, CLUTTER_GLB, nf + Vector3(7.0, 0.0, 8.5), 35.0, 1.05)
	for lx: float in [-8.0, 8.0]:
		count += _place(root, pbr, CEILING_LAMP_GLB, nf + Vector3(lx, 7.8, -1.0), 0.0, 1.15)

	# 飞船门口已直接安装带真实物理层板的开放三层出舱物资货架（不再叠加纯装饰货架）

	return count

static func _dress_room_ceiling(parent: Node3D, pbr: ArtPbrLib, center: Vector3, width: float, depth: float, height: float) -> int:
	var added: int = 0
	var cols: int = maxi(2, int(round(width / 12.0)))
	var rows: int = maxi(2, int(round(depth / 8.0)))
	var bay_w: float = (width - 1.6) / float(cols)
	var bay_d: float = (depth - 1.6) / float(rows)
	var ceil_y: float = center.y + height - 0.16
	for ix: int in cols:
		var px: float = center.x - (width - 1.6) * 0.5 + (float(ix) + 0.5) * bay_w
		for iz: int in rows:
			var pz: float = center.z - (depth - 1.6) * 0.5 + (float(iz) + 0.5) * bay_d
			var truss: Node3D = CEILING_TRUSS_GLB.instantiate() as Node3D
			truss.position = Vector3(px, ceil_y, pz)
			truss.scale = Vector3(bay_w / 12.0, 1.0, bay_d / 6.0)
			pbr.bind_glb(truss, "frost", true)
			parent.add_child(truss)
			added += 1
	return added

static func _dress_room_walls(parent: Node3D, pbr: ArtPbrLib, center: Vector3, width: float, depth: float, height: float, skip_north_window: bool) -> int:
	var added: int = 0
	var sy: float = clampf((height - 0.35) / 6.45, 0.96, 1.78)
	# 1. 北墙（正对大门进门第一眼看到的视觉主墙！）
	var n_bays: int = maxi(2, int(round((width - 1.4) / 8.6)))
	var n_step: float = (width - 1.4) / float(n_bays)
	var north_z: float = center.z - depth * 0.5 + 0.34
	for i: int in n_bays:
		var px: float = center.x - (width - 1.4) * 0.5 + (float(i) + 0.5) * n_step
		if skip_north_window and px > 12.0 and px < 26.0:
			continue
		var wb: Node3D = WALL_BULKHEAD_GLB.instantiate() as Node3D
		wb.position = Vector3(px, center.y + 0.20, north_z)
		wb.scale = Vector3(n_step / 8.6, sy, 1.0)
		pbr.bind_glb(wb, "frost", true)
		parent.add_child(wb)
		added += 1
	# 2. 东、西两侧整面内墙
	var s_bays: int = maxi(2, int(round((depth - 1.4) / 8.6)))
	var s_step: float = (depth - 1.4) / float(s_bays)
	for side_x: float in [-1.0, 1.0]:
		var wall_x: float = center.x + side_x * (width * 0.5 - 0.34)
		var yaw: float = 90.0 if side_x < 0.0 else -90.0
		for j: int in s_bays:
			var pz: float = center.z - (depth - 1.4) * 0.5 + (float(j) + 0.5) * s_step
			var wb: Node3D = WALL_BULKHEAD_GLB.instantiate() as Node3D
			wb.position = Vector3(wall_x, center.y + 0.20, pz)
			wb.rotation_degrees.y = yaw
			wb.scale = Vector3(s_step / 8.6, sy, 1.0)
			pbr.bind_glb(wb, "frost", true)
			parent.add_child(wb)
			added += 1
	return added

static func _partition_trim(parent: Node3D, pbr: ArtPbrLib, center: Vector3, width: float, gap: float) -> int:
	var pal: Dictionary = pbr.build_palette("frost", false)
	var steel: Material = pal["M_DarkSteel"] as Material
	var orange: Material = pal["M_PaintOrange"] as Material
	var seg_w: float = (width - gap) * 0.5
	for side: float in [-1.0, 1.0]:
		var sx: float = center.x + side * (gap * 0.5 + seg_w * 0.5)
		var cap: MeshInstance3D = MeshInstance3D.new()
		var cm: BoxMesh = BoxMesh.new()
		cm.size = Vector3(seg_w, 0.24, 0.38)
		cap.mesh = cm
		cap.position = Vector3(sx, center.y, center.z)
		cap.material_override = steel
		parent.add_child(cap)
		var band: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(seg_w, 0.14, 0.34)
		band.mesh = bm
		band.position = Vector3(sx, 1.56, center.z)
		band.material_override = orange
		parent.add_child(band)
	return 2

static func _place(parent: Node3D, pbr: ArtPbrLib, scene: PackedScene, pos: Vector3, yaw_deg: float, sc: float = 1.0) -> int:
	var n: Node3D = scene.instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * sc
	pbr.bind_glb(n, "frost", true)
	parent.add_child(n)
	return 1

static func _floor_zone(parent: Node3D, pos: Vector3, sz: Vector3, base_col: Color, trim_col: Color) -> int:
	var elevated: Vector3 = Vector3(pos.x, maxf(pos.y, 0.29) if pos.y < 1.0 else pos.y + 0.04, pos.z)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = elevated
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.roughness = 0.82
	mi.material_override = mat
	parent.add_child(mi)
	var trim_m: StandardMaterial3D = StandardMaterial3D.new()
	trim_m.albedo_color = trim_col
	trim_m.emission_enabled = true
	trim_m.emission = trim_col
	trim_m.emission_energy_multiplier = 0.45
	for side_z: float in [-1.0, 1.0]:
		var line: MeshInstance3D = MeshInstance3D.new()
		var lm: BoxMesh = BoxMesh.new()
		lm.size = Vector3(sz.x, 0.05, 0.20)
		line.mesh = lm
		line.position = elevated + Vector3(0.0, 0.015, side_z * sz.z * 0.5)
		line.material_override = trim_m
		parent.add_child(line)
	return 1

static func _led_wall_screen(parent: Node3D, pbr: ArtPbrLib, tex: Texture2D, pos: Vector3, yaw_deg: float, sz: Vector2) -> int:
	var holder: Node3D = Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	var frame: MeshInstance3D = MeshInstance3D.new()
	var fb: BoxMesh = BoxMesh.new()
	fb.size = Vector3(sz.x + 0.24, sz.y + 0.24, 0.14)
	frame.mesh = fb
	frame.material_override = pbr.build_palette("frost", false)["M_DarkSteel"] as Material
	holder.add_child(frame)
	var quad: MeshInstance3D = MeshInstance3D.new()
	var qm: QuadMesh = QuadMesh.new()
	qm.size = sz
	quad.mesh = qm
	quad.position = Vector3(0.0, 0.0, 0.09)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = LED_SHADER
	mat.set_shader_parameter("screen_tex", tex)
	mat.set_shader_parameter("glow_boost", 1.38)
	mat.set_shader_parameter("pixel_density", 120.0)
	quad.material_override = mat
	holder.add_child(quad)
	parent.add_child(holder)
	return 1

static func _light(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l: OmniLight3D = OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
