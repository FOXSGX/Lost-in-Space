extends "res://previews/frost_first_playable/player.gd"

func simulate(delta: float) -> void:
	var director: Node = get_parent()
	var on_cart: bool = director.world.cart != null and director.world.cart.riders.has(peer_id)
	var on_moto: bool = director.world.snowmobile != null and director.world.snowmobile.riders.has(peer_id)
	if on_cart or on_moto:
		rotation.y = float(controls.get("yaw",rotation.y))
		_network_view_pitch = float(controls.get("pitch",0))
		velocity = Vector3.ZERO
		impact_speed = 0
		stop_jet()
		return
	super.simulate(delta)
	# 热可可【极地暖流】或薯片【脆香冲刺】期间提供额外水平冲刺加速！
	var buff_mul: float = 1.0
	if float(get_meta("thermos_buff", 0.0)) > 0.0:
		buff_mul += 0.20
	if float(get_meta("chips_buff", 0.0)) > 0.0:
		buff_mul += 0.16
	if buff_mul > 1.01 and is_on_floor():
		var extra: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * (buff_mul - 1.0) * delta
		if extra.length_squared() > 0.00001 and not test_move(global_transform, extra):
			position += extra
