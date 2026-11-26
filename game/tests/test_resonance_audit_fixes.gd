extends SceneTree

## Comprehensive Godot CLI verification for Resonance audit fixes (R-08 ~ R-53).
## Run: godot --headless --path game --script res://tests/test_resonance_audit_fixes.gd

const WinchCableScript := preload("res://act23/scripts/winch/winch_cable.gd")
const MovingCartScript := preload("res://act23/scripts/moving_cart.gd")
const CaveTunnelScript := preload("res://act23/scripts/cave_tunnel.gd")
const Act1EntryDoorScript := preload("res://act1/scripts/machines/act1_entry_door.gd")
const Act1PowerCartScript := preload("res://act1/scripts/machines/act1_power_cart.gd")
const Act1MineCartScript := preload("res://act1/scripts/machines/act1_mine_cart.gd")
const Act1CargoRigScript := preload("res://act1/scripts/machines/act1_cargo_rig.gd")
const Act1VentilationScript := preload("res://act1/scripts/machines/act1_ventilation.gd")
const Act1WheelChockScript := preload("res://act1/scripts/machines/act1_wheel_chock.gd")
const Act1ParkingBrakeScript := preload("res://act1/scripts/machines/act1_parking_brake_r2.gd")
const Act1FanInterlockScript := preload("res://act1/scripts/machines/act1_fan_interlock.gd")
const Act1PowerLatchScript := preload("res://act1/machines/power_latch.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("AUDIT_FIX ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	await _test_winch_cable_r09()
	await _test_moving_cart_r10_r11()
	await _test_push_door_r08()
	await _test_weight_cart_r27()
	await _test_act1_fixes_r34_to_r45()
	await _test_act4_and_net_r15_r46_to_r53()

	print("RESONANCE_AUDIT_FIXES_REPORT ", JSON.stringify({
		"checks": checks,
		"failures": failures,
		"ok": failures == 0,
	}))
	quit(0 if failures == 0 else 1)


func _test_winch_cable_r09() -> void:
	var cable: Node3D = WinchCableScript.new() as Node3D
	root.add_child(cable)
	await frames(2)
	var mesh_node: MeshInstance3D = cable.get_node_or_null("CableMesh") as MeshInstance3D
	check(mesh_node != null and mesh_node.mesh is ArrayMesh, "R-09 cable uses persistent ArrayMesh")
	var first_id: int = mesh_node.mesh.get_instance_id() if mesh_node != null and mesh_node.mesh != null else -1
	for i in range(60):
		cable.call("update_cable", Vector3(0.0, 1.0, 0.0), Vector3(4.0 + float(i) * 0.01, 1.2, 0.5), 0.35, 0.6, true)
	var after_id: int = mesh_node.mesh.get_instance_id() if mesh_node != null and mesh_node.mesh != null else -2
	check(first_id == after_id and first_id != 0, "R-09 update_cable reuses ArrayMesh without recreating", {"id": first_id, "after": after_id})
	cable.queue_free()
	await frames(1)


func _test_moving_cart_r10_r11() -> void:
	var cart: AnimatableBody3D = MovingCartScript.new() as AnimatableBody3D
	var vis: Node3D = Node3D.new()
	vis.name = "CartVisualMock"
	cart.add_child(vis)
	cart.set("visual_node", vis)
	var fake_stage: Node3D = Node3D.new()
	var fake_bend: Node3D = Node3D.new()
	cart.set("stage", null)
	cart.set("bend_event", fake_bend)
	fake_bend.set("stage", fake_stage)
	fake_bend.set_script(preload("res://act23/scripts/cart_bend_event.gd"))
	root.add_child(fake_stage)
	fake_bend.set("stage", fake_stage)
	root.add_child(fake_bend)
	root.add_child(cart)
	cart.set("stage", null)
	cart.set("distance", 35.0)
	cart.set("speed", 1.5)
	cart.set("running", true)
	cart.global_transform = MovingCartScript.route_pose(35.0)
	fake_bend.set("active", true)
	fake_bend.set("phase", 1)
	await frames(5)
	var wvel: Vector3 = cart.get("world_velocity") as Vector3
	check(wvel.is_finite() and absf(wvel.y) < 0.05, "R-11 10Hz bend jitter does not pollute cart world_velocity.y", {"vy": wvel.y})

	# R-10: client mirror mid-run stall catches up smoothly instead of 6.5 m single-frame jump
	cart.set("network_client", true)
	cart.set("distance", 40.0)
	cart.global_transform = MovingCartScript.route_pose(40.0)
	var before_pos: Vector3 = cart.global_position
	cart.call("apply_net_state", [46.5, 1.5, true, false, false, false, "", "行驶"])
	await frames(1)
	var step: float = cart.global_position.distance_to(before_pos)
	check(step < 0.5, "R-10 client mirror catches up smoothly on 6.5 m stall", {"step_m": step})

	cart.queue_free()
	fake_bend.queue_free()
	fake_stage.queue_free()
	await frames(1)


func _test_push_door_r08() -> void:
	var door: PushDoor = PushDoor.new()
	root.add_child(door)
	door.build()
	door.progress = 0.6
	door.body.position.y = 0.6 * 3.55
	var blocker: CharacterBody3D = CharacterBody3D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0.0, 0.88, 0.0)
	blocker.add_child(cs)
	root.add_child(blocker)
	blocker.global_position = door.global_position + Vector3(0.0, 0.0, 0.0)
	await frames(3)
	var y_before: float = door.body.position.y
	await frames(30)
	var y_after: float = door.body.position.y
	check(door.body is AnimatableBody3D, "R-08 PushDoor body is AnimatableBody3D")
	check(absf(y_after - y_before) < 0.02, "R-08 PushDoor holds height while player is in doorway", {"before": y_before, "after": y_after})
	blocker.queue_free()
	door.queue_free()
	await frames(1)


func _test_weight_cart_r27() -> void:
	var wc: WeightCart = WeightCart.new()
	root.add_child(wc)
	wc.setup(1.0, 0.5)
	await frames(2)
	var cb: AnimatableBody3D = wc.get_node_or_null("WeightCartBody") as AnimatableBody3D
	check(cb != null and cb.collision_layer == 8 and cb.get_child_count() > 0, "R-27 WeightCart has solid AnimatableBody3D on machine layer")
	wc.queue_free()
	await frames(1)


func _test_act1_fixes_r34_to_r45() -> void:
	var dummy_stage: Node3D = Node3D.new()
	root.add_child(dummy_stage)

	# R-40: EntryDoor frame posts not children of moving door body
	var edoor: AnimatableBody3D = Act1EntryDoorScript.new() as AnimatableBody3D
	dummy_stage.add_child(edoor)
	edoor.call("setup", dummy_stage)
	edoor.call("open_now")
	var static_posts: int = 0
	for child: Node in dummy_stage.get_children():
		if child is MeshInstance3D:
			static_posts += 1
	check(static_posts >= 2, "R-40 Act1EntryDoor frame is parented to static host, not moving door", {"static_frame_meshes": static_posts})

	# R-34, R-35, R-44: PowerCart
	var pcart: AnimatableBody3D = Act1PowerCartScript.new() as AnimatableBody3D
	dummy_stage.add_child(pcart)
	pcart.call("setup", dummy_stage)
	var mod: RigidBody3D = RigidBody3D.new()
	dummy_stage.add_child(mod)
	pcart.call("bind_module", mod)
	pcart.call("start_dock_approach")
	var tw: Variant = pcart.get("_transfer_tween")
	check(tw != null and (tw as Tween).is_valid(), "R-34 start_dock_approach tracks _transfer_tween")
	pcart.call("reset_cart")
	check(pcart.get("_transfer_tween") == null, "R-34 reset_cart cancels _transfer_tween")
	var snap_pc: Dictionary = pcart.call("snapshot") as Dictionary
	check(snap_pc.has("module_xform") and bool(snap_pc.get("has_power_module", false)), "R-44 PowerCart snapshot includes real power_module rigid body")

	# R-35: PowerCart clamp stalled holds impulse instead of 0
	var jaw: RigidBody3D = RigidBody3D.new()
	var bracket: StaticBody3D = StaticBody3D.new()
	var hinge: HingeJoint3D = HingeJoint3D.new()
	dummy_stage.add_child(bracket)
	dummy_stage.add_child(jaw)
	dummy_stage.add_child(hinge)
	hinge.node_a = hinge.get_path_to(bracket)
	hinge.node_b = hinge.get_path_to(jaw)
	pcart.call("bind_clamp", jaw, hinge)
	pcart.call("set_clamp", true)
	pcart.set("_clamp_timer", 3.5)
	await frames(2)
	var imp: float = hinge.get_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE)
	check(imp > 0.0, "R-35 stalled clamp keeps non-zero holding impulse", {"max_impulse": imp})

	# R-36: MineCart stops integrating once handoff is reached
	var mcart: AnimatableBody3D = Act1MineCartScript.new() as AnimatableBody3D
	mcart.sync_to_physics = false
	dummy_stage.add_child(mcart)
	mcart.global_position = Vector3(0.0, 0.0, float(Act1MineCartScript.TUNNEL_END_Z) + 0.01)
	mcart.set("departing", true)
	mcart.set("speed", 2.0)
	await frames(10)
	var z_after: float = mcart.global_position.z
	check(bool(mcart.get("handoff")) and not bool(mcart.get("departing")) and is_equal_approx(z_after, float(Act1MineCartScript.TUNNEL_END_Z)),
		"R-36 MineCart stops at TUNNEL_END_Z after handoff", {"z": z_after})

	# R-37 / R-38 / R-39: CargoRig _loop_points safe + pump re-baselines payout + straps hold outside zone
	var crig: Node3D = Act1CargoRigScript.new() as Node3D
	dummy_stage.add_child(crig)
	crig.set("cart", mcart)
	crig.set("crate", null)
	var pts: Array = crig.call("_loop_points", {"a": Vector3.ZERO, "h": Vector3.FORWARD}) as Array
	check(pts.size() == 4, "R-39 CargoRig _loop_points guards null crate")
	var mock_crate: RigidBody3D = RigidBody3D.new()
	mock_crate.mass = 100.0
	dummy_stage.add_child(mock_crate)
	crig.set("crate", mock_crate)
	crig.set("_loops", [{"a": Vector3(-1, 0, 0), "h": Vector3(1, 0, 0), "c1": Vector3(-0.4, 0.4, 0), "c2": Vector3(0.4, 0.4, 0), "rest": 2.0, "L": 2.0, "L_prev": 2.0, "tension": 0.0}])
	crig.set("payout", 0.45)
	mock_crate.position = Vector3(0.0, 0.0, 0.0)
	crig.set("clicks", 1)
	var pumped: bool = bool(crig.call("pump")) if bool(crig.call("crate_in_zone")) else false
	# Even when crate is outside zone, _apply_strap_forces still applies tension when anchors_attached() is true:
	mock_crate.position = Vector3(2.0, 0.0, 0.0)
	crig.call("_apply_strap_forces", 0.016)
	var lp_arr: Array = crig.get("_loops") as Array
	var out_zone_tension: float = float((lp_arr[0] as Dictionary).get("tension", 0.0))
	check(out_zone_tension > 0.0, "R-37 CargoRig straps still apply tension outside crate_in_zone", {"tension": out_zone_tension, "pumped": pumped})
	# R-38: pump() re-baselines rest length before clearing payout
	var crate_zone_pos: Vector3 = crig.to_global(Act1CargoRigScript.CRATE_CENTER)
	mock_crate.global_position = crate_zone_pos
	crig.set("payout", 0.45)
	crig.set("clicks", 0)
	crig.call("_measure_rest_lengths")
	var ok_pump: bool = bool(crig.call("pump"))
	var rest_after: float = float(crig.call("rest_length", (crig.get("_loops") as Array)[0]))
	var l_after: float = float(((crig.get("_loops") as Array)[0] as Dictionary).get("L", rest_after))
	check(ok_pump and float(crig.get("payout")) == 0.0 and (rest_after - l_after) >= -0.01,
		"R-38 CargoRig pump re-baselines rest length without sudden over-stretch", {"rest": rest_after, "L": l_after})
	crig.queue_free()
	mock_crate.queue_free()

	# R-41: Ventilation smoothstep + non-additive overlap
	var vent: Node3D = Act1VentilationScript.new() as Node3D
	dummy_stage.add_child(vent)
	vent.call("setup", dummy_stage)
	vent.set("running", true)
	vent.set("_smooth_main", 0.8)
	vent.set("_smooth_bypass", 0.8)
	var overlap_strength: float = float(vent.call("get_wind_strength_at", Vector3(8.0, 2.0, -28.5)))
	check(overlap_strength <= 4.35 * 0.8 + 0.05, "R-41 overlapping wind ducts do not double-add", {"strength": overlap_strength})

	# R-43: Act1 machine rigid bodies sit on layer 4 (solid to act1_player mask 1|4|16)
	var chock: Node3D = Act1WheelChockScript.new() as Node3D
	chock.call("setup", dummy_stage, Vector3.ZERO)
	var chock_body: RigidBody3D = chock.get("body") as RigidBody3D
	check(chock_body != null and chock_body.collision_layer == 4 and (chock_body.collision_mask & 2) != 0,
		"R-43 Act1WheelChock body uses layer 4 with player mask", {"layer": chock_body.collision_layer if chock_body != null else -1})

	var pbrake: Node3D = Act1ParkingBrakeScript.new() as Node3D
	pbrake.call("setup", dummy_stage, Vector3.ZERO)
	var pdrum: RigidBody3D = pbrake.get("drum") as RigidBody3D
	var ppin: RigidBody3D = pbrake.get("pin") as RigidBody3D
	check(pdrum != null and pdrum.collision_layer == 4 and ppin != null and ppin.collision_layer == 4,
		"R-43 Act1ParkingBrake drum/pin use layer 4")

	var fan_i: Node3D = Act1FanInterlockScript.new() as Node3D
	fan_i.call("setup", dummy_stage, Vector3.ZERO, Vector3(2.0, 0.0, 0.0))
	var fpin: RigidBody3D = fan_i.get("pin") as RigidBody3D
	var fcol: RigidBody3D = fan_i.get("collar") as RigidBody3D
	check(fpin != null and fpin.collision_layer == 4 and fcol != null and fcol.collision_layer == 4,
		"R-43 Act1FanInterlock pin/collar use layer 4")

	# R-45: PowerLatch axis matches hinge basis.z
	var platch: Node3D = Act1PowerLatchScript.new() as Node3D
	dummy_stage.add_child(platch)
	platch.call("setup", Vector3.ZERO)
	var laxis: Vector3 = platch.get("axis") as Vector3
	var lhinge: HingeJoint3D = platch.get("hinge") as HingeJoint3D
	check(lhinge != null and laxis.distance_to(lhinge.global_transform.basis.z.normalized()) < 0.01,
		"R-45 PowerLatch axis matches hinge basis.z", {"axis": laxis})

	dummy_stage.queue_free()
	await frames(1)


func _test_act4_and_net_r15_r46_to_r53() -> void:
	# R-15: HammerRig anvil collision + head probe
	var hrig: HammerRig = HammerRig.new()
	root.add_child(hrig)
	hrig.build()
	await frames(2)
	var anvil_col: StaticBody3D = hrig.get_node_or_null("AnvilCollision") as StaticBody3D
	var head_probe: Area3D = hrig.get_node_or_null("PendulumPivot/Head/HammerHeadProbe") as Area3D
	check(anvil_col != null and head_probe != null, "R-15 HammerRig has AnvilCollision and HammerHeadProbe")
	hrig.queue_free()

	# R-46 & R-50: FreightPlatform snapshot guard + client cargo kinematic freeze
	var fp: FreightPlatform = FreightPlatform.new()
	fp.authority = false
	root.add_child(fp)
	await frames(2)
	fp.travel_x = -8.8
	fp.set("_net_x", -8.8)
	fp.apply_net_state({"x": NAN, "y": 2.6, "speed": 0.0, "roll": 0.0, "pitch": 0.0})
	check(is_equal_approx(fp.get("_net_x"), -8.8), "R-50 FreightPlatform rejects NaN snapshot")
	fp.apply_net_state({"x": 999.0, "y": 2.6, "speed": 0.0, "roll": 0.0, "pitch": 0.0})
	check(is_equal_approx(fp.get("_net_x"), -8.8), "R-50 FreightPlatform rejects out-of-range x snapshot")
	var client_crystal: PortableCrystal = PortableCrystal.new()
	client_crystal.add_to_group("portable_crystal")
	root.add_child(client_crystal)
	client_crystal.global_position = Vector3(-8.8, 2.7, 3.0)
	fp.apply_net_state({
		"x": -8.8, "y": 2.6, "speed": 0.0, "roll": 0.0, "pitch": 0.0,
		"cargo": true, "cargo_pos": Vector3(-8.8, 2.8, 3.0), "cargo_rot": Vector3.ZERO,
	})
	check(client_crystal.freeze and client_crystal.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
		"R-46 non-authority FreightPlatform freezes mirrored cargo kinematically")
	client_crystal.queue_free()
	fp.queue_free()

	# R-47: EchoPlayer remote update rejects NaN & caps step <= 0.35 m
	InputSetup.ensure_actions()
	var ep: EchoPlayer = EchoPlayer.new()
	ep.input_enabled = false
	root.add_child(ep)
	await frames(2)
	ep.global_position = Vector3(0.0, 0.0, 0.0)
	ep.update_remote_state(Vector3(NAN, 0.0, 0.0), 0.0, Vector3.ZERO, false, false)
	check(ep.global_position.is_finite(), "R-47 EchoPlayer rejects NaN remote position")
	ep.update_remote_state(Vector3(2.0, 0.0, 0.0), 0.5, Vector3.ZERO, false, false)
	check(ep.global_position.x <= 0.36, "R-47 EchoPlayer caps per-tick remote interpolation step", {"x": ep.global_position.x})
	ep.queue_free()

	# R-53 part 2: CoopNet shutdown clears _signals_wired
	var cnet: CoopNet = CoopNet.new()
	root.add_child(cnet)
	cnet.set("_signals_wired", true)
	cnet.shutdown()
	check(not bool(cnet.get("_signals_wired")), "R-53 CoopNet.shutdown clears _signals_wired")
	cnet.queue_free()

	# R-49: CoopSnapshotWire encodes Act4 snapshot shape cleanly under 1200 B
	var sample_act4: Dictionary = {
		"seq": 1, "players": {1: {"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "grab": false, "carry": false}},
		"platform": {"x": -8.8, "y": 2.6, "speed": 0.0, "roll": 0.0, "pitch": 0.0},
		"crystal_a_pos": Vector3(1, 0, 1), "crystal_b_pos": Vector3(-1, 0, -1),
		"crystal_a_carrier": 0, "crystal_b_carrier": 0,
		"memories": {}, "stage": 1, "gate_open": false, "strikes": 0, "completed": false,
		"reset_seq": 0, "peer_count": 1,
	}
	var pkts: Array[Dictionary] = CoopSnapshotWire.encode_packets(1, sample_act4, false)
	check(pkts.size() == 1 and var_to_bytes(pkts[0]).size() <= CoopSnapshotWire.MAX_PACKET_BYTES,
		"R-49 Act4 snapshot encodes cleanly via CoopSnapshotWire under MTU")
	await frames(1)
