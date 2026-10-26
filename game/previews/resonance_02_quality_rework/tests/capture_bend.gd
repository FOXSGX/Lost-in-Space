extends "res://tests/test_cart_interactions.gd"

# Visual capture of the resonance bend event phases.
func run() -> void:
	await boot()
	await travel(Vector3(1,0,1.55))
	await frames(20)
	await start_from_console()
	var bend: Node3D = scene.get("bend_event") as Node3D
	for target: float in [31.0, 37.0, 41.0]:
		while float(cart.get("distance")) < target:
			await frames(1)
		await frames(6)
		await shot("bend_%02d" % int(target))
		print("PHASE_AT ", target, " = ", bend.get("phase"), " intensity=", bend.get("intensity"))
	await finish()
