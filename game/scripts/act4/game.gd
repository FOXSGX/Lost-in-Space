class_name ResonanceGame
extends Node3D
## Level orchestration for Resonance 04.
##
## Authoritative state (network, cradle occupancy, memory progress, exit) lives
## here and in ResonanceModel, not in the HUD or camera. A future multiplayer
## layer only needs to relay strike/seating/reset intents and let every client
## replay the same deterministic resonance events.

const STORY_PATH := "res://assets/story/story.json"
const SPAWN := R04LevelBuilder.SPAWN

var story: Dictionary = {}
var data: Dictionary = {}
var model: ResonanceModel
var network: ResonanceNetwork
var crystals: Dictionary = {}
var cradles: Dictionary = {}
var crystal_a: PortableCrystal
var crystal_b: PortableCrystal
var hammer: HammerRig
var gate: ExitGate
var memory: MemoryDirector
var player: EchoPlayer
var hud: EchoHUD
var audio: R04Audio
var platform: FreightPlatform
var freight_data: Dictionary = {}

var stage: int = 0
var seen_memories: Dictionary = {}
var memory_queue: Array[int] = []
var current_memory: int = 0
var completed: bool = false
var completion_seconds: float = 0.0
var game_time: float = 0.0
var reset_count: int = 0

# --- Act 4 co-op (same SessionHub session as Act 5) -------------------------
# Two processes bind the same CoopNet. The HOST owns all mission state: the
# hammer wave / memories / stage / gate, freight platform authority, crystal
# ownership (one holder) and cradle seats. The client mirrors the host snapshot
# and forwards real actions (strike, pickup, seat) as validated intents.
var coop_mode: String = "solo"      # solo | host | client
var coop_net: CoopNet = null
var coop_players: Dictionary = {}   # pid -> EchoPlayer (local + remote body)
var remote_player: EchoPlayer = null
var coop_host_port: int = CoopNet.PORT_DEFAULT
var coop_address: String = "127.0.0.1"
# Act 4 join telemetry: how many reliable initial-state payloads this process
# applied (client) / how many it served to a joining client (host).
var act4_bootstrap_count: int = 0
var act4_sync_requests: int = 0
var _act4_frame: int = 0
var _last_accident_phase: int = 0
var _act4_seen_at_gate: Dictionary = {}
var _last_gate_toast_ms: int = 0
# Client mirror observability: remember which pids this client has already
# logged as phase-04-ready so authority sync is printed once per pid.
var _act4_ready04_seen: Dictionary = {}
# Client platform lever stream is rate limited (the raw per-frame send was 60
# reliable RPCs/s and could starve the strike intent on the same channel).
var _act4_platform_axis_clock: float = 0.0
var _act4_last_axis_sent: float = 0.0

var _dead_end_count: int = 0
var _last_hint_ms: int = 0
var _next_memory_timer: float = 0.0
const Act4PhysicalLinks := preload("res://scripts/act4/physical_links.gd")
var _alcove_lamp: OmniLight3D
var _crystal_b_lamp: OmniLight3D
var _ledge_lamp: OmniLight3D
var _physical_links: Act4PhysicalLinks


func _ready() -> void:
	name = "Resonance04"
	InputSetup.ensure_actions()
	_load_story()
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = load("res://resources/cave_environment.tres") as Environment
	add_child(world)

	audio = R04Audio.new()
	add_child(audio)

	var builder: R04LevelBuilder = R04LevelBuilder.new()
	data = builder.build(self)
	model = data["model"] as ResonanceModel
	network = data["network"] as ResonanceNetwork
	crystals = data["crystals"] as Dictionary
	cradles = data["cradles"] as Dictionary
	crystal_a = data["crystal_a"] as PortableCrystal
	crystal_b = data["crystal_b"] as PortableCrystal
	hammer = data["hammer"] as HammerRig
	gate = data["gate"] as ExitGate
	freight_data = data["freight"] as Dictionary
	platform = data["platform"] as FreightPlatform

	memory = MemoryDirector.new()
	add_child(memory)
	memory.build(data)

	_physical_links = Act4PhysicalLinks.new()
	add_child(_physical_links)
	_physical_links.build(self)

	player = EchoPlayer.new()
	player.position = SPAWN
	add_child(player)
	player.spawn_position = SPAWN
	player.teleport(SPAWN, 0.0)

	hud = EchoHUD.new()
	add_child(hud)

	const Act4ExploreProps := preload("res://scripts/act4/act4_explore_props.gd")
	var explore := Act4ExploreProps.new() as Node3D
	add_child(explore)
	explore.setup(self, hud)

	_connect_signals()
	_apply_story_texts()
	_find_guide_lights()
	hud.set_objective(_objective("start"))
	hud.show_view_settings(false, player.mouse_sensitivity, player.invert_y)
	_reset_memory_lights()
	_setup_coop()
	if "--packaged-smoke" in OS.get_cmdline_user_args():
		_run_packaged_smoke()
	elif "--smoke" in OS.get_cmdline_args() or "--smoke" in OS.get_cmdline_user_args():
		_run_smoke_capture()
	elif "--smoke-play" in OS.get_cmdline_args() or "--smoke-play" in OS.get_cmdline_user_args():
		_run_smoke_play()


## Packaged-build acceptance (Act 4 half): after the launcher hands off into
## this scene, capture the entered cave and quit.
func _run_packaged_smoke() -> void:
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# Take the destination from the caller (or user://) so a packaged build never
	# writes to a developer's absolute desktop path.
	var out_dir: String = ""
	for arg_value in OS.get_cmdline_user_args():
		var arg: String = str(arg_value)
		if arg.begins_with("--shot-dir="):
			out_dir = arg.split("=", true, 1)[1]
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("user://packaged_smoke")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if img != null:
		img.save_png(out_dir + "/act4_entered.png")
		print("PKG_SHOT act4_entered")
	print("PACKAGED_SMOKE_DONE scene=", name)
	get_tree().quit()


## Packaged-build acceptance: drives the real input map inside the exported PCK
## and writes a JSON verdict next to the executable. A screenshot alone cannot
## prove that the camera, movement, hammer and crystal pickup still work.
func _run_smoke_play() -> void:
	var checks: Dictionary = {}
	await get_tree().create_timer(1.0).timeout
	var forward_before: float = -player.camera.global_transform.basis.z.y
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(0.0, -80.0)
	motion.screen_relative = Vector2(0.0, -80.0)
	Input.parse_input_event(motion)
	await get_tree().create_timer(0.15).timeout
	checks["mouse_up_looks_up"] = (-player.camera.global_transform.basis.z.y) > forward_before + 0.05
	checks["mouse_captured"] = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	var start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.9).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.2).timeout
	checks["moves"] = player.global_position.distance_to(start) > 1.0

	player.teleport(Vector3(2.25, 0.2, -1.2), 0.0)
	player.aim_camera_at(Vector3(2.25, 1.2, -4.5), -0.08)
	await get_tree().create_timer(0.6).timeout
	Input.action_press("interact")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.3).timeout
	checks["hammer_grabbed"] = hammer.mode == "held"
	Input.action_press("move_forward")
	await get_tree().create_timer(1.1).timeout
	Input.action_release("move_forward")
	Input.action_press("interact")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("interact")
	await get_tree().create_timer(3.0).timeout
	checks["hammer_struck"] = hammer.strike_count >= 1
	checks["hammer_settled"] = hammer.mode == "idle"

	# Suspended freight platform: board, take the handle and ride it. This is
	# the packaged-build proof that the moving collider still carries a player.
	player.teleport(Vector3(-8.8, 2.66, 2.5), 0.0)
	await get_tree().create_timer(0.55).timeout
	var platform_start: float = platform.travel_x
	player.aim_camera_at(platform.to_global(Vector3(-1.02, 1.10, -0.50)), -99.0)
	await get_tree().create_timer(0.45).timeout
	Input.action_press("interact")
	await get_tree().create_timer(0.14).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.25).timeout
	checks["freight_handle"] = player.platform_control == platform
	Input.action_press("move_forward")
	await get_tree().create_timer(1.3).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.2).timeout
	checks["freight_moves"] = platform.travel_x < platform_start - 0.4
	checks["freight_rides_player"] = player.global_position.y > 2.2
	Input.action_press("interact")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.25).timeout

	# The carryable crystal now starts on the far loading dock.
	player.teleport(Vector3(-17.2, 2.66, 3.0), 0.0)
	await get_tree().create_timer(0.55).timeout
	player.aim_camera_at(crystal_a.global_position + Vector3(0.0, 0.6, 0.0), -99.0)
	await get_tree().create_timer(0.3).timeout
	Input.action_press("pickup")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("pickup")
	await get_tree().create_timer(0.3).timeout
	checks["crystal_picked"] = player.carrying != null
	Input.action_press("pickup")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("pickup")
	await get_tree().create_timer(0.4).timeout
	checks["crystal_dropped"] = player.carrying == null

	reset_level()
	await get_tree().create_timer(0.6).timeout
	checks["reset_ok"] = stage == 0 and crystal_a.global_position.distance_to(R04LevelBuilder.CRYSTAL_A_SPAWN) < 1.5
	checks["player_back_at_spawn"] = player.global_position.distance_to(R04LevelBuilder.SPAWN) < 1.0
	checks["freight_reset"] = absf(platform.travel_x - FreightArena.NEAR_PARK_X) < 0.1 and not platform.cargo_attached

	var passed: bool = true
	for key: Variant in checks.keys():
		if not bool(checks[key]):
			passed = false
	var payload: Dictionary = {
		"passed": passed,
		"checks": checks,
		"strikes": hammer.strike_count,
		"engine": Engine.get_version_info()["string"],
	}
	var path: String = OS.get_executable_path().get_base_dir().path_join("smokeplay.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()
	print("SMOKEPLAY_RESULT ", JSON.stringify(payload))
	get_tree().quit(0 if passed else 1)


func _run_smoke_capture() -> void:
	await get_tree().create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var base_dir: String = OS.get_executable_path().get_base_dir()
	var path: String = base_dir.path_join("smoke_capture.png")
	image.save_png(path)
	print("SMOKE_CAPTURE ", path, " ", image.get_width(), "x", image.get_height())
	get_tree().quit(0)


func _load_story() -> void:
	var text: String = FileAccess.get_file_as_string(STORY_PATH)
	if text.is_empty():
		push_error("Story JSON missing: " + STORY_PATH)
		return
	story = JSON.parse_string(text) as Dictionary


func _apply_story_texts() -> void:
	if hud != null:
		hud.show_prompt("")


func _find_guide_lights() -> void:
	_alcove_lamp = find_child("AlcoveLamp", true, false) as OmniLight3D
	_crystal_b_lamp = find_child("CrystalBLamp", true, false) as OmniLight3D
	_ledge_lamp = find_child("LedgeLamp", true, false) as OmniLight3D


func _reset_memory_lights() -> void:
	if _alcove_lamp != null:
		_alcove_lamp.light_energy = 0.85
	if _crystal_b_lamp != null:
		_crystal_b_lamp.light_energy = 0.0
	if _ledge_lamp != null:
		_ledge_lamp.light_energy = 0.0


func _connect_signals() -> void:
	player.prompt_changed.connect(_on_player_prompt)
	player.interactable_changed.connect(_on_player_target)
	player.menu_toggled.connect(_on_menu_toggled)
	player.view_settings_changed.connect(_on_view_settings_changed)
	hammer.struck.connect(_on_hammer_struck)
	hammer.grabbed.connect(_on_hammer_grabbed)
	hammer.released.connect(_on_hammer_released)
	hammer.weak_swing.connect(_on_weak_swing)
	network.memory_reached.connect(_on_memory_reached)
	network.dead_end.connect(_on_dead_end)
	network.weak_memory.connect(_on_weak_memory)
	network.wave_started.connect(_on_wave_started)
	gate.player_entered.connect(_on_exit_entered)
	memory.memory_started.connect(_on_memory_started)
	memory.memory_finished.connect(_on_memory_finished)
	memory.subtitle_requested.connect(_on_subtitle)
	memory.camera_shake.connect(_on_memory_shake)
	memory.exit_opened.connect(_on_exit_opened)
	for key: Variant in cradles.keys():
		var cradle: ResonanceCradle = cradles[key] as ResonanceCradle
		cradle.seated.connect(_on_cradle_seated)
		cradle.released.connect(_on_cradle_released)
	gate.add_to_group("interactable")
	if platform != null:
		platform.notice.connect(_on_freight_notice)
		platform.accident_warning_started.connect(_on_freight_warning)
		platform.accident_shock.connect(_on_freight_shock)
		platform.cargo_state_changed.connect(_on_freight_cargo_changed)
		platform.control_changed.connect(_on_freight_control_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_level"):
		reset_level()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F3:
		_debug_blocker_probe()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		# The player owns Esc (it toggles the view-settings overlay and the
		# capture state). This handler only guarantees the cursor is released if
		# the player node was removed.
		if player == null or not is_instance_valid(player):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Debug aid asked for by the first-person brief: F3 reports what is actually in
## front of the lens (object name, collision layer, shape, contact point) and
## what overlaps the eye. It prints to the console and shows a HUD toast, so a
## tester can identify an invisible blocker without opening the editor.
func _debug_blocker_probe() -> void:
	if player == null or player.camera == null:
		return
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	ray.from = eye
	ray.to = eye + forward * 3.0
	ray.collision_mask = 1
	ray.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(ray)
	var text: String = "位置 %s · 目标 %s" % [
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
		str(player.current_target.name) if player.current_target != null else "无"
	]
	if hit.is_empty():
		text += " · 前方 3m 无阻挡"
	else:
		var collider: Node = hit.get("collider") as Node
		var layer: int = 0
		var shape: String = "静态体"
		if collider is CollisionObject3D:
			layer = (collider as CollisionObject3D).collision_layer
			for child: Node in collider.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
					shape = (child as CollisionShape3D).shape.get_class()
					break
		text += " · 阻挡 %s  层=%d  形状=%s  接触=%s" % [
			collider.name if collider != null else "?", layer, shape,
			str((hit.get("position") as Vector3).snapped(Vector3(0.01, 0.01, 0.01)))
		]
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.30
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), eye)
	params.collision_mask = 1
	params.exclude = [player.get_rid()]
	var overlaps: Array[Dictionary] = space.intersect_shape(params, 2)
	if not overlaps.is_empty():
		var near_collider: Node = overlaps[0].get("collider") as Node
		text += " · 眼睛 0.30m 内有 %s" % (near_collider.name if near_collider != null else "?")
	print("DEBUG_BLOCKER ", text)
	if hud != null:
		hud.show_toast(text, 5.0)


func _on_menu_toggled(open: bool) -> void:
	if hud != null:
		hud.show_view_settings(open, player.mouse_sensitivity, player.invert_y)


func _on_view_settings_changed(sensitivity: float, invert: bool) -> void:
	if hud != null and player != null and player.is_menu_open():
		hud.show_view_settings(true, sensitivity, invert)


func _process(delta: float) -> void:
	game_time += delta
	_act4_frame += 1
	if _next_memory_timer > 0.0:
		_next_memory_timer -= delta
		if _next_memory_timer <= 0.0:
			_start_next_memory()
	if coop_mode == "host":
		_act4_host_tick(delta)
	elif coop_mode == "client":
		_act4_client_tick(delta)


func _physics_process(_delta: float) -> void:
	if player != null and player.global_position.y < FreightArena.PIT_FLOOR_Y - 2.8 and not completed:
		if player.carrying != null:
			player.drop_carried(false)
		player.teleport(SPAWN, 0.0)


func _on_player_prompt(text: String) -> void:
	if hud != null:
		hud.show_prompt(text)


func _on_player_target(_target: Node) -> void:
	pass


func _on_hammer_grabbed() -> void:
	if hud != null:
		hud.show_prompt("按住 W 拉索   ·   E 松开撞锤   ·   S 放回")


func _on_hammer_released() -> void:
	if hud != null:
		hud.show_prompt("")


func _on_weak_swing() -> void:
	_toast("weak_hammer")


func _on_hammer_struck(strength: float, impact_position: Vector3) -> void:
	# Co-op: mission state is host-authoritative. The client's local hammer still
	# swings and strikes (its own physical rig), but it forwards the strike to
	# the host, which applies it to the shared ResonanceNetwork and broadcasts
	# the resulting memory/stage. The client never runs the wave locally.
	if coop_mode == "client" and coop_net != null:
		# The local hammer already struck. Forward it; the host decides whether
		# the strike is applied and whether this pid earns phase-04.
		coop_net.act4_submit_action("hammer_strike", "", strength)
		print("ACT4 client strike forwarded pid=%d strength=%.2f" % [
			coop_net.local_pid, strength])
		return
	if network == null:
		return
	network.strike("bell", strength)
	_act4_credit_strike(1)
	if player != null:
		var distance: float = player.global_position.distance_to(impact_position)
		if distance < 22.0:
			player.shake(clampf(0.28 - distance * 0.008, 0.06, 0.28), 0.36)
	if strength < 0.56:
		_toast("weak_hammer")


func _on_wave_started(source_id: String, strength: float) -> void:
	if _physical_links != null:
		_physical_links.pulse_wave(source_id)
	if source_id == "bell" and strength < 0.5:
		_toast("weak_hammer")


func _on_memory_reached(memory_index: int, _amplitude: float, node_id: String) -> void:
	var crystal: EchoCrystal = crystals.get(node_id) as EchoCrystal
	if crystal != null:
		crystal.set_memory_awake(true)
	if bool(seen_memories.get(memory_index, false)):
		return
	if memory_index in memory_queue or memory_index == current_memory:
		return
	memory_queue.append(memory_index)
	_start_next_memory()


func _start_next_memory() -> void:
	if memory == null or memory.playing or memory_queue.is_empty():
		return
	var index: int = memory_queue.pop_front()
	current_memory = index
	memory.play(index)


func _on_memory_started(index: int) -> void:
	if hud != null:
		hud.show_memory_title(memory.get_memory_title(index))
		hud.set_controls_visible(false)


func _on_memory_finished(index: int) -> void:
	seen_memories[index] = true
	current_memory = 0
	if hud != null:
		hud.set_controls_visible(true)
	match index:
		1:
			stage = maxi(stage, 1)
			_set_objective("memory_1")
			if _alcove_lamp != null:
				_alcove_lamp.light_energy = 1.5
			_toast("memory_1")
			if hud != null:
				hud.show_subtitle("矿工 · 通讯残响", "西侧装货台被断层切开了。启动悬吊货运平台，把晶体吊回来。", 7.0)
		2:
			stage = maxi(stage, 3)
			_set_objective("memory_2")
			if _crystal_b_lamp != null:
				_crystal_b_lamp.light_energy = 1.5
			if _ledge_lamp != null:
				_ledge_lamp.light_energy = 1.2
			_toast("memory_2")
		3:
			stage = maxi(stage, 5)
			_set_objective("memory_3")
			# MECHANICS-004C：剧情条件满足时**只授予电机驱动许可**。
			# 门是否真的能开、开多高、能不能通行，全部由门体实际位置决定。
			if gate != null:
				gate.unlock("memory_3")
				gate.open()
			_toast("memory_3")
	_update_objective_from_state()
	if _physical_links != null:
		_physical_links.refresh()
	_next_memory_timer = 0.8


func _on_cradle_seated(cradle: ResonanceCradle, crystal: PortableCrystal, aligned: bool) -> void:
	_update_relay_node(cradle, crystal)
	network.rebuild_edges()
	# 三种状态必须分开：
	#   * 只是落进叉口（锁爪还没合拢）——中性提示，不能报“放错了”；
	#   * 锁爪夹住且朝向对——通路接通；
	#   * 锁爪夹住但朝向错——才需要玩家按 F 取下重放。
	if not cradle.latched:
		_toast("crystal_snapped")
	elif aligned:
		_play_seat_sound(crystal.global_position)
		_toast("crystal_seated_aligned")
	else:
		_play_wrong_sound(crystal.global_position)
		_toast("wrong_seat")
	_update_objective_from_state()
	if _physical_links != null:
		_physical_links.refresh()


func _on_cradle_released(cradle: ResonanceCradle) -> void:
	model.set_enabled(cradle.cradle_id, false)
	network.rebuild_edges()
	_update_objective_from_state()
	if _physical_links != null:
		_physical_links.refresh()


func _update_relay_node(cradle: ResonanceCradle, crystal: PortableCrystal) -> void:
	var id: String = cradle.cradle_id
	if not model.has_node(id):
		return
	var node_position: Vector3 = crystal.global_position + Vector3(0.0, R04LevelBuilder.PORTABLE_CENTER_HEIGHT, 0.0)
	model.set_transform(id, node_position, crystal.focus_direction())
	model.set_enabled(id, true)


func _update_objective_from_state() -> void:
	if completed:
		return
	var b1_ok: bool = _relay_ready("b1")
	var b3_ok: bool = _relay_ready("b3")
	if bool(seen_memories.get(3, false)):
		_set_objective("memory_3")
	elif b3_ok:
		stage = maxi(stage, 4)
		_set_objective("relay_b")
	elif bool(seen_memories.get(2, false)):
		_set_objective("memory_2")
	elif b1_ok:
		stage = maxi(stage, 2)
		_set_objective("relay_a")
	elif bool(seen_memories.get(1, false)):
		# The crystal lives on the far loading dock until the player brings it
		# east of the fault (or seats it). The objective follows that physical
		# fact, not a hidden quest flag.
		var on_far_side: bool = crystal_a != null and crystal_a.global_position.x < -8.4
		var onboard: bool = platform != null and platform.cargo_attached
		if onboard and on_far_side:
			if platform.clamp_t > 0.9:
				_set_objective("freight_fixed")
			else:
				_set_objective("freight_loaded")
		elif on_far_side:
			_set_objective("freight")
		else:
			_set_objective("freight_carry")
	else:
		_set_objective("start")


func _on_freight_notice(text: String) -> void:
	if hud != null and not text.is_empty():
		hud.show_toast(text, 2.8)


func _on_freight_warning(seconds: float) -> void:
	if hud != null:
		hud.show_warning("断层共振上升  ·  固定晶体 / 抓住扶手 / 拉下制动", seconds)
	if audio != null:
		audio.play_ui("radio_beep", 0.55)


func _on_freight_shock(strength: float) -> void:
	if player != null and platform != null:
		var distance: float = player.global_position.distance_to(platform.global_position)
		if distance > 3.0 and distance < 16.0:
			player.shake(0.08 * strength, 0.45)
	if hud != null:
		hud.show_warning("共振冲击！", 1.4)


func _on_freight_cargo_changed(_mode: String) -> void:
	_update_objective_from_state()


func _on_freight_control_changed(_owner_id: int) -> void:
	pass


func _relay_ready(cradle_id: String) -> bool:
	var cradle: ResonanceCradle = cradles.get(cradle_id) as ResonanceCradle
	if cradle == null or not cradle.aligned or cradle.occupied == null:
		return false
	return true


func _play_seat_sound(position_value: Vector3) -> void:
	if audio != null:
		audio.play_at("crystal_seat", position_value, 0.8)


func _play_wrong_sound(position_value: Vector3) -> void:
	if audio != null:
		audio.play_at("crystal_wrong", position_value, 0.7)


func _on_dead_end(node_id: String) -> void:
	_dead_end_count += 1
	if node_id.begins_with("b"):
		_toast("wrong_cradle")
	else:
		if _dead_end_count <= 2:
			_toast("dead_end_first")
		else:
			_toast("dead_end_repeat")
	if node_id == "m2" and bool(seen_memories.get(2, false)):
		if _ledge_lamp != null:
			_ledge_lamp.light_energy = 1.2


func _on_weak_memory(_node_id: String, _amplitude: float) -> void:
	_toast("weak_memory")


func _on_subtitle(speaker: String, text: String, duration: float) -> void:
	if hud != null:
		hud.show_subtitle(speaker, text, duration)


func _on_memory_shake(strength: float, duration: float) -> void:
	if player != null:
		player.shake(strength, duration)


func _on_exit_opened() -> void:
	if _ledge_lamp != null:
		_ledge_lamp.light_energy = 0.8


func _on_exit_entered() -> void:
	if completed:
		return
	# MECHANICS-004C：`gate.is_open` / `gate.exit_allowed` 现在是**门体实际净空**
	# 的结果（门板底缘 ≥ 门洞上沿 + 稳定 + 有保持），不是剧情标记。门还在上升、
	# 被障碍卡住、或净空不足时，这里一律不放行。
	if gate == null or not gate.exit_allowed or not gate.is_open:
		return
	if not bool(seen_memories.get(3, false)):
		return
	# The host is the only authority for "the chapter is complete". A client
	# may physically stand in the exit, but it must never set its own completed
	# flag or invent a phase-04 record: it waits for the host's reliable
	# `completed` event / scene switch.
	if coop_mode == "client":
		print("ACT4 client reached the exit; waiting for host authority")
		return
	# Co-op participation gate (anti-afk): every active participant must have
	# at least one Act-4 verified credit. Evaluate the authoritative host
	# ledger, and refuse an empty active roster so a missing/removed player
	# cannot silently turn into a free pass.
	if coop_mode == "host" and coop_net != null and coop_net.session != null:
		var ledger: ParticipationLedger = coop_net.session.ledger
		var host_pid: int = int(SessionHub.net.local_pid)
		var active: Array[int] = ledger.active_ids()
		var disconnected: Array[int] = []
		for pid in ledger.player_ids():
			if ledger.status_of(pid) == ParticipationLedger.STATUS_DISCONNECTED:
				disconnected.append(pid)
		if active.is_empty() or not active.has(host_pid):
			print("ACT4 GATE_REFUSED reason=no_active_host active=%s disconnected=%s" % [
				str(active), str(disconnected)])
			_gate_toast("出口校验失败：主机参与者状态缺失，不能结算。")
			return
		var missing: Array[int] = []
		for pid in active:
			if not ledger.ready_for_phase(pid, ParticipationLedger.PHASE_04):
				missing.append(pid)
		if not missing.is_empty():
			var names: Array[String] = []
			for pid in missing:
				names.append("%s（%s）" % [ledger.display_name(pid), " 或 ".join(ledger.missing_kinds(pid, ParticipationLedger.PHASE_04))])
			print("ACT4 GATE_REFUSED reason=missing_phase04 missing=%s active=%s disconnected=%s" % [
				str(missing), str(active), str(disconnected)])
			_gate_toast("收队前：%s 还缺参与。完成真实机械操作再回来。" % "、".join(names))
			return
		print("ACT4 GATE_OPEN active=%s disconnected=%s phases=%s" % [
			str(active), str(disconnected), _ledger_phase_summary(ledger, active)])
	completed = true
	stage = 6
	completion_seconds = game_time
	if player != null:
		player.set_input_enabled(false)
	if hud != null:
		hud.set_controls_visible(false)
		hud.show_prompt("")
		hud.show_completion(
			"矿工不是死于事故。他们亲手切断了轨道，\n是为了阻止某种东西继续向矿区深处传播。\n\n他们留下的最后一段回声，指向了矿区核心。\n\n你正走向更深的地层……"
		)
	if audio != null:
		audio.play_ui("success_chime", 0.8)
		audio.stop_loop("cart_roll")
		audio.stop_loop("alarm_loop")
	# Tell every connected client the host has accepted the exit. The client
	# sets its own `completed` only from this reliable event, never locally.
	if coop_net != null:
		coop_net.act4_send_event("completed", {
			"pid": int(SessionHub.net.local_pid) if SessionHub.net != null else 0,
			"seconds": completion_seconds,
		})
	# Store the hand-off payload on the shared session hub, then switch to
	# Act 5 (main.tscn) in the SAME session. In coop the host orders this and
	# every client follows via SessionHub.do_scene_switch.
	var handoff_payload: Dictionary = completion_payload()
	SessionHub.chapter_progress = handoff_payload
	# Act4 predates the uniform complete_chapter() path. Record its own chapter
	# here so the host history and the reliable scene-switch envelope agree; the
	# client must not display an empty Act04 history while keeping phase credit.
	SessionHub.record_chapter_done("act04", handoff_payload.duplicate(true))
	var spawn: Dictionary = {
		"chapter": "resonance_04",
		"completed": completed,
		"from_act4": true,
		# Carried in the reliable scene-switch payload so the client's Act05
		# handoff consumer sees the same authoritative Act04 record as the host.
		"_chapter_progress": handoff_payload.duplicate(true),
		"_chapter_history": (SessionHub.chapter_history as Dictionary).duplicate(true),
		"_current_chapter": "act05",
	}
	_session_hub_call_switch(spawn)


func _gate_toast(text: String) -> void:
	if hud == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_gate_toast_ms <= 4000:
		return
	_last_gate_toast_ms = now
	hud.show_toast(text, 4.5)


func _ledger_phase_summary(ledger: ParticipationLedger, pids: Array[int]) -> String:
	var parts: Array[String] = []
	for pid in pids:
		parts.append("%d:%s" % [pid, str(ledger.get_record(pid).get("phases", {}))])
	return " ".join(parts)


func _session_hub_call_switch(spawn: Dictionary) -> void:
	# Probe runs (which drive `game` directly) must not auto-switch away from
	# the act or their reset-and-replay section breaks. They pass --to-act5 to
	# opt into the hand-off test explicitly; the real slice launch always has
	# SessionHub (so it always switches).
	if has_meta("suppress_act5") and not ("--to-act5" in OS.get_cmdline_user_args()):
		print("ACT4 completed but scene switch suppressed (probe mode)")
		return
	await get_tree().create_timer(3.5).timeout
	if SessionHub != null:
		SessionHub.request_scene_switch("res://scenes/main.tscn", spawn)


func _set_objective(key: String) -> void:
	if hud == null:
		return
	hud.set_objective(_objective(key))


func _objective(key: String) -> String:
	var objectives: Dictionary = story.get("objectives", {}) as Dictionary
	return str(objectives.get(key, ""))


func _toast(key: String) -> void:
	if hud == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_hint_ms < 650:
		return
	_last_hint_ms = now
	var feedback: Dictionary = story.get("feedback", {}) as Dictionary
	var text: String = str(feedback.get(key, ""))
	if not text.is_empty():
		hud.show_toast(text)


func reset_level() -> void:
	if player != null:
		if player.carrying != null:
			player.drop_carried(false)
		player.set_input_enabled(true)
		player.teleport(SPAWN, 0.0)
	if crystal_a != null:
		crystal_a.reset_crystal()
	if crystal_b != null:
		crystal_b.reset_crystal()
	if platform != null:
		platform.reset_platform()
	for key: Variant in cradles.keys():
		var cradle: ResonanceCradle = cradles[key] as ResonanceCradle
		# MECHANICS-004A：复位时锁爪也要回到张开位（不然下一轮会带着旧钳口状态）
		cradle.reset_cradle()
	for key: Variant in cradles.keys():
		var cradle: ResonanceCradle = cradles[key] as ResonanceCradle
		model.set_enabled(cradle.cradle_id, false)
	if hammer != null:
		hammer.reset_hammer()
	# MECHANICS-004C：出口门是真实刚体，复位时必须一次性放回关闭位并收回
	# 驱动许可与机械承接梁，否则下一轮会带着上一轮的开门状态。
	if gate != null:
		gate.reset_gate()
	if memory != null:
		memory.reset_all()
	if network != null:
		network.clear_all()
		network.rebuild_edges()
	for crystal_key: Variant in crystals.keys():
		var crystal: EchoCrystal = crystals[crystal_key] as EchoCrystal
		crystal.set_alarm(0.0)
		if crystal.is_memory:
			crystal.set_memory_awake(false)
	stage = 0
	seen_memories.clear()
	memory_queue.clear()
	current_memory = 0
	completed = false
	completion_seconds = 0.0
	_dead_end_count = 0
	_next_memory_timer = 0.0
	reset_count += 1
	_reset_memory_lights()
	if _physical_links != null:
		_physical_links.refresh()
	if hud != null:
		hud.hide_completion()
		hud.set_controls_visible(true)
		hud.set_objective(_objective("start"))
		hud.show_prompt("")
		hud.show_toast(str((story.get("feedback", {}) as Dictionary).get("reset", "关卡已重置。")))
	if audio != null:
		audio.stop_loop("cart_roll")
		audio.stop_loop("alarm_loop")
		audio.start_loop("cave_loop", 0.42)
		audio.start_loop("drone_loop", 0.28)


## Hand-off payload for the next chapter (Act 5). Pure read: no state changes.
func completion_payload() -> Dictionary:
	return {
		"chapter": "resonance_04",
		"completed": completed,
		"seconds": completion_seconds,
		"memories": seen_memories.duplicate(),
		"strikes": hammer.strike_count if hammer != null else 0,
		"gate_open": gate.is_open if gate != null else false,
		"player_exit_position": player.global_position if player != null else Vector3.ZERO,
		"freight_accident_fired": platform.accident_fired if platform != null else false,
		"freight_cargo_on_platform": platform.cargo_attached if platform != null else false,
		"freight_cargo_clamped": platform.is_cargo_fixed() if platform != null else false,
		"freight_platform_x": platform.travel_x if platform != null else 0.0,
	}


func debug_snapshot() -> Dictionary:
	return {
		"stage": stage,
		"seen": seen_memories.duplicate(),
		"completed": completed,
		"completion_seconds": completion_seconds,
		"gate_open": gate.is_open if gate != null else false,
		"hammer_strikes": hammer.strike_count if hammer != null else 0,
		"last_dead_end": network.last_dead_end if network != null else "",
		"crystal_a_position": crystal_a.global_position if crystal_a != null else Vector3.ZERO,
		"crystal_b_position": crystal_b.global_position if crystal_b != null else Vector3.ZERO,
		"player_position": player.global_position if player != null else Vector3.ZERO,
		"reset_count": reset_count,
		"b1_aligned": _relay_ready("b1"),
		"b3_aligned": _relay_ready("b3"),
		"freight_x": platform.travel_x if platform != null else 0.0,
		"freight_y": platform.deck_y if platform != null else 0.0,
		"freight_speed": platform.speed if platform != null else 0.0,
		"freight_roll": platform.tilt_roll if platform != null else 0.0,
		"freight_cargo": platform.cargo_attached if platform != null else false,
		"freight_clamped": platform.clamp_closed if platform != null else false,
		"freight_accident": platform.accident_phase if platform != null else 0,
		"freight_accident_fired": platform.accident_fired if platform != null else false,
		"freight_control": platform.control_owner_id if platform != null else 0,
	}


# ---------------------------------------------------------------------------
# Act 4 co-op implementation (same SessionHub session as Act 5)
# ---------------------------------------------------------------------------
# The host owns every shared mechanic: the resonance wave / memories / stage /
# gate, the freight platform authority, crystal ownership (one holder) and the
# cradle seats. The client mirrors the host snapshot and forwards real actions
# (strike, pickup, drop, seat, platform input) as validated intents — exactly
# the contract `CoopNet._act4_*` methods expect on `act4_game`.

func _setup_coop() -> void:
	coop_net = SessionHub.the_net()
	coop_host_port = CoopNet.PORT_DEFAULT
	coop_address = "127.0.0.1"
	# Detect host / client from the unified session (launcher, --host/--client,
	# or --auto=host/--auto=client for the two-process tests).
	var as_host: bool = false
	var as_client: bool = false
	if SessionHub.mode == "host":
		as_host = true
	elif SessionHub.mode == "client":
		as_client = true
	if coop_net == null or not coop_net.is_online():
		if as_host:
			SessionHub.start(true, coop_host_port)
			coop_net = SessionHub.the_net()
		elif as_client:
			SessionHub.start(false, coop_host_port, coop_address)
			coop_net = SessionHub.the_net()
		as_host = SessionHub.mode == "host"
		as_client = SessionHub.mode == "client"
	if as_host:
		coop_mode = "host"
	elif as_client:
		coop_mode = "client"
	else:
		coop_mode = "solo"
	if coop_mode == "solo" or coop_net == null:
		coop_net = null
		return
	# Bind this game world to the shared peer; Act 5 scene refs get cleared.
	coop_net.bind_act4(self)
	# The campaign launcher registers pid 1. Direct Act-4 bootstraps (tests,
	# packaged scene launch) do not; without a record the host's own strike has
	# nowhere to land and the exit gate can see an empty active roster. Register
	# the real local host here; never copy it to any other pid.
	if coop_mode == "host" and coop_net.session != null:
		var host_pid: int = int(SessionHub.net.local_pid)
		if coop_net.session.ledger.get_record(host_pid).is_empty():
			coop_net.session.add_player(host_pid, "七号", true)
	platform.configure_network(coop_net, coop_mode == "host")
	platform.authority = coop_mode == "host"
	# The platform needs the one body this process really drives: a client can
	# then turn the host's grab table into local rail state by pid.
	if platform != null and player != null:
		platform.bind_local_player(player)
	if coop_mode == "host" and platform != null:
		# ACT04-3P4P: the host's own legal lever / handhold / brake actions are
		# local calls, not forwarded intents. They must still reach the
		# authoritative ledger; the platform emits this only for the locally
		# driven body, so remote actions keep their single host-side credit path.
		if not platform.action_used.is_connected(_on_platform_action_used):
			platform.action_used.connect(_on_platform_action_used)
	# One body for every live participant (ACT04-3P4P). The roster comes from
	# the shared ledger the host records on every join; clients receive the same
	# roster in the reliable bootstrap / ledger mirror. The local body is the
	# only body this process ever drives.
	var local_pid: int = int(SessionHub.net.local_pid)
	coop_players[local_pid] = player
	if player != null:
		player.player_id = local_pid
	_act4_sync_bodies()
	# The Act 4 world can bind long after the ENet connection was established
	# (the normal Act01→Act23→Act04 campaign order), so no connect callback will
	# fire on this side. Pull/push the authoritative roster explicitly instead.
	if coop_mode == "client" and _act4_peer_live():
		coop_net.act4_request_sync_now()
	elif coop_mode == "host":
		_act4_broadcast_roster()
	# The local player's carry changes are host-arbitrated through the net.
	if player != null:
		player.coop_pickup_gate = (coop_mode != "host")
		if not player.carry_changed.is_connected(_on_coop_carry_changed):
			player.carry_changed.connect(_on_coop_carry_changed)
		if not player.pickup_requested.is_connected(_on_coop_pickup_requested):
			player.pickup_requested.connect(_on_coop_pickup_requested)
	# Host immediately credits whoever is local when they finish a real action.
	_act4_track_local_actions()
	if coop_mode == "host":
		print("ACT4 coop host · pid=", SessionHub.net.local_pid)
	else:
		print("ACT4 coop client · pid=", SessionHub.net.local_pid)
	# Bodies for participants that were already in the session before Act 4
	# bound (the normal launcher order) belong to this world from the first
	# frame. `_act4_attach` is idempotent and also covers the opposite order.
	for pid in _act4_remote_pids():
		_act4_attach(pid)
	# Two-process automated run: --auto=host / --auto=client spawn the coop bot.
	var auto_role: String = _act4_auto_arg()
	if auto_role != "":
		var bot: Node = load("res://tests/act4_coop_auto.gd").new()
		bot.name = "Act4CoopAuto"
		bot.set("role", auto_role)
		add_child(bot)


func _act4_auto_arg() -> String:
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg == "--auto=host":
			return "host"
		elif arg == "--auto=client":
			return "client"
	return ""


func _act4_track_local_actions() -> void:
	pass


# --- Peer presence and Act 4 initial state ----------------------------------
# The ENet connection may be established before OR after this scene binds Act 4
# (both are real launcher/join orders), so neither presence nor the initial
# state can depend on a single callback. Both orders funnel through
# `_act4_attach`, which is idempotent.

## Show the other player's body and pull the authoritative initial state once.
## Called from the bind path, from the connect hook and from peer_connected.
func _act4_attach(pid: int) -> void:
	if coop_net == null or pid <= 0 or pid == SessionHub.net.local_pid:
		return
	if coop_mode == "client":
		if not _act4_peer_live():
			return
		_act4_set_presence(pid, true)
		coop_net.act4_request_sync_now()
	elif coop_mode == "host":
		if multiplayer.get_peers().is_empty():
			return
		_act4_set_presence(pid, true)
		# A client that connected before Act 4 bound never received the join
		# bootstrap; send the current authoritative state once now.
		coop_net.act4_send_event("bootstrap", build_act4_snapshot(true))


## CoopNet calls this on `connected_to_server`. It runs when the connection
## completes while Act 4 is already in the tree; the opposite order is covered
## by `_setup_coop()` → `_act4_attach()`.
func on_act4_connected() -> void:
	if coop_mode != "client" or coop_net == null:
		return
	var host_pid: int = 1
	print("ACT4 client connected · attaching host body pid=%d" % host_pid)
	_act4_attach(host_pid)


## CoopNet reports that one client pulled the initial state. Recorded so the
## acceptance run can prove the late-join path really executed.
func on_act4_sync_request(pid: int) -> void:
	act4_sync_requests += 1
	if coop_mode == "host" and hud != null:
		hud.show_toast("队友 %d 已同步第四幕世界状态" % pid, 2.0)


func _act4_set_presence(pid: int, present: bool) -> void:
	var body: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if body == null:
		if not present:
			return
		body = _act4_spawn_remote_body(pid)
	if body == null or body.visible == present:
		return
	body.visible = present
	print("ACT4 %s · body pid=%d visible=%s" % [coop_mode, pid, str(present)])


# --- ACT04-3P4P · one body per live participant ------------------------------
# `coop_players` is the single mapping between a participant PID and the body it
# owns. It is reconciled from the shared session ledger (the host registers a
# record for every peer; the reliable bootstrap carries the same roster to each
# client), so the third/fourth player gets a real body, a leaving player's body
# is freed, and re-entering the scene rebuilds the same table without ghosts.

func _act4_local_pid() -> int:
	return int(SessionHub.net.local_pid) if SessionHub.net != null else 1


## Every live participant except us, sorted. `disconnected` bodies are removed
## by `on_act4_peer_disconnected`; they are filtered here as well so a stale
## ledger row can never resurrect a body in a later snapshot.
func _act4_remote_pids() -> Array:
	var out: Array = []
	if coop_net == null or coop_net.session == null:
		return out
	var local_pid: int = _act4_local_pid()
	var ledger: ParticipationLedger = coop_net.session.ledger
	for raw in ledger.player_ids():
		var pid: int = int(raw)
		if pid <= 0 or pid == local_pid:
			continue
		if ledger.status_of(pid) == ParticipationLedger.STATUS_DISCONNECTED:
			continue
		out.append(pid)
	out.sort()
	return out


func _act4_sync_bodies() -> void:
	if coop_net == null or player == null:
		return
	var local_pid: int = _act4_local_pid()
	for key in coop_players.keys():
		if int(key) <= 0:
			coop_players.erase(key)
	if local_pid > 0:
		coop_players[local_pid] = player
		player.player_id = local_pid
	var wanted: Array = _act4_remote_pids()
	var existing: Array = []
	for key in coop_players.keys():
		var pid: int = int(key)
		if pid == local_pid:
			continue
		existing.append(pid)
	for pid in wanted:
		if not existing.has(int(pid)):
			_act4_spawn_remote_body(int(pid))
	for pid in existing:
		if not wanted.has(int(pid)):
			_act4_despawn_remote_body(int(pid))


## Deterministic, non-overlapping spawn around the real player spawn. The capsule
## radius is 0.38 m, so 0.9 m of separation can never intersect another body.
func _act4_body_spawn(pid: int) -> Vector3:
	var slot: int = clampi(pid - 1, 0, CoopSession.MAX_PLAYERS - 1)
	return SPAWN + Vector3(0.9 * float(slot), 0.0, 0.55 * float(slot % 2))


func _act4_spawn_remote_body(pid: int) -> EchoPlayer:
	var existing: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if existing != null and is_instance_valid(existing):
		return existing
	var spawn: Vector3 = _act4_body_spawn(pid)
	var body: EchoPlayer = EchoPlayer.new()
	body.name = "RemotePlayer%d" % pid
	body.player_id = pid
	body.is_remote = true
	body.position = spawn
	add_child(body)
	body.teleport(spawn, 180.0)
	body.set_physics_process(false)
	body.set_process(false)
	body.visible = false
	coop_players[pid] = body
	if remote_player == null or not is_instance_valid(remote_player):
		remote_player = body
	print("ACT4 body spawn · pid=%d bodies=%d" % [pid, coop_players.size()])
	return body


func _act4_despawn_remote_body(pid: int) -> void:
	var body: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if body == null or body == player:
		return
	coop_players.erase(pid)
	if remote_player == body:
		remote_player = null
		for key in coop_players.keys():
			var other: EchoPlayer = coop_players[key] as EchoPlayer
			if other != null and other != player:
				remote_player = other
				break
	print("ACT4 body despawn · pid=%d bodies=%d" % [pid, coop_players.size()])
	body.queue_free()


## Host -> every client: the authoritative roster changed. Reuses the existing
## reliable `ledger` event (schema unchanged): the client applies the snapshot
## and then reconciles its body table against it.
func _act4_broadcast_roster() -> void:
	if coop_mode != "host" or coop_net == null or coop_net.session == null:
		return
	coop_net.act4_send_event("ledger", {
		"pid": _act4_local_pid(),
		"ledger": coop_net.session.ledger.snapshot(),
	})


## Client side: every remote pid in the freshly applied roster must have a
## visible mirror body, but the roster event itself is already the sync.
func _act4_reveal_remotes() -> void:
	for pid in _act4_remote_pids():
		_act4_set_presence(int(pid), true)


func _act4_peer_live() -> bool:
	return coop_net != null and coop_net.peer_connected_now()


func _act4_host_tick(delta: float) -> void:
	if coop_net == null or player == null:
		return
	# The host feeds its own authoritative mission state through the shared
	# session ledger so the participation gate can see it.
	_act4_stage_credits_into_session()


func _act4_mirror_crystal(crystal_id: String, pos: Vector3, carrier_pid: int) -> void:
	if not pos.is_finite() or absf(pos.x) > 200.0 or absf(pos.z) > 200.0 or pos.y < -30.0 or pos.y > 100.0:
		return
	var crystal: PortableCrystal = find_crystal(crystal_id)
	if crystal == null:
		return
	var local_pid: int = SessionHub.net.local_pid if SessionHub.net != null else 1
	if carrier_pid == local_pid:
		# The host says we carry it; pick it up locally if we aren't already.
		if not crystal.is_carried:
			crystal.begin_carry(player.hold_point)
			player.carrying = crystal
		crystal.global_position = player.hold_point.global_position
	else:
		if crystal.is_carried and player.carrying == crystal:
			player.drop_carried(false)
		# On non-authority clients, keep host-driven free crystals kinematic so
		# client gravity never fights the host's 15 Hz mirror (R-46).
		if crystal.freight == null:
			crystal.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			crystal.freeze = true
		crystal.global_position = pos
		crystal.linear_velocity = Vector3.ZERO
		crystal.angular_velocity = Vector3.ZERO


func _act4_client_tick(delta: float) -> void:
	if coop_net == null or platform == null or player == null:
		return
	# If this client holds the platform lever, stream the real W/S axis so the
	# host can apply it to the authoritative platform. Rate-limit the reliable
	# stream (a raw per-frame send is 60 RPCs/s) and send the final zero so the
	# host does not keep driving after the lever is released.
	_act4_platform_axis_clock = maxf(_act4_platform_axis_clock - delta, 0.0)
	if platform.control_owner_id == SessionHub.net.local_pid:
		var axis: float = Input.get_axis("move_back", "move_forward")
		var changed: bool = absf(axis - _act4_last_axis_sent) > 0.01
		if (_act4_platform_axis_clock <= 0.0 and absf(axis) > 0.01) \
				or (changed and absf(axis) <= 0.01):
			_act4_platform_axis_clock = 1.0 / 15.0
			_act4_last_axis_sent = axis
			coop_net.act4_submit_action("platform", "drive_axis", axis)


func _act4_stage_credits_into_session() -> void:
	if coop_net == null:
		return
	# No special staging needed: credits are issued at the moment of the action
	# (see _act4_credit_strike and the platform/ crystal handlers below).


## Issue the phase-04 strike credit to the player who really rang the bell and
## log the authoritative result. On the host this is the single source of truth
## for "this pid completed Act 4"; it must never be called with a guessed pid.
func _act4_credit_strike(pid: int) -> bool:
	if coop_mode == "solo":
		# Solo has no participation ledger; the exit gate is not applied.
		return true
	if coop_net == null or coop_net.session == null:
		print("ACT4 CREDIT_REJECTED pid=%d kind=act4_hammer_strike reason=no_session" % pid)
		return false
	var record: Dictionary = coop_net.session.ledger.get_record(pid)
	var already: bool = not record.is_empty() and (record.get("credits", {}) as Dictionary).has("act4_hammer_strike")
	var ok: bool = coop_net.session.credit(pid, "act4_hammer_strike", 1.0, "拉响撞钟引发共振")
	if ok:
		print("ACT4 CREDIT pid=%d kind=act4_hammer_strike phases=%s" % [
			pid, str(record.get("phases", {}))])
		_act4_broadcast_ledger(pid)
	elif already:
		# A second/third strike is a real input but the same credit kind is
		# recorded once per player; the phase count must not inflate.
		print("ACT4 CREDIT_ALREADY_RECORDED pid=%d kind=act4_hammer_strike phases=%s" % [
			pid, str(record.get("phases", {}))])
	else:
		print("ACT4 CREDIT_REJECTED pid=%d kind=act4_hammer_strike status=%s phases=%s" % [
			pid, str(coop_net.session.status_of(pid)), str(record.get("phases", {}))])
	return ok


## Reliable host -> client mirror of the authoritative ledger. This is the
## explicit acknowledgement that a client's real action was recorded by the
## authority; it is never used to create a credit.
func _act4_broadcast_ledger(pid: int) -> void:
	if coop_mode != "host" or coop_net == null or coop_net.session == null:
		return
	coop_net.act4_send_event("ledger", {
		"pid": pid,
		"ledger": coop_net.session.ledger.snapshot(),
	})


func _act4_credit_crystal(pid: int) -> void:
	if coop_net == null or coop_net.session == null:
		return
	var ok: bool = coop_net.session.credit(pid, "act4_crystal_carry", 1.0, "搬运 / 安放共振晶体")
	if ok:
		print("ACT4 CREDIT pid=%d kind=act4_crystal_carry phases=%s" % [
			pid, str(coop_net.session.ledger.get_record(pid).get("phases", {}))])
		_act4_broadcast_ledger(pid)


func _on_coop_carry_changed(carried: Node) -> void:
	if coop_mode == "solo" or coop_net == null:
		return
	if coop_mode == "host":
		# The host already `begin_carry`'d through its own path; nothing to do.
		return
	if carried != null:
		coop_net.act4_submit_action("pickup", crystal_id_of(carried), 0.0)
	else:
		coop_net.act4_submit_action("drop", "", 0.0)


func _on_coop_pickup_requested(crystal: PortableCrystal) -> void:
	if coop_mode == "client" and coop_net != null:
		coop_net.act4_submit_action("pickup", crystal_id_of(crystal), 0.0)


func crystal_id_of(crystal: Node) -> String:
	if crystal == crystal_a:
		return "crystal_a"
	if crystal == crystal_b:
		return "crystal_b"
	return ""


func find_crystal(id: String) -> PortableCrystal:
	if id == "crystal_a":
		return crystal_a
	if id == "crystal_b":
		return crystal_b
	return null


# --- Player transform stream (client -> host -> snapshot) -------------------

func local_act4_player_state() -> Dictionary:
	if player == null:
		return {}
	return {
		"pos": player.global_position,
		"yaw": player.rotation.y,
		"vel": player.velocity,
		"grab": player.grab_platform != null,
		"carry": player.carrying != null,
	}


func on_act4_remote_state(pid: int, state: Dictionary) -> void:
	if coop_mode != "host":
		return
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if remote == null or state.is_empty():
		return
	var pos: Vector3 = state.get("pos", remote.global_position) as Vector3
	var yaw: float = float(state.get("yaw", 0.0))
	var vel: Vector3 = state.get("vel", Vector3.ZERO) as Vector3
	remote.update_remote_state(pos, yaw, vel, bool(state.get("grab", false)), bool(state.get("carry", false)))
	if bool(state.get("carry", false)):
		_act4_credit_crystal(pid)


# --- Host authoritative snapshot --------------------------------------------

## `include_ledger` is only true for reliable bootstrap/authority messages. The
## 15 Hz unreliable snapshot must stay below the ENet MTU (1392 bytes), so the
## participation ledger travels on the reliable `ledger` event instead.
func build_act4_snapshot(include_ledger: bool = false) -> Dictionary:
	var players_snap: Dictionary = {}
	if player != null:
		players_snap[SessionHub.net.local_pid] = local_act4_player_state()
	for pid in coop_players.keys():
		var remote: EchoPlayer = coop_players[int(pid)] as EchoPlayer
		if remote == null or remote == player:
			continue
		var rp: int = int(pid)
		players_snap[rp] = {
			"pos": remote.global_position,
			"yaw": remote.rotation.y,
			"vel": remote.velocity,
			"grab": remote.grab_platform != null,
			"carry": remote.carrying != null,
		}
	var out: Dictionary = {
		"seq": coop_net._seq,
		"players": players_snap,
		"platform": platform.snapshot() if platform != null else {},
		"crystal_a_pos": crystal_a.global_position if crystal_a != null else Vector3.ZERO,
		"crystal_b_pos": crystal_b.global_position if crystal_b != null else Vector3.ZERO,
		"crystal_a_carrier": _crystal_carrier_pid("crystal_a"),
		"crystal_b_carrier": _crystal_carrier_pid("crystal_b"),
		"memories": seen_memories.duplicate(),
		"stage": stage,
		"gate_open": gate.is_open if gate != null else false,
		"strikes": hammer.strike_count if hammer != null else 0,
		"completed": completed,
		"reset_seq": coop_net.reset_seq,
		"peer_count": coop_net.peer_count(),
	}
	if include_ledger and coop_net != null and coop_net.session != null:
		out["ledger"] = coop_net.session.ledger.snapshot()
	return out


func _crystal_carrier_pid(crystal_id: String) -> int:
	var crystal: PortableCrystal = find_crystal(crystal_id)
	if crystal == null or not crystal.is_carried:
		return 0
	# Find which coop player's body the crystal is attached to.
	for pid in coop_players.keys():
		var body: EchoPlayer = coop_players[int(pid)] as EchoPlayer
		if body != null and body.carrying == crystal:
			return int(pid)
	return 0


# --- Client snapshot application ---------------------------------------------

func apply_act4_snapshot(snap: Dictionary) -> void:
	if coop_mode != "client" or coop_net == null:
		return
	if platform != null:
		platform.apply_net_state(snap.get("platform", {}) as Dictionary)
	var players_snap: Dictionary = snap.get("players", {}) as Dictionary
	for key in players_snap.keys():
		var pid: int = int(key)
		if pid == SessionHub.net.local_pid:
			continue
		var state: Dictionary = players_snap[key] as Dictionary
		var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
		if remote != null and state is Dictionary:
			var pos_v: Variant = state.get("pos", remote.global_position)
			var vel_v: Variant = state.get("vel", Vector3.ZERO)
			var yaw_v: Variant = state.get("yaw", remote.rotation.y)
			if pos_v is Vector3 and vel_v is Vector3 and (yaw_v is float or yaw_v is int):
				var pos: Vector3 = pos_v as Vector3
				var vel: Vector3 = vel_v as Vector3
				var yaw: float = float(yaw_v)
				if pos.is_finite() and vel.is_finite() and is_finite(yaw) \
						and absf(pos.x) < 200.0 and absf(pos.z) < 200.0 and pos.y > -30.0 and pos.y < 100.0:
					remote.update_remote_state(pos, yaw, vel, bool(state.get("grab", false)), bool(state.get("carry", false)))
	# Crystal positions & carry mirror (host owns which player carries what).
	if snap.has("crystal_a_pos"):
		var a_v: Variant = snap.get("crystal_a_pos")
		if a_v is Vector3 and (a_v as Vector3).is_finite():
			_act4_mirror_crystal("crystal_a", a_v as Vector3, int(snap.get("crystal_a_carrier", 0)))
	if snap.has("crystal_b_pos"):
		var b_v: Variant = snap.get("crystal_b_pos")
		if b_v is Vector3 and (b_v as Vector3).is_finite():
			_act4_mirror_crystal("crystal_b", b_v as Vector3, int(snap.get("crystal_b_carrier", 0)))
	# Mission state (memories / stage / gate) — host is authoritative.
	var mems: Dictionary = snap.get("memories", {}) as Dictionary
	for mi in mems.keys():
		var index: int = int(mi)
		if not bool(seen_memories.get(index, false)):
			seen_memories[index] = true
			if memory != null:
				memory.play(index)
				current_memory = index
	stage = maxi(stage, int(snap.get("stage", 0)))
	if bool(snap.get("gate_open", false)) and gate != null and not gate.is_open:
		gate.unlock("host_snapshot")
		gate.open()
	if _physical_links != null:
		_physical_links.refresh()
	# Mirror the host's participation ledger (host is the only writer). This
	# makes the client's phase-04 state and its logs truthful instead of an
	# always-empty local ledger.
	var ledger_snap: Dictionary = snap.get("ledger", {}) as Dictionary
	if coop_net.session != null and not ledger_snap.is_empty():
		coop_net.session.ledger.apply_snapshot(ledger_snap)
		_act4_log_authority_sync()
		# The reliable bootstrap/roster carries every live participant: give each
		# remote pid exactly one mirror body now. Do not pull another sync here --
		# this snapshot already is the authoritative state.
		_act4_sync_bodies()
		_act4_reveal_remotes()


func _act4_log_authority_sync() -> void:
	if coop_net == null or coop_net.session == null:
		return
	var ledger: ParticipationLedger = coop_net.session.ledger
	for pid in ledger.player_ids():
		if not ledger.ready_for_phase(pid, ParticipationLedger.PHASE_04):
			continue
		if bool(_act4_ready04_seen.get(pid, false)):
			continue
		_act4_ready04_seen[pid] = true
		print("ACT4 AUTHORITY_SYNC pid=%d ready04=true phases=%s" % [
			pid, str(ledger.get_record(pid).get("phases", {}))])


# --- Client / host action intents --------------------------------------------

func on_act4_remote_action(pid: int, kind: String, detail: String, value: float) -> void:
	if coop_mode != "host":
		return
	match kind:
		"hammer_strike":
			_act4_host_apply_strike(pid, value)
		"pickup":
			_act4_host_apply_pickup(pid, detail)
		"drop":
			_act4_host_apply_drop(pid)
		"seat":
			_act4_host_apply_seat(pid, detail)
		"platform":
			_act4_host_apply_platform(pid, detail, value)


## FreightPlatform's non-authority side calls net.rpc "act4_freight_action"
## with its own kinds (drive/brake/clamp/grab/call/winch) + a dock id string.
func on_act4_freight_action(pid: int, kind: String, dock_id: String) -> void:
	if coop_mode != "host":
		return
	_act4_host_freight_platform_action(pid, kind, dock_id)


func _act4_host_apply_strike(pid: int, strength: float) -> void:
	if network == null:
		print("ACT4 CREDIT_REJECTED pid=%d kind=act4_hammer_strike reason=no_network" % pid)
		return
	network.strike("bell", strength)
	# Credit the sender before any presentation code: a missing audio method or
	# HUD error must never decide whether the authoritative ledger changes.
	_act4_credit_strike(pid)
	if audio != null:
		var impact: Vector3 = hammer.global_position if hammer != null else SPAWN
		# R04Audio exposes play_at(), not play_sfx(); the old call raised a
		# script error on every remote strike.
		audio.play_at("hammer_impact", impact, -2.0)


func _act4_host_apply_pickup(pid: int, crystal_id: String) -> void:
	var crystal: PortableCrystal = find_crystal(crystal_id)
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if crystal == null or remote == null:
		return
	if crystal.is_carried or crystal.is_seated:
		return
	if remote.global_position.distance_to(crystal.global_position) > 4.0:
		return
	crystal.begin_carry(remote.hold_point)
	# The carrier-pid snapshot relies on the remote body's `carrying` field.
	remote.carrying = crystal
	_act4_credit_crystal(pid)
	if hud != null:
		hud.show_toast("队友 %d 拿起了晶体" % pid, 2.2)


func _act4_host_apply_drop(pid: int) -> void:
	var crystal: PortableCrystal = _carried_of(pid)
	if crystal == null:
		return
	crystal.end_carry(false)
	# Clear the remote body's carry mirror so the carrier-pid snapshot drops.
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if remote != null and remote.carrying == crystal:
		remote.carrying = null


func _act4_host_apply_seat(pid: int, cradle_id: String) -> void:
	var crystal: PortableCrystal = _carried_of(pid)
	var cradle: ResonanceCradle = cradles.get(cradle_id) as ResonanceCradle
	if crystal == null or cradle == null:
		return
	# Teleport crystal above the cradle and drive the same real logic.
	crystal.global_position = cradle.global_position + Vector3(0, 1.0, 0)
	crystal.linear_velocity = Vector3.ZERO
	crystal.angular_velocity = Vector3.ZERO
	_on_cradle_seated(cradle, crystal, true)
	_act4_credit_crystal(pid)


func _act4_host_apply_platform(pid: int, kind: String, value: float) -> void:
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if platform == null:
		return
	if remote == null:
		return
	if remote.global_position.distance_to(platform.global_position) > 18.0 and kind != "drive_axis":
		return
	if kind == "drive_axis":
		platform.set_drive_input(clampf(value, -1.0, 1.0))
		return
	_act4_host_apply_platform_control(pid, remote, kind)


func _act4_platform_credit(pid: int, kind: String) -> void:
	if coop_net != null and coop_net.session != null:
		var ok: bool = coop_net.session.credit(pid, kind, 1.0, "操作货运平台")
		if ok:
			print("ACT4 CREDIT pid=%d kind=%s phases=%s" % [
				pid, kind, str(coop_net.session.ledger.get_record(pid).get("phases", {}))])
			_act4_broadcast_ledger(pid)


## Local (host) platform action -> authoritative credit. The platform emits this
## only for the body this process drives, so a client's forwarded request is
## still credited once by `_act4_host_freight_platform_action`.
func _on_platform_action_used(kind: String, peer_id: int) -> void:
	if coop_mode != "host" or coop_net == null or coop_net.session == null:
		return
	var local_pid: int = int(SessionHub.net.local_pid)
	if peer_id != local_pid:
		return
	match kind:
		"drive":
			_act4_platform_credit(peer_id, "act4_platform_drive")
		"brake":
			_act4_platform_credit(peer_id, "act4_brake")
		"grab":
			_act4_platform_credit(peer_id, "act4_grab")


## FreightPlatform's own RPC path (the non-authority side calls it). `kind` is
## the platform kind (drive/brake/clamp/grab/call/winch), `dock_id` a string
## dock. The authoritative credit follows the platform's own answer, so a
## refused lever (occupied), a taken handhold, an unknown point or a duplicate
## request can never move the ledger.
func _act4_host_freight_platform_action(pid: int, kind: String, dock_id: String) -> void:
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if platform == null or remote == null:
		return
	if remote.global_position.distance_to(platform.global_position) > 18.0:
		return
	_act4_host_apply_platform_control(pid, remote, kind, dock_id)


## Single host-side gate for both freight entry points (the `platform` action
## stream and FreightPlatform's RPC path): apply the real control, then credit
## only what the platform reports as a performed participation action.
func _act4_host_apply_platform_control(pid: int, remote: Node, kind: String, dock_id: String = "") -> void:
	if platform == null or remote == null:
		return
	var result: String = platform.handle_control(kind, remote, dock_id)
	if result == FreightPlatform.RESULT_CREDIT:
		_act4_host_freight_credit(pid, kind)
		return
	if result == FreightPlatform.RESULT_REJECTED:
		print("ACT4 FREIGHT_REJECTED pid=%d kind=%s dock=%s credit=none" % [pid, kind, dock_id])


## The credited freight kinds and nothing else: the mapping is unchanged, only
## the condition for reaching it is.
func _act4_host_freight_credit(pid: int, kind: String) -> void:
	match kind:
		"drive":
			_act4_platform_credit(pid, "act4_platform_drive")
		"brake":
			_act4_platform_credit(pid, "act4_brake")
		"grab":
			_act4_platform_credit(pid, "act4_grab")


func _carried_of(pid: int) -> PortableCrystal:
	var remote: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if remote == null:
		return null
	if remote.carrying == crystal_a:
		return crystal_a
	if remote.carrying == crystal_b:
		return crystal_b
	return null


# --- Reliable events (host -> client) ---------------------------------------

func on_act4_net_event(kind: String, payload: Dictionary) -> void:
	if coop_mode != "client":
		return
	match kind:
		"bootstrap":
			act4_bootstrap_count += 1
			print("ACT4 %s · initial state #%d applied" % [coop_mode, act4_bootstrap_count])
			apply_act4_snapshot(payload)
		"ledger":
			var ledger_snap: Dictionary = payload.get("ledger", {}) as Dictionary
			if coop_net != null and coop_net.session != null and not ledger_snap.is_empty():
				coop_net.session.ledger.apply_snapshot(ledger_snap)
				print("ACT4 AUTHORITY_LEDGER source=host pid=%d" % int(payload.get("pid", 0)))
				_act4_log_authority_sync()
				# A roster change also travels through this reliable event: keep
				# exactly one body per live remote pid, and no ghost for ourselves.
				_act4_sync_bodies()
				_act4_reveal_remotes()
		"toast":
			if hud != null:
				hud.show_toast(str(payload.get("text", "")), float(payload.get("seconds", 2.0)))
		"memory":
			var index: int = int(payload.get("index", 0))
			if index > 0 and not bool(seen_memories.get(index, false)):
				seen_memories[index] = true
				if memory != null:
					memory.play(index)
					current_memory = index
		"gate":
			if gate != null and not gate.is_open:
				gate.unlock("host_event")
				gate.open()
		"completed":
			completed = true
			stage = 6
			print("ACT4 client applied host completion pid=%d seconds=%.1f" % [
				int(payload.get("pid", 0)), float(payload.get("seconds", 0.0))])


# --- Peer membership ----------------------------------------------------------

func on_act4_peer_connected(pid: int) -> void:
	if coop_net == null:
		return
	_act4_sync_bodies()
	_act4_set_presence(pid, true)
	if coop_mode == "host":
		# The host registered this peer in the shared ledger before calling here;
		# every already-connected client must learn the new roster so it can own
		# exactly one body for the newcomer.
		_act4_broadcast_roster()
	if coop_mode == "host" and hud != null:
		hud.show_toast("队友 %d 已连接" % pid, 2.5)


func on_act4_peer_disconnected(pid: int) -> void:
	if coop_net == null:
		return
	_act4_ready04_seen.erase(pid)
	_act4_set_presence(pid, false)
	if platform != null:
		# A leaving body must not keep a handhold or the lever: the grant and
		# the point lock are released before the entity is freed.
		platform.release_grabs_by_peer(pid)
		platform.release_control_by_peer(pid)
	if coop_net.session != null:
		coop_net.session.release_all_for(pid, "disconnect")
	# The body must go with the participant: a leftover entity would keep a dead
	# pid in every broadcast snapshot and in the crystal-carrier lookup.
	var body: EchoPlayer = coop_players.get(pid) as EchoPlayer
	if body != null and body != player:
		if body.carrying != null:
			body.carrying.end_carry(false)
			body.carrying = null
		_act4_despawn_remote_body(pid)
	if coop_mode == "host":
		_act4_broadcast_roster()
	if hud != null:
		hud.show_toast("队友 %d 已断开 · 机械占用已释放" % pid, 3.0)


# --- Scene teardown ----------------------------------------------------------
# Leaving the tree is the authoritative moment this Act 4 world stops being
# usable. The shared CoopNet must be released HERE, before this node and its
# player/crystals are freed, otherwise its snapshot loop keeps reading a dead
# world (`Condition "!is_inside_tree()" is true` on every Act 5 frame).

func _exit_tree() -> void:
	_teardown_coop()


func _teardown_coop() -> void:
	if player != null and is_instance_valid(player):
		if player.carry_changed.is_connected(_on_coop_carry_changed):
			player.carry_changed.disconnect(_on_coop_carry_changed)
		if player.pickup_requested.is_connected(_on_coop_pickup_requested):
			player.pickup_requested.disconnect(_on_coop_pickup_requested)
	if platform != null and is_instance_valid(platform):
		if platform.action_used.is_connected(_on_platform_action_used):
			platform.action_used.disconnect(_on_platform_action_used)
	if coop_net != null:
		coop_net.unbind_act4(self)
	coop_net = null
	coop_players.clear()
	_act4_ready04_seen.clear()
	remote_player = null

