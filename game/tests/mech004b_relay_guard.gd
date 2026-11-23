extends Node
## MECHANICS-004B · 第九节附加核实：锁爪锁定后，晶体因真实外力离开叉口时，
## 中继是否仍错误地报告成功？
##
## 做法：把晶体真实落进 b1、按 E 让锁爪合拢锁定（中继成立），
## 然后施加真实外力把晶体推出叉口，检查 `locked()` 与 `_relay_ready()`。
## 失败返回非零退出码。

var stage: Node
var cradles: Dictionary
var player: Node3D
var crystal: Node3D
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	cradles = stage.get("cradles") as Dictionary
	player = stage.get("player") as Node3D
	crystal = stage.get("crystal_a") as Node3D
	var b1: Node3D = cradles["b1"] as Node3D

	# 1 真实落座
	crystal.set("freeze", false)
	crystal.call("set_collision_enabled", true)
	crystal.rotation = Vector3(0.0, deg_to_rad(float(b1.get("required_yaw_deg"))), 0.0)
	crystal.set("held_yaw_deg", float(b1.get("required_yaw_deg")))
	crystal.global_position = (b1.call("get_seat_position") as Vector3) + Vector3(0.0, 0.85, 0.0)
	crystal.set("linear_velocity", Vector3.ZERO)
	crystal.set("angular_velocity", Vector3.ZERO)
	var seated := false
	for i in range(200):
		await get_tree().physics_frame
		if bool(b1.call("is_occupied")):
			seated = true
			break
	_check("F1 晶体真实落进 b1 叉口（occupied）", seated, "occupied=%s" % str(seated))

	# 2 玩家按 E 合拢锁爪
	var at: Vector3 = b1.global_position + Vector3(-0.95, 0.05, 1.35)
	player.call("teleport", at, 0.0)
	player.call("aim_camera_at", b1.global_position + Vector3(0.0, 0.35, 0.0), -35.0)
	await _w(25)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	var locked := false
	for i in range(260):
		await get_tree().physics_frame
		if bool(b1.call("locked")):
			locked = true
			break
	var relay_locked: bool = bool(stage.call("_relay_ready", "b1"))
	_check("F2 锁定后中继成立（locked + aligned + occupied）",
		locked and relay_locked,
		"locked=%s relay=%s aligned=%s" % [str(locked), str(relay_locked),
			str(b1.get("aligned"))])

	# 3 施加真实外力，把晶体推出叉口（不是 F 取走，也不是传送）
	var seat_pos: Vector3 = b1.call("get_seat_position") as Vector3
	var pushed := false
	crystal.apply_central_impulse(Vector3(2.6, 0.6, 2.6) * float(crystal.get("mass")))
	for i in range(180):
		await get_tree().physics_frame
		var local: Vector3 = b1.to_local(crystal.global_position)
		if Vector2(local.x, local.z).length() > 0.45:
			pushed = true
			break
	var inside_after: bool = bool(b1.call("crystal_inside"))
	var locked_after: bool = bool(b1.call("locked"))
	var aligned_after: bool = bool(b1.get("aligned"))
	var relay_after: bool = bool(stage.call("_relay_ready", "b1"))
	_check("F3 晶体被真实外力推出叉口后，中继不再报告成功（不缓存 aligned）",
		pushed and not inside_after and not locked_after and not relay_after,
		"pushed=%s inside=%s locked=%s aligned=%s relay=%s 位移=%.2f m" % [
			str(pushed), str(inside_after), str(locked_after), str(aligned_after),
			str(relay_after),
			Vector2((b1.to_local(crystal.global_position) as Vector3).x,
				(b1.to_local(crystal.global_position) as Vector3).z).length()])

	print("MECH004B_RELAY_DONE checks=%d passed=%d failures=%d" % [
		checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s  %s  |  %s" % ["PASS" if ok else "FAIL", label, detail])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
