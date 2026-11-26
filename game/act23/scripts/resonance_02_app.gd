extends "res://act23/scripts/playtest_app.gd"

var moving_mode: bool = false

# Smoke-test hook for packaged builds: `--autostart` skips the menu and goes
# straight to the cart slice, so an exported EXE can be verified end to end
# without driving the mouse. It has no effect on a normal double-click launch.
func _ready() -> void:
	super._ready()
	var user: PackedStringArray = OS.get_cmdline_user_args()
	if "--autostart" in OS.get_cmdline_args() or user.has("--coop-host") \
			or user.has("--coop-client") or user.has("--host") or user.has("--join"):
		start_cart.call_deferred()

func show_main() -> void:
	moving_mode = false
	screen = "main"
	_page("迷失太空 · Resonance 02", "最后一班矿车 → 被故意切断的轨道 · 1～4 人合作")
	if message != "": _label(message, 17, Color("#ffc37b"))
	_button("单人开始（02 → 03 连续）", start_cart).grab_focus()
	_button("创建房间（主机 · 可 1～4 人）", start_coop_host)
	_button("加入房间（127.0.0.1）", start_coop_join)
	_button("设置", show_settings)
	_button("退出", func() -> void: get_tree().quit())
	_label("主机与客户端各自启动一个游戏进程。主机先开，客户端后加入；断线不会卡住剩下的人。", 16, Color("#a3c5ca"))

# Co-op entry points. Both build the same single continuous 02+03 stage, so the
# cart, its cargo and the repair bay are always the same objects for everybody.
func start_coop_host() -> void:
	start_cart()
	if stage != null and stage.get("coop") != null:
		(stage.get("coop") as Node).call("start_host")

func start_coop_join(address: String = "127.0.0.1") -> void:
	start_cart()
	if stage != null and stage.get("coop") != null:
		(stage.get("coop") as Node).call("start_client", address)

func start_cart() -> void:
	moving_mode = true
	message = ""
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate() as Node3D
	stage.name = "MovingCartSlice"
	add_child(stage)
	_apply_settings()
	_enter_mission()

func _enter_mission() -> void:
	if moving_mode and stage != null:
		screen = "playing"
		overlay.hide()
		stage.call("set_paused", false)
		(stage.get("hud") as CanvasLayer).show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		super._enter_mission()

func show_pause() -> void:
	if not moving_mode:
		super.show_pause()
		return
	screen = "pause"
	stage.call("set_paused", true)
	_page("矿车任务菜单", "单人暂停 · 继续后车辆和货物恢复运动")
	_button("继续探索", _enter_mission).grab_focus()
	_button("重新开始矿车样板", func() -> void:
		stage.call("reset_run")
		_enter_mission())
	_button("设置", show_settings)
	_button("返回主菜单", func() -> void: leave_room(""))
	_label("E 在扶手抓扶、松开；前端控制器 E 发车\nB 手制动（连按 1 档→2 档→松开）；停车后 R 回收散落容器 / 救援登车\nF 拾取 / 停车解锁 · X 缓放 · G 放置到固定座 · E 合拢锁爪\nWASD 自由移动 · Shift 跑 · 鼠标视角 · F1 提示", 18)

func _apply_settings() -> void:
	if not moving_mode:
		super._apply_settings()
		return
	if stage == null: return
	(stage.get("player") as Node).set("mouse_sensitivity", sensitivity)
	stage.set("reduced_effects", reduced_effects)

func leave_room(reason: String = "") -> void:
	if not moving_mode:
		super.leave_room(reason)
		return
	if stage != null:
		remove_child(stage)
		stage.queue_free()
		stage = null
	moving_mode = false
	message = reason
	show_main()
