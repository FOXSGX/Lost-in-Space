extends SceneTree

## Quick navigability probe: can the player really walk from the left ramp foot
## to the left counterweight console? This path used to be clear before the V2
## station additions, and the legacy walking bot now stalls somewhere on it.

var app: Node3D
var player: PlayerController


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(20)
	player = app.get("player") as PlayerController
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	player.teleport(Vector3(-5.0, 0.06, 2.4), 0.0, 0.0)
	await frames(10)
	var target: Vector3 = Vector3(-8.0, 0.06, 2.2)
	var yaw: float = atan2(-(target.x - player.global_position.x), -(target.z - player.global_position.z))
	player.teleport(player.global_position, yaw, 0.0)
	await frames(5)
	print("WALK start pos=", player.global_position, " yaw=", yaw)
	Input.action_press("move_forward")
	for i in range(300):
		await physics_frame
		if i % 30 == 0:
			var d: Vector3 = target - player.global_position
			print("WALK t=%.2f pos=%s dist=%.2f" % [float(i) / 60.0, str(player.global_position), Vector2(d.x, d.z).length()])
	Input.action_release("move_forward")
	var flat: Vector3 = target - player.global_position
	print("WALK end pos=", player.global_position, " dist=", Vector2(flat.x, flat.z).length())
	quit(0)
