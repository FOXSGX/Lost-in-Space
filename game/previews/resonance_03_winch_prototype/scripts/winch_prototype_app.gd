extends Node3D

# -----------------------------------------------------------------------------
# WinchPrototypeApp - the playable entry point.
#
# Responsibilities, kept deliberately small:
#   * assemble the test bay (world, winch, rail, cable, lock station, player)
#   * route input to the rig: proximity-gated E (hook / console / socket),
#     W/S drum, Space brake, Q release, F lock, R reset
#   * own the pause menu and the reset path
#   * drive the winch audio
# It holds no simulation state of its own; everything it displays comes from the
# rig, so the mission can be reset at any time without the app desynchronising.
# -----------------------------------------------------------------------------

const Kit := preload("res://scripts/build/mesh_kit.gd")
const SceneBuilder := preload("res://scripts/build/winch_scene.gd")
const RailScript := preload("res://scripts/winch/misaligned_rail.gd")
const RailAssemblyScript := preload("res://scripts/winch/rail_assembly.gd")
const WinchStationScript := preload("res://scripts/winch/winch_station.gd")
const WinchMachineScript := preload("res://scripts/winch/winch_machine.gd")
const CableScript := preload("res://scripts/winch/winch_cable.gd")
const RigScript := preload("res://scripts/winch/winch_rig.gd")
const PlayerScript := preload("res://scripts/player/ranger_player.gd")
const HudScript := preload("res://scripts/ui/winch_hud.gd")

const HOOK_RANGE: float = 3.4
const CONSOLE_RANGE: float = 2.8
const LOCK_RANGE: float = 3.0
const SPAWN: Vector3 = Vector3(0.6, 0.3, 5.2)

var world: Node3D
var rail_assembly: Node3D
var rail_body: AnimatableBody3D
var winch_station: Node3D
var machine: Node3D
var cable: Node3D
var rig: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var lock_station: Node3D
var lock_beacon: MeshInstance3D
var lock_light: OmniLight3D
var _lock_mat_off: StandardMaterial3D
var _lock_mat_amber: StandardMaterial3D
var _lock_mat_green: StandardMaterial3D

var paused: bool = false
var at_console: bool = false
var _reset_cooldown: float = 0.0
var _audio: Dictionary = {}
var _haul_stream: AudioStreamPlayer3D
var _strain_stream: AudioStreamPlayer3D
var _one_shot: AudioStreamPlayer
var _slip_timer: float = 0.0

func _ready() -> void:
	_build_world()
	_build_rail()
	_build_winch()
	_build_player()
	_build_rig()
	_build_hud()
	_build_audio()
	_configure_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rig.connect("feedback", _on_feedback)
	rig.connect("mission_completed", _on_mission_completed)
	hud.call("show_feedback", "轨道卡在碎石里。先走近看看断裂处。", "info")
	_maybe_start_demo()

func _maybe_start_demo() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var demo_mode: String = ""
	var demo_out: String = ""
	for arg: String in args:
		if arg.begins_with("--demo="):
			demo_mode = arg.trim_prefix("--demo=")
		elif arg.begins_with("--demo-out="):
			demo_out = arg.trim_prefix("--demo-out=")
	if demo_mode.is_empty():
		return
	var driver_script: Script = load("res://scripts/demo/demo_driver.gd") as Script
	if driver_script == null:
		return
	var driver: Node = Node.new()
	driver.name = "DemoDriver"
	driver.set_script(driver_script)
	driver.set("mode", demo_mode)
	driver.set("output_file", demo_out)
	add_child(driver)

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	world.set_script(SceneBuilder)
	add_child(world)
	world.call("build")

func _build_rail() -> void:
	rail_body = AnimatableBody3D.new()
	rail_body.name = "RailBody"
	rail_body.set_script(RailScript)
	rail_body.position = Vector3.ZERO

	rail_assembly = Node3D.new()
	rail_assembly.name = "RailAssembly"
	rail_assembly.set_script(RailAssemblyScript)
	rail_assembly.set("moving_body_path", NodePath("RailBody"))
	rail_assembly.add_child(rail_body)
	world.add_child(rail_assembly)

func _build_winch() -> void:
	machine = Node3D.new()
	machine.name = "Machine"
	machine.set_script(WinchMachineScript)

	winch_station = Node3D.new()
	winch_station.name = "WinchStation"
	winch_station.set_script(WinchStationScript)
	winch_station.set("machine_path", NodePath("Machine"))
	winch_station.position = Vector3(-2.6, 0.0, 3.4)
	winch_station.rotation.y = deg_to_rad(-34.0)
	winch_station.add_child(machine)
	world.add_child(winch_station)

	cable = Node3D.new()
	cable.name = "Cable"
	cable.set_script(CableScript)
	world.add_child(cable)

	lock_station = Node3D.new()
	lock_station.name = "LockStation"
	lock_station.position = Vector3(7.05, 0.0, 1.16)
	world.add_child(lock_station)
	Kit.box(lock_station, "LockPost", Vector3(0.20, 1.05, 0.20), Vector3(0, 0.52, 0), Kit.material(Color(0.30, 0.32, 0.34), 0.7, 0.45))
	Kit.box(lock_station, "LockPlate", Vector3(0.42, 0.10, 0.42), Vector3(0, 1.10, 0), Kit.material(Color(0.80, 0.55, 0.16), 0.4, 0.5))
	Kit.box(lock_station, "LockLeverBase", Vector3(0.12, 0.12, 0.12), Vector3(0.28, 0.78, 0), Kit.material(Color(0.22, 0.24, 0.26), 0.7, 0.45))
	Kit.cylinder(lock_station, "LockLever", 0.035, 0.55, Vector3(0.36, 0.98, 0), Kit.material(Color(0.85, 0.58, 0.18), 0.5, 0.4), "x", 10)
	Kit.box(lock_station, "LockLeverGrip", Vector3(0.10, 0.10, 0.22), Vector3(0.64, 1.05, 0), Kit.material(Color(0.10, 0.11, 0.12), 0.4, 0.6))
	_lock_mat_off = Kit.material(Color(0.10, 0.12, 0.13), 0.5, 0.6)
	_lock_mat_amber = Kit.material(Color(0.95, 0.62, 0.16), 0.1, 0.35, Color(1.0, 0.55, 0.10), 2.0)
	_lock_mat_green = Kit.material(Color(0.24, 0.92, 0.52), 0.1, 0.3, Color(0.18, 1.0, 0.45), 2.2)
	lock_beacon = Kit.sphere(lock_station, "LockBeacon", 0.09, Vector3(0, 1.36, 0), _lock_mat_off)
	lock_light = OmniLight3D.new()
	lock_light.name = "LockLight"
	lock_light.position = Vector3(0, 1.55, 0)
	lock_light.omni_range = 4.0
	lock_light.light_energy = 0.0
	lock_light.light_color = Color(0.3, 1.0, 0.5)
	lock_station.add_child(lock_light)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PlayerScript)
	player.position = SPAWN
	player.rotation.y = -0.18
	player.set("_camera_yaw", -0.18)
	player.set("_camera_yaw_target", -0.18)
	world.add_child(player)

func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "WinchRig"
	rig.set_script(RigScript)
	rig.set("winch_path", NodePath("../WinchStation/Machine"))
	rig.set("rail_path", NodePath("../RailAssembly/RailBody"))
	rig.set("cable_path", NodePath("../Cable"))
	rig.set("sheave_path", NodePath("../WinchStation/Sheave"))
	rig.set("player_path", NodePath("../Player"))
	world.add_child(rig)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "Hud"
	hud.set_script(HudScript)
	add_child(hud)

func _configure_hud() -> void:
	hud.set("rig", rig)
	hud.set("player", player)

func _build_audio() -> void:
	_audio = {
		"hum": load("res://assets/audio/hum.wav") as AudioStream,
		"latch": load("res://assets/audio/latch.wav") as AudioStream,
		"error": load("res://assets/audio/error.wav") as AudioStream,
		"ready": load("res://assets/audio/ready.wav") as AudioStream,
		"segment": load("res://assets/audio/segment.wav") as AudioStream,
		"charge": load("res://assets/audio/charge.wav") as AudioStream,
	}
	_haul_stream = AudioStreamPlayer3D.new()
	_haul_stream.name = "HaulLoop"
	_haul_stream.stream = _audio["hum"] as AudioStream
	_haul_stream.unit_size = 6.0
	_haul_stream.max_db = 2.0
	_haul_stream.volume_db = -60.0
	_haul_stream.position = machine.position
	add_child(_haul_stream)
	_strain_stream = AudioStreamPlayer3D.new()
	_strain_stream.name = "StrainLoop"
	_strain_stream.stream = _audio["hum"] as AudioStream
	_strain_stream.unit_size = 7.0
	_strain_stream.max_db = 0.0
	_strain_stream.volume_db = -60.0
	_strain_stream.position = machine.position
	add_child(_strain_stream)
	_one_shot = AudioStreamPlayer.new()
	_one_shot.name = "OneShot"
	add_child(_one_shot)

func _play(sound_name: String, volume_db: float = -6.0) -> void:
	if not _audio.has(sound_name):
		return
	_one_shot.stream = _audio[sound_name] as AudioStream
	_one_shot.volume_db = volume_db
	_one_shot.play()

# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_toggle_pause()
		return
	if paused:
		return
	if event.is_action_pressed("toggle_help"):
		hud.call("toggle_help")
		return
	if event.is_action_pressed("toggle_debug"):
		hud.call("toggle_debug")
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		return
	if event.is_action_pressed("winch_brake"):
		rig.call("toggle_brake")
		_play("latch", -10.0)
		return
	if event.is_action_pressed("winch_release"):
		rig.call("detach_cable")
		at_console = false
		player.call("set_operating", null)
		_play("latch", -10.0)
		return
	if event.is_action_pressed("reset_mission"):
		_reset_mission()
		return

func _try_interact() -> void:
	# Pick the nearest thing the player can actually use. Fixed priorities made
	# the already-hooked far eye steal the "install lock" press, because the lock
	# socket stands barely three metres away from it.
	var target: Dictionary = _nearest_interaction()
	match str(target.get("kind", "")):
		"anchor":
			var anchor: Node3D = target.get("anchor") as Node3D
			var result: Dictionary = rig.call("attach_cable", str(anchor.get("anchor_id"))) as Dictionary
			if bool(result.get("ok", false)):
				_play("latch", -6.0)
				at_console = false
				player.call("set_operating", null)
			else:
				_play("error", -12.0)
			return
		"lock":
			var lock_result: Dictionary = rig.call("try_install_lock") as Dictionary
			if bool(lock_result.get("ok", false)):
				_play("ready", -6.0)
			else:
				_play("error", -12.0)
			return
		"console":
			at_console = not at_console
			player.call("set_operating", winch_station if at_console else null)
			_play("segment", -12.0)
			hud.call("show_feedback", "已接管绞盘" if at_console else "已离开绞盘", "info")
			return
	hud.call("show_feedback", "这里没有可以操作的装置", "warn")

func _nearest_interaction() -> Dictionary:
	var best: Dictionary = {"kind": "", "distance": 1.0e9, "anchor": null}
	var machine: Node3D = rig.get("winch") as Node3D
	var cable_attached: bool = machine != null and bool(machine.get("attached"))
	# Before the cable is hooked, the lifting eyes are the only sensible target.
	# Otherwise the lock socket (only ~3 m from the far eye) steals the prompt and
	# the player cannot connect the cable at all.
	if not cable_attached:
		for node: Node in get_tree().get_nodes_in_group("winch_anchor"):
			var anchor: Node3D = node as Node3D
			if anchor == null or bool(anchor.get("occupied")):
				continue
			var at: Vector3 = anchor.call("attach_point") as Vector3
			var distance: float = player.global_position.distance_to(at)
			if distance <= HOOK_RANGE and distance < float(best["distance"]):
				best = {"kind": "anchor", "distance": distance, "anchor": anchor}
		if str(best["kind"]) == "anchor":
			return best
	var socket_distance: float = player.global_position.distance_to(lock_station.global_position)
	if socket_distance <= LOCK_RANGE and socket_distance < float(best["distance"]):
		best = {"kind": "lock", "distance": socket_distance, "anchor": null}
	var console_distance: float = player.global_position.distance_to(winch_station.global_position)
	if console_distance <= CONSOLE_RANGE and console_distance < float(best["distance"]):
		best = {"kind": "console", "distance": console_distance, "anchor": null}
	return best

func _physics_process(delta: float) -> void:
	if rig == null or hud == null:
		return
	_reset_cooldown = maxf(0.0, _reset_cooldown - delta)
	# Keep the console stance honest: walking away releases control.
	if at_console and player.global_position.distance_to(winch_station.global_position) > CONSOLE_RANGE + 0.9:
		at_console = false
		player.call("set_operating", null)
	# Held keys are polled, not edge-triggered: W/S are continuous controls, and
	# polling keeps the same behaviour for real keys and for scripted input.
	var operating: bool = at_console and not paused
	rig.call("set_winch_input", "haul", operating and Input.is_action_pressed("winch_haul"))
	rig.call("set_winch_input", "payout", operating and Input.is_action_pressed("winch_payout"))
	rig.call("set_winch_input", "creep", operating and Input.is_action_pressed("sprint"))
	player.set("camera_shoulder_offset", 1.15 if at_console else 0.0)
	_update_interaction_prompt()
	_update_lock_beacon()
	_update_haul_audio(delta)

func _update_lock_beacon() -> void:
	if lock_beacon == null or rig == null:
		return
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	var lockable: bool = bool(rail.get("lockable", false)) or bool(rig.get("completed"))
	var in_band: bool = bool(rail.get("in_band", false))
	lock_beacon.material_override = _lock_mat_green if lockable else (_lock_mat_amber if in_band else _lock_mat_off)
	if lock_light != null:
		lock_light.light_energy = 1.0 if lockable else (0.35 if in_band else 0.0)

func _update_interaction_prompt() -> void:
	var text: String = ""
	var target: Dictionary = _nearest_interaction()
	var target_anchor: Node3D = null
	if str(target.get("kind", "")) == "anchor":
		target_anchor = target.get("anchor") as Node3D
	for node: Node in get_tree().get_nodes_in_group("winch_anchor"):
		var anchor: Node3D = node as Node3D
		if anchor != null and anchor.has_method("set_highlight"):
			anchor.call("set_highlight", not at_console and anchor == target_anchor)
	if paused:
		text = ""
	elif at_console:
		text = "W 收缆 · S 放线 · Shift 微调 · 空格刹车 · E 离开绞盘"
	else:
		match str(target.get("kind", "")):
			"anchor":
				text = "E 连接缆绳 · %s" % str(target_anchor.get("display_name"))
			"lock":
				var rail: Dictionary = rig.call("alignment_state") as Dictionary
				text = "E 插入锁定销" if bool(rail.get("lockable", false)) else "E 检查锁定机构"
			"console":
				text = "E 接管绞盘"
			_:
				var attached_anchor: Node3D = _nearby_attached_anchor()
				if attached_anchor != null:
					text = "Q 松开缆绳 · %s" % str(attached_anchor.get("display_name"))
				else:
					text = "走近装置按 E 互动 · F1 查看操作"
	hud.call("set_prompt", text)

func _nearby_attached_anchor() -> Node3D:
	if rig == null:
		return null
	var machine: Node3D = rig.get("winch") as Node3D
	if machine == null:
		return null
	var anchor: Node3D = machine.get("anchor") as Node3D
	if anchor == null:
		return null
	var at: Vector3 = anchor.call("attach_point") as Vector3
	if player.global_position.distance_to(at) > HOOK_RANGE:
		return null
	return anchor

func _update_haul_audio(delta: float) -> void:
	if _haul_stream == null:
		return
	var winch: Dictionary = rig.call("tension_state") as Dictionary
	var mode: String = str(winch.get("mode", "idle"))
	var ratio: float = float(winch.get("tension_ratio", 0.0))
	var stalled: bool = bool(winch.get("stalled", false))
	var active: bool = mode == "haul" or mode == "payout" or mode == "stall"
	var target: float = -60.0
	if active:
		target = -12.0
		if not _haul_stream.playing:
			_haul_stream.play()
	_haul_stream.pitch_scale = 0.85 + ratio * 0.55
	_haul_stream.volume_db = lerpf(_haul_stream.volume_db, target, 0.12)
	if _haul_stream.volume_db < -55.0 and _haul_stream.playing:
		_haul_stream.stop()

	# A lower, slower strain layer fades in as the cable loads up, so tension is
	# audible before the HUD bar fills.
	if _strain_stream != null:
		var strain_target: float = -60.0
		if bool(winch.get("attached", false)) and (ratio > 0.45 or stalled):
			strain_target = -24.0 + ratio * 9.0
			if not _strain_stream.playing:
				_strain_stream.play()
		_strain_stream.pitch_scale = 0.58 + ratio * 0.18
		_strain_stream.volume_db = lerpf(_strain_stream.volume_db, strain_target, 0.08)
		if _strain_stream.volume_db < -55.0 and _strain_stream.playing:
			_strain_stream.stop()

	if stalled:
		_slip_timer -= delta
		if _slip_timer <= 0.0:
			_slip_timer = 1.15
			_play("error", -20.0)
	else:
		_slip_timer = 0.0

func _on_feedback(text: String, tone: String) -> void:
	if hud != null:
		hud.call("show_feedback", text, tone)
	if tone == "error":
		_play("error", -16.0)

func _on_mission_completed() -> void:
	_play("ready", -4.0)
	rig.call("set_winch_input", "haul", false)

func _reset_mission() -> void:
	if _reset_cooldown > 0.0:
		return
	_reset_cooldown = 0.6
	rig.call("reset_mission")
	at_console = false
	player.call("set_operating", null)
	player.call("teleport_to", SPAWN, -0.18)
	_play("segment", -10.0)

func _toggle_pause() -> void:
	paused = not paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	player.set("paused", paused)
	if paused:
		rig.call("set_winch_input", "haul", false)
		rig.call("set_winch_input", "payout", false)
		_haul_stream.stop()
		if _strain_stream != null:
			_strain_stream.stop()
