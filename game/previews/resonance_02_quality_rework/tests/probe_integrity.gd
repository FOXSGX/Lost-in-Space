extends SceneTree

# Ray-based integrity test. Casts a dense sphere of rays from inside the
# corridor and reports every direction that escapes to the background.
#
# A ray that simply runs down the open corridor will exhaust its length without
# hitting anything, which is not a hole. So an empty cast only counts as a
# defect when its end point is actually outside the generated corridor envelope.

const CART := preload("res://scripts/moving_cart.gd")

var tunnel: Node3D

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var host: Node3D = Node3D.new()
	root.add_child(host)
	current_scene = host
	tunnel = preload("res://scripts/cave_tunnel.gd").new() as Node3D
	host.add_child(tunnel)
	tunnel.call("build", host)
	await _frames(4)
	var space: PhysicsDirectSpaceState3D = host.get_world_3d().direct_space_state
	var directions: Array[Vector3] = []
	var count: int = 720
	for i: int in range(count):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(count)
		var radius: float = sqrt(maxf(0.0, 1.0 - y * y))
		var theta: float = PI * (1.0 + sqrt(5.0)) * float(i)
		directions.append(Vector3(cos(theta) * radius, y, sin(theta) * radius).normalized())

	var total_holes: int = 0
	var total_along: int = 0
	var stations: Array[float] = [1.0, 8.0, 16.0, 24.0, 32.0, 40.0, 48.0, 56.0, 64.0, 72.0, 80.0, 88.0]
	for s: float in stations:
		var centre: Vector3 = CART.route_pose(s) * Vector3(0.0, 2.4, 0.0)
		var holes: Array[String] = []
		var along: int = 0
		for dir: Vector3 in directions:
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(centre, centre + dir * 40.0, 6)
			if not space.intersect_ray(query).is_empty():
				continue
			var end: Vector3 = centre + dir * 40.0
			if inside(end):
				along += 1
			else:
				holes.append("%.2f,%.2f,%.2f" % [dir.x, dir.y, dir.z])
		total_holes += holes.size()
		total_along += along
		if holes.size() > 0:
			print("HOLE   s=%5.1f count=%3d  first=%s" % [s, holes.size(), holes.slice(0, 6)])
		else:
			print("SEALED s=%5.1f  (lengthwise rays=%d)" % [s, along])
	print("TOTAL_HOLES ", total_holes, "  lengthwise=", total_along, "  rays=", stations.size() * 720)

	print("=== floor vs deck plane ===")
	for s: float in [0.0, 12.0, 24.0, 36.0, 48.0, 60.0, 72.0, 84.0, 90.0]:
		var top: Vector3 = CART.route_pose(s) * Vector3(0.0, 2.2, 0.0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(top, top - Vector3.UP * 4.0, 6)
		var hit: Dictionary = space.intersect_ray(query)
		var y: float = (hit["position"] as Vector3).y if not hit.is_empty() else -999.0
		print("  s=%5.1f floor_y=%7.3f  rail_y=%7.3f  gap=%6.3f" % [s, y, CART.route_pose(s).origin.y, y - CART.route_pose(s).origin.y])
	quit(0)

func inside(point: Vector3) -> bool:
	# The route bends, so point.x is NOT the arc length. Projecting onto the
	# nearest station is the only correct test; using x directly misclassified
	# every lengthwise ray through the bend as a hole.
	var s: float = nearest_s(point)
	var local: Vector3 = CART.route_pose(s).affine_inverse() * point
	var lateral: float = local.z - 2.2
	var up: float = local.y
	return absf(lateral) <= float(tunnel.call("half_width", s)) + 0.05 and up <= float(tunnel.call("height", s)) + 0.05 and up >= -0.6

func nearest_s(point: Vector3) -> float:
	var best_s: float = 0.0
	var best_d: float = 1e18
	var s: float = -EXTEND
	while s <= 96.0:
		var d: float = CART.route_pose(s).origin.distance_squared_to(Vector3(point.x, 0.0, point.z))
		if d < best_d:
			best_d = d
			best_s = s
		s += 0.5
	var fine: float = best_s - 0.5
	while fine <= best_s + 0.5:
		var d: float = CART.route_pose(fine).origin.distance_squared_to(Vector3(point.x, 0.0, point.z))
		if d < best_d:
			best_d = d
			best_s = fine
		fine += 0.05
	return clampf(best_s, -EXTEND, 96.0)

const EXTEND: float = 6.0
