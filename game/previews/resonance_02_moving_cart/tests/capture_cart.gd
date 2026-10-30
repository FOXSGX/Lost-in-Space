extends "res://tests/test_moving_cart.gd"

func run() -> void:
	await boot()
	await shot("00_entry")
	check(await travel(Vector3(1,0,1.55)), "登车")
	await frames(30)
	await shot("01_deck")
	player.set("_camera_yaw_target",-PI * 0.5)
	await frames(65)
	await shot("02_reverse_view")
	await finish()
