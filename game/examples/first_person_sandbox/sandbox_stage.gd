extends LISDemoStage
## 示例 1 · 第一人称基础物理沙盒
##
## 玩家可以：走近箱子 → 身体推动 → 准星抓取 → 拖动重箱 → 放下轻箱
##           → 抛掷物体 → 观察摩擦、碰撞和惯性
##
## 场景内容全部程序化生成（没有手写节点路径），因此复制到任何工程都能跑。

func _ready() -> void:
	stage_title = "示例 1 · 第一人称基础物理沙盒"
	stage_help = """WASD 移动 · Shift 加速 · 空格跳
左键 抓取 / 松手 · 右键 松手 · X 抛掷
Q / E 旋转持有物 · R 复位

轻箱 6 kg / 中箱 18 kg / 重柜 130 kg
重柜拖得动但举不起来 —— 这是真实力上限。"""
	spawn_point = Vector3(0.0, 1.2, 7.0)
	stage_half = 14.0
	super()


func _build_scenery() -> void:
	# 四面矮墙，让人看得出场地边界（也提供推挤用的障碍）
	# 正面只留一半，免得挡住视线
	add_static_box("WallNorth", Vector3(24, 2.4, 0.5), Vector3(0, 1.2, -11), Vector3.ZERO,
		Color(0.24, 0.27, 0.31))
	add_static_box("WallSouth", Vector3(24, 2.4, 0.5), Vector3(0, 1.2, 12), Vector3.ZERO,
		Color(0.24, 0.27, 0.31))
	add_static_box("WallWest", Vector3(0.5, 2.4, 24), Vector3(-12, 1.2, 0), Vector3.ZERO,
		Color(0.24, 0.27, 0.31))
	add_static_box("WallEast", Vector3(0.5, 2.4, 24), Vector3(12, 1.2, 0), Vector3.ZERO,
		Color(0.24, 0.27, 0.31))
	# 地面色带：标出"轻 / 中 / 重"三个货区（贴地色块，不是漂浮文字）
	_add_floor_patch(Vector3(-3.2, 0.01, 0.0), Color(0.18, 0.34, 0.26), "轻货区")
	_add_floor_patch(Vector3(0.0, 0.01, 0.0), Color(0.34, 0.30, 0.16), "中货区")
	_add_floor_patch(Vector3(3.6, 0.01, 0.0), Color(0.36, 0.18, 0.16), "重货区")
	# 一面矮台，用来演示"推上去 / 掉下来"的碰撞与惯性
	add_static_box("LowPlatform", Vector3(4.0, 0.5, 2.2), Vector3(0, 0.25, -5.5), Vector3.ZERO,
		Color(0.28, 0.31, 0.34))
	# 斜杆：抛掷物可以真的打上去
	add_static_box("Ramp", Vector3(3.0, 0.16, 4.0), Vector3(-6.5, 0.6, -3.0),
		Vector3(-18, 0, 0), Color(0.30, 0.29, 0.26))


func _add_floor_patch(pos: Vector3, color: Color, label_text: String) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Patch_%s" % label_text
	var qm: PlaneMesh = PlaneMesh.new()
	qm.size = Vector2(2.6, 2.6)
	mi.mesh = qm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _build_content() -> void:
	# 轻箱 6 kg —— 单手轻松举起、抛得很远
	add_body("LightBox", Vector3(-3.2, 0.31, 0.0), Vector3(0.55, 0.55, 0.55), 6.0,
		Color(0.42, 0.72, 0.50),
		{"display_name": "轻木箱", "friction": 0.62})
	# 中箱 18 kg —— 提着走有点费劲
	add_body("MediumBox", Vector3(0.0, 0.31, 0.0), Vector3(0.62, 0.62, 0.62), 18.0,
		Color(0.82, 0.70, 0.32),
		{"display_name": "标准货箱", "friction": 0.72})
	# 重柜 130 kg —— 拖得动、举不动
	add_body("HeavyCabinet", Vector3(3.6, 0.66, 0.0), Vector3(0.9, 1.3, 0.7), 130.0,
		Color(0.62, 0.30, 0.26),
		{"display_name": "重机柜", "friction": 0.85, "liftable": false})
	# 一组小方块，用来观察堆叠与碰撞
	for i in range(4):
		add_body("Brick%d" % i, Vector3(-1.0 + float(i) * 0.5, 0.16 + float(i) * 0.32, -5.5),
			Vector3(0.42, 0.30, 0.42), 5.0,
			Color(0.50 + 0.1 * float(i), 0.56, 0.68),
			{"display_name": "积木%d" % (i + 1), "friction": 0.55, "handles": 0})
	# 圆滑的抛掷靶：一个薄柱（薄壁碰撞，容易观察弹飞）
	add_body("ThrowTarget", Vector3(6.0, 0.5, -6.0), Vector3(0.8, 1.0, 0.8), 9.0,
		Color(0.68, 0.42, 0.72),
		{"display_name": "抛掷靶", "friction": 0.5, "bounce": 0.15})
