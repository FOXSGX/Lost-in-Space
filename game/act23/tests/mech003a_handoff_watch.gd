extends Node
## 临时观察者：挂在 /root，场景切到 act4 后仍存活，确认第四幕真的初始化。

var done: bool = false
var frames: int = 0


func _physics_process(_delta: float) -> void:
	if done:
		return
	frames += 1
	var current: Node = get_tree().current_scene
	if current == null:
		return
	if str(current.scene_file_path) == "res://scenes/act4.tscn":
		done = true
		var ok: bool = current.has_method("is_completed") or current.get("completed") != null
		print("PASS  H4 过幕后场景 = %s" % str(current.scene_file_path))
		print(("PASS  " if ok else "FAIL  ") + "H5 第四幕控制器已初始化（completed/stage 字段在线）")
		print("MECH003A_HANDOFF_DONE failures=%d" % (0 if ok else 1))
		get_tree().quit(0 if ok else 1)
		return
	if frames > 1800:
		done = true
		print("FAIL  H4 30 s 内没有切到 act4（当前=%s）" % (
			str(current.scene_file_path) if current != null else "null"))
		print("MECH003A_HANDOFF_DONE failures=1")
		get_tree().quit(1)
