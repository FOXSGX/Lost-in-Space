extends "res://tests/test_cart_interactions.gd"

# Camera occlusion audit across the whole run, including the bend at speed.
# The earlier M1/M3 suites only sampled overlap on a fixed cadence, which missed
# the bend. This samples every physics frame and records the worst moments.
func run() -> void:
	await boot()
	await travel(Vector3(1, 0, 1.55))
	await frames(30)
	var overlaps: int = 0
	var samples: int = 0
	var worst: Dictionary = {}
	var worst_count: int = 0
	await start_from_console()
	# Drive the whole route while sweeping the camera.
	for _i: int in range(3200):
		await frames(1)
		samples += 1
		player.set("_camera_yaw_target", PI * 0.5 + sin(float(_i) * 0.02) * 1.5)
		var bad: bool = bool(player.call("camera_overlap"))
		if bad:
			overlaps += 1
			worst_count += 1
			if worst.is_empty():
				worst = {
					"distance": cart.get("distance"),
					"phase": scene.get("bend_event").get("phase"),
					"camera": str(player.get("camera").global_position),
					"player": str(player.global_position),
				}
		if bool(cart.get("arrived")):
			break
	print("CAMERA_AUDIT samples=", samples, " overlaps=", overlaps, " first=", JSON.stringify(worst))
	check(overlaps == 0, "全流程逐帧采样相机未穿模", {"samples": samples, "overlaps": overlaps, "first": worst})
	await shot("camera_audit_end")
	await finish()
