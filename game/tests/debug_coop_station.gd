extends SceneTree

## One-off debug for co-op station targeting (development only).

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var hud: GameHud


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func report(label: String) -> void:
	print("-- ", label)
	print("   pos=", player.global_position, " yaw=%.2f pitch=%.2f" % [player.yaw, player.pitch])
	print("   operating=", player.operating, " target=", player.current_target.name if player.current_target != null else "none")
	var from: Vector3 = player.camera.global_position
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + fwd * 2.9, 1 | 8, [player.get_rid()])
	q.collide_with_areas = true
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("   ray=miss")
	else:
		var col: Object = hit.get("collider")
		print("   ray=", (col as Node).get_path() if col is Node else str(col), " point=", hit.get("position"))
	var best: Node = null
	var best_score: float = -1.0
	for n in get_root().get_tree().get_nodes_in_group("interactable"):
		var n3: Node3D = n as Node3D
		if n3 == null:
			continue
		var d: Vector3 = n3.global_position - from
		var dist: float = d.length()
		var dot: float = (d / maxf(dist, 0.001)).dot(fwd)
		if dist < 4.0:
			print("   cand ", n3.name, " dist=%.2f dot=%.2f pos=%s" % [dist, dot, str(n3.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
		if dist > 2.6 or dot < 0.30:
			continue
		var score: float = dot - dist * 0.12
		if score > best_score:
			best_score = score
			best = n
	print("   nearest=", best.name if best != null else "none")


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(60)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	hud = app.get("hud") as GameHud
	hud.title_layer.visible = false

	var station: LeverStation = level.left_station
	print("station pos=", station.global_position, " anchor=", station.anchor.origin, " area=", station.area.global_position)
	player.teleport(Vector3(-8.5, 1.7, 7.47), -0.52, -0.55)
	await frames(30)
	report("teleport to documented anchor")
	player.teleport(station.anchor.origin + Vector3(0, 0.05, 0.0), -0.52, -0.35)
	await frames(30)
	report("at anchor +0.05")
	player.teleport(station.anchor.origin + Vector3(0, 0.05, -0.6), -0.52, -0.30)
	await frames(30)
	report("0.6 m back from anchor")
	quit()
