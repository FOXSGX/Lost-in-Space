extends "res://scripts/carry_motion.gd"

var cart: AnimatableBody3D
var local_from: Transform3D
var local_to: Transform3D

func prepare_place(at: Vector3) -> bool:
	if not super.prepare_place(at): return false
	local_from = cart.global_transform.affine_inverse() * _place_from
	local_to = cart.global_transform.affine_inverse() * _place_to
	return true

func tick_place(delta: float) -> bool:
	_place_from = cart.global_transform * local_from
	_place_to = cart.global_transform * local_to
	var done: bool = super.tick_place(delta)
	if done:
		core.linear_velocity = cart.call("point_velocity", core.global_position) as Vector3
		core.collision_mask = 34
	return done
