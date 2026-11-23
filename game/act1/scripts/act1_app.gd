class_name Act1App
extends Node3D

## Resonance 01 / Act 01 — "The Silent Mining Station" (integratable chapter).
##
## Host-authoritative Act 01 orchestration, adapted from the standalone
## `deepseek-resonance-01-rebuild-v2` project's `act01.gd`. The world is still
## built procedurally, the player interacts through physical raycasts, and every
## machine transition is validated here. The host owns all flags and credits;
## clients only send intentions and their own body state.
##
## INTEGRATION ADAPTATIONS (this module):
## * All class_names are `Act1*`-prefixed; all res:// paths are module-relative
##   (`res://act1/…`), so the subtree is copy-importable into `res://act1/`.
## * The old `RunState` autoload was replaced by `Act1SessionBridge`.
## * The old local `CoopNet` was replaced by `Act1NetFacade` (thin adapter):
##   standalone → original Act1CoopNet backend; integrated → unified session.
## * The departure ride no longer switches to a local fake "act02_ride" scene.
##   It emits an Act01 completion via `bridge.complete_act01(...)`; the main
##   integration handles the true Act 02/03 transition.

const SPAWN := Vector3(0.0, 0.06, 22.0)
const MAX_PLAYERS := 4
## Above this count the packed flag mask falls back to a full Dictionary on the
## wire (one int shift per flag; 30 leaves 2 bits of headroom under 32).
const ACT1_FLAG_BITS_MAX := 30
const PHASES: Array[String] = ["entry", "power", "vent", "hazard", "departure"]
const PHASE_NAMES := {
	"entry": "入口",
	"power": "电源",
	"vent": "通风",
	"hazard": "事故",
	"departure": "发车",
}
const CREDIT_PHASE := {
	"entry_latch": "entry",
	"entry_door": "entry",
	"entry_shove": "entry",
	"power_dock": "power",
	"power_seat": "power",
	"power_clamp": "power",
	"fan_lock": "vent",
	"fan_coupling": "vent",
	"fan_start": "vent",
	"damper": "vent",
	"governor": "vent",
	"crate_secure": "hazard",
	"brace": "hazard",
	"rescue": "hazard",
	"self_rescue": "hazard",
	"emergency_stop": "hazard",
	"chock": "departure",
	"brake": "departure",
	"cargo": "departure",
	"launch": "departure",
}

# --- network payload guards -------------------------------------------------
# These are application-layer limits on top of the engine's @rpc authority
# check. Keep them generous enough for the authored animations, but bounded:
# a malformed grant must never be able to move a body outside the station.
const NET_ID_MAX_CHARS := 64
const NET_GRANT_MAX_FIELDS := 6
const NET_STATE_MAX_FIELDS := 24
const NET_INTERACTION_KINDS: Array[String] = ["press", "begin", "end", "grab_end"]
const NET_CART_MAX_OFFSET := 3.5
const NET_CLIMB_MAX_DISTANCE := 20.0
const NET_CLIMB_LANDING_RADIUS := 1.25
## Minimum gap between two refusals for the same actor and the same machine.
## Holding E on a machine whose interlock is closed would otherwise re-fire the
## same sentence on every press.
const FEEDBACK_COOLDOWN_MS := 1200

var builder: Act1StationBuilder
var net: Act1NetFacade
var hud: Act1Hud
var bridge: Act1SessionBridge
var local_player: Act1StationPlayer
var remotes: Dictionary = {}
var remote_states: Dictionary = {}
var player_states: Dictionary = {}
var interactables: Dictionary = {}
var flags: Dictionary = {}
var credits: Dictionary = {}
var active_pids: Dictionary = {1: true}
var local_pid := 1
var hold_owner: Dictionary = {}
## Per-player grab ownership: pid -> rail interaction id. Act01 has five rails
## and two+ players, so "who holds which rail" must be tracked per actor. The
## previous single `hold_owner["grab"]` slot made a remote player's request
## depend on the HOST body's grab state (see `_player_grabbing`).
var grab_owner: Dictionary = {}
var cart_operator := 0
var reset_seq := 0
var started_msec := 0
var event_log: Array = []
var _last_y: Dictionary = {}
var _host_clock := 0.0
var _aim_clock := 0.0
var _hud_clock := 0.0
var _gust_phase := "idle"
var _gust_timer := 0.0
var _gust_credited := false
var _rail_obstruction_last := ""
## MECHANICS-001A：电源模块连续"在插座内且静止"的帧数
var _seat_streak := 0
var _handoff_started := false
var _ride_sent := false
var _no_handoff := false
var _capture_seen := {}
var _last_state_dump := 0
var _last_cart_pusher := 0
var _last_door_pusher := 0
## First actor that physically shoved the collapsed gantry. The physics
## verification below runs on the host for every shove request, so crediting
## local_pid there handed the host a second credit for a client's action. The
## per-action owner is recorded on the first accepted press and reused when the
## 54 kg body finally crosses the cleared threshold.
var _last_gantry_pusher := 0
var _last_state_reject_ms := 0
## (pid|machine) -> last refusal timestamp, used to keep a held E from spamming.
const Act1PhysicalLinks := preload("res://act1/scripts/world/act1_physical_links.gd")
const Act1ExploreProps := preload("res://act1/scripts/world/act1_explore_props.gd")
var _feedback_seen: Dictionary = {}
var physical_links: Act1PhysicalLinks = null
var explore_props: Node3D = null


func _ready() -> void:
	started_msec = Time.get_ticks_msec()
	var args := OS.get_cmdline_args()
	_no_handoff = "--no-handoff" in args
	bridge = Act1SessionBridge.new()
	bridge.test_mode = "--test-mode" in args
	_init_flags()
	_setup_input_fallback()
	builder = Act1StationBuilder.new()
	builder.build(self)
	physical_links = Act1PhysicalLinks.new()
	physical_links.setup(self)
	physical_links.refresh(flags, builder)
	explore_props = Act1ExploreProps.new()
	add_child(explore_props)
	explore_props.setup(self)
	_spawn_local_player()
	hud = Act1Hud.new()
	add_child(hud)
	hud.set_objective("① 解除入口封锁", "从外部接驳台进入 K-17 矿站")
	hud.set_participation(_participation_lines())
	hud.fade_to(0.0, 1.8)
	hud.show_intro(6.5)
	_connect_player_signals()
	_join_local_participation()
	net = Act1NetFacade.new()
	add_child(net)
	net.setup(self)
	net.ride_started.connect(_on_net_ride_started)
	if bridge.integrated:
		hud.toast("已接入统一会话 · 完成发车将交接给主整合工程", 4.0)
	else:
		hud.toast("抵达 K-17 · 通信静默 · 从入口气闸进入", 4.0)
	_record("spawn", {"pos": _arr(local_player.global_position), "mode": net.mode})
	if "--capture" in args:
		_capture_checkpoint("spawn")
	# test harness hooks
	if "--autotest" in args:
		var runner := load("res://act1/tests/act1_autotest.gd") as Script
		if runner != null:
			var r: Node = runner.new() as Node
			r.name = "Act1Autotest"
			r.set("stage", self)
			get_tree().root.add_child.call_deferred(r)
	if _has_arg_prefix("--early-coop=") or _has_arg_prefix("--sync3=") or _has_arg_prefix("--attrib="):
		var probe_path := "res://act1/tests/act1_early_service_coop.gd"
		var probe_name := "Act1EarlyServiceCoop"
		if _has_arg_prefix("--sync3="):
			probe_path = "res://act1/tests/act1_sync3.gd"
			probe_name = "Act1Sync3"
		elif _has_arg_prefix("--attrib="):
			probe_path = "res://act1/tests/act1_refusal_attribution.gd"
			probe_name = "Act1RefusalAttribution"
		var early := load(probe_path) as Script
		if early != null:
			var e: Node = early.new() as Node
			e.name = probe_name
			e.set("stage", self)
			get_tree().root.add_child.call_deferred(e)


## Detect a flag whether it was passed before or after the `--` separator: the
## co-op probe runner puts its role argument in user args, while `--autotest`
## stays an engine-level argument.
func _has_arg_prefix(prefix: String) -> bool:
	for list in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		for a in list:
			if str(a).begins_with(prefix):
				return true
	return false


func _init_flags() -> void:
	flags = {
		"latch_released": false,
		"debris_cleared": false,
		"door_open": false,
		"power_docked": false,
		"power_seated": false,
		"power_clamped": false,
		"power_ready": false,
		"rotor_lock_released": false,
		"coupling_engaged": false,
		"fan_started": false,
		"damper_open": false,
		"vent_complete": false,
		"crate_secured": false,
		"rail_cleared": false,
		"chock_removed": false,
		"brake_released": false,
		"cargo_secured": false,
		"departure_started": false,
		"completed": false,
		"handoff": false,
	}


func _setup_input_fallback() -> void:
	# Idempotent input map (also covers exported builds where the input section
	# could be stripped). Reuses the unified action names where Act 01 agrees
	# with the 04-05 base map; Q-let-go is module-specific (`act1_cancel`) so it
	# never overwrites the unified `cancel=Esc`.
	var fallback := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E,
		"emergency": KEY_X, "reset_level": KEY_R, "toggle_debug": KEY_F1,
		"act1_cancel": KEY_Q,
	}
	for a in fallback:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = int(fallback[a])
			InputMap.action_add_event(a, ev)


func _spawn_local_player() -> void:
	local_player = Act1StationPlayer.new()
	local_player.name = "LocalPlayer"
	local_player.stage = self
	local_player.player_pid = 1
	add_child(local_player)
	local_player.teleport(SPAWN, 0.0, -0.05)
	player_states[1] = local_player.get_state_packet()


func _connect_player_signals() -> void:
	local_player.prompt_changed.connect(_on_prompt_changed)
	local_player.downed_changed.connect(_on_local_downed_changed)
	local_player.grabbed_changed.connect(func(_v: bool) -> void: pass)


func _join_local_participation() -> void:
	_init_participant(local_pid, "本地玩家" if not net or not net.online else "玩家%d" % local_pid)


func _init_participant(pid: int, name: String) -> void:
	if not credits.has(pid):
		credits[pid] = {
			"name": name,
			"kinds": {},
			"phases": {},
			"active": true,
			"downed": false,
			# A player joining after the ventilation phase can only work on the
			# station; requiring a second unavailable phase would soft-lock them.
			"late_join": bool(flags.get("vent_complete", false)),
		}
	active_pids[pid] = true


func make_interactable(id: String, prompt: String, pos: Vector3, size: Vector3, hold: bool = false) -> Act1Interactable:
	var point := Act1Interactable.new()
	point.setup(id, prompt, size, hold)
	point.stage = self
	point.position = pos
	add_child(point)
	interactables[id] = point
	return point


func get_flag(key: String) -> bool:
	return bool(flags.get(key, false))


func set_flag(key: String, value: bool) -> void:
	flags[key] = value


func is_host_authority() -> bool:
	return net == null or net.is_authority()


func get_vent_pressure() -> float:
	return builder.vent.pressure if builder != null and builder.vent != null else 0.0


func get_wind_acceleration(at: Vector3, grabbing: bool = false) -> Vector3:
	if builder == null or builder.vent == null:
		return Vector3.ZERO
	return builder.vent.get_wind_acceleration(at, grabbing)


func get_phase_credit(pid: int) -> int:
	var rec: Dictionary = credits.get(pid, {})
	if rec.is_empty():
		return 0
	return (rec.get("phases", {}) as Dictionary).size()


func has_phase_credit(pid: int, phase: String) -> bool:
	var rec: Dictionary = credits.get(pid, {})
	if rec.is_empty():
		return false
	return (rec.get("phases", {}) as Dictionary).has(phase)


func can_participate(pid: int) -> bool:
	var rec: Dictionary = credits.get(pid, {})
	var required := 1 if bool(rec.get("late_join", false)) else 2
	return get_phase_credit(pid) >= required


func required_phases(pid: int) -> int:
	var rec: Dictionary = credits.get(pid, {})
	return 1 if bool(rec.get("late_join", false)) else 2


func all_active_ready() -> bool:
	for pid in active_pids.keys():
		if not can_participate(int(pid)):
			return false
	return true


func all_active_aboard() -> bool:
	if builder == null or builder.mine_cart == null:
		return false
	if active_pids.is_empty():
		return false
	for pid in active_pids.keys():
		var pos: Vector3 = _player_position(int(pid))
		if not builder.mine_cart.is_player_aboard(pos):
			return false
	return true


func _player_position(pid: int) -> Vector3:
	if pid == local_pid and local_player != null:
		return local_player.global_position
	var st: Dictionary = remote_states.get(pid, {})
	return st.get("pos", Vector3(0, -100, 0))


func _player_for(pid: int) -> Act1StationPlayer:
	if pid == local_pid:
		return local_player
	return null


func _credit(pid: int, kind: String, detail: String = "") -> void:
	if not CREDIT_PHASE.has(kind):
		return
	var rec: Dictionary = credits.get(pid, {})
	if rec.is_empty():
		_init_participant(pid, "玩家%d" % pid)
		rec = credits[pid]
	var kinds: Dictionary = rec["kinds"]
	if kinds.has(kind):
		return
	var phase: String = CREDIT_PHASE[kind]
	kinds[kind] = Time.get_ticks_msec()
	var phases: Dictionary = rec["phases"]
	phases[phase] = int(phases.get(phase, 0)) + 1
	_record("credit", {"pid": pid, "kind": kind, "phase": phase, "detail": detail})
	if hud != null and pid == local_pid:
		hud.toast("有效参与：%s · %s" % [PHASE_NAMES.get(phase, phase), detail], 2.6)


func _on_prompt_changed(text: String) -> void:
	if hud != null:
		hud.set_prompt(text)


func _on_local_downed_changed(value: bool) -> void:
	if value:
		hud.toast("你从维修栈桥跌落 · 沿梯自救或等待队友操作救援卷扬", 4.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_level"):
		if net != null and net.mode == "client":
			net.submit_reset()
		elif net != null and net.is_host and net.peer_count() > 1:
			host_reset_run(0)
		else:
			reset_seq += 1
			_reset_state()
	if net != null:
		if builder != null and builder.vent != null:
			# Only the authority (host/solo) advances the 6 s pressure test; a
			# client mirrors the host's timer and completion from the snapshot.
			builder.vent.authority_test = net.is_authority()
		if net.is_authority():
			_host_update(delta)
		else:
			_client_update(delta)
	_update_hud(delta)
	if physical_links != null:
		physical_links.refresh(flags, builder)
	if Input.is_action_just_pressed("toggle_debug"):
		bridge.debug_enabled = not bridge.debug_enabled
		if bridge.debug_enabled:
			hud.show_debug(_debug_text())
		else:
			hud.hide_debug()


func _host_update(delta: float) -> void:
	_host_clock += delta
	_update_physics_verifications()
	# host local state mirror
	player_states[local_pid] = local_player.get_state_packet()
	if cart_operator == local_pid:
		builder.power_cart.set_axis(Input.get_axis("move_back", "move_forward"))
	_prepare_gust(delta)
	# pressure completion
	_sync_fan_interlock()
	_sync_wheel_chock()
	_sync_parking_brake()
	_sync_cargo()
	if builder.vent.vent_complete and not flags["vent_complete"]:
		flags["vent_complete"] = true
		_vent_feedback("通风压力测试通过 · 深层站台已解锁", 4.0)
		_credit(local_pid, "damper", "完成主通风压力测试")
	# handoff
	if flags["departure_started"] and builder.mine_cart.departing:
		if builder.mine_cart.handoff and not _handoff_started:
			flags["handoff"] = true
			_begin_handoff_host()
	if bridge.debug_enabled and _host_clock - _last_state_dump > 0.5:
		_last_state_dump = _host_clock
		hud.show_debug(_debug_text())


func _client_update(_delta: float) -> void:
	# The client's own body physics runs in Act1StationPlayer. This function only
	# handles local presentation that must happen before the next snapshot.
	# Only a power-trolley grip is authority-bound to cart_operator. A `ride`
	# grant attaches the body to the departing mine cart, whose operator is 0;
	# detaching that attachment would silently drop every client ride.
	if local_player.external_hold and local_player.attach_action_id == "cart_push" \
			and cart_operator != local_pid:
		local_player.detach()
	if local_player.grabbing and hold_owner.get("grab", 0) != local_pid and not hold_owner.is_empty():
		pass


func _update_physics_verifications() -> void:
	if builder.entry_obstruction != null:
		var p := builder.entry_obstruction.global_position
		var cleared := absf(p.x) > 1.55 and p.z > 7.8 and p.z < 10.1
		if cleared and not flags["debris_cleared"]:
			flags["debris_cleared"] = true
			hud.toast("门轨清理完毕 · 机械门闩现在可以释放", 3.0)
			# Credit the actor who actually shoved the gantry; a body that only
			# walked into the body (or the host's physics tick) must not earn a
			# second credit for the same action.
			var shover: int = _last_gantry_pusher if _last_gantry_pusher != 0 else local_pid
			_credit(shover, "entry_shove", "推开压住门轨的维护架")
			if interactables.has("shove_gantry"):
				(interactables["shove_gantry"] as Act1Interactable).set_interaction_enabled(false)
	# MECHANICS-001A：电源模块是否"就位"由**真实刚体状态**判定，
	# 不再由 Tween 完成回调决定。条件：模块中心落在插座容差内且基本静止。
	if builder.power_module != null and builder.power_cart != null:
		var mod: RigidBody3D = builder.power_module
		var flat := Vector2(mod.global_position.x - Act1StationBuilder.SOCKET.x,
			mod.global_position.z - Act1StationBuilder.SOCKET.z).length()
		var seated: bool = flat < 0.40 and mod.linear_velocity.length() < 0.25
		if seated and not builder.power_cart.module_transferred_flag:
			_seat_streak += 1
		else:
			_seat_streak = 0
		if _seat_streak >= 20:
			builder.power_cart.mark_module_seated()
		# MECHANICS-001B-R2：通电 = 实体锁爪真的转到锁止角 + 模块仍在插座内且静止
		if builder.power_cart.clamp_locked() and not bool(flags.get("power_clamped", false)):
			flags["power_clamped"] = true
			flags["power_ready"] = true
			hud.toast("旋转锁爪已闭合 · 电源锁定 · 风机控制回路得电", 3.0)
			_play_sfx("lock_success", Act1StationBuilder.SOCKET, -1.0)
			_builder_power_light_on()
	if builder.rail_obstacle != null and builder.power_cart != null:
		var p := builder.rail_obstacle.global_position
		var cart_x := builder.power_cart.global_position.x
		var blocked: bool = not bool(flags["rail_cleared"]) and absf(p.z - Act1PowerCart.RAIL_Z) < 0.55 and p.x > cart_x and (p.x - cart_x) < 3.0
		builder.power_cart.path_blocked = blocked
	# The crate falling is not scripted: it is read from its physical position.
	if builder.wind_crate != null:
		if not flags["crate_secured"] and builder.wind_crate.global_position.y < 1.0 and not flags.get("crate_fell", false):
			flags["crate_fell"] = true
			hud.toast("仪器箱被吹落到下层维修区 · 可从梯井取回", 4.0)
	# If all powered machines are done, ensure the flag is visible to clients.
	if flags["power_clamped"] and not flags["power_ready"]:
		flags["power_ready"] = true


func _prepare_gust(delta: float) -> void:
	var vent := builder.vent
	if vent == null:
		return
	if _gust_phase == "idle":
		if flags["damper_open"] and vent.speed > 0.58 and not bool(flags.get("gust_done", false)):
			_gust_phase = "warning"
			_gust_timer = 3.2
			vent.gust_factor = 1.0
			hud.toast("风道压力失衡 · 抓住栏杆！3 秒后泄压冲击", 4.0)
			net_sync_message("风道压力失衡 · 抓住栏杆！", 4.0)
			_record("gust_warning", {"speed": vent.speed})
	elif _gust_phase == "warning":
		_gust_timer -= delta
		if _gust_timer <= 0.0:
			_gust_phase = "active"
			_gust_timer = 4.2
			vent.gust_factor = 1.9
			_gust_credited = false
			hud.toast("泄压冲击！强风横扫维修栈桥", 3.0)
			net_sync_message("泄压冲击！强风横扫维修栈桥", 3.0)
			_record("gust_active", {"speed": vent.speed})
	elif _gust_phase == "active":
		_gust_timer -= delta
		# Verified brace credit: the host knows who is actually holding a rail.
		if not _gust_credited:
			for pid in active_pids.keys():
				var p := _player_position(int(pid))
				if pid == local_pid and local_player.grabbing:
					_credit(int(pid), "brace", "在泄压冲击中抓住栏杆")
					_gust_credited = true
				elif pid != local_pid:
					var st: Dictionary = remote_states.get(int(pid), {})
					if bool(st.get("grab", false)):
						_credit(int(pid), "brace", "在泄压冲击中抓住栏杆")
						_gust_credited = true
		if _gust_timer <= 0.0:
			_gust_phase = "done"
			vent.gust_factor = 1.0
			flags["gust_done"] = true
			hud.toast("冲击过去 · 风机仍在高负载运行", 2.5)


## ---------------------------------------------------------------------------
## Interaction request path
## ---------------------------------------------------------------------------

func request_interaction(id: String, player: Node, kind: String) -> void:
	var pid := local_pid
	if player != null and player == local_player:
		pid = local_pid
	if net != null and net.mode == "client":
		net.submit_interaction(id, kind)
		return
	if not _validate_interaction(pid, id, kind):
		return
	_execute_interaction(pid, id, kind)


func host_handle_interaction_request(pid: int, id: String, kind: String) -> void:
	if not net.is_host:
		return
	if not _validate_interaction(pid, id, kind):
		print("ACT1_INTERACTION_REJECT pid=%d id=%s kind=%s reason=validation" % [pid, id, kind])
		return
	_execute_interaction(pid, id, kind)


func _validate_interaction(pid: int, id: String, kind: String) -> bool:
	if pid <= 0 or id.length() == 0 or id.length() > NET_ID_MAX_CHARS:
		return false
	if not NET_INTERACTION_KINDS.has(kind):
		return false
	if not interactables.has(id):
		return false
	# A release is still an authorization boundary: it may only clear the
	# sender's own hold, never another player's authored interaction.
	if kind == "end" or kind == "grab_end":
		if id == "cart_push":
			return cart_operator == pid
		if id == "door_handle":
			return int(hold_owner.get("door_handle", 0)) == pid
		if id.begins_with("grab_"):
			return str(grab_owner.get(pid, "")) == id
		return false
	var target: Act1Interactable = interactables[id]
	if target == null or not is_instance_valid(target) or not target.enabled:
		return false
	var pos: Vector3 = _player_position(pid)
	if not pos.is_finite() or pos.y < -8.0 or pos.y > 30.0:
		return false
	if pos.distance_to(target.global_position) > 4.25:
		return false
	return true


func _execute_interaction(pid: int, id: String, kind: String) -> void:
	var vent := builder.vent
	var cart := builder.power_cart
	var door := builder.door
	var mine := builder.mine_cart
	var crate := builder.wind_crate
	if id == "shove_gantry":
		if kind != "press" or flags["debris_cleared"]:
			return
		if builder.entry_obstruction == null:
			return
		# The same 54 kg body can be shoved more than once; only the first real
		# actor owns the credit. Later helpers still apply the physical impulse.
		if _last_gantry_pusher == 0:
			_last_gantry_pusher = pid
		builder.entry_obstruction.sleeping = false
		builder.entry_obstruction.apply_central_impulse(Vector3(-builder.entry_obstruction.mass * 10.0, builder.entry_obstruction.mass * 0.20, 0))
		if _last_gantry_pusher == pid:
			_credit(pid, "entry_shove", "推开压住门轨的维护架")
		_send_local_toast("金属摩擦 · 维护架被推开了一截", 2.2)
		_play_sfx("metal_clank", builder.entry_obstruction.global_position, -2.0)
	elif id == "rail_shove":
		if kind != "press" or builder.rail_obstacle == null:
			return
		builder.rail_obstacle.sleeping = false
		builder.rail_obstacle.apply_central_impulse(Vector3(0, builder.rail_obstacle.mass * 1.6, -builder.rail_obstacle.mass * 7.5))
		flags["rail_cleared"] = true
		builder.power_cart.path_blocked = false
		if interactables.has("rail_shove"):
			(interactables["rail_shove"] as Act1Interactable).set_interaction_enabled(false)
		_send_local_toast("断裂支架被踢下轨道 · 推车路径已清", 2.5)
		_play_sfx("metal_clank", builder.rail_obstacle.global_position, -2.0)
	elif id == "release_latch":
		if kind != "press" or not flags["debris_cleared"]:
			if kind == "press" and not flags["debris_cleared"]:
				_send_local_toast("门轨被塌落维护架压住 · 先推开它")
			return
		if flags["latch_released"]:
			return
		flags["latch_released"] = true
		_credit(pid, "entry_latch", "释放工业门机械闩")
		_send_local_toast("咔哒 · 门闩已释放，按住 E 推门")
		_play_sfx("door_latch", Vector3(2.7, 1.5, 9.4), -4.0)
	elif id == "door_handle":
		if kind == "begin":
			var ok := door.begin_push(pid)
			if ok:
				hold_owner["door_handle"] = pid
				_last_door_pusher = pid
				_send_local_toast("门体很重 · 保持按住 E")
			else:
				_send_local_toast("门仍被锁住或门轨未清")
		elif kind == "end":
			door.end_push(pid)
			hold_owner.erase("door_handle")
	elif id == "cart_push":
		if kind == "begin":
			if flags["power_clamped"]:
				# Already delivered: staying silent is correct, nothing is wrong.
				return
			if not flags["door_open"]:
				_refuse(pid, "cart_push", "推车被门禁挡住 · 先打开工业入口门")
				return
			if cart.begin_push(pid):
				cart_operator = pid
				_last_cart_pusher = pid
				hold_owner["cart_push"] = pid
				if pid == local_pid and local_player != null:
					local_player.attach_to(cart, Vector3(-2.05, 0.02, 0.0), -PI * 0.5, "cart_push")
					_send_local_toast("握住推车 · W/S 推拉，送模块到导轨插座")
				else:
					_send_grant(pid, "cart_push", {
						"attach": true,
						"offset": [-2.05, 0.02, 0.0],
						"yaw": -PI * 0.5,
					})
				_play_sfx("door_grind", cart.global_position, -8.0)
			else:
				# `begin_push()` refuses only in two later states: the cart is
				# walking itself into the dock, or the module already left it. The
				# handle is no longer the control that matters, so name the one
				# that is. Public flags only — no reach into the cart's internals.
				if cart.module_transferred_flag:
					_refuse(pid, "cart_push", "推车已经卸下电源模块 · 改用导轨绞盘")
				else:
					_refuse(pid, "cart_push", "推车正在自动对准插座 · 松手等它入坞")
		elif kind == "end":
			if cart_operator == pid:
				cart_operator = 0
				hold_owner.erase("cart_push")
				cart.end_push(pid)
				if pid == local_pid and local_player != null:
					local_player.detach()
				else:
					_send_grant(pid, "cart_push", {"attach": false})
	elif id == "power_winch":
		if kind != "press":
			return
		if not cart.docked or cart.module_transferred_flag:
			_send_local_toast("推车尚未对准插座 · 用 W/S 微调后再锁定")
			return
		cart.transfer_module(Act1StationBuilder.SOCKET)
		_credit(pid, "power_seat", "操作导轨绞盘把电源模块送入插座")
		_send_local_toast("导轨绞盘转动 · 模块沿导轨滑入插座")
		_play_sfx("servo", Act1StationBuilder.SOCKET, -2.0)
	elif id == "power_clamp":
		if kind != "press":
			return
		if flags["power_clamped"]:
			return
		if not cart.module_transferred_flag:
			_refuse(pid, "power_clamp", "机械夹夹不到模块 · 先用导轨绞盘把模块送入插座")
			return
		# MECHANICS-001B-R2：E 只发出夹紧指令；真正的锁止由实体锁爪转到锁止角后判定
		cart.set_clamp(true)
		_credit(pid, "power_clamp", "启动电源模块旋转锁爪")
		_send_local_toast("锁爪电机启动 · 等待机械闭合到位（再按一次可松开）")
		_play_sfx("servo", Act1StationBuilder.SOCKET, -1.0)
	elif id == "rotor_lock":
		# The rotor lock is a mechanical pin: pulling it needs no control-circuit
		# power, so it may be done before `power_ready` (advance maintenance).
		# The fan itself stays gated on `power_ready` at `start_fan`, so an
		# unpowered fan can never spin up.
		if kind != "press" or flags["rotor_lock_released"]:
			return
		# MECHANICS-001C：E 只启动执行器；销钉是否真的拔出由机械位置判定
		if builder.fan_interlock == null or not builder.fan_interlock.pull_rotor_lock():
			_send_local_toast("锁销执行器无响应")
			return
		_credit(pid, "fan_lock", "启动转子锁销拔出执行器")
		_send_local_toast("执行器拉动锁销 · 等待销钉脱开")
		_play_sfx("pin_pull", Vector3(7.6, 1.2, -23.6), -3.0)
	elif id == "coupling":
		if kind != "press" or flags["coupling_engaged"]:
			return
		if not flags["rotor_lock_released"]:
			_send_local_toast("联轴器推不动 · 先拔出转子机械锁销")
			return
		# MECHANICS-001C：E 只启动推入执行器；啮合由滑套真实位置判定
		if builder.fan_interlock == null or not builder.fan_interlock.push_coupling():
			_send_local_toast("联轴器执行器无响应")
			return
		_credit(pid, "fan_coupling", "启动联轴器推入执行器")
		_send_local_toast("执行器推动联轴器 · 等待啮合到位")
		_play_sfx("metal_clank", Vector3(8.1, 1.4, -29.05), -3.0)
	elif id == "start_fan":
		if kind != "press":
			return
		if flags["fan_started"]:
			_send_local_toast("风机已经在转动 · 用调速器与风门控制")
			return
		if builder.fan_interlock == null or not builder.fan_interlock.machine_ready():
			_send_local_toast("启动手柄无反应 · 转子锁未脱开或联轴器未啮合")
			return
		# Last line of defence: a fan without auxiliary power must never start,
		# even when the rotor lock and coupling were prepared early.
		if not flags["power_ready"]:
			_send_local_toast("启动手柄无反应 · 控制回路未得电，先恢复辅助电源")
			return
		flags["fan_started"] = true
		vent.set_running(true)
		vent.set_emergency(false)
		_credit(pid, "fan_start", "启动主通风机")
		_send_local_toast("主风机启动 · 转子正在建立惯量")
		_play_sfx("servo", Act1Ventilation.FAN_POS, 0.0)
	elif id == "governor":
		if kind != "press" or not flags["fan_started"]:
			return
		var nxt := Act1Ventilation.next_governor_value(vent.governor)
		vent.set_governor(nxt)
		_credit(pid, "governor", "调整风机调速器")
		_vent_feedback(_governor_feedback(nxt))
		_play_sfx("lever_click", Vector3(-8.0, 1.4, -23.3), -4.0)
	elif id == "damper":
		if kind != "press" or not flags["fan_started"]:
			return
		flags["damper_open"] = not flags["damper_open"]
		vent.set_damper_target(1.0 if flags["damper_open"] else 0.0)
		_credit(pid, "damper", "切换双风道风门")
		if flags["damper_open"]:
			var target := int(round(Act1Ventilation.PRESSURE_MIN * 100.0))
			if vent.governor > Act1Ventilation.PRESSURE_MIN:
				_vent_feedback("主风道开启 · 调速器 %d%% · 风压可达 %d%% 目标 · 稳定 %.0f 秒" % [
					int(round(vent.governor * 100.0)), target, Act1Ventilation.PRESSURE_TEST_SECONDS])
			else:
				_vent_feedback("主风道开启 · 调速器只有 %d%%，风压只能到约 %d%%（目标 ≥%d%%）· 按 E 调速器升到 %d%%" % [
					int(round(vent.governor * 100.0)), int(round(vent.governor * 100.0)), target,
					int(round(Act1Ventilation.next_governor_value(vent.governor) * 100.0))])
		else:
			_vent_feedback("主风道关闭 · 风压会掉到 %d%% 目标以下，测试计时回落" % int(round(Act1Ventilation.PRESSURE_MIN * 100.0)))
		_play_sfx("door_grind", Act1Ventilation.FAN_POS, -2.0)
	elif id == "emergency_stop":
		if kind != "press" or not flags["fan_started"]:
			return
		vent.set_emergency(not vent.emergency)
		_credit(pid, "emergency_stop", "执行紧急停机/恢复")
		_send_local_toast("紧急停机%s" % ("已接通 · 风场卸压" if vent.emergency else "解除 · 风机重新加载"))
		_play_sfx("alarm", Act1Ventilation.FAN_POS, -1.0)
	elif id.begins_with("grab_"):
		if kind == "press":
			# Judge the grab state of the ACTUAL requester (`pid`), never the
			# host's local body: `_execute_interaction` runs on the host for a
			# remote player's request too. `grab_owner` is the authoritative
			# per-actor ledger; if the actor's body already let go (Q cancel
			# releases locally without a request) the entry is stale and may be
			# replaced. A player that is genuinely still holding keeps its rail
			# and a duplicate press is ignored.
			if grab_owner.has(pid):
				if _player_grabbing(pid):
					return
				grab_owner.erase(pid)
			grab_owner[pid] = id
			if pid == local_pid:
				_grab_local(id)
			else:
				_send_grant(pid, id, {"grab": true, "anchor": _arr(interactables[id].global_position)})
			_send_local_toast("抓住扶手 · 风场中保持身体")
		elif kind == "grab_end" or kind == "end":
			if str(grab_owner.get(pid, "")) == id:
				grab_owner.erase(pid)
				if pid == local_pid:
					local_player.release_grab()
				else:
					_send_grant(pid, id, {"grab": false})
	elif id == "secure_crate":
		if kind != "press" or flags["crate_secured"]:
			return
		flags["crate_secured"] = true
		crate.set_secured(true)
		_credit(pid, "crate_secure", "固定风道上的仪器箱")
		_send_local_toast("固定带扣紧 · 仪器箱不会在冲击中滑落")
		_play_sfx("lever_click", builder.wind_crate.global_position, -3.0)
	elif id == "self_rescue":
		if kind != "press" or not local_down_or_remote_downed(pid):
			return
		if _player_position(pid).distance_to(Vector3(4.5, -2.0, -22.2)) > 4.4:
			return
		_credit(pid, "self_rescue", "沿维护梯自救")
		_climb_pid(pid, Vector3(3.9, -2.0, -22.2), Vector3(2.35, Act1StationBuilder.CATWALK_Y + 0.08, -22.2), 2.4)
		_send_local_toast("沿维护梯爬回栈桥", 2.5)
	elif id == "rescue_winch":
		if kind != "press":
			return
		var downed_pid := _find_downed_pid()
		if downed_pid == 0:
			_send_local_toast("卷扬没有检测到倒下的队员")
			return
		if downed_pid == pid:
			_send_local_toast("不能操作卷扬救援自己 · 沿维护梯自救")
			return
		var rescue_from := _player_position(downed_pid)
		_credit(pid, "rescue", "操作救援卷扬拉起队友")
		_climb_pid(downed_pid, rescue_from, Vector3(2.25, Act1StationBuilder.CATWALK_Y + 0.10, -22.8), 3.2)
		_send_local_toast("救援卷扬启动 · 队友正在被拉回栈桥", 3.5)
		_play_sfx("servo", Vector3(0.95, Act1StationBuilder.CATWALK_Y + 1.0, -22.6), -2.0)
	elif id == "chock":
		if kind != "press":
			return
		if flags["chock_removed"]:
			return
		if not flags["vent_complete"]:
			_refuse(pid, "chock", "止轮楔卡在轮下 · 通风未恢复，站台仍被联锁")
			return
		# MECHANICS-001D：E 只启动拖出执行器；楔块是否真的脱离轮下由刚体位置判定
		if builder.wheel_chock == null or not builder.wheel_chock.pull():
			_send_local_toast("撬棍没有着力点 · 检查止轮楔位置")
			return
		_credit(pid, "chock", "启动止轮楔拖出执行器")
		_send_local_toast("执行器在拖止轮楔 · 等待楔块脱离轮下")
		_play_sfx("metal_clank", Vector3(-5.62, 0.2, -46.8), -3.0)
	elif id == "parking_brake":
		if kind != "press":
			return
		if flags["brake_released"]:
			return
		# The chock holds the wheels: releasing the brake first would let the cart
		# roll. This ordering is the machine's, not a rule invented here.
		if not flags["chock_removed"]:
			_refuse(pid, "parking_brake", "闸把压不下去 · 先移走车轮止轮楔")
			return
		# MECHANICS-001E-R2：E 只启动抽出执行器；解除由销爪真实行程判定
		if builder.parking_brake == null or not builder.parking_brake.release_brake():
			_send_local_toast("制动执行器无响应 · 检查销爪是否卡住")
			return
		_credit(pid, "brake", "扳动停车制动手柄")
		_send_local_toast("执行器在抽销爪 · 等待销爪退出齿圈")
		_play_sfx("lever_click", Vector3(6.4, 2.4, -50.0), -3.0)
	elif id == "cargo":
		if kind != "press":
			return
		var rig: Act1CargoRig = builder.cargo_rig
		if rig == null:
			_send_local_toast("货舱固定带系统缺失")
			return
		if rig.secured():
			# 已锁定：棘轮不再接受行程（提示语已说明用锁扣手柄释放），重复按键保持安静
			return
		if not flags["chock_removed"]:
			_refuse(pid, "cargo", "固定带拉不动 · 先移走车轮止轮楔")
			return
		if not flags["brake_released"]:
			_refuse(pid, "cargo", "固定带被制动联锁锁住 · 先释放停车制动")
			return
		# MECHANICS-001F：E 只启动一个棘轮行程；是否"固定"由张力/棘爪/锁扣的真实状态判定
		if not rig.pump():
			if rig.lever_busy():
				_send_local_toast("棘轮正在收紧 · 等这一档到位")
			elif not rig.crate_in_zone():
				_refuse(pid, "cargo", "货物没摆正在货台上 · 固定带扣不上")
			else:
				_send_local_toast("棘轮已到行程末端 · 张力 %.0f N" % rig.tension())
			return
		_credit(pid, "cargo", "操作货舱棘轮张紧固定带")
		_send_local_toast("棘轮转过一齿 · 固定带正在收紧（%d/%d 齿）" % [
			rig.clicks + 1, Act1CargoRig.MAX_CLICKS])
		_play_sfx("lever_click", rig.global_position + Act1CargoRig.DRUM_ANCHOR, -3.0)
	elif id == "cargo_latch":
		if kind != "press":
			return
		var rig2: Act1CargoRig = builder.cargo_rig
		if rig2 == null or not rig2.open_latch():
			_send_local_toast("锁扣已经打开，或固定带本来就没有张力")
			return
		_credit(pid, "cargo_release", "释放货舱固定带机械锁扣")
		_send_local_toast("锁扣打开 · 固定带在张力下回卷，货物恢复自由")
		_play_sfx("latch", rig2.global_position + Act1CargoRig.DRUM_ANCHOR, -3.0)
	elif id == "launch_cart":
		if kind != "press":
			return
		if not _launch_conditions_ok():
			_send_local_toast(_launch_block_reason())
			return
		flags["departure_started"] = true
		flags["completed"] = true
		_credit(pid, "launch", "启动矿车发车联锁")
		mine.begin_departure()
		_send_local_toast("发车联锁通过 · 矿车正在驶入深层轨道", 5.0)
		_play_sfx("ready", mine.global_position, 0.0)
	elif id.begins_with("explore_") and explore_props != null:
		if kind == "press":
			explore_props.trigger(id, pid, self)


func _launch_conditions_ok() -> bool:
	if not flags["vent_complete"]:
		return false
	if not flags["chock_removed"] or not flags["brake_released"] or not flags["cargo_secured"]:
		return false
	if not all_active_aboard():
		return false
	if not all_active_ready():
		return false
	if get_vent_pressure() < Act1Ventilation.PRESSURE_MIN:
		return false
	return true


func _launch_block_reason() -> String:
	if not flags["vent_complete"]:
		return "发车联锁：通风未恢复"
	if not flags["chock_removed"]:
		return "发车联锁：车轮止轮楔未移除"
	if not flags["brake_released"]:
		return "发车联锁：停车制动未释放"
	if not flags["cargo_secured"]:
		return "发车联锁：货舱固定带未拉紧"
	if not all_active_aboard():
		return "发车联锁：仍有队友未进入车厢"
	if not all_active_ready():
		return "合作检查：每名在线玩家需要在至少两个工序中留下真实改变"
	if get_vent_pressure() < Act1Ventilation.PRESSURE_MIN:
		return "发车联锁：通风压力不足（当前 %d%%，需要 ≥%d%%）· 用调速器升档" % [
			int(round(get_vent_pressure() * 100.0)), int(round(Act1Ventilation.PRESSURE_MIN * 100.0))]
	return "发车联锁未就绪"


## Ventilation feedback shared by host and client. The host owns the numbers;
## broadcasting the same sentence keeps both screens on the same story.
## MECHANICS-001C：把真实机械位置同步成任务状态；机械不成立时风机必须停
## MECHANICS-001D：止轮楔状态由真实刚体位置同步（不再是按 E 隐藏网格）
## MECHANICS-001E-R2：制动状态由销爪真实行程同步
func _sync_parking_brake() -> void:
	if builder == null or builder.parking_brake == null:
		return
	var rel: bool = builder.parking_brake.released()
	if rel and not bool(flags.get("brake_released", false)):
		flags["brake_released"] = true
		_send_local_toast("停车制动已解除 · 销爪退出齿圈")
	elif (not rel) and bool(flags.get("brake_released", false)):
		flags["brake_released"] = false
		_send_local_toast("停车制动重新施加 · 销爪伸入齿圈")


## MECHANICS-001F：货舱固定状态由真实机械状态同步（张力 + 棘爪 + 锁扣 + 货物在货台）
## 发车前若固定带松脱或货物失去约束，cargo_secured 会恢复 false；
## 已经开始剧情发车之后不无条件刹停矿车：只报警并如实把状态回退。
func _sync_cargo() -> void:
	if builder == null or builder.cargo_rig == null:
		return
	var rig: Act1CargoRig = builder.cargo_rig
	if rig.latch_point != null:
		rig.latch_point.set_interaction_enabled(rig.clicks > 0)
	var sec: bool = rig.secured()
	var had: bool = bool(flags.get("cargo_secured", false))
	if sec and not had:
		flags["cargo_secured"] = true
		_send_local_toast("货舱固定带达到工作张力 %.0f N · 棘爪落位 · 发车联锁该项完成" % rig.tension(), 3.5)
		_play_sfx("metal_clank", rig.global_position + Act1CargoRig.DRUM_ANCHOR, -3.0)
	elif (not sec) and had:
		flags["cargo_secured"] = false
		if bool(flags.get("departure_started", false)):
			flags["cargo_lost_in_transit"] = true
			_send_local_toast("货舱固定带在行驶中松脱 · 货物失去约束（矿车继续前进）", 4.0)
		else:
			_send_local_toast("货舱固定带失去约束 · 发车联锁中断", 3.0)


func _sync_wheel_chock() -> void:
	if builder == null or builder.wheel_chock == null:
		return
	if builder.wheel_chock.removed() and not bool(flags.get("chock_removed", false)):
		flags["chock_removed"] = true
		_send_local_toast("止轮楔已拖出 · 车轮仍被机械制动锁住")
		_play_sfx("metal_clank", Vector3(-5.62, 0.2, -46.8), -3.0)


func _sync_fan_interlock() -> void:
	if builder == null or builder.fan_interlock == null or builder.vent == null:
		return
	var il: Act1FanInterlock = builder.fan_interlock
	var released: bool = il.rotor_released()
	var engaged: bool = il.coupling_engaged()
	if released and not bool(flags.get("rotor_lock_released", false)):
		flags["rotor_lock_released"] = true
		_send_local_toast("锁销已脱开 · 转子可自由转动")
	if engaged and not bool(flags.get("coupling_engaged", false)):
		flags["coupling_engaged"] = true
		_send_local_toast("联轴器啮合到位 · 动力可传递")
	if (not released or not engaged) and bool(flags.get("fan_started", false)):
		flags["fan_started"] = false
		builder.vent.set_running(false)
		_send_local_toast("机械联锁断开 · 主风机失去动力")


func _vent_feedback(text: String, seconds := 4.0) -> void:
	_send_local_toast(text, seconds)
	net_sync_message(text, seconds)


func _governor_feedback(value: float) -> String:
	var pct := int(round(value * 100.0))
	var target := int(round(Act1Ventilation.PRESSURE_MIN * 100.0))
	if value > Act1Ventilation.PRESSURE_MIN:
		return "调速器 → %d%% · 高于 %d%% 目标 · 保持主风道开启 %.0f 秒" % [
			pct, target, Act1Ventilation.PRESSURE_TEST_SECONDS]
	var nxt := int(round(Act1Ventilation.next_governor_value(value) * 100.0))
	return "调速器 → %d%% · 低于 %d%% 目标（风压只有约 %d%%）· 再按一次 E 调到 %d%%" % [pct, target, pct, nxt]


## Live prompts on the three fan interlocks. They read the same flags the press
## handler reads, so the sentence on screen is always exactly why a press would
## be accepted or refused — and they make the "prepare early, power still gates
## the start" rule visible before the player presses E.
func _rotor_lock_prompt(_player: Node = null) -> String:
	if bool(flags.get("rotor_lock_released", false)):
		return "转子机械锁已拔出"
	if bool(flags.get("power_ready", false)):
		return "E 拔出转子机械锁销"
	return "E 拔出转子机械锁销（可提前检修 · 风机需得电才能启动）"


func _coupling_prompt(_player: Node = null) -> String:
	if bool(flags.get("coupling_engaged", false)):
		return "传动联轴器已接合"
	if not bool(flags.get("rotor_lock_released", false)):
		return "E 接合风机传动联轴器（需先拔出转子锁销）"
	if bool(flags.get("power_ready", false)):
		return "E 接合风机传动联轴器"
	return "E 接合风机传动联轴器（可提前检修 · 风机需得电才能启动）"


func _start_fan_prompt(_player: Node = null) -> String:
	if bool(flags.get("fan_started", false)):
		return "主风机已启动 · 用调速器与风门控制"
	if not bool(flags.get("coupling_engaged", false)):
		return "E 拉动主启动手柄（联轴器未接合）"
	if not bool(flags.get("power_ready", false)):
		return "E 拉动主启动手柄（控制回路未得电·无法启动）"
	return "E 拉动主启动手柄"


## Live prompts for the launch platform chain. Each reads the same flags the press
## handler reads, so the sentence on screen is the sentence the press will
## produce — the player learns the order without having to press E and fail.
## Completed machines say so instead of repeating "press E", so a finished step
## never reads like an invitation.
func _chock_prompt(_player: Node = null) -> String:
	if bool(flags.get("chock_removed", false)):
		return "车轮止轮楔已移走"
	if not bool(flags.get("vent_complete", false)):
		return "E 移走车轮止轮楔（通风未恢复 · 站台仍被联锁）"
	return "E 移走车轮止轮楔"


func _parking_brake_prompt(_player: Node = null) -> String:
	if bool(flags.get("brake_released", false)):
		return "停车制动已释放"
	if not bool(flags.get("chock_removed", false)):
		return "E 释放机械停车制动（需先移走止轮楔）"
	return "E 释放机械停车制动"


func _cargo_prompt(_player: Node = null) -> String:
	if builder == null or builder.cargo_rig == null:
		return "货舱固定带缺失"
	var rig: Act1CargoRig = builder.cargo_rig
	if bool(flags.get("cargo_secured", false)):
		return "货舱固定带已锁定 · 用锁扣手柄可释放"
	if rig.lever_busy():
		return "棘轮正在张紧 · 张力 %d N" % int(round(rig.tension()))
	if not bool(flags.get("chock_removed", false)):
		return "E 拉紧货舱固定带（需先移走止轮楔）"
	if not bool(flags.get("brake_released", false)):
		return "E 拉紧货舱固定带（需先释放停车制动）"
	return rig.prompt_pump()


func _cargo_latch_prompt(_player: Node = null) -> String:
	if builder == null or builder.cargo_rig == null:
		return ""
	return (builder.cargo_rig as Act1CargoRig).prompt_latch()


func _power_clamp_prompt(_player: Node = null) -> String:
	if bool(flags.get("power_clamped", false)):
		return "电源模块机械夹已锁定"
	if builder == null or builder.power_cart == null or not builder.power_cart.module_transferred_flag:
		return "E 锁定电源模块机械夹（需先用绞盘把模块送入插座）"
	return "E 锁定电源模块机械夹"


## Live prompt on the governor wheel: the current gear and what the next press
## will actually do (same helper the press handler uses).
func _governor_prompt(_player: Node = null) -> String:
	if builder == null or builder.vent == null or not bool(flags.get("fan_started", false)):
		return "E 调整风机调速器（需先启动主风机）"
	var pct := int(round(builder.vent.governor * 100.0))
	var nxt := int(round(Act1Ventilation.next_governor_value(builder.vent.governor) * 100.0))
	return "E 调速器 %d%% → 下一档 %d%%" % [pct, nxt]


func local_player_grabbing() -> bool:
	return local_player != null and local_player.grabbing


## Grab state of the ACTUAL actor. The host knows its own body directly; for a
## remote player it has the 20 Hz `grab` mirror in `remote_states`. Using the
## host's local body for a remote request was the F3 asymmetry: a client could
## not grab while the host held a rail, and the host could overwrite the single
## global grab slot while a client held one.
func _player_grabbing(pid: int) -> bool:
	if pid == local_pid:
		return local_player != null and local_player.grabbing
	var st: Dictionary = remote_states.get(pid, {})
	return bool(st.get("grab", false))


func local_down_or_remote_downed(pid: int) -> bool:
	if pid == local_pid:
		return local_player != null and local_player.downed
	var st: Dictionary = remote_states.get(pid, {})
	return bool(st.get("downed", false))


func _find_downed_pid() -> int:
	for pid in active_pids.keys():
		if local_down_or_remote_downed(int(pid)):
			return int(pid)
	return 0


func _grab_local(id: String) -> void:
	if not interactables.has(id):
		return
	var rail := interactables[id] as Act1GrabRail
	if rail == null:
		return
	var offset := rail.global_transform.affine_inverse() * local_player.global_position
	offset.x = clampf(offset.x, -0.65, 0.65)
	offset.z = clampf(offset.z, -0.65, 0.65)
	offset.y = 0.0
	local_player.start_grab(rail, offset)


## ---------------------------------------------------------------------------
## Machine callbacks
## ---------------------------------------------------------------------------

func on_door_opened() -> void:
	if flags["door_open"]:
		return
	flags["door_open"] = true
	var pid := _last_door_pusher if _last_door_pusher != 0 else local_pid
	_credit(pid, "entry_door", "推开工业入口门")
	_send_local_toast("工业门打开 · 辅助电源维修区的应急灯亮了", 3.5)
	_play_sfx("door_open", Vector3(0, 2.0, 8.3), 0.0)


func on_power_cart_docked() -> void:
	if flags["power_docked"]:
		return
	flags["power_docked"] = true
	var pid := _last_cart_pusher if _last_cart_pusher != 0 else local_pid
	_credit(pid, "power_dock", "把电源推车推入导轨插座")
	net_sync_message("推车已对准插座 · 操作绞盘把模块送入", 3.0)
	_send_local_toast("推车锁定 · 绞盘现在可以把模块沿导轨送入插座", 3.5)
	_play_sfx("endstop", builder.power_cart.global_position, -2.0)


func on_power_module_seated() -> void:
	flags["power_seated"] = true
	net_sync_message("电源模块已进入插座 · 锁定机械夹", 3.0)
	_send_local_toast("模块到位 · 锁定机械夹完成供电", 3.0)


func on_cart_departing() -> void:
	flags["completed"] = true
	_credit(local_pid, "launch", "矿车发车")
	if local_player != null and builder.mine_cart != null:
		var local_off := builder.mine_cart.ride_offset_for(local_player)
		local_player.attach_to(builder.mine_cart, local_off, 0.0)
		local_player.set_look(0.0, -0.035)
		hud.toast("发车 · 矿车正在驶向深层矿区", 5.0)
	if net != null and net.is_host:
		for pid in active_pids.keys():
			if int(pid) != local_pid:
				_send_grant(int(pid), "ride", {"attach": true})
	net_sync_message("矿车发车 · 前往 Resonance 02", 5.0)


func on_self_rescue_complete(pid: int) -> void:
	flags["self_rescued"] = true
	net_sync_message("玩家%d 已沿维护梯自救返回栈桥" % pid, 3.0)


## ---------------------------------------------------------------------------
## Actions that need a visible or network-driven body animation
## ---------------------------------------------------------------------------

func report_player_fall(player: Node) -> void:
	if player != local_player:
		return
	if local_player.downed:
		return
	local_player.set_downed(true)
	_record("fall", {"pid": local_pid, "pos": _arr(local_player.global_position)})
	_send_local_toast("你跌入了下层维修区 · 沿梯自救或等待救援卷扬", 4.0)


func report_out_of_bounds(player: Node) -> void:
	if player != local_player:
		return
	local_player.teleport(Vector3(0.5, Act1StationBuilder.PIT_Y + 0.15, -26.0), 0.0, 0.0)
	local_player.set_downed(true)
	hud.toast("安全网接住了你 · 沿维护梯自救", 3.0)


func _climb_pid(pid: int, from: Vector3, to: Vector3, duration: float) -> void:
	if pid == local_pid:
		_animate_climb(local_player, from, to, duration)
	else:
		_send_grant(pid, "climb", {"from": _arr(from), "to": _arr(to), "duration": duration})


func _animate_climb(p: Act1StationPlayer, from: Vector3, to: Vector3, duration: float) -> void:
	var anchor := Node3D.new()
	anchor.name = "ClimbAnchor"
	add_child(anchor)
	anchor.global_position = from
	p.teleport(from)
	p.attach_to(anchor, Vector3.ZERO, p.yaw)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(anchor, "global_position", to, duration)
	tw.tween_callback(func() -> void:
		p.detach()
		p.teleport(to, p.yaw, -0.05)
		p.set_downed(false)
		anchor.queue_free()
		on_self_rescue_complete(local_pid)
		if hud != null:
			hud.toast("已回到维修栈桥", 2.0)
	)


func _hide_chock(hidden := true) -> void:
	for child in get_children():
		if child.name == "WheelChockVisual":
			child.visible = not hidden
	# The chock visual is authored as non-colliding geometry; the actual blocking
	# wheel chock is the interaction body, so there is no invisible step left.


func _builder_power_light_on() -> void:
	# The socket's cyan practical is authored as emissive; add one real light at
	# the socket so power restoration is readable from the hall entrance.
	var l := OmniLight3D.new()
	l.position = Act1StationBuilder.SOCKET + Vector3(0, 0.5, 0.3)
	l.light_color = Color(0.22, 0.82, 0.92)
	l.light_energy = 3.2
	l.omni_range = 8.0
	l.shadow_enabled = false
	add_child(l)


## ---------------------------------------------------------------------------
## Network state
## ---------------------------------------------------------------------------

func get_local_state() -> Dictionary:
	if local_player == null:
		return {}
	var st := local_player.get_state_packet()
	st["grab_id"] = local_player.grab_anchor.interaction_id if local_player.grabbing and local_player.grab_anchor != null else ""
	st["cart_axis"] = Input.get_axis("move_back", "move_forward") if local_player.external_hold and cart_operator == local_pid else 0.0
	return st


## Integrated CoopNet contract: `/root/SessionHub/CoopNet._act1_client_process()`
## streams `stage.local_player_state()` to the host at 20 Hz
## (`act1_submit_state` -> `host_receive_state`). Act 01 only ever exposed
## `get_local_state()`, so the client body stream was silently skipped and the
## host kept the client at its spawn pose (no avatar, no interaction authority).
## Same payload, contract name.
func local_player_state() -> Dictionary:
	return get_local_state()


func build_snapshot(seq: int = 0) -> Dictionary:
	var players: Dictionary = {}
	for pid in active_pids.keys():
		var p := int(pid)
		if p == local_pid:
			players[p] = local_player.get_state_packet()
		else:
			players[p] = remote_states.get(p, {"pos": SPAWN, "yaw": 0.0})
	return {
		"seq": seq,
		"time": Time.get_ticks_msec(),
		"flags": flags.duplicate(true),
		"credits": _credits_snapshot(),
		"active": active_pids.keys(),
		"players": players,
		"door": builder.door.snapshot(),
		"cart": builder.power_cart.snapshot(),
		"vent": builder.vent.snapshot(),
		"crate": builder.wind_crate.snapshot(),
		"mine": builder.mine_cart.snapshot(),
		"obstacles": {
			"entry_pos": builder.entry_obstruction.global_position,
			"entry_rot": builder.entry_obstruction.global_rotation,
			"rail_pos": builder.rail_obstacle.global_position,
			"rail_rot": builder.rail_obstacle.global_rotation,
		},
		"cart_operator": cart_operator,
		"gust_phase": _gust_phase,
		"gust_factor": builder.vent.gust_factor,
		"reset_seq": reset_seq,
		"all_aboard": all_active_aboard(),
		"all_ready": all_active_ready(),
	}


## Split one authoritative snapshot into the three network channels:
##   pose    — 15 Hz, unreliable, small (bodies + continuous scalars)
##   dynamic — 10 Hz, unreliable (continuous machine motion)
##   state   — reliable, on change + 1 s keyframe (discrete task/machine state)
## Deriving all three from the same `build_snapshot()` keeps the host's reads
## consistent within a tick and avoids re-reading transforms per channel.
func split_snapshot(snap: Dictionary) -> Dictionary:
	var pose := {
		"seq": int(snap.get("seq", 0)),
		"players": snap.get("players", {}),
		"cart_operator": int(snap.get("cart_operator", cart_operator)),
		"gust_phase": str(snap.get("gust_phase", _gust_phase)),
		"gust_factor": float(snap.get("gust_factor", builder.vent.gust_factor)),
	}
	var dynamic := {"seq": int(snap.get("seq", 0))}
	var door_snap: Dictionary = snap.get("door", {})
	var cart_snap: Dictionary = snap.get("cart", {})
	var vent_snap: Dictionary = snap.get("vent", {})
	var crate_snap: Dictionary = snap.get("crate", {})
	var mine_snap: Dictionary = snap.get("mine", {})
	var door: Dictionary = door_snap.duplicate()
	door.erase("pusher")
	dynamic["door"] = door
	var cart: Dictionary = cart_snap.duplicate()
	cart.erase("docked")
	cart.erase("transferred")
	cart.erase("operator")
	dynamic["cart"] = cart
	var vent: Dictionary = vent_snap.duplicate()
	vent.erase("running")
	vent.erase("emergency")
	vent.erase("complete")
	dynamic["vent"] = vent
	var crate: Dictionary = crate_snap.duplicate()
	crate.erase("secured")
	dynamic["crate"] = crate
	var mine: Dictionary = mine_snap.duplicate()
	mine.erase("departing")
	mine.erase("departed")
	mine.erase("handoff")
	dynamic["mine"] = mine
	var state := {
		"flags": (snap.get("flags", {}) as Dictionary).duplicate(true),
		"credits": snap.get("credits", {}),
		"active": snap.get("active", []),
		"door": {"pusher": int(door_snap.get("pusher", 0))},
		"cart": {
			"docked": bool(cart_snap.get("docked", false)),
			"transferred": bool(cart_snap.get("transferred", false)),
		},
		"vent": {
			"running": bool(vent_snap.get("running", false)),
			"emergency": bool(vent_snap.get("emergency", false)),
			"complete": bool(vent_snap.get("complete", false)),
		},
		"crate": {"secured": bool(crate_snap.get("secured", false))},
		"mine": {
			"departing": bool(mine_snap.get("departing", false)),
			"departed": bool(mine_snap.get("departed", false)),
			"handoff": bool(mine_snap.get("handoff", false)),
		},
		"obstacles": snap.get("obstacles", {}),
		"reset_seq": int(snap.get("reset_seq", 0)),
	}
	return {"pose": pose, "dynamic": dynamic, "state": state}


## Compact wire form of the flags dictionary. 20 booleans serialized as a
## Dictionary cost ~616 B; the bit mask plus a key-order hash costs ~12 B. The
## bootstrap also carries the full dictionary so a layout mismatch can heal.
func pack_flags() -> Dictionary:
	var keys := _flag_key_order()
	if keys.size() > ACT1_FLAG_BITS_MAX:
		return {"flags": flags.duplicate(true)}
	var bits := 0
	var i := 0
	for key in keys:
		if bool(flags.get(key, false)):
			bits |= 1 << i
		i += 1
	return {
		"flags_bits": bits,
		"flags_ver": _flag_signature(keys),
		"flags_count": keys.size(),
	}


func unpack_flags(bits: int, ver: int, count: int) -> Dictionary:
	var keys := _flag_key_order()
	if keys.size() != count or _flag_signature(keys) != ver:
		return {}
	var out := {}
	var i := 0
	for key in keys:
		out[key] = ((bits >> i) & 1) == 1
		i += 1
	return out


func _flag_key_order() -> PackedStringArray:
	var keys := PackedStringArray()
	for key in flags.keys():
		keys.append(str(key))
	return keys


func _flag_signature(keys: PackedStringArray) -> int:
	var text := ""
	for key in keys:
		text += key + ","
	return hash(text)


func _credits_snapshot() -> Dictionary:
	var out := {}
	for pid in credits.keys():
		var rec: Dictionary = credits[pid]
		out[int(pid)] = {
			"name": rec.get("name", "玩家%d" % pid),
			"kinds": (rec.get("kinds", {}) as Dictionary).keys(),
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"active": bool(rec.get("active", true)),
			"late_join": bool(rec.get("late_join", false)),
		}
	return out


## Apply the reliable discrete state channel. Returns false when the packed flag
## layout does not match the local build; the caller then re-requests the full
## bootstrap (which carries the complete flags dictionary).
func client_apply_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var flags_ok := true
	if state.has("flags"):
		flags = (state["flags"] as Dictionary).duplicate(true)
	elif state.has("flags_bits"):
		var unpacked: Dictionary = unpack_flags(
			int(state["flags_bits"]), int(state.get("flags_ver", 0)), int(state.get("flags_count", 0)))
		if unpacked.is_empty():
			flags_ok = false
		else:
			flags = unpacked
	if state.has("active"):
		active_pids.clear()
		for pid in state.get("active", []):
			active_pids[int(pid)] = true
	if state.has("credits"):
		for pid in (state.get("credits", {}) as Dictionary).keys():
			var src: Dictionary = state["credits"][pid]
			credits[int(pid)] = {
				"name": str(src.get("name", "玩家%d" % int(pid))),
				"kinds": _kind_dict(src.get("kinds", [])),
				"phases": (src.get("phases", {}) as Dictionary).duplicate(true),
				"active": bool(src.get("active", true)),
				"late_join": bool(src.get("late_join", false)),
			}
	if state.has("door"):
		var d: Dictionary = state["door"]
		builder.door.apply_snapshot({"pusher": int(d.get("pusher", builder.door.pusher_pid))})
	if state.has("cart"):
		var c: Dictionary = state["cart"]
		builder.power_cart.apply_snapshot({
			"docked": bool(c.get("docked", builder.power_cart.docked)),
			"transferred": bool(c.get("transferred", builder.power_cart.module_transferred_flag)),
		})
	if state.has("vent"):
		var v: Dictionary = state["vent"]
		builder.vent.apply_snapshot({
			"running": bool(v.get("running", builder.vent.running)),
			"emergency": bool(v.get("emergency", builder.vent.emergency)),
			"complete": bool(v.get("complete", builder.vent.vent_complete)),
		})
	if state.has("crate"):
		var cr: Dictionary = state["crate"]
		builder.wind_crate.apply_snapshot({"secured": bool(cr.get("secured", builder.wind_crate.secured))})
	if state.has("mine"):
		var m: Dictionary = state["mine"]
		builder.mine_cart.apply_snapshot({
			"departing": bool(m.get("departing", builder.mine_cart.departing)),
			"departed": bool(m.get("departed", builder.mine_cart.has_departed)),
			"handoff": bool(m.get("handoff", builder.mine_cart.handoff)),
		})
	if state.has("obstacles"):
		var obs: Dictionary = state["obstacles"]
		if obs.has("entry_pos"):
			builder.entry_obstruction.global_position = obs["entry_pos"]
			builder.entry_obstruction.global_rotation = obs.get("entry_rot", Vector3.ZERO)
		if obs.has("rail_pos"):
			builder.rail_obstacle.global_position = obs["rail_pos"]
			builder.rail_obstacle.global_rotation = obs.get("rail_rot", Vector3.ZERO)
	if state.has("reset_seq"):
		var seq := int(state.get("reset_seq", reset_seq))
		if seq != reset_seq:
			reset_seq = seq
			client_reset_run(seq)
	if flags.get("debris_cleared", false) and interactables.has("shove_gantry"):
		(interactables["shove_gantry"] as Act1Interactable).set_interaction_enabled(false)
	if flags.get("rail_cleared", false) and interactables.has("rail_shove"):
		(interactables["rail_shove"] as Act1Interactable).set_interaction_enabled(false)
	_hide_chock(bool(flags.get("chock_removed", false)))
	if flags.get("chock_removed", false) and interactables.has("chock"):
		(interactables["chock"] as Act1Interactable).set_interaction_enabled(false)
	if builder.mine_cart.departing and not local_player.external_hold:
		var off := builder.mine_cart.ride_offset_for(local_player)
		local_player.attach_to(builder.mine_cart, off, 0.0)
		local_player.set_look(0.0, -0.035)
	if flags.get("handoff", false) and not _handoff_started:
		begin_scene_handoff({"mode": "coop_client", "credits": _credits_snapshot()})
	_update_hud(0.0)
	return flags_ok


## Apply the unreliable continuous-machine channel. Only the fields present are
## applied; discrete state stays owned by `client_apply_state`.
func client_apply_dynamic(dyn: Dictionary) -> void:
	if dyn.is_empty():
		return
	if dyn.has("door"):
		builder.door.apply_snapshot(dyn["door"] as Dictionary)
	if dyn.has("cart"):
		builder.power_cart.apply_snapshot(dyn["cart"] as Dictionary)
	if dyn.has("vent"):
		builder.vent.apply_snapshot(dyn["vent"] as Dictionary)
	if dyn.has("crate"):
		builder.wind_crate.apply_snapshot(dyn["crate"] as Dictionary)
	if dyn.has("mine"):
		builder.mine_cart.apply_snapshot(dyn["mine"] as Dictionary)


## Apply the unreliable high-frequency pose channel: remote bodies plus the two
## continuously-changing scalars. Never touches authoritative task state.
func client_apply_pose(pose: Dictionary) -> void:
	if pose.is_empty():
		return
	if pose.has("players"):
		_apply_players(pose.get("players", {}) as Dictionary)
	if pose.has("cart_operator"):
		cart_operator = int(pose["cart_operator"])
	if pose.has("gust_phase"):
		apply_gust_snapshot(str(pose["gust_phase"]), float(pose.get("gust_factor", builder.vent.gust_factor)))
	_update_hud(0.0)


func _apply_players(players: Dictionary) -> void:
	for key in players.keys():
		var pid := int(key)
		if pid == local_pid:
			continue
		remote_states[pid] = players[key]
		if not remotes.has(pid):
			_spawn_remote(pid)
		(remotes[pid] as Act1RemotePlayer).apply_state(players[key])


## Legacy/full payload (protocol v1 bootstrap or the act1_sync_snapshot
## fallback): one dictionary carries every channel.
func client_apply_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	client_apply_state(snap)
	client_apply_dynamic(snap)
	client_apply_pose(snap)


func _kind_dict(arr: Array) -> Dictionary:
	var d := {}
	for k in arr:
		d[str(k)] = true
	return d


func apply_gust_snapshot(phase: String, factor: float) -> void:
	if _gust_phase != phase and phase == "warning":
		hud.toast("风道压力失衡 · 抓住栏杆！", 3.0)
	if _gust_phase != phase and phase == "active":
		hud.toast("泄压冲击！强风横扫维修栈桥", 3.0)
	_gust_phase = phase
	builder.vent.gust_factor = factor


func host_receive_state(pid: int, state: Dictionary) -> void:
	if not active_pids.has(pid):
		return
	var reason: String = _validate_player_state(state)
	if reason != "":
		var now: int = Time.get_ticks_msec()
		if now - _last_state_reject_ms >= 1000:
			_last_state_reject_ms = now
			print("ACT1_STATE_REJECT pid=%d reason=%s" % [pid, reason])
		return
	var clean: Dictionary = state.duplicate(true)
	var pos: Vector3 = clean["pos"]
	clean["pos"] = pos
	remote_states[pid] = clean
	if cart_operator == pid:
		var axis: float = clampf(float(clean.get("cart_axis", 0.0)), -1.0, 1.0)
		builder.power_cart.set_axis(axis)
	if remotes.has(pid):
		(remotes[pid] as Act1RemotePlayer).apply_state(clean)


## Host-side schema check for the client body stream. A transform stream is not
## authority over tasks/machines, but it is the proximity evidence used by the
## interaction gate; reject NaN/out-of-world/oversized packets before they enter
## `remote_states`.
func _validate_player_state(state: Dictionary) -> String:
	if state.is_empty() or state.size() > NET_STATE_MAX_FIELDS:
		return "shape"
	if not (state.get("pos") is Vector3):
		return "pos_type"
	var pos: Vector3 = state["pos"] as Vector3
	if not pos.is_finite() or not _in_station_bounds(pos, 30.0):
		return "pos_range"
	for key in ["yaw", "pitch"]:
		if state.has(key) and not _is_finite_number(state[key]):
			return "%s_range" % key
	for key in ["grab", "downed", "hold", "external"]:
		if state.has(key) and not (state[key] is bool):
			return "%s_type" % key
	if state.has("cart_axis") and not _is_finite_number(state["cart_axis"]):
		return "cart_axis_range"
	if state.has("grab_id") and str(state["grab_id"]).length() > NET_ID_MAX_CHARS:
		return "grab_id_length"
	return ""


func _in_station_bounds(pos: Vector3, y_max: float = 20.0) -> bool:
	return pos.x >= -80.0 and pos.x <= 80.0 \
		and pos.y >= -8.0 and pos.y <= y_max \
		and pos.z >= -90.0 and pos.z <= 50.0


func _is_finite_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value)
	return false


func host_add_player(pid: int) -> void:
	if active_pids.has(pid) and remotes.has(pid):
		# Idempotent: a repeated ready / duplicate join must not re-add the seat,
		# reset the mirrored body or fire a second "joined" toast.
		return
	active_pids[pid] = true
	remote_states[pid] = {"pos": SPAWN, "yaw": 0.0, "downed": false}
	if not credits.has(pid):
		credits[pid] = {"name": "玩家%d" % pid, "kinds": {}, "phases": {}, "active": true, "downed": false}
	_spawn_remote(pid)
	hud.toast("玩家%d 已接入 K-17" % pid, 3.0)
	if net != null and net.is_host and net.online:
		sync_message.rpc("玩家%d 已加入 · 每人至少完成两个工序才能发车" % pid, 3.0)
	if net != null:
		net.peer_joined.emit(pid)


func host_remove_player(pid: int) -> void:
	active_pids.erase(pid)
	if credits.has(pid):
		credits[pid]["active"] = false
	if cart_operator == pid:
		cart_operator = 0
		builder.power_cart.end_push(pid)
	if hold_owner.get("cart_push", 0) == pid:
		hold_owner.erase("cart_push")
	if hold_owner.get("door_handle", 0) == pid:
		builder.door.end_push(pid)
		hold_owner.erase("door_handle")
	grab_owner.erase(pid)
	if remotes.has(pid):
		(remotes[pid] as Node).queue_free()
		remotes.erase(pid)
	remote_states.erase(pid)
	hud.toast("玩家%d 已断开 · 其占用已释放" % pid, 3.0)


func set_local_pid(pid: int) -> void:
	if pid <= 0:
		return
	var changed: bool = pid != local_pid
	local_pid = pid
	local_player.player_pid = pid
	# The join bootstrap snapshot can arrive before the seat assignment
	# (`act1_bootstrap` before `act1_welcome`), so a remote avatar for our OWN
	# pid may already exist. Drop it: a client must never render a clone of
	# itself, and its body state must not be mirrored as a remote. This also
	# runs for a duplicate welcome, so a late clone can never survive.
	if remotes.has(pid):
		var own: Node = remotes[pid] as Node
		if own != null and is_instance_valid(own):
			# Free immediately: a re-applied welcome in the same frame must not
			# leave two avatars alive for one pid.
			own.free()
		remotes.erase(pid)
	remote_states.erase(pid)
	if not changed and credits.has(pid):
		# Duplicate welcome: the seat and its participation record already
		# exist. Re-running the ledger join must not add a second entry.
		return
	_init_participant(pid, "玩家%d" % pid)
	_join_local_participation()
	if hud != null:
		hud.toast("已连接主机 · 你是玩家 %d" % pid, 3.0)


func _spawn_remote(pid: int) -> void:
	if remotes.has(pid):
		return
	var r := Act1RemotePlayer.new()
	r.setup(pid, "玩家 %d" % pid)
	add_child(r)
	r.global_position = SPAWN + Vector3(0.8 * float(pid - 1), 0, 0)
	remotes[pid] = r


func _send_grant(pid: int, id: String, payload: Dictionary) -> void:
	if net == null or not net.is_host:
		return
	var check: Dictionary = grant_payload_valid(id, payload)
	if not bool(check.get("ok", false)):
		print("ACT1_GRANT_REJECT side=host_send pid=%d id=%s reason=%s" % [
			pid, id, str(check.get("reason", "invalid"))])
		return
	net.send_grant(pid, id, payload)


## Host -> client grant receiver. `sender_peer_id` and `recipient_pid` are
## supplied by the transport after the @rpc authority gate, so this handler has
## a second, application-level identity check that does not depend on the
## annotation alone. Direct local calls with the default 0/0 fail closed.
func client_apply_grant(
		id: String, payload: Dictionary,
		sender_peer_id: int = 0, recipient_pid: int = 0) -> void:
	if sender_peer_id != 1:
		print("ACT1_GRANT_REJECT side=client reason=sender id=%s sender=%d" % [id, sender_peer_id])
		return
	if recipient_pid != local_pid:
		print("ACT1_GRANT_REJECT side=client reason=recipient id=%s pid=%d local=%d" % [id, recipient_pid, local_pid])
		return
	var check: Dictionary = grant_payload_valid(id, payload)
	if not bool(check.get("ok", false)):
		print("ACT1_GRANT_REJECT side=client reason=%s id=%s sender=%d pid=%d" % [
			str(check.get("reason", "invalid")), id, sender_peer_id, recipient_pid])
		return
	if id == "cart_push":
		if bool(payload.get("attach", false)):
			# The host grant is authoritative; mirror it before `_client_update()`
			# can compare against the one-tick-stale 15 Hz cart_operator pose.
			cart_operator = local_pid
			var off: Array = payload.get("offset", [-2.05, 0.02, 0.0]) as Array
			local_player.attach_to(
				builder.power_cart,
				Vector3(float(off[0]), float(off[1]), float(off[2])),
				float(payload.get("yaw", -PI * 0.5)), "cart_push")
			hud.toast("握住推车 · W/S 推拉", 2.0)
		else:
			if cart_operator == local_pid:
				cart_operator = 0
			local_player.detach()
		return
	if id == "climb":
		var from: Array = payload["from"] as Array
		var to: Array = payload["to"] as Array
		_animate_climb(
			local_player,
			Vector3(float(from[0]), float(from[1]), float(from[2])),
			Vector3(float(to[0]), float(to[1]), float(to[2])),
			float(payload.get("duration", 2.5)))
		return
	if id == "ride":
		if builder.mine_cart != null and local_player != null:
			var off := builder.mine_cart.ride_offset_for(local_player)
			local_player.attach_to(builder.mine_cart, off, 0.0)
			local_player.set_look(0.0, -0.035)
			hud.toast("矿车发车 · 留在车厢内", 4.0)
		return
	if id.begins_with("grab_"):
		if bool(payload.get("grab", false)):
			if interactables.has(id):
				var rail := interactables[id] as Act1GrabRail
				if rail != null:
					var offset := rail.global_transform.affine_inverse() * local_player.global_position
					offset.x = clampf(offset.x, -0.65, 0.65)
					offset.z = clampf(offset.z, -0.65, 0.65)
					offset.y = 0.0
					local_player.start_grab(rail, offset)
		else:
			local_player.release_grab()


## Pure payload schema check shared by the host's outbound guard and the
## client's receive-side guard. Returns {ok, reason}. Numeric arrays must be
## exactly length 3, finite, and inside authored station bounds; unknown ids or
## extra/mistyped fields are rejected.
func grant_payload_valid(id: String, payload: Dictionary) -> Dictionary:
	if id.is_empty() or id.length() > NET_ID_MAX_CHARS:
		return {"ok": false, "reason": "id"}
	if payload.is_empty() or payload.size() > NET_GRANT_MAX_FIELDS:
		return {"ok": false, "reason": "shape"}
	if id == "cart_push":
		if not (payload.get("attach") is bool):
			return {"ok": false, "reason": "attach_type"}
		if not bool(payload["attach"]):
			return {"ok": true, "reason": ""} if payload.size() == 1 else {"ok": false, "reason": "detach_fields"}
		if payload.size() != 3:
			return {"ok": false, "reason": "attach_fields"}
		var off_variant: Variant = payload.get("offset")
		var off: Variant = _vec3_or_null(off_variant)
		if off == null:
			return {"ok": false, "reason": "offset_shape"}
		var offset: Vector3 = off as Vector3
		if absf(offset.x) > NET_CART_MAX_OFFSET or absf(offset.z) > NET_CART_MAX_OFFSET \
				or offset.y < -1.5 or offset.y > 2.5:
			return {"ok": false, "reason": "offset_range"}
		var yaw: Variant = payload.get("yaw")
		if not _is_finite_number(yaw) or absf(float(yaw)) > TAU:
			return {"ok": false, "reason": "yaw_range"}
		return {"ok": true, "reason": ""}
	if id == "climb":
		if payload.size() != 3:
			return {"ok": false, "reason": "climb_shape"}
		var from_variant: Variant = _vec3_or_null(payload.get("from"))
		var to_variant: Variant = _vec3_or_null(payload.get("to"))
		if from_variant == null or to_variant == null:
			return {"ok": false, "reason": "climb_points"}
		var from: Vector3 = from_variant as Vector3
		var to: Vector3 = to_variant as Vector3
		if not _in_station_bounds(from, 20.0) or not _in_station_bounds(to, 20.0):
			return {"ok": false, "reason": "climb_bounds"}
		if from.distance_to(to) > NET_CLIMB_MAX_DISTANCE:
			return {"ok": false, "reason": "climb_distance"}
		var landing_a := Vector3(2.35, Act1StationBuilder.CATWALK_Y + 0.08, -22.2)
		var landing_b := Vector3(2.25, Act1StationBuilder.CATWALK_Y + 0.10, -22.8)
		if to.distance_to(landing_a) > NET_CLIMB_LANDING_RADIUS \
				and to.distance_to(landing_b) > NET_CLIMB_LANDING_RADIUS:
			return {"ok": false, "reason": "climb_landing"}
		var duration: Variant = payload.get("duration")
		if not _is_finite_number(duration) or float(duration) < 1.5 or float(duration) > 4.5:
			return {"ok": false, "reason": "climb_duration"}
		return {"ok": true, "reason": ""}
	if id == "ride":
		if payload.size() != 1 or not (payload.get("attach") is bool) or not bool(payload["attach"]):
			return {"ok": false, "reason": "ride_shape"}
		return {"ok": true, "reason": ""}
	if id.begins_with("grab_"):
		if payload.size() > 2 or not (payload.get("grab") is bool):
			return {"ok": false, "reason": "grab_shape"}
		if payload.has("anchor"):
			var anchor: Variant = _vec3_or_null(payload["anchor"])
			if anchor == null or not _in_station_bounds(anchor as Vector3, 20.0):
				return {"ok": false, "reason": "grab_anchor"}
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unknown_id"}


func _vec3_or_null(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var arr: Array = value as Array
	if arr.size() != 3:
		return null
	for component in arr:
		if not _is_finite_number(component):
			return null
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func host_reset_run(requester_enet: int = 0) -> void:
	reset_seq += 1
	_reset_state()
	if net != null and net.is_host and net.online:
		do_reset.rpc(reset_seq)
	if requester_enet != 0 and net != null and net.is_host and net.online:
		sync_message.rpc_id(requester_enet, "主机已重置 K-17", 2.5)


func client_reset_run(_seq: int) -> void:
	reset_seq = _seq
	_reset_local_visuals()


func _reset_state() -> void:
	_init_flags()
	cart_operator = 0
	hold_owner.clear()
	grab_owner.clear()
	_last_gantry_pusher = 0
	_gust_phase = "idle"
	_gust_timer = 0.0
	_gust_credited = false
	flags["gust_done"] = false
	credits.clear()
	active_pids.clear()
	active_pids[1] = true
	_init_participant(1, "本地玩家")
	if net != null and net.is_host:
		for pid in net.peer_pids():
			active_pids[int(pid)] = true
			_init_participant(int(pid), "玩家%d" % int(pid))
	builder.door.reset_door()
	builder.power_cart.reset_cart()
	builder.vent.reset_vent()
	builder.wind_crate.reset_crate()
	builder.mine_cart.reset_cart()
	if builder.cargo_rig != null:
		builder.cargo_rig.reset_cargo()
	builder.reset_static_obstacles()
	# MECHANICS-001F：001D 加了 reset_chock() 但 _reset_state 一直没有调用它，
	# 于是 R 复位后止轮楔仍停在拖出位置，_sync_wheel_chock() 又把 chock_removed 置回 true。
	if builder.wheel_chock != null:
		builder.wheel_chock.reset_chock()
	# 同理：001E 的制动销爪也必须复位，否则 _sync_parking_brake() 立刻把 brake_released 置回 true。
	if builder.parking_brake != null:
		builder.parking_brake.reset_brake()
	_hide_chock(false)
	for id in ["shove_gantry", "rail_shove", "chock"]:
		if interactables.has(id):
			(interactables[id] as Act1Interactable).set_interaction_enabled(true)
	if builder.power_cart != null:
		builder.power_cart.path_blocked = false
	if local_player != null:
		local_player.teleport(SPAWN, 0.0, -0.05)
		local_player.detach()
		local_player.release_grab()
		local_player.set_downed(false)
	player_states.clear()
	remote_states.clear()
	for pid in remotes.keys():
		(remotes[pid] as Act1RemotePlayer).apply_state({"pos": SPAWN, "yaw": 0.0})
	hud.toast("场景已重置 · K-17 恢复为初始故障状态", 3.0)


func _reset_local_visuals() -> void:
	if local_player != null:
		local_player.teleport(SPAWN, 0.0, -0.05)
		local_player.detach()
		local_player.release_grab()
		local_player.set_downed(false)
	flags["handoff"] = false
	_handoff_started = false


func begin_scene_handoff(completion: Dictionary) -> void:
	if _handoff_started:
		return
	_handoff_started = true
	hud.toast("发车 · Act01 完成 · 交接给统一会话", 3.0)
	hud.fade_to(1.0, 1.6)
	await get_tree().create_timer(1.8).timeout
	if bridge != null:
		# Integrated mode → SessionHub.complete_chapter → real Act 02/03.
		# Standalone mode → records locally and emits act01_completed (module
		# tests assert on the completion signal, not on a local fake second act).
		bridge.complete_act01(completion)


func _begin_handoff_host() -> void:
	if _ride_sent:
		return
	_ride_sent = true
	var completion := {
		"mode": "coop_host" if net.peer_count() > 1 else "solo",
		"credits": _credits_snapshot(),
		"completed": true,
		"time": Time.get_ticks_msec(),
		"chapter": "act01",
	}
	if net.peer_count() > 1:
		start_ride.rpc(completion)
	if not _no_handoff:
		begin_scene_handoff(completion)
	else:
		flags["handoff"] = true


@rpc("authority", "call_remote", "reliable")
func start_ride(completion: Dictionary) -> void:
	begin_scene_handoff(completion)


@rpc("authority", "call_remote", "reliable")
func do_reset(seq: int) -> void:
	client_reset_run(seq)


@rpc("authority", "call_remote", "reliable")
func sync_message(text: String, seconds: float) -> void:
	hud.toast(text, seconds)


func net_sync_message(text: String, seconds: float) -> void:
	if net != null and net.is_host and net.peer_count() > 1:
		sync_message.rpc(text, seconds)


func _on_net_ride_started(_pid: int, completion: Dictionary) -> void:
	begin_scene_handoff(completion)


func show_network_message(text: String, seconds: float) -> void:
	hud.toast(text, seconds)


## ---------------------------------------------------------------------------
## Presentation
## ---------------------------------------------------------------------------

func _update_hud(delta: float) -> void:
	if hud == null:
		return
	_hud_clock += delta
	if _hud_clock < 0.08:
		return
	_hud_clock = 0.0
	var obj := _objective_text()
	hud.set_objective(obj["title"], obj["sub"])
	var mode := "单人"
	if net != null and net.online:
		mode = "主机" if net.is_host else "客户端"
	var aboard := "是" if all_active_aboard() else "否"
	var ready := "是" if all_active_ready() else "否"
	hud.set_status("%s · PID %d · 在线 %d · 全员上车 %s · 协作检查 %s" % [mode, local_pid, net.peer_count() if net != null else 1, aboard, ready])
	var fan_prepped := bool(flags.get("rotor_lock_released", false)) and bool(flags.get("coupling_engaged", false))
	hud.set_wind(builder.vent.speed, builder.vent.pressure, builder.vent.damper, builder.vent.running, builder.vent.emergency,
		builder.vent.governor, builder.vent.pressure_test_seconds, builder.vent.vent_complete,
		bool(flags.get("damper_open", false)), fan_prepped, bool(flags.get("power_ready", false)))
	hud.set_participation(_participation_lines())
	if bridge.debug_enabled:
		hud.show_debug(_debug_text())


func _objective_text() -> Dictionary:
	if flags["handoff"]:
		return {"title": "列车已发车", "sub": "Act01 完成 · 交接给主整合会话"}
	if flags["departure_started"]:
		return {"title": "⑤ 矿车正在发车", "sub": "留在车内 · 前往深层矿区"}
	if flags["vent_complete"]:
		return {"title": "④ 准备矿车并发车", "sub": "止轮楔 → 停车制动 → 货舱固定带 → 全员登车 → 发车联锁"}
	if flags["fan_started"]:
		return {"title": "③ 完成工业通风压力测试", "sub": "开主风道 ≥72% · 调速器 78%+ · 风压 ≥58% 稳 6 秒"}
	if flags["power_ready"]:
		if flags["coupling_engaged"]:
			return {"title": "③ 启动主通风机", "sub": "检修已完成 · 拉启动手柄 → 打开主风道"}
		if flags["rotor_lock_released"]:
			return {"title": "③ 启动主通风机", "sub": "接合联轴器 → 启动 → 打开主风道"}
		return {"title": "③ 启动主通风机", "sub": "拔出转子锁 → 接合联轴器 → 启动 → 打开主风道"}
	if flags["door_open"]:
		# The fan's rotor lock and coupling are mechanical and need no power, so a
		# player who wanders into the ventilation hall can already prepare them.
		if flags["rotor_lock_released"] or flags["coupling_engaged"]:
			return {"title": "② 把辅助电源送到导轨插座", "sub": "握住推车 W/S 推拉 · 绞盘送入 · 锁定机械夹（通风机检修可先做）"}
		return {"title": "② 把辅助电源送到导轨插座", "sub": "握住推车 W/S 推拉 · 对准插座 · 绞盘送入 · 锁定机械夹"}
	if flags["latch_released"]:
		return {"title": "① 推开工业入口门", "sub": "按住 E 推动门体 · 门后是辅助电源维修区"}
	return {"title": "① 解除入口封锁", "sub": "推开压住门轨的维护架 → 释放机械闩 → 按住 E 推门"}


func _participation_lines() -> Array[String]:
	var out: Array[String] = []
	for pid in credits.keys():
		var rec: Dictionary = credits[pid]
		var name := str(rec.get("name", "玩家%d" % int(pid)))
		var phases: Dictionary = rec.get("phases", {})
		var labels: Array[String] = []
		for key in PHASES:
			if phases.has(key):
				labels.append(PHASE_NAMES[key])
		var active := "在线" if active_pids.has(int(pid)) else "离线"
		out.append("玩家%d %s  [%s]  %d/%d 工序%s" % [int(pid), name, active, phases.size(), required_phases(int(pid)), (" · " + " ".join(labels)) if not labels.is_empty() else " · 尚未贡献"])
	if out.is_empty():
		out.append("等待玩家…")
	return out


func _debug_text() -> String:
	return "DEBUG  pid=%d  pos=%s  downed=%s  grab=%s  hold=%s  cart_op=%d\nobstruction=%s  rail_obstruction=%s  gust=%s  vent=%.2f/%.2f" % [
		local_pid, str(local_player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(local_player.downed), str(local_player.grabbing), str(local_player.external_hold), cart_operator,
		str(builder.entry_obstruction.global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(builder.rail_obstacle.global_position.snapped(Vector3(0.01, 0.01, 0.01))), _gust_phase, builder.vent.speed, builder.vent.pressure,
	]


func _send_local_toast(text: String, seconds := 3.0) -> void:
	if hud != null:
		hud.toast(text, seconds)


## Refusal feedback aimed at the ACTOR, not at the process that happens to run
## the state machine. `_execute_interaction()` runs on the host for a remote
## player's request too, so a plain `_send_local_toast()` during a refused press
## put the sentence on the HOST's screen while the player who pressed E saw
## nothing (this was the multiplayer half of the "silent refusal" problem).
##
## Routing:
##   * local actor      -> local toast only
##   * remote actor     -> addressed `sync_message.rpc_id(enet_id, …)` so only
##                         that client sees it; the host does not get a copy
##   * actor unresolvable -> local toast, so a refusal can never be invisible
func _feedback_to(pid: int, text: String, seconds := 2.5) -> void:
	if text.is_empty():
		return
	if pid == local_pid or net == null or not net.is_host or not net.online:
		_send_local_toast(text, seconds)
		return
	var enet_id := 0 if net == null else net.enet_for_pid(pid)
	if enet_id == 0:
		# Unknown mapping: better on the host's screen than nowhere at all.
		_send_local_toast(text, seconds)
		return
	sync_message.rpc_id(enet_id, text, seconds)


## Rate-limited refusal. The key is (actor, machine): pressing the same blocked
## machine again inside the cooldown stays quiet instead of re-spamming, while a
## different machine — or a different actor — still answers immediately.
func _refuse(pid: int, machine: String, text: String, seconds := 2.5) -> void:
	var key := "%d|%s" % [pid, machine]
	var now := Time.get_ticks_msec()
	if now - int(_feedback_seen.get(key, 0)) < FEEDBACK_COOLDOWN_MS:
		return
	_feedback_seen[key] = now
	_feedback_to(pid, text, seconds)


func _play_sfx(name: String, pos: Vector3, volume_db: float) -> void:
	var path := "res://act1/assets/audio/%s.wav" % name
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path) as AudioStream
	p.position = pos
	p.volume_db = volume_db
	p.unit_size = 7.0
	p.max_distance = 35.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _capture_checkpoint(name: String) -> void:
	if _capture_seen.has(name):
		return
	_capture_seen[name] = true
	await RenderingServer.frame_post_draw
	# Capture output directory is created at runtime (legacy debug harness).
	# lint:ignore res_path runtime-capture-output-directory
	var dir := ProjectSettings.globalize_path("res://../evidence/screens")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("CAPTURE %s" % name)


func capture_scene(name: String) -> void:
	await _capture_checkpoint(name)


func _record(kind: String, data: Dictionary) -> void:
	event_log.append({"t": Time.get_ticks_msec() - started_msec, "kind": kind, "data": data})
	if event_log.size() > 500:
		event_log.pop_front()


func write_run_report(path: String) -> void:
	var payload := {
		"mode": net.mode if net != null else "solo",
		"completed": bool(flags.get("completed", false)),
		"flags": flags.duplicate(true),
		"credits": _credits_snapshot(),
		"active": active_pids.keys(),
		"events": event_log,
		"engine": Engine.get_version_info()["string"],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
		f.close()


func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]