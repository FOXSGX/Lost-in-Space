extends "res://act23/station_base.gd"

var cart: AnimatableBody3D
var device: Node3D
var bend_event: Node3D
var yard: Node3D
# MECHANICS-003A: 晶体门（03）停靠夹钳
var dock: Node3D
var flow: Node
var airwall: Node
var coop: Node
var participation: Node
var paused: bool = false
var actors: Dictionary = {}
var ui_font: SystemFont
var hud: CanvasLayer
var input_blocked: bool = false
var reduced_effects: bool = false
var local_slot: int = 1
var roster: Dictionary = {1: {"connected": true, "name": "玩家 1"}}
var host_stage_mirror: int = 0
var action_revision: int = 0
var last_action_ok: bool = true
var session_status: String = "离线"
var grips: Array[Vector3] = [Vector3(-0.7, 2.91, 0.87), Vector3(1.9, 2.91, 3.53)]
var grip_owners: Dictionary = {}
var brake_anchor: Vector3 = Vector3(2.48, 2.64, 1.08)
var feedback: String = "沿黄色踏步登车。可先固定货物，再到前端控制器按 E 发车。"
var events: Array[Dictionary] = []
var restart_count: int = 0
var clock: float = 0.0
const Act23PhysicalLinks := preload("res://act23/scripts/act23_physical_links.gd")
var physical_links: Act23PhysicalLinks = null
var explore_props: Node3D = null
var grip_bars: Array[MeshInstance3D] = []
var grip_materials: Array[StandardMaterial3D] = []

# --- safety brake: a rider left the moving deck -----------------------------
# The host owns the motor, so the host alone decides to stop it; clients mirror
# that decision (running / brake_reason) from the 20 Hz snapshot. The old guard
# ran on every peer, read only that process's own character and asked for a
# brake through request_action("cart_brake"), which rejects any actor that is
# not on the deck - i.e. exactly the actor that just left it. So the "crew left
# the deck" stop could never actually be executed. This version evaluates every
# connected, spawned participant against the host's authoritative speed, brakes
# once per ride, and never counts a disconnected or never-boarded player as crew.
var _safety_armed: bool = false
var _safety_triggered: bool = false
var _safety_riders: Dictionary = {}
var _safety_brake_count: int = 0

# --- rescue landing spots ----------------------------------------------------
# Every rescued crew member used to be placed on ONE deck point
# (cart-local (1.0, 1.91, 1.6)). Character capsules collide with each other
# (cart_player's collision_mask includes the player layer), so two rescues in the
# same stop landed inside one another and the depenetration could shove a body
# out of the open near-side boarding gate. Each seat now owns a standing spot on
# the open front half of the deck: 1.2 m apart (> the 0.76 m capsule diameter),
# 0.68 m clear of the near-side rail plane, clear of the cab (x >= 2.95), the
# rear ring post (x <= -2.35), both loose-container start pads (z >= 2.0) and the
# fixed cargo seats (z = 2.92). Deck top is 1.9546; 1.91 puts the capsule's
# 0.05 m bottom clearance exactly on it, which is the stance the authored grip
# and deck-spawn points already use.
const RESCUE_SPOTS: Dictionary = {
	1: Vector3(2.25, 1.91, 1.45),
	2: Vector3(1.05, 1.91, 1.45),
	3: Vector3(-0.15, 1.91, 1.45),
	4: Vector3(-1.35, 1.91, 1.45),
}
# Two capsules are 0.76 m wide; below this the landing spots are not a solution
# any more and the best free spot wins instead.
const RESCUE_SPOT_GAP: float = 0.95

# --- campaign hand-off (Act 23 -> Act 04) ------------------------------------
# Once the cart has arrived at the crystal-mine entrance (phase == "done") the
# module hands off to the next chapter through the shared SessionHub, so the two
# acts stay in one session / one ENet socket / one player identity.
var _chapter_handoff_started: bool = false
var _chapter_handoff_timer: float = 0.0
var _chapter_handoff_delay: float = 4.5

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 120
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	profiles = JSON.parse_string(FileAccess.get_file_as_string("res://act23/assets/material_profiles.json")) as Dictionary
	var source: Node3D = (load("res://act23/assets/station_static.glb") as PackedScene).instantiate() as Node3D
	_adapt_materials(source, {})
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.070)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.68, 0.64)
	# The authored rock kit is lit PBR now, so ambient is a base fill rather than
	# a substitute for lighting. The directional fill gives every rock a readable
	# top plane while the warm work lamps and cyan crystals carry the contrast.
	environment.ambient_light_energy = 0.92
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.07
	environment.adjustment_brightness = 1.01
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.055, 0.072, 0.095)
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.0055
	environment.fog_depth_begin = 18.0
	environment.fog_depth_end = 105.0
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	# Shadowless key fill: the cave is enclosed, but a pure ambient-only setup
	# reads as flat clay. This gives the rock shelves a consistent upper plane
	# without pretending sunlight reaches the tunnel.
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "CaveFormFill"
	fill.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	fill.light_color = Color("b9bfc9")
	fill.light_energy = 0.46
	fill.shadow_enabled = false
	add_child(fill)
	cart = preload("res://act23/scripts/moving_cart.gd").new() as AnimatableBody3D
	cart.name = "MovingCart"
	cart.set("stage", self)
	add_child(cart)
	var cart_visual: Node3D = (load("res://act23/assets/moving_cart_visual.scn") as PackedScene).instantiate() as Node3D
	_adapt_materials(cart_visual, {})
	# The paint and the suit are authored much brighter than any rock albedo in the
	# chapter, so against the re-graded warm stone they read as blown out. Trimming
	# the albedo (not the lights) keeps the rock readable and the vehicle believable
	# without touching the lamps everyone signed off on.
	_trim_exposure(cart_visual, 0.90)
	cart.add_child(cart_visual)
	var wheel_list: Array[Node3D] = []
	for node: Node in cart_visual.get_children():
		if str(node.name).begins_with("Wheel"): wheel_list.append(node as Node3D)
	cart.set("wheels", wheel_list)
	cart.set("visual_node", cart_visual)
	var tunnel: Node3D = preload("res://act23/scripts/cart_environment.gd").new() as Node3D
	tunnel.name = "StationaryCave"
	add_child(tunnel)
	tunnel.call("build", self, source)
	# M4 event reads the cart's real distance/speed, never a fixed timeline.
	bend_event = preload("res://act23/scripts/cart_bend_event.gd").new() as Node3D
	bend_event.name = "BendEvent"
	bend_event.set("stage", self)
	bend_event.set("cart", cart)
	add_child(bend_event)
	cart.set("bend_event", bend_event)
	# Original source is only an instancing palette, never a second visible cart.
	source.free()
	_inputs()
	player = preload("res://act23/scripts/cart_player.gd").new() as CharacterBody3D
	player.name = "Player1"
	player.position = Vector3(1, 0.38, -2.0)
	player.set("cart", cart)
	player.set("moving_stage", self)
	actors[1] = player
	add_child(player)
	device = preload("res://act23/scripts/cart_cargo_system.gd").new() as Node3D
	device.name = "CargoSystem"
	device.set("stage", self)
	device.set("cart", cart)
	add_child(device)
	# Resonance 03's winch mechanics, rebuilt as a maintenance bay on this line.
	# Built after the player exists so the WinchRig can resolve its distance
	# checks against the real character instead of a placeholder.
	yard = preload("res://act23/scripts/repair_yard.gd").new() as Node3D
	yard.name = "RepairYard"
	add_child(yard)
	yard.call("build", self, cart, player)
	# MECHANICS-003A: 03 · 晶体矿区入口的停靠夹钳，建在 106 m 站台上。
	# 它就是第三幕的“抵达”这一步的机械：矿车停稳 + 闸臂压住车侧 + 销子插到底，
	# 章节才允许进入 done 并交接第四幕。
	dock = preload("res://act23/scripts/dock_clamp.gd").new() as Node3D
	dock.name = "CrystalDock"
	dock.transform = preload("res://act23/scripts/moving_cart.gd").route_pose(106.0)
	dock.set("stage", self)
	dock.set("cart", cart)
	dock.set("player", player)
	add_child(dock)
	physical_links = Act23PhysicalLinks.new()
	physical_links.setup(self, yard, dock)
	physical_links.refresh(yard, dock, cart)
	flow = preload("res://act23/scripts/level_flow.gd").new() as Node
	flow.name = "LevelFlow"
	add_child(flow)
	flow.call("setup", self, cart, player, yard)
	explore_props = preload("res://act23/scripts/env/act23_explore_props.gd").new() as Node3D
	add_child(explore_props)
	explore_props.call("setup", self, cart)
	# F3/F4 air-wall inspector. Built after every collider exists, before the HUD
	# so the HUD can read its summary on the first frame.
	airwall = preload("res://act23/scripts/airwall_debug.gd").new() as Node
	add_child(airwall)
	airwall.call("setup", self, player, cart)
	hud = preload("res://act23/scripts/cart_hud.gd").new() as CanvasLayer
	hud.set("stage", self)
	add_child(hud)
	# Participation is host-owned bookkeeping, not a hidden score: it only ever
	# records real actions that changed the shared world, and the HUD shows it.
	participation = preload("res://act23/scripts/participation.gd").new() as Node
	participation.name = "Participation"
	add_child(participation)
	participation.call("setup", self)
	# CoopNet is created last: it reads the command line and may start hosting
	# immediately, and every node it will touch has to exist by then.
	coop = preload("res://act23/scripts/coop_net.gd").new() as Node
	coop.name = "CoopNet"
	add_child(coop)
	coop.call("setup", self)
	coop.connect("link_changed", _on_link_changed)
	_build_controls()
	loaded = true
	call_deferred("_trim_exposure", player, 0.92)
	player.call("restore_at", player.global_position)


# Scales albedo only, so a bright painted object can sit in the same exposure range
# as the environment without dimming the work lamps that light the rock.
func _trim_exposure(root: Node, factor: float) -> void:
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface: int in range(mesh_instance.mesh.get_surface_count()):
					var material: Material = mesh_instance.get_active_material(surface)
					if material is StandardMaterial3D:
						var standard: StandardMaterial3D = material as StandardMaterial3D
						var tint: Color = standard.albedo_color
						standard.albedo_color = Color(
							tint.r * factor, tint.g * factor, tint.b * factor, tint.a)
		_trim_exposure(child, factor)

func _inputs() -> void:
	super._inputs()
	# `winch_*` mirrors the movement keys on purpose: while the console is taken
	# over the character is locomotion-locked, so W/S can only mean "drum" in
	# that state. They are separate actions so scripted input can drive the winch
	# without also walking the character.
	var bindings: Dictionary = {
		"repair": KEY_E, "pickup": KEY_F, "drop": KEY_X, "deposit": KEY_G,
		"cart_brake": KEY_B, "cart_recover": KEY_R, "show_help": KEY_F1,
		"mute_preview": KEY_M, "toggle_debug": KEY_F3, "airwall_scan": KEY_F4,
		"winch_haul": KEY_W, "winch_payout": KEY_S, "winch_creep": KEY_SHIFT,
		"winch_brake": KEY_SPACE, "winch_release": KEY_Q,
	}
	for action: String in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = int(bindings[action]) as Key
		InputMap.action_add_event(action, key)

func _build_controls() -> void:
	var env: Script = preload("res://act23/scripts/cart_environment.gd")
	for i: int in range(grips.size()):
		var at: Vector3 = grips[i]
		# A cyan grip bar that lights up while held. The old amber bar was the
		# same colour as the railing and the deck trim, so the one spot the
		# player is supposed to grab was visually identical to decoration.
		var grip_mat: StandardMaterial3D = env.material(Color("8ee9f2"), 0.2, 0.45)
		var bar: MeshInstance3D = env.box(cart, Vector3(0.50, 0.06, 0.09), grip_mat, at)
		grip_bars.append(bar)
		grip_materials.append(grip_mat)
	# The 42 pt world-space dock title and the 30 pt floating sign used to occupy
	# the centre of the frame at 1280x800. The HUD now carries the objective, so
	# the world only keeps small station plaques on the hardware itself.

func label_at(parent: Node3D, text: String, at: Vector3, tint: Color) -> Label3D:
	var result: Label3D = Label3D.new()
	result.text = text
	result.font = ui_font
	result.font_size = 20
	result.pixel_size = 0.0022
	result.outline_size = 5
	result.modulate = tint
	result.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	result.position = at
	parent.add_child(result)
	return result

func _physics_process(delta: float) -> void:
	if not loaded or input_blocked: return
	clock += delta
	if player == null:
		return
	if physical_links != null:
		physical_links.refresh(yard, dock, cart)
	for action: String in ["repair", "pickup", "drop", "deposit", "cart_brake", "cart_recover"]:
		if Input.is_action_just_pressed(action): _local_request(action)
	# Winch keys are edge-triggered here and polled in LevelFlow, matching the
	# prototype: the drum brake is a discrete throw, W/S are continuous.
	if Input.is_action_just_pressed("winch_release"):
		_local_request("winch_release")
	if Input.is_action_just_pressed("winch_brake"):
		_local_request("winch_brake")
	# Held winch keys are pushed every tick while this player owns the console.
	# On a client they are forwarded; on the host they drive the rig directly.
	if flow != null and bool(flow.call("console_owned_by", local_slot)):
		flow.call("set_local_winch_input",
			Input.is_action_pressed("winch_haul"),
			Input.is_action_pressed("winch_payout"),
			Input.is_action_pressed("winch_creep"))
	if Input.is_action_just_pressed("mute_preview"): AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	if Input.is_action_just_pressed("show_help"): hud.call("toggle_help")
	if Input.is_action_just_pressed("toggle_debug"):
		# F3 is the air-wall inspector, not a second help key. The HUD debug
		# panel follows it so the numbers and the ghost markers stay in sync.
		if airwall != null:
			airwall.call("toggle")
		hud.call("set_debug", bool(airwall.get("enabled")) if airwall != null else false)
	if Input.is_action_just_pressed("airwall_scan") and airwall != null:
		airwall.call("scan")
	# The 18 m leash is measured from the hull centre; the repair bay is longer
	# than that, so a rider who has legitimately walked to the winch must not be
	# teleported back onto the deck. Only rescue when the player cannot be
	# standing somewhere legitimate (fell out of the world / left the stage).
	if player.global_position.y < -3.0:
		rescue_player(player)
	elif player.global_position.distance_to(cart.global_position) > 18.0 and not _in_repair_bay(player):
		rescue_player(player)
	_safety_brake_tick()
	# Held grip bars glow solid, free ones breathe so they stay findable.
	for i: int in range(grip_materials.size()):
		var held: bool = grip_owners.has(i)
		grip_materials[i].emission_energy_multiplier = (
			1.35 if held else 0.40 + 0.18 * sin(clock * 2.4 + float(i)))
	_check_chapter_handoff(delta)


# --- campaign hand-off (Act 23 -> Act 04) -----------------------------------
# The moving_stage is a scene-root script (not a `-s` preloaded test script), so
# it may reference the HubLookup global class directly. Hand-off is routed
# through the shared SessionHub so host + clients switch together and the ENet
# socket / roster / participation survive. Standalone boot (no SessionHub) is a
# safe no-op, so the module's own tests still pass.
func _check_chapter_handoff(_delta: float) -> void:
	if _chapter_handoff_started:
		return
	if flow == null or cart == null:
		return
	# A client never orders the switch; the host broadcasts do_scene_switch.
	# Use the unified-session role (fixed at launch) rather than Act23's own coop
	# mode: after a server loss Act23's coop resets to "offline" and a client
	# must still not auto-advance the campaign on its own.
	if coop != null and str(coop.get("mode")) == "client":
		return
	if HubLookup.available() and HubLookup.mode_is("client"):
		return
	if str(flow.get("phase")) != "done":
		return
	if not HubLookup.available():
		return
	_chapter_handoff_started = true
	# Stop the chapter's pose/action stream before the scene swap: Act04 binds
	# the same persistent SessionHub peer, and a late RPC from a freeing Act23
	# scene is neither useful nor safe.
	if coop != null and coop.has_method("begin_handoff"):
		coop.call("begin_handoff")
	feedback = "矿车已抵达晶体矿区入口 · 正在进入第四幕……"
	print("ACT23_HANDOFF phase=done cart_distance=", float(cart.get("distance")))
	var payload: Dictionary = {
		"phase": str(flow.get("phase")),
		"completed": true,
		"cart_distance": float(cart.get("distance")),
		"cart_arrived": bool(cart.get("arrived")),
		"participation": participation.call("snapshot") if participation != null else {},
	}
	var spawn: Dictionary = {
		"from_chapter": "act23",
		"to_chapter": "act04",
	}
	var timer: SceneTreeTimer = get_tree().create_timer(_chapter_handoff_delay)
	timer.timeout.connect(func() -> void: _do_chapter_handoff(payload, spawn))


func _do_chapter_handoff(payload: Dictionary, spawn: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	if not HubLookup.available():
		return
	# MECHANICS-004A 边界修复（003A 遗漏）：交接前重新核对“停靠仍然成立”。
	# 4.5 s 倒计时期间玩家可以按 E 抬棘爪解除停靠；那种情况下章节不能过幕，
	# 必须取消这次交接并允许重新停靠后再次触发。
	if flow == null or str(flow.get("phase")) != "done" \
			or (dock != null and not bool(dock.call("docked"))):
		_chapter_handoff_started = false
		feedback = "停靠已解除 · 交接取消，重新停靠夹钳后再过幕。"
		print("ACT23_HANDOFF cancelled: dock released during countdown")
		return
	print("ACT23_HANDOFF switching to act4")
	HubLookup.complete_chapter("act23", payload, "act04", "res://scenes/act4.tscn", spawn)

func _in_repair_bay(actor: CharacterBody3D = null) -> bool:
	if yard == null:
		return false
	var who: CharacterBody3D = actor if actor != null else player
	if who == null:
		return false
	var local: Vector3 = yard.to_local(who.global_position)
	return local.x > -7.0 and local.x < 12.0 and absf(local.z) < 7.0

func can_reach(actor: CharacterBody3D, target: Vector3, limit: float = 1.6) -> bool:
	var direction: Vector3 = target - (actor.global_position + Vector3.UP * 0.8)
	if direction.length() > limit: return false
	var flat: Vector3 = target - actor.global_position
	flat.y = 0.0
	return flat.length() < 0.25 or (-actor.global_basis.z).dot(flat.normalized()) > -0.15

# Local input enters here on every peer. A client turns it into a request; the
# host (or an offline run) executes it against the same actor id immediately.
func _local_request(action: String, reason: String = "") -> bool:
	if coop != null and str(coop.get("mode")) == "client":
		return bool(coop.call("request_action", action))
	var ok: bool = request_action(action, local_slot)
	if reason != "" and action == "cart_brake" and ok:
		cart.call("brake", reason)
	return ok

func request_action(action: String, actor_id: int = 1, expected_revision: int = -1) -> bool:
	# Host-only entry point. Clients never reach this with someone else's id:
	# CoopNet maps the ENet sender to a slot and calls it with that slot.
	if not multiplayer.is_server() or not actors.has(actor_id): return false
	if expected_revision >= 0 and expected_revision != int(cart.get("revision")): return false
	var actor: CharacterBody3D = actors[actor_id] as CharacterBody3D
	if action == "cart_brake":
		if not bool(cart.call("contains_point", actor.global_position)):
			feedback = "只有车上的人能拉手制动。"
			return false
		# MECHANICS-002B：B 拉的是前甲板上的机械手制动（棘轮三档），
		# 制动力来自闸瓦压紧力，不是"让速度归零"。
		var notch: int = int(cart.call("pull_brake"))
		match notch:
			0:
				feedback = "手制动已松开 · 矿车按当前惯性继续滑行；要动力请到控制器按 E。"
			1:
				feedback = "手制动 1 档 · 闸瓦压上制动鼓，矿车正在因制动力减速。"
			_:
				feedback = "手制动 2 档（紧急） · 闸瓦满行程压在鼓上，停车距离更短。"
		record("brake", actor_id)
		return true
	if action == "cart_recover":
		if float(cart.get("speed")) > 0.03:
			cart.call("brake")
			feedback = "救援先制动。停车后再按 R，回收散落容器；离车船员重新登车。"
			return false
		if not bool(cart.call("contains_point", actor.global_position)): rescue_player(actor)
		device.call("recover_free")
		feedback = "检修回收已完成。容器仍未固定，请自行搬运锁定。"
		record("recover", actor_id)
		return true
	if action == "winch_release":
		if flow == null: return false
		flow.call("release_cable", actor_id)
		record("winch_release", actor_id)
		return true
	if action == "winch_brake":
		if flow == null or not bool(flow.call("console_owned_by", actor_id)): return false
		(flow.get("rig") as Node3D).call("toggle_brake")
		record("winch_brake", actor_id)
		return true
	if action == "repair":
		# Off the deck the same E key belongs to the repair mission (lifting eyes,
		# console, lock socket). On the deck it stays the cart's own control.
		if not bool(cart.call("contains_point", actor.global_position, 0.35)):
			if flow != null and bool(flow.call("try_interact", actor)):
				record("winch_interact", actor_id)
				return true
		if int(actor.get("grip_id")) >= 0:
			grip_owners.erase(int(actor.get("grip_id")))
			actor.call("release_grip")
			feedback = "已松开扶手，可以自由走动。"
			record("release_grip", actor_id)
			return true
		if int(actor.get("carrying")) == 0:
			for i: int in range(grips.size()):
				var target: Vector3 = cart.to_global(grips[i])
				if can_reach(actor, target, 1.05) and not grip_owners.has(i):
					grip_owners[i] = actor_id
					# Snap to a braced stance at the rail instead of freezing
					# wherever E was pressed. The old version left the Ranger
					# standing a full arm length away and reaching forward, which
					# read as "pointing at the rail" rather than holding it.
					var inward: float = signf(2.2 - float(grips[i].z))
					var stand: Vector3 = cart.to_global(
						Vector3(grips[i].x, 1.91, float(grips[i].z) + inward * 0.42))
					actor.global_position = stand
					actor.reset_physics_interpolation()
					actor.set("grip_id", i)
					actor.set("grip_stand", cart.to_local(stand))
					feedback = "已抓牢栏杆 · E 松开 · 鼠标观察 · B 制动"
					record("grip", actor_id)
					return true
		if can_reach(actor, cart.to_global(brake_anchor), 1.6):
			if not bool(cart.call("contains_point", actor.global_position)):
				feedback = "先登上甲板，再操作发车器。"
				return false
			var started: bool = bool(cart.call("start"))
			if started:
				feedback = "矿车发车 · 松散货物会受加减速和弯道影响。B 可随时制动。"
			else:
				var refusal: String = str(cart.call("start_refusal"))
				feedback = refusal if refusal != "" else "矿车暂时无法发车。"
			record("start", actor_id)
			return started
	if bool(device.call("handle_action", actor_id, action)):
		return true
	if explore_props != null and bool(explore_props.call("try_interact", actor, self)):
		return true
	return false


func explore_prompt() -> String:
	if explore_props == null or player == null:
		return ""
	return str(explore_props.call("nearest_prompt", player))

# --- safety brake: crew left the moving deck ---------------------------------
# Host-only decision. The cart motor, its speed and its brake reason are host
# state, so evaluating this on a client could only produce a request the host
# would refuse (the actor asking is off the deck by definition) and, with a
# lagging mirror speed, a stream of pointless retries. One evaluation on the
# authoritative side is enough and it covers every participant.
func _safety_brake_tick() -> void:
	# The chapter hand-off is not a ride. Once Act23 has ordered the transfer to
	# Act04 the mission is over, the old player nodes are released during the
	# 4.5 s timer, and a protective stop here would be caused by teardown rather
	# than by a crew member stepping off - and could stall the hand-off.
	if _chapter_handoff_started or not is_inside_tree():
		_safety_reset()
		return
	if coop != null and str(coop.get("mode")) == "client":
		return
	if not multiplayer.is_server() or cart == null:
		return
	if not bool(cart.get("running")):
		# A stopped cart ends the ride: re-arm for the next departure.
		_safety_reset()
		return
	_safety_armed = true
	var moving: bool = float(cart.get("speed")) > 0.2
	var seen: Dictionary = {}
	for slot: int in actors:
		# Read the slot as a Variant first: casting a *freed* object with `as`
		# raises "Trying to cast a freed object" before is_instance_valid can
		# reject it. The hand-off frees the old players while this dictionary
		# still holds their entries for a frame.
		var value: Variant = actors[slot]
		if value == null or not is_instance_valid(value):
			continue
		var actor: CharacterBody3D = value as CharacterBody3D
		# A slot that is being torn down by the scene hand-off is not a fall:
		# require the body to still be a live node inside this scene.
		if actor == null or not actor.is_inside_tree():
			continue
		if not _safety_slot_connected(slot):
			continue
		seen[slot] = true
		var local: Vector3 = cart.to_local(actor.global_position)
		if bool(cart.call("contains_point", actor.global_position)):
			# On the deck: this slot is crew for the ride. A late joiner spawned
			# onto a moving deck is crew from the moment it appears there.
			_safety_riders[slot] = true
		elif local.y < 1.5 and _safety_riders.has(slot) and moving and not _safety_triggered:
			# A crew member who boarded this ride is now below deck level: one
			# protective stop, latched so a slowing cart cannot retrigger. The
			# vertical test (not the whole deck box) is the original single-player
			# criterion, so standing in the open boarding gate is not a "fall".
			_safety_triggered = true
			_safety_brake_count += 1
			cart.call("brake", "driver_left_deck")
			record("safety_brake", slot)
			feedback = "船员离开甲板，安全制动已触发。停车后按 R 请求救援登车。"
			print("SAFETY_BRAKE slot=", slot, " distance=", float(cart.get("distance")),
				" speed=", float(cart.get("speed")), " local=", local)
	# A disconnected / despawned slot is no longer crew, not a fall.
	for slot: int in _safety_riders.keys():
		if not seen.has(slot):
			_safety_riders.erase(slot)

# Only connected peers that this process actually simulates count as crew.
func _safety_slot_connected(slot: int) -> bool:
	if coop == null:
		return true
	var mode: String = str(coop.get("mode"))
	if mode != "host" and mode != "offline":
		return true
	var known: Dictionary = coop.get("slots") as Dictionary
	if known == null or known.is_empty():
		return true
	if not known.has(slot):
		return false
	return bool((known[slot] as Dictionary).get("connected", false))

func _safety_reset() -> void:
	_safety_armed = false
	_safety_triggered = false
	_safety_riders.clear()

func rescue_player(actor: CharacterBody3D = null) -> void:
	var who: CharacterBody3D = actor if actor != null else player
	if who == null or not is_instance_valid(who):
		return
	cart.call("brake", "rescue")
	if float(cart.get("speed")) > 0.03: return
	var slot: int = int(who.get("peer_id"))
	# Give back every device this actor holds before moving it. The drum came
	# from leave_console(); the receiver hand wheel and the safety prop were
	# never released here, so a rescued seat could keep another player's
	# workstation occupied - and its 2.5 deg capture bonus - from the deck.
	if flow != null: flow.call("release_slot", slot)
	for index: int in grip_owners.keys():
		if int(grip_owners[index]) == slot:
			grip_owners.erase(index)
	who.call("release_grip")
	who.set("fp_console", false)
	var spot: Vector3 = _rescue_spot_for(slot)
	if coop != null and str(coop.get("mode")) == "host" and slot != local_slot:
		# A remote body is integrated by its own process: a teleport of the host
		# proxy would be overwritten by that client's next 20 Hz pose, and the
		# client was never told about the rescue at all. Move the proxy (so the
		# client's post-rescue pose passes the anti-teleport gate in CoopNet) and
		# send the same production restore to the owner as a reliable command.
		who.set("remote_position", spot)
		who.global_position = spot
		who.reset_physics_interpolation()
		coop.call("rescue_remote", slot, spot)
	else:
		who.call("restore_at", spot)
	who.set("recovery_count", int(who.get("recovery_count")) + 1)
	feedback = "安全绳救援登车。车辆已停车，货物未自动完成任务。"
	record("player_rescued", slot)

# A rescued crew member must not be dropped inside a teammate. The seat's own
# spot wins unless somebody already stands on it; then the spot with the largest
# clearance wins (never a fixed shared point, never a disabled collision layer).
func _rescue_spot_for(slot: int) -> Vector3:
	var preferred: Vector3 = RESCUE_SPOTS.get(slot, RESCUE_SPOTS[1]) as Vector3
	var others: Array[Vector3] = []
	for other: int in actors:
		if other == slot:
			continue
		var value: Variant = actors[other]
		if value == null or not is_instance_valid(value):
			continue
		var body: CharacterBody3D = value as CharacterBody3D
		if body == null or not body.is_inside_tree():
			continue
		others.append(cart.to_local(body.global_position))
	var best: Vector3 = preferred
	var best_gap: float = _flat_gap(preferred, others)
	if best_gap < RESCUE_SPOT_GAP:
		for key: int in RESCUE_SPOTS:
			var spot: Vector3 = RESCUE_SPOTS[key] as Vector3
			var gap: float = _flat_gap(spot, others)
			if gap > best_gap + 0.001:
				best = spot
				best_gap = gap
	return cart.to_global(best)

func _flat_gap(spot: Vector3, others: Array[Vector3]) -> float:
	var best: float = 99.0
	for at: Vector3 in others:
		best = minf(best, Vector2(spot.x - at.x, spot.z - at.z).length())
	return best

func reset_run() -> void:
	device.call("reset_all")
	grip_owners.clear()
	for slot: int in actors:
		(actors[slot] as CharacterBody3D).call("release_grip")
	cart.call("reset_run")
	if dock != null:
		dock.call("reset")
	_safety_reset()
	device.call("reset_all")
	# The repair mission has to come back with the cart: rail angle, cable
	# length, drum, lock pin, entrance signage and the player position.
	if flow != null:
		flow.call("reset_all")
	for slot: int in actors:
		var actor: CharacterBody3D = actors[slot] as CharacterBody3D
		actor.call("restore_at", Vector3(1, 0.38, -2.0))
	if participation != null:
		participation.call("reset")
	restart_count += 1
	feedback = "任务已重置：矿车回到起点，轨道回到错位状态，缆绳已收回。"
	record("reset", local_slot)

func set_paused(value: bool) -> void:
	input_blocked = value
	paused = value
	for slot: int in actors:
		(actors[slot] as CharacterBody3D).set("paused", value)
	cart.set("paused", value)
	device.set("paused", value)
	if flow != null:
		flow.set("paused", value)

func record(kind: String, actor_id: int) -> void:
	events.append({"kind": kind, "actor_id": actor_id, "distance": cart.get("distance"), "time": clock})
	if participation != null:
		participation.call("record", actor_id, kind)

# --- co-op roster / network hooks ------------------------------------------

func _on_link_changed(next_mode: String, detail: String) -> void:
	session_status = detail
	if hud != null:
		hud.call("set_link_text", detail)

func net_spawn_remote(slot: int, spawn: Vector3) -> void:
	if actors.has(slot):
		return
	var actor: CharacterBody3D = preload("res://act23/scripts/cart_player.gd").new() as CharacterBody3D
	actor.name = "Player%d" % slot
	actor.set("peer_id", slot)
	actor.set("is_local_actor", false)
	actor.set("input_enabled", false)
	actor.set("use_first_person", false)
	actor.position = spawn
	actor.set("remote_position", spawn)
	actor.set("cart", cart)
	actor.set("moving_stage", self)
	add_child(actor)
	(actor.get("camera") as Camera3D).current = false
	actors[slot] = actor
	roster[slot] = {"connected": true, "name": "玩家 %d" % slot}
	# Remote bodies must keep their head and torso: render layer 2 is a local
	# first-person hide, and applying it to everyone would make every teammate
	# headless.
	for mesh: Node in actor.get("visual").find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = 1

func net_despawn_remote(slot: int) -> void:
	if not actors.has(slot):
		return
	if int(slot) == local_slot:
		return
	var actor: Node = actors[slot] as Node
	actors.erase(slot)
	roster.erase(slot)
	if actor != null and is_instance_valid(actor):
		actor.queue_free()

func net_release_slot(slot: int) -> void:
	if flow != null:
		flow.call("release_slot", slot)
	for index: int in grip_owners.keys():
		if int(grip_owners[index]) == slot:
			grip_owners.erase(index)
	for body: Variant in device.get("cargo") as Array:
		(body as Node3D).set("carrier_id", 0)

func net_set_local_slot(slot: int, spawn: Vector3) -> void:
	var previous: int = local_slot
	local_slot = slot
	if actors.has(1) and previous == 1:
		var actor: CharacterBody3D = actors[1] as CharacterBody3D
		actors.erase(1)
		actor.set("peer_id", slot)
		actor.name = "Player%d" % slot
		actors[slot] = actor
		if slot != 1:
			actor.global_position = spawn
			actor.set("remote_position", spawn)
			actor.reset_physics_interpolation()
	roster[slot] = {"connected": true, "name": "玩家 %d" % slot}
	if flow != null:
		flow.call("set_local_slot", slot)

func net_roster_changed(next: Dictionary) -> void:
	roster = next
	if hud != null:
		hud.call("set_roster_text", roster)

func net_slot_position(slot: int) -> Vector3:
	if actors.has(slot):
		return (actors[slot] as CharacterBody3D).global_position
	return Vector3.ZERO

func net_apply_remote_pose(slot: int, at: Vector3, yaw: float, motion: Vector3, grip: int, carrying: int) -> void:
	if not actors.has(slot):
		return
	var actor: CharacterBody3D = actors[slot] as CharacterBody3D
	actor.set("remote_position", at)
	actor.set("remote_yaw", yaw)
	actor.set("remote_motion", motion)
	actor.set("grip_id", grip)
	actor.set("carrying", carrying)

func net_console_input(slot: int, haul: bool, payout: bool, creep: bool) -> void:
	if flow != null:
		flow.call("set_remote_winch_input", slot, haul, payout, creep)

func net_console_owned_by_local() -> bool:
	if flow == null:
		return false
	return bool(flow.call("console_owned_by", local_slot))

func net_snapshot_packet() -> PackedByteArray:
	var snapshot: Dictionary = {
		"rev": int(cart.get("revision")),
		"phase": str(flow.get("phase")),
		"objective": str(flow.get("objective_text")),
		"prompt": str(flow.get("prompt_text")),
		"feedback": feedback,
		"cart": [float(cart.get("distance")), float(cart.get("speed")), bool(cart.get("running")),
			bool(cart.get("arrived")), bool(cart.get("route_clear")),
			bool(cart.get("stopped_for_fault")), str(cart.get("brake_reason")), str(cart.get("state"))],
		"console": int(flow.get("console_actor")),
		"grips": grip_owners.duplicate(),
		"cargo": device.call("net_rows"),
		"rig": rig_snapshot_for_net(),
		"poses": _pose_rows(),
		"part": participation.call("snapshot"),
		"roster": roster.duplicate(),
		"cstage": int(coop.get("client_stage")) if coop != null else 0,
	}
	var raw: PackedByteArray = var_to_bytes(snapshot)
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(4)
	packet.encode_u32(0, raw.size())
	packet.append_array(raw.compress(FileAccess.COMPRESSION_FASTLZ))
	return packet

func _pose_rows() -> Array:
	var rows: Array = []
	for slot: int in actors:
		var actor: CharacterBody3D = actors[slot] as CharacterBody3D
		rows.append([slot, actor.global_position, actor.rotation.y, actor.velocity,
			int(actor.get("grip_id")), int(actor.get("carrying"))])
	return rows

func rig_snapshot_for_net() -> Dictionary:
	if yard == null:
		return {}
	var rig: Node3D = yard.get("rig") as Node3D
	if rig == null:
		return {}
	return rig.call("net_state") as Dictionary

func net_apply(snapshot: Dictionary) -> void:
	var cart_rows: Array = snapshot.get("cart", []) as Array
	cart.set("network_client", true)
	if cart_rows.size() >= 8:
		cart.call("apply_net_state", cart_rows)
	device.call("apply_net_rows", snapshot.get("cargo", []))
	if flow != null:
		flow.call("apply_net_state", snapshot)
	if participation != null:
		participation.call("apply_net", snapshot.get("part", {}))
	var poses: Array = snapshot.get("poses", []) as Array
	for row: Array in poses:
		var slot: int = int(row[0])
		if slot == local_slot:
			continue
		if not actors.has(slot):
			net_spawn_remote(slot, row[1] as Vector3)
		net_apply_remote_pose(slot, row[1] as Vector3, float(row[2]), row[3] as Vector3,
			int(row[4]), int(row[5]))
	roster = snapshot.get("roster", roster) as Dictionary
	host_stage_mirror = int(snapshot.get("cstage", host_stage_mirror))
	if hud != null:
		hud.call("set_roster_text", roster)
	feedback = str(snapshot.get("feedback", feedback))
	_mirror_local_ownership(snapshot)

# The host owns occupancy. The client's own body has to reflect that too, or a
# client could keep walking while the host thinks it is holding the drum.
func _mirror_local_ownership(snapshot: Dictionary) -> void:
	if player == null:
		return
	if physical_links != null:
		physical_links.refresh(yard, dock, cart)
	var console_owner: int = int(snapshot.get("console", 0))
	var owns_console: bool = console_owner == local_slot
	player.set("interaction_locked", owns_console)
	player.set("fp_console", owns_console)
	var grips: Dictionary = snapshot.get("grips", {}) as Dictionary
	var my_grip: int = -1
	for index: int in grips:
		if int(grips[index]) == local_slot:
			my_grip = int(index)
	if my_grip != int(player.get("grip_id")):
		if my_grip >= 0:
			var stand: Vector3 = cart.to_global(Vector3(grips_local(my_grip).x, 1.91,
				grips_local(my_grip).z + signf(2.2 - grips_local(my_grip).z) * 0.42))
			player.call("restore_at", stand)
			player.set("grip_id", my_grip)
			player.set("grip_stand", cart.to_local(stand))
		else:
			player.call("release_grip")

func grips_local(index: int) -> Vector3:
	return (grips as Array[Vector3])[index]

func net_on_reset() -> void:
	if flow != null:
		flow.call("reset_all")
	device.call("reset_all")
	cart.call("reset_run")
	if dock != null:
		dock.call("reset")
	_safety_reset()
	grip_owners.clear()
	if participation != null:
		participation.call("reset")
	feedback = "主机重置了任务：矿车回到起点，轨道回到错位状态。"

# --- campaign hand-off -----------------------------------------------------
# If a future build has to change scenes between 02 and 03, this dictionary is
# the contract: it carries the cart, its cargo, the bay and the crew. The
# shipped chapter does NOT need it (one scene, one cart), but the data path is
# implemented and exercised by the reset test so it cannot rot.

func export_run_state() -> Dictionary:
	return {
		"cart": {
			"distance": float(cart.get("distance")), "speed": float(cart.get("speed")),
			"running": bool(cart.get("running")), "arrived": bool(cart.get("arrived")),
			"route_clear": bool(cart.get("route_clear")),
			"stopped_for_fault": bool(cart.get("stopped_for_fault")),
			"brake_reason": str(cart.get("brake_reason")), "state": str(cart.get("state")),
		},
		"cargo": device.call("net_rows"),
		"rig": rig_snapshot_for_net(),
		"players": _pose_rows(),
		"grips": grip_owners.duplicate(),
		"phase": str(flow.get("phase")),
		"participation": participation.call("snapshot"),
		"cart_instance": cart.get_instance_id(),
	}

func apply_run_state(state: Dictionary) -> void:
	var cart_state: Dictionary = state.get("cart", {}) as Dictionary
	if not cart_state.is_empty():
		cart.call("apply_net_state", [
			float(cart_state.get("distance", 0.0)), float(cart_state.get("speed", 0.0)),
			bool(cart_state.get("running", false)), bool(cart_state.get("arrived", false)),
			bool(cart_state.get("route_clear", false)), bool(cart_state.get("stopped_for_fault", false)),
			str(cart_state.get("brake_reason", "")), str(cart_state.get("state", "")),
		])
		cart.call("snap_to_distance", float(cart_state.get("distance", 0.0)))
	device.call("apply_net_rows", state.get("cargo", []))
	var rig_state: Dictionary = state.get("rig", {}) as Dictionary
	if not rig_state.is_empty() and yard != null:
		(yard.get("rig") as Node3D).call("apply_net_state", rig_state)
	var players: Array = state.get("players", []) as Array
	for row: Array in players:
		var slot: int = int(row[0])
		if slot == local_slot or not actors.has(slot):
			continue
		net_apply_remote_pose(slot, row[1] as Vector3, float(row[2]), Vector3.ZERO, -1, 0)
	grip_owners = state.get("grips", grip_owners) as Dictionary
	if participation != null:
		participation.call("apply_net", state.get("participation", {}))
	feedback = "已交接 02→03 运行状态（同一辆矿车）"

func _unhandled_key_input(_event: InputEvent) -> void:
	pass



