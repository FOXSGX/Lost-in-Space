extends LISDemoStage
## 示例 3 · 第一人称多人搬运场（程序化输入代理）
##
## ⚠ 本示例用的是**程序化输入代理**，不是真人试玩。
##   它验证的是"多股力在物理世界里如何合成"，不能证明手感有趣。
##
## 玩家（第 1 人）可以用键盘操作；另外 1~3 名代理会自动协助抬箱，
## 用来观察：合力 / 独立抓握点 / 共同搬运 / 反向拉扯 / 一人松手 /
##           碰撞受阻 / 长箱穿门。
##
## 操作：F1 添加一名代理（最多到 4 人）· F2 移除一名代理
##       F3 让所有代理反向拉扯（观察力偶）· F4 让一名代理松手

const MAX_AGENTS := 3

var agents: Array[LISFirstPersonAdapter] = []
var crate: LISBody
var agent_roots: Array[Node3D] = []
var pulling_apart: bool = false

var _agent_hud: Label


func _ready() -> void:
	stage_title = "示例 3 · 第一人称多人搬运场（程序化代理）"
	stage_help = """F1 添加代理 · F2 移除代理
F3 反向拉扯（观察真实力偶）
F4 让一名代理松手（其他人继续抓住）
R 复位

主玩家：左键抓取 / 松手 · 右键松手 · X 抛掷
⚠ 这些是程序化输入代理，不是真人试玩。"""
	spawn_point = Vector3(0.0, 1.2, 9.0)
	stage_half = 16.0
	super()


func _build_scenery() -> void:
	# 两道门洞：0.90 m 窄门 与 2.20 m 宽门
	add_static_box("WallA", Vector3(6.0, 3.0, 0.4), Vector3(-6.0, 1.5, -4.0),
		Vector3.ZERO, Color(0.26, 0.29, 0.33))
	add_static_box("WallB", Vector3(6.0, 3.0, 0.4), Vector3(6.0, 1.5, -4.0),
		Vector3.ZERO, Color(0.26, 0.29, 0.33))
	add_static_box("LintelNarrow", Vector3(0.90, 0.8, 0.4), Vector3(-1.0, 2.6, -4.0),
		Vector3.ZERO, Color(0.22, 0.25, 0.28))
	add_static_box("LintelWide", Vector3(2.20, 0.8, 0.4), Vector3(3.0, 2.6, -4.0),
		Vector3.ZERO, Color(0.22, 0.25, 0.28))
	add_static_box("SideL", Vector3(0.5, 3.0, 24), Vector3(-12.0, 1.5, 0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("SideR", Vector3(0.5, 3.0, 24), Vector3(12.0, 1.5, 0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))


func _build_content() -> void:
	# 主搬运目标：长箱 70 kg —— 单人举不动（上限 42 kg），两人可以
	crate = add_body("CoopCrate", Vector3(0.0, 0.41, 3.0), Vector3(1.9, 0.7, 0.7), 70.0,
		Color(0.72, 0.64, 0.42), {"display_name": "长箱（70 kg）", "friction": 0.7,
		"rot_deg": Vector3(0, 90, 0)})
	# 附带的轻箱，单人就能搬
	add_body("SoloBox", Vector3(-6.0, 0.31, 4.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.48, 0.76, 0.60), {"display_name": "单人木箱 12 kg"})
	# HUD 行
	_agent_hud = Label.new()
	_agent_hud.name = "AgentHud"
	var cl: CanvasLayer = CanvasLayer.new()
	cl.name = "AgentLayer"
	cl.layer = 6
	add_child(cl)
	_agent_hud.position = Vector2(24, 90)
	_agent_hud.add_theme_font_size_override("font_size", 15)
	_agent_hud.add_theme_color_override("font_color", Color(0.86, 0.92, 0.72))
	cl.add_child(_agent_hud)


func _process(_delta: float) -> void:
	if _agent_hud == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("代理人数：%d / %d" % [agents.size(), MAX_AGENTS])
	if crate != null and is_instance_valid(crate):
		lines.append("长箱持有者：%d 人 · 高度 %.2f m" % [
			crate.holder_count(), crate.global_position.y])
	for i in range(agents.size()):
		var ad: LISFirstPersonAdapter = agents[i]
		if ad != null and is_instance_valid(ad):
			lines.append("  代理%d：%s" % [i + 1,
				"持有中" if ad.is_holding() else "空手"])
	lines.append("反向拉扯：%s" % ("开" if pulling_apart else "关"))
	if hud != null and is_instance_valid(hud):
		hud.extra_lines = lines
	_agent_hud.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F1:
				add_agent()
			KEY_F2:
				remove_agent()
			KEY_F3:
				pulling_apart = not pulling_apart
			KEY_F4:
				release_one_agent()


## 添加一名程序化第一人称代理，并让它抓住长箱。
func add_agent() -> void:
	if agents.size() >= MAX_AGENTS or crate == null or not is_instance_valid(crate):
		return
	var idx: int = agents.size() + 1
	var ang: float = TAU * float(idx) / 4.0
	var eye: Vector3 = crate.global_position + Vector3(cos(ang) * 2.6, 1.15, sin(ang) * 2.6)
	var root: Node3D = Node3D.new()
	root.name = "Agent%d" % idx
	add_child(root)
	root.global_position = eye
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = LISPhysics.LAYER_PLAYER
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.position = Vector3(0.0, -0.86, 0.0)
	root.add_child(body)
	var cam: Camera3D = Camera3D.new()
	cam.current = false
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(crate.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP)
	var ad: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad.read_input = false
	ad.player_id = 10 + idx
	root.add_child(ad)
	ad.body = root
	ad.camera = cam
	agent_roots.append(root)
	agents.append(ad)
	ad.grab(crate)


## 移除最后一名代理（它的抓握引用会被自动清理）。
func remove_agent() -> void:
	if agents.is_empty():
		return
	var ad: LISFirstPersonAdapter = agents.pop_back()
	var root: Node3D = agent_roots.pop_back()
	if root != null and is_instance_valid(root):
		root.queue_free()
	var _unused: LISFirstPersonAdapter = ad


## 让一名代理松手 —— 其他人继续抓住，用于观察团队举升上限下降。
func release_one_agent() -> void:
	if agents.is_empty():
		return
	agents[agents.size() - 1].release_held(false)


func _physics_process(_delta: float) -> void:
	if crate == null or not is_instance_valid(crate):
		return
	# 代理每帧把准星对着箱子，并根据"是否反向拉扯"选择站位
	for i in range(agents.size()):
		var ad: LISFirstPersonAdapter = agents[i]
		if ad == null or not is_instance_valid(ad) or not ad.is_holding():
			continue
		var root: Node3D = agent_roots[i]
		if root == null or not is_instance_valid(root):
			continue
		var ang: float = TAU * float(i + 1) / 4.0
		var radius: float = 2.6
		if pulling_apart:
			# 反向拉扯：各自朝自己的切线方向退开
			radius = 2.6 + fmod(Time.get_ticks_msec() * 0.001, 1.2)
		var eye: Vector3 = crate.global_position + Vector3(cos(ang) * radius, 1.15, sin(ang) * radius)
		root.global_position = eye - Vector3(0.0, 0.86, 0.0)
		if ad.camera != null:
			ad.camera.global_position = eye
			ad.camera.look_at(crate.global_position + Vector3(0.0, 0.25, 0.0), Vector3.UP)


func reset_stage() -> void:
	super()
	for ad: LISFirstPersonAdapter in agents:
		if ad != null and is_instance_valid(ad):
			ad.release_held(false)
