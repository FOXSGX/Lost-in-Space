extends "res://tests/test_cart_interactions.gd"

# M4 · Resonance bend event, covering the three required situations:
#   A  prepared      - cargo locked before departure, bend is passed cleanly
#   B  improvise     - cargo loose, slides in the bend, player brakes and locks
#   C  failure       - cargo thrown off, player recovers and still finishes
# All three use the same rules; only the player's choices differ.

func bend() -> Node3D:
	return scene.get("bend_event") as Node3D

func bodies() -> Array[RigidBody3D]:
	return cargo.get("cargo") as Array[RigidBody3D]

func lock_all() -> bool:
	for index: int in range(bodies().size()):
		var body: RigidBody3D = bodies()[index]
		await pick_body(body)
		await lock_body(body, index)
	return int(cargo.call("locked_count")) == bodies().size()

func run_to(distance: float, limit: int = 4000) -> void:
	for _i: int in range(limit):
		if float(cart.get("distance")) >= distance: return
		await frames(1)

func run() -> void:
	await boot()
	check(await travel(Vector3(1,0,1.55)), "从菜单步行登车")
	check(bend() != null, "共振弯道事件已接入场景")

	# ── Situation A: prepare before departure ────────────────────────────────
	check(await lock_all(), "A 出发前把两件货物全部固定")
	await start_from_console()
	await run_to(31.0)
	check(str(bend().get("phase")) in ["approaching","entering"], "A 事件由真实里程进入预警状态", {"phase":bend().get("phase"),"distance":cart.get("distance")})
	var locked_before: int = int(cargo.call("locked_count"))
	await run_to(41.0)
	check(str(bend().get("phase")) == "peak", "A 到达共振峰值阶段", {"phase":bend().get("phase"),"distance":cart.get("distance")})
	check(int(cargo.call("locked_count")) == locked_before, "A 固定货物在弯道中保持锁定")
	var socket: Vector3 = (cargo.get("slots") as Array[Vector3])[0]
	check(cart.to_local(bodies()[0].global_position).distance_to(socket) < 0.01, "A 固定货物未因弯道滑离固定座")
	await shot("A_peak_locked")
	await run_to(47.0)
	check(str(bend().get("phase")) == "cleared", "A 驶出弯道后事件结束", {"phase":bend().get("phase")})
	await scene.call("reset_run")
	await frames(40)

	# ── Situation B: improvise during the run ────────────────────────────────
	check(await travel(Vector3(1,0,1.55)), "B 重置后重新登车")
	check(int(cargo.call("locked_count")) == 0, "B 重置清空了固定状态")
	await start_from_console()
	await run_to(34.0)
	var slip_before: float = float(bodies()[0].get("slip_max"))
	await run_to(39.0)
	var slip_after: float = float(bodies()[0].get("slip_max"))
	check(slip_after > slip_before + 0.05, "B 未固定货物在弯道中继续滑动", {"before":slip_before,"after":slip_after})
	await shot("B_sliding")
	await press("cart_brake")
	await frames(150)
	check(float(cart.get("speed")) < 0.001, "B 紧急制动平缓停车")
	check(str(bend().get("phase")) == "idle", "B 停车后事件强度归零", {"phase":bend().get("phase")})
	check(float(bend().get("intensity")) < 0.01, "B 停车后晶体脉冲停止")
	await shot("B_braked")
	check(await lock_all(), "B 停车后把货物重新固定")
	await start_from_console()
	await run_to(50.0)
	check(str(bend().get("phase")) in ["cleared","leaving","idle"], "B 补救后重新通过弯道", {"phase":bend().get("phase")})
	await scene.call("reset_run")
	await frames(40)

	# ── Situation C: failure and recovery ────────────────────────────────────
	check(await travel(Vector3(1,0,1.55)), "C 重置后重新登车")
	await start_from_console()
	await run_to(36.0)
	# The player loses a container over the side during the bend.
	bodies()[1].global_position = cart.to_global(Vector3(-1.0, -2.0, 6.5))
	bodies()[1].linear_velocity = Vector3.ZERO
	bodies()[1].reset_physics_interpolation()
	await frames(30)
	await press("cart_brake")
	await frames(150)
	check(float(cart.get("speed")) < 0.001, "C 货物掉落后玩家制动停车")
	await press("cart_recover")
	await frames(50)
	check(str(bodies()[1].get("phase")) == "free" and cart.to_local(bodies()[1].global_position).y > 1.8, "C 回收把货物送回甲板")
	check(int(cargo.call("locked_count")) == 0, "C 回收不等于固定，仍需玩家自己锁定")
	await shot("C_recovered")
	check(await lock_all(), "C 玩家重新固定货物")
	await start_from_console()
	await run_to(52.0)
	check(str(bend().get("phase")) in ["cleared","leaving","idle"], "C 补救后仍能继续通过弯道", {"phase":bend().get("phase")})
	await shot("C_passed")

	# ── Event is state-driven, not a fixed timeline ──────────────────────────
	check(bend().get("phase_log") is Array and (bend().get("phase_log") as Array).size() > 4, "事件阶段由里程与速度驱动并留下记录", {"entries":(bend().get("phase_log") as Array).size()})
	await finish()
