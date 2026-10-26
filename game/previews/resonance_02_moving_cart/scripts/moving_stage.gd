extends "res://station_base.gd"

var cart: AnimatableBody3D
var device: Node3D
var bend_event: Node3D
var actors: Dictionary = {}
var ui_font: SystemFont
var hud: CanvasLayer
var input_blocked: bool = false
var reduced_effects: bool = false
var grips: Array[Vector3] = [Vector3(-0.7, 2.91, 0.87), Vector3(1.9, 2.91, 3.53)]
var grip_owners: Dictionary = {}
var brake_anchor: Vector3 = Vector3(2.48, 2.64, 1.08)
var feedback: String = "沿黄色踏步登车。可先固定货物，再到前端控制器按 E 发车。"
var events: Array[Dictionary] = []
var restart_count: int = 0
var clock: float = 0.0

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 120
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	profiles = JSON.parse_string(FileAccess.get_file_as_string("res://assets/material_profiles.json")) as Dictionary
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	_adapt_materials(source, {})
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.025, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.56, 0.63, 0.72)
	environment.ambient_light_energy = 0.30
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	cart = preload("res://scripts/moving_cart.gd").new() as AnimatableBody3D
	cart.name = "MovingCart"
	cart.set("stage", self)
	add_child(cart)
	var cart_visual: Node3D = (load("res://assets/moving_cart_visual.scn") as PackedScene).instantiate() as Node3D
	_adapt_materials(cart_visual, {})
	cart.add_child(cart_visual)
	var wheel_list: Array[Node3D] = []
	for node: Node in cart_visual.get_children():
		if str(node.name).begins_with("Wheel"): wheel_list.append(node as Node3D)
	cart.set("wheels", wheel_list)
	var tunnel: Node3D = preload("res://scripts/cart_environment.gd").new() as Node3D
	tunnel.name = "StationaryCave"
	add_child(tunnel)
	tunnel.call("build", self, source)
	# M4 event reads the cart's real distance/speed, never a fixed timeline.
	bend_event = preload("res://scripts/cart_bend_event.gd").new() as Node3D
	bend_event.name = "BendEvent"
	bend_event.set("stage", self)
	bend_event.set("cart", cart)
	add_child(bend_event)
	cart.set("bend_event", bend_event)
	# Original source is only an instancing palette, never a second visible cart.
	source.free()
	_inputs()
	player = preload("res://scripts/cart_player.gd").new() as CharacterBody3D
	player.name = "Player1"
	player.position = Vector3(1, 0.38, -2.0)
	player.set("cart", cart)
	player.set("moving_stage", self)
	actors[1] = player
	add_child(player)
	device = preload("res://scripts/cart_cargo_system.gd").new() as Node3D
	device.name = "CargoSystem"
	device.set("stage", self)
	device.set("cart", cart)
	add_child(device)
	hud = preload("res://scripts/cart_hud.gd").new() as CanvasLayer
	hud.set("stage", self)
	add_child(hud)
	_build_controls()
	loaded = true
	player.call("restore_at", player.global_position)

func _inputs() -> void:
	super._inputs()
	var bindings: Dictionary = {"repair": KEY_E, "pickup": KEY_F, "drop": KEY_X, "deposit": KEY_G, "cart_brake": KEY_B, "cart_recover": KEY_R, "show_help": KEY_F1, "mute_preview": KEY_M}
	for action: String in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = int(bindings[action]) as Key
		InputMap.action_add_event(action, key)

func _build_controls() -> void:
	var env: Script = preload("res://scripts/cart_environment.gd")
	for i: int in range(grips.size()):
		var at: Vector3 = grips[i]
		env.box(cart, Vector3(0.50, 0.06, 0.09), env.material(Color("e4bd69"), 0.75), at)
		label_at(cart, "E · 抓扶 %d" % (i + 1), at + Vector3.UP * 0.30, Color("ffda94"))
	label_at(cart, "E · 发车 / B · 制动", brake_anchor + Vector3.UP * 0.5, Color("ffc37b"))
	label_at(self, "RESONANCE 02\n矿洞短途运输 · 90 m", Vector3(-1, 4.4, -0.5), Color("98dbe0"))

func label_at(parent: Node3D, text: String, at: Vector3, tint: Color) -> Label3D:
	var result: Label3D = Label3D.new()
	result.text = text
	result.font = ui_font
	result.font_size = 30
	result.pixel_size = 0.0034
	result.outline_size = 6
	result.modulate = tint
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	result.position = at
	parent.add_child(result)
	return result

func _physics_process(delta: float) -> void:
	if not loaded or input_blocked: return
	clock += delta
	for action: String in ["repair", "pickup", "drop", "deposit", "cart_brake", "cart_recover"]:
		if Input.is_action_just_pressed(action): request_action(action)
	if Input.is_action_just_pressed("mute_preview"): AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	if Input.is_action_just_pressed("show_help"): hud.call("toggle_help")
	var local: Vector3 = cart.to_local(player.global_position)
	if player.global_position.y < -3.0 or player.global_position.distance_to(cart.global_position) > 18.0:
		rescue_player()
	if local.y < 1.5 and float(cart.get("speed")) > 0.2:
		cart.call("brake")
		feedback = "船员离开甲板，安全制动已触发。停车后按 R 请求救援登车。"

func can_reach(actor: CharacterBody3D, target: Vector3, limit: float = 1.6) -> bool:
	var direction: Vector3 = target - (actor.global_position + Vector3.UP * 0.8)
	if direction.length() > limit: return false
	var flat: Vector3 = target - actor.global_position
	flat.y = 0.0
	return flat.length() < 0.25 or (-actor.global_basis.z).dot(flat.normalized()) > -0.15

func request_action(action: String, actor_id: int = 1, expected_revision: int = -1) -> bool:
	# Explicit authority / actor / revision boundary for future ENet integration.
	if not multiplayer.is_server() or not actors.has(actor_id): return false
	if expected_revision >= 0 and expected_revision != int(cart.get("revision")): return false
	var actor: CharacterBody3D = actors[actor_id] as CharacterBody3D
	if action == "cart_brake":
		if not bool(cart.call("contains_point", actor.global_position)): return false
		cart.call("brake")
		feedback = "紧急制动 · 平缓停车后整理货物。到前端控制器按 E 重新发车。"
		record("brake", actor_id)
		return true
	if action == "cart_recover":
		if float(cart.get("speed")) > 0.03:
			cart.call("brake")
			feedback = "救援先制动。停车后再按 R，回收散落容器；离车船员重新登车。"
			return false
		if not bool(cart.call("contains_point", actor.global_position)): rescue_player()
		device.call("recover_free")
		feedback = "检修回收已完成。容器仍未固定，请自行搬运锁定。"
		record("recover", actor_id)
		return true
	if action == "repair":
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
					actor.set("grip_id", i)
					actor.set("grip_stand", cart.to_local(actor.global_position))
					feedback = "抓扶中 · E 松开 · 鼠标观察 · B 制动"
					record("grip", actor_id)
					return true
		if can_reach(actor, cart.to_global(brake_anchor), 1.6):
			if not bool(cart.call("contains_point", actor.global_position)):
				feedback = "先登上甲板，再操作发车器。"
				return false
			var started: bool = bool(cart.call("start"))
			feedback = "矿车发车 · 松散货物会受加减速和弯道影响。B 可随时制动。" if started else "已到短途终点。沿黄色踏步下车，Esc 可重新开始。"
			record("start", actor_id)
			return started
	return bool(device.call("handle_action", actor_id, action))

func rescue_player() -> void:
	cart.call("brake")
	if float(cart.get("speed")) > 0.03: return
	grip_owners.clear()
	player.call("restore_at", cart.to_global(Vector3(1.0, 1.91, 1.6)))
	player.set("recovery_count", int(player.get("recovery_count")) + 1)
	feedback = "安全绳救援登车。车辆已停车，货物未自动完成任务。"
	record("player_rescued", int(player.get("peer_id")))

func reset_run() -> void:
	device.call("reset_all")
	grip_owners.clear()
	player.call("release_grip")
	cart.call("reset_run")
	device.call("reset_all")
	player.call("restore_at", Vector3(1, 0.38, -2.0))
	restart_count += 1
	feedback = "已重新开始。登车后可提前固定货物，也可以先出发再补救。"
	record("reset", int(player.get("peer_id")))

func set_paused(value: bool) -> void:
	input_blocked = value
	player.set("paused", value)
	cart.set("paused", value)
	device.set("paused", value)

func record(kind: String, actor_id: int) -> void:
	events.append({"kind": kind, "actor_id": actor_id, "distance": cart.get("distance"), "time": clock})

func _unhandled_key_input(_event: InputEvent) -> void:
	pass
