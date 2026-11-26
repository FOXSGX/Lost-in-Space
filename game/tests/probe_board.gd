extends SceneTree

## Is the crew duty board actually visible from the hall? Cast a ray from a few
## candidate viewpoints to the board centre and report the first hit.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var board: Node3D = level.duty_board
	var target: Vector3 = board.global_position + Vector3(0, 2.35, 0)
	var space: PhysicsDirectSpaceState3D = app.get_world_3d().direct_space_state
	for p in [Vector3(4.6, 1.7, 12.0), Vector3(4.6, 1.7, 9.0), Vector3(2.0, 1.7, 8.0), Vector3(7.0, 1.7, 8.0), Vector3(4.6, 1.7, 1.0)]:
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p, target, 1)
		var hit: Dictionary = space.intersect_ray(q)
		var hit_name: String = "clear"
		if not hit.is_empty():
			var col: Object = hit.get("collider")
			hit_name = str(col.get_path()) if col is Node else str(col)
		print("VIS from=%s hit=%s at=%s" % [str(p), hit_name, str(hit.get("position", Vector3.ZERO))])
	quit(0)
