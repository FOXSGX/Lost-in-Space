extends Node
## 临时观察者：挂在 /root 上，场景切换后仍然存活，用来确认真的切到了第二幕。

var done: bool = false
var frames: int = 0

func _physics_process(_delta: float) -> void:
	if done:
		return
	frames += 1
	var current: Node = get_tree().current_scene
	if current != null and str(current.scene_file_path) == "res://scenes/act23.tscn":
		done = true
		var slice: Node = _find(current, "MovingCartSlice")
		var ok: bool = slice != null and slice.get("cart") != null and slice.get("device") != null
		var brake: bool = false
		if ok:
			brake = (slice.get("cart") as Node).get("brake_rig") != null
		print("PASS  H3 过幕后当前场景 = %s" % str(current.scene_file_path))
		print(("PASS  " if ok else "FAIL  ") + "H4 过幕后的第二幕切片在线（cart/device）")
		print(("PASS  " if brake else "FAIL  ") + "H5 过幕后手制动机构随矿车构建")
		print("MECH002B_HANDOFF_DONE failures=%d" % (0 if (ok and brake) else 1))
		get_tree().quit(0 if (ok and brake) else 1)
		return
	if frames > 900:
		done = true
		print("FAIL  H3 过幕调用后 15 s 内没有切到 res://scenes/act23.tscn（当前=%s）" % (
			str(current.scene_file_path) if current != null else "null"))
		print("MECH002B_HANDOFF_DONE failures=1")
		get_tree().quit(1)

func _find(node: Node, target: String) -> Node:
	if node == null:
		return null
	if str(node.name) == target:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, target)
		if hit != null:
			return hit
	return null
