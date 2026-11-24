extends Node
## MECHANICS-002C · 端到端：board → ride → 断轨停车 → 绞盘维修 → 恢复行驶 → 到站
##
## 不设置任何"维修成功"标志：发车、停车、挂缆、收缆、落闸、插销、再发车全部走
## 游戏内真实入口（控制器 E / 绞盘控制台 W·S·空格 / 锁定座 E）。

var stage: Node
var flow: Node
var rig: Node
var winch: Node
var rail: Node
var cart: AnimatableBody3D
var player: CharacterBody3D
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(120)
	flow = stage.get("flow")
	rig = flow.get("rig")
	winch = rig.get("winch")
	rail = rig.get("rail")
	cart = stage.get("cart") as AnimatableBody3D
	player = stage.get("player") as CharacterBody3D

	# 1 发车（真实控制器 E）
	await _at_console()
	var started: bool = bool(stage.call("request_action", "repair", 1))
	_check("E1 玩家在矿车控制器按 E 发车（进入 ride）", started and bool(cart.get("running")),
		"started=%s running=%s phase=%s" % [str(started), str(cart.get("running")),
			str(flow.get("phase"))])

	# 2 断轨停车（调速器电制动）
	var fault: bool = false
	for i in range(12000):
		await get_tree().physics_frame
		if bool(cart.get("stopped_for_fault")):
			fault = true
			break
	var stop_distance: float = float(cart.get("distance"))
	_check("E2 矿车在断轨前安全停车", fault and absf(stop_distance - 88.0) < 0.6,
		"stopped_for_fault=%s distance=%.2f speed=%.3f" % [str(fault), stop_distance,
			float(cart.get("speed"))])
	await _w(30)
	var phase_fault: String = str(flow.get("phase"))
	_check("E3 停车后进入维修阶段（fault/repair，目标提示去断轨处）",
		phase_fault in ["fault", "repair"],
		"phase=%s objective=%s" % [phase_fault, str(flow.get("objective_text"))])

	# 3 走到断轨处挂缆（真实 E 交互：flow.try_interact）
	var anchor: Node3D = rig.call("find_anchor", "eye_far")
	player.global_position = (anchor.call("attach_point") as Vector3) + Vector3(1.2, 0.2, 0.4)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(10)
	var attached: bool = false
	for attempt in range(8):
		if bool(winch.get("attached")):
			attached = true
			break
		stage.call("request_action", "repair", 1)
		await _w(20)
	attached = attached or bool(winch.get("attached"))
	_check("E4 玩家在断轨处用 E 把缆绳挂上吊耳（真实连接点）", attached,
		"attached=%s anchor=%s" % [str(attached), str(winch.get("anchor_name"))])

	# 4 回到绞盘控制台收缆（真实控制台 + W）
	var machine: Node3D = winch as Node3D
	player.global_position = machine.global_position + Vector3(0.0, 0.2, -2.0)
	await _w(6)
	flow.call("_enter_console", player)
	await _w(4)
	Input.action_press("winch_haul")
	var deg: float = 15.0
	var t: float = 0.0
	for i in range(3000):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		deg = float((rail.call("alignment") as Dictionary).get("angle_deg"))
		if absf(deg) <= 2.6:
			break
	Input.action_release("winch_haul")
	await _w(2)
	_check("E5 收缆把摆动轨从 15° 拉到导向槽内（真实张力驱动）",
		absf(deg) <= 4.0 and float(rail.get("tension_estimate")) < 3000.0,
		"angle=%.2f° 用时 %.1f s 峰值张力 %.0f N" % [deg, t,
			float(winch.get("tension"))])

	# 5 落鼓刹保持（空格）
	Input.action_press("winch_brake")
	await _w(3)
	Input.action_release("winch_brake")
	await _w(30)
	var braked: bool = bool(winch.get("brake"))
	flow.call("leave_console", 0)
	await _w(20)
	var angle_held: float = float((rail.call("alignment") as Dictionary).get("angle_deg"))
	_check("E6 落鼓刹后轨道被抱住（离开控制台也不会掉回去）",
		braked and absf(angle_held) <= 4.5,
		"brake=%s angle=%.2f°" % [str(braked), angle_held])

	# 6 锁定座插销（真实 E：flow.try_interact / rig.try_install_lock）
	var lock_node: Node3D = (flow.get("yard") as Node3D).get("lock_station") as Node3D
	player.global_position = lock_node.global_position + Vector3(1.1, 0.2, -0.9)
	await _w(10)
	for attempt in range(8):
		if bool(rig.get("completed")):
			break
		stage.call("request_action", "repair", 1)
		await _w(20)
	await _w(90)
	_check("E7 在锁定座插销，维修完成、线路恢复（route_clear 来自真实锁定）",
		bool(rig.get("completed")) and bool(cart.get("route_clear")),
		"completed=%s route_clear=%s angle=%.2f°" % [str(rig.get("completed")),
			str(cart.get("route_clear")), float((rail.call("alignment") as Dictionary).get("angle_deg"))])

	# 7 回到矿车控制器重新发车
	await _at_console()
	var restarted: bool = bool(stage.call("request_action", "repair", 1))
	await _w(60)
	_check("E8 回到控制器按 E 重新发车（修复后继续行驶）",
		restarted and bool(cart.get("running")) and float(cart.get("speed")) > 0.2,
		"restarted=%s running=%s speed=%.2f" % [str(restarted), str(cart.get("running")),
			float(cart.get("speed"))])

	# 8 到站
	var arrived: bool = false
	for i in range(2400):
		await get_tree().physics_frame
		if bool(cart.get("arrived")):
			arrived = true
			break
	_check("E9 修复后到达终点（106 m，剧情 done）",
		arrived and absf(float(cart.get("distance")) - 106.0) < 0.1,
		"arrived=%s distance=%.2f phase=%s" % [str(arrived), float(cart.get("distance")),
			str(flow.get("phase"))])
	_report()


func _at_console() -> void:
	player.global_position = cart.to_global(Vector3(2.48, 2.05, 1.20))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(8)


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS  " if ok else "FAIL  ") + name + "  |  " + detail)


func _report() -> void:
	print("MECH002C_E2E_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
