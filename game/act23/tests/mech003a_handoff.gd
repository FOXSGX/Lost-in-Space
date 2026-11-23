extends Node
## MECHANICS-003A · 第二幕/第三幕 → 第四幕的真实章节交接
##
## 从正式包装场景 res://scenes/act23.tscn 进入，把矿车开到晶体门、拉合夹钳完成
## 03 停靠，然后等关卡自己的 _check_chapter_handoff 把场景切到 act4。
## 观察者挂在 /root 上，切换后仍能断言目标场景真的初始化。

var slice: Node
var cart: AnimatableBody3D
var dock: Node3D
var flow: Node
var player: CharacterBody3D


func _ready() -> void:
	var entry: Node = (load("res://scenes/act23.tscn") as PackedScene).instantiate()
	add_child(entry)
	await _w(180)
	slice = _find(entry, "MovingCartSlice")
	if slice == null:
		print("FAIL  H1 正式入口里找不到 MovingCartSlice")
		return _finish(1)
	cart = slice.get("cart") as AnimatableBody3D
	flow = slice.get("flow") as Node
	dock = slice.get("dock") as Node3D
	player = slice.get("player") as CharacterBody3D
	print("PASS  H1 正式入口 res://scenes/act23.tscn 构建出第三幕切片（dock=%s）" % str(dock != null))
	# 直接开到 103 m，再走完最后一段让调速器停车（route_clear 由维修完成触发；
	# 这里用 release_route 模拟第三幕已经通过 002C 的维修——维修本身另有专项）。
	cart.call("snap_to_distance", 103.0)
	cart.call("release_route")
	await _w(20)
	cart.call("start")
	for i in range(900):
		await get_tree().physics_frame
		if bool(cart.get("arrived")):
			break
	if not bool(cart.get("arrived")):
		print("FAIL  H2 矿车没有到达晶体门")
		return _finish(1)
	print("PASS  H2 矿车到达晶体门（distance=%.2f，phase=%s）" % [
		float(cart.get("distance")), str(slice.get("flow").get("phase"))])
	# 站到夹钳旁拉闸臂
	var handle: Vector3 = dock.call("handle_world") as Vector3
	player.call("restore_at", handle + Vector3(0.0, -0.85, -1.25))
	var look: Vector3 = (dock.call("arm_tip_world") as Vector3) - (player.global_position + Vector3.UP * 1.5)
	player.set("_camera_yaw", atan2(-look.x, -look.z))
	player.set("_camera_yaw_target", atan2(-look.x, -look.z))
	await _w(20)
	# 交接前把观察者挂到 /root：场景切换会把本节点释放
	var watcher: Node = (load("res://act23/tests/mech003a_handoff_watch.gd") as Script).new() as Node
	get_tree().root.add_child.call_deferred(watcher)
	Input.action_press("repair")
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			break
	Input.action_release("repair")
	await _w(30)
	if not bool(dock.call("docked")):
		print("FAIL  H3 停靠没有成立")
		return _finish(1)
	print("PASS  H3 晶体门停靠成立（闸臂 %.1f°，棘爪=%s）" % [
		float(dock.call("state").get("angle_deg", 0.0)), str(dock.get("latched"))])
	# 边界：在 4.5 s 交接倒计时期间解除停靠 → 不得过幕（003A 遗漏，本轮修复）
	await _w(40)
	Input.action_press("repair")
	await _w(3)
	Input.action_release("repair")
	flow.call("try_interact", player)
	await _w(30)
	var released: bool = not bool(dock.call("docked"))
	# 等过 6 s（超过 4.5 s 倒计时），场景必须还在 act23
	for i in range(420):
		await get_tree().physics_frame
	# 真正的过幕会换掉当前场景并释放本测试节点；能走到这里且 act23 切片仍在，
	# 就说明交接确实被取消了。
	var stayed: bool = is_inside_tree() and slice != null and slice.is_inside_tree()
	print(("PASS  " if (released and stayed) else "FAIL  ") + "H3b 倒计时期间解除停靠 → 交接被取消（released=%s stayed=%s）" % [
		str(released), str(stayed)])
	var phase_after: String = str(flow.get("phase"))
	print("P phase_after_release=%s docked=%s" % [phase_after, str(dock.call("docked"))])
	# 重新停靠，让交接真正发生
	await _w(20)
	var handle2: Vector3 = dock.call("handle_world") as Vector3
	player.call("restore_at", handle2 + Vector3(0.0, -0.85, -1.25))
	var look2: Vector3 = (dock.call("arm_tip_world") as Vector3) - (player.global_position + Vector3.UP * 1.5)
	player.set("_camera_yaw", atan2(-look2.x, -look2.z))
	player.set("_camera_yaw_target", atan2(-look2.x, -look2.z))
	await _w(20)
	Input.action_press("repair")
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			break
	Input.action_release("repair")
	await _w(30)
	print(("PASS  " if bool(dock.call("docked")) else "FAIL  ") + "H3c 重新停靠成立后再过幕")
	# 之后交给 watcher：它会在场景切换后打印 H4/H5 并退出


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


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _finish(code: int) -> void:
	print("MECH003A_HANDOFF_DONE failures=%d" % code)
	get_tree().quit(code)



