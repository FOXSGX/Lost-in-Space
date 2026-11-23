extends SceneTree

var app: Node3D
var level: LevelBuilder
var cam: Camera3D


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	level = app.get("level") as LevelBuilder
	var player: PlayerController = app.get("player") as PlayerController
	player.camera.current = false
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.03
	cam.far = 260.0
	cam.current = true
	level.add_child(cam)
	cam.global_position = Vector3(9.4, 1.68, -4.8)
	cam.look_at(Vector3(12.7, 3.2, -12.1), Vector3.UP)
	await frames(2)
	print("CAMERA XFORM ", cam.global_transform)
	print("VIEWPORT ", root.get_visible_rect())
	var items: Array = []
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var c: Vector3 = box.get_center()
		if cam.is_position_behind(c):
			continue
		var sp: Vector2 = cam.unproject_position(c)
		var d: float = cam.global_position.distance_to(c)
		if d > 30.0:
			continue
		if sp.x < 380.0 or sp.x > 900.0 or sp.y < 150.0 or sp.y > 650.0:
			continue
		var chain: String = ""
		var p: Node = mi
		while p != null and p != level:
			chain = p.name + "/" + chain
			p = p.get_parent()
		items.append({"d": d, "name": chain, "screen": sp, "size": box.size, "center": c})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for it in items.slice(0, 40):
		print("  %-56s d=%5.1f screen=%s size=%s c=%s" % [it["name"], it["d"], str((it["screen"] as Vector2).round()), str(it["size"]), str(it["center"])])
	quit()




