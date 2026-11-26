extends "res://previews/frost_first_playable/player.gd"

func simulate(delta: float) -> void:
	var director: Node = get_parent()
	if director.world.cart.riders.has(peer_id):
		rotation.y = float(controls.get("yaw",rotation.y))
		_network_view_pitch = float(controls.get("pitch",0))
		velocity = Vector3.ZERO
		impact_speed = 0
		stop_jet()
		return
	super.simulate(delta)
