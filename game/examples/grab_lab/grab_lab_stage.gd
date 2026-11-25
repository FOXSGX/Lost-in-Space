extends LISDemoStage
## 示例 2 · 第一人称抓握实验场
##
## 包含：轻物体 / 重物 / 长箱 / 薄墙 / 宽窄不同的门洞 / 受阻提示 /
##       抓握点显示 / 施力状态 HUD。
##
## 目的：让开发者一眼看懂"抓得动 / 抓不动 / 卡住"分别长什么样。

func _ready() -> void:
	stage_title = "示例 2 · 第一人称抓握实验场"
	stage_help = """左键 抓取 / 松手 · 右键 松手 · X 抛掷
Q / E 旋转持有物 · R 复位

从左到右：轻箱 5 kg → 中箱 20 kg → 长箱 45 kg → 重柜 180 kg
墙上三个门洞宽度：0.85 / 1.30 / 2.00 m
长箱横着过不去窄门 —— 按 Q/E 转成竖向才能过。"""
	spawn_point = Vector3(0.0, 1.2, 10.5)
	stage_half = 16.0
	super()


func _build_scenery() -> void:
	# 后墙 + 三个门洞（用四段墙体拼出三个开口）
	var wall_z: float = -9.0
	var wall_h: float = 3.0
	var openings: Array[float] = [0.85, 1.30, 2.00]
	# 门洞中心 x
	var centers: Array[float] = [-4.0, 0.0, 4.0]
	var cursor: float = -11.0
	for i in range(centers.size()):
		var left_edge: float = centers[i] - openings[i] * 0.5
		# 从左边界到洞口左沿
		if left_edge > cursor + 0.01:
			var w: float = left_edge - cursor
			add_static_box("WallSeg%d" % i, Vector3(w, wall_h, 0.4),
				Vector3(cursor + w * 0.5, wall_h * 0.5, wall_z), Vector3.ZERO,
				Color(0.26, 0.29, 0.33))
		# 门洞上沿
		add_static_box("Lintel%d" % i, Vector3(openings[i], wall_h - 2.2, 0.4),
			Vector3(centers[i], 2.2 + (wall_h - 2.2) * 0.5, wall_z), Vector3.ZERO,
			Color(0.22, 0.25, 0.28))
		cursor = centers[i] + openings[i] * 0.5
	if cursor < 11.0:
		add_static_box("WallSegEnd", Vector3(11.0 - cursor, wall_h, 0.4),
			Vector3(cursor + (11.0 - cursor) * 0.5, wall_h * 0.5, wall_z), Vector3.ZERO,
			Color(0.26, 0.29, 0.33))
	# 侧墙（挡住左右跑出去）
	add_static_box("SideL", Vector3(0.5, wall_h, 26), Vector3(-11.5, wall_h * 0.5, 0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("SideR", Vector3(0.5, wall_h, 26), Vector3(11.5, wall_h * 0.5, 0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))

	# 薄墙（0.12 m）放在场中间，用来测"手持物体撞墙受阻"
	add_static_box("ThinWall", Vector3(9.0, 2.4, 0.12), Vector3(0.0, 1.2, 2.0),
		Vector3.ZERO, Color(0.34, 0.30, 0.26))


func _build_content() -> void:
	# 轻箱 5 kg
	add_body("LightBox", Vector3(-6.0, 0.31, 6.0), Vector3(0.55, 0.55, 0.55), 5.0,
		Color(0.42, 0.78, 0.52), {"display_name": "轻木箱", "friction": 0.6})
	# 中箱 20 kg
	add_body("MidBox", Vector3(-2.0, 0.36, 6.0), Vector3(0.65, 0.65, 0.65), 20.0,
		Color(0.86, 0.72, 0.34), {"display_name": "标准货箱", "friction": 0.72})
	# 长箱 45 kg（1.80 × 0.5 × 0.5）—— 横着过不去 0.85 m 的门
	add_body("LongBox", Vector3(2.5, 0.31, 6.0), Vector3(1.80, 0.5, 0.5), 45.0,
		Color(0.55, 0.62, 0.86), {"display_name": "长箱", "friction": 0.65,
		"rot_deg": Vector3(0, 90, 0)})
	# 重柜 180 kg —— 只能拖
	add_body("HeavyCabinet", Vector3(7.0, 0.76, 6.0), Vector3(0.9, 1.5, 0.7), 180.0,
		Color(0.66, 0.30, 0.26), {"display_name": "重机柜", "friction": 0.88, "liftable": false})
	# 几个可用于测试"手持物体撞墙"的小块
	for i in range(3):
		add_body("Block%d" % i, Vector3(-8.0 + float(i) * 0.7, 0.21, 0.0),
			Vector3(0.4, 0.4, 0.4), 6.0, Color(0.60, 0.84, 0.90),
			{"display_name": "测试块%d" % (i + 1), "friction": 0.5, "handles": 0})

	# 地面上的抓握点参考标记：一条贴地的细线，指向"准星该瞄哪儿"
	for i in range(3):
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "LaneStrip%d" % i
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.06, 0.01, 8.0)
		mi.mesh = bm
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.55, 0.72)
		m.emission_enabled = true
		m.emission = Color(0.35, 0.55, 0.72)
		m.emission_energy_multiplier = 0.4
		mi.material_override = m
		mi.position = Vector3(-6.0 + float(i) * 4.5, 0.01, 3.0)
		add_child(mi)
