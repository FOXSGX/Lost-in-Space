extends SceneTree

## Act23 独立入口的第一人称冒烟测试：不依赖主游戏 main_3d。
## 运行：godot --headless --path game --script res://act23/tests/act23_first_person_smoke.gd

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var packed := load("res://act23/act23_entry.tscn") as PackedScene
	check(packed != null, "Act23 入口场景没有加载")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame
	var stage := scene.get_node_or_null("MovingCartSlice")
	check(stage != null, "Act23 没有 MovingCartSlice")
	if stage == null:
		_finish()
		return
	var player := stage.get("player") as CharacterBody3D
	check(player != null, "Act23 没有生成玩家")
	if player == null:
		_finish()
		return
	check(bool(player.get("use_first_person")), "Act23 玩家不是第一人称")
	var camera := player.get("camera") as Camera3D
	check(camera != null, "Act23 玩家没有相机")
	if camera != null:
		check(camera.current, "Act23 相机不是当前相机")
		check(camera.get_parent() == player, "Act23 相机没有刚性挂在玩家身上")
		check(camera.position.distance_to(Vector3(0.0, 1.30, 0.0)) < 0.05, "Act23 眼高不是第一人称高度")
	check(player.get("fp_rig") != null, "Act23 没有第一人称手部模型")
	check(bool(player.get("is_local_actor")), "本地玩家标记异常")
	print("ACT23_FIRST_PERSON_SMOKE: %d checks, %d failures" % [checks, failures.size()])
	_finish()


func _finish() -> void:
	quit(0 if failures.is_empty() else 1)
