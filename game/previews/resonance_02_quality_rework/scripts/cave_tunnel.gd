extends Node3D

# Closed cave corridor generated along the cart route.
#
# Why this exists: the previous round cropped a 43 m straight diorama into a
# 90 m bent corridor. The crop deleted the cave floor (y < 0.35) and the ceiling
# (y > 6.0) and left the cut edges open, so the player looked straight into the
# background clear colour. Offsetting four copies of the diorama by a Z bend that
# reached 5.8 m also pushed the route outside the source floor near the bend.
# No amount of extra ambient light fixes missing geometry, so the corridor is now
# generated as one closed shell that follows the real route.
#
# Visual parity with the approved scene is kept by driving the same baked-AgX
# shader with generated vertex data:
#   UV0 = (albedo.r, 1 - albedo.g)     UV1 = (albedo.b, 1 - roughness)
#   COLOR = log2(irradiance + 1) / 8   (log_irradiance with irradiance_scale 8)

const CART := preload("res://scripts/moving_cart.gd")

const STEP: float = 0.45
const WALL_SEGMENTS: int = 104
const FLOOR_SEGMENTS: int = 32
const ROUTE_LENGTH: float = 90.0
# The shell and floor run past both stops so the end plugs never sit on an open
# edge and no ray can slip underneath them. 12 m, not 6: the third-person camera
# sits 5 m behind the player, and at the boarding dock that put the lens outside
# the old -6 m end, looking at the plug from behind. From there the missing floor
# outside the corridor showed the clear colour between the plug base and the
# invisible ground collider.
const EXTEND_BACK: float = 18.0
const EXTEND_FRONT: float = 12.0
# The cart is 9.8 m long and swings ~1.6 m sideways through the bend, so the
# corridor keeps a real margin instead of hugging the hull.
const HALF_WIDTH: float = 4.70
const HALF_WIDTH_STATION: float = 6.90
const HEIGHT: float = 6.90
const HEIGHT_STATION: float = 8.70
# No wall vertex may come closer than this to the centreline at deck height.
const CLEAR_RADIUS: float = 3.10
# How far the end plugs reach behind each stop.
const PLUG_DEPTH: float = 7.0
const PLUG_STEPS: int = 9

var stage: Node3D
var rock: ShaderMaterial
var floor_material: ShaderMaterial
var chamber_noise: FastNoiseLite
var wall_noise: FastNoiseLite
var crease_noise: FastNoiseLite
var grain_noise: FastNoiseLite
var albedo_noise: FastNoiseLite
var lamps: Array[Dictionary] = []
var shell: MeshInstance3D
var floor_mesh: MeshInstance3D
var collision: StaticBody3D
var triangles: int = 0

func build(controller: Node3D) -> void:
	stage = controller
	_setup_noise()
	_setup_materials()
	_place_lamps()
	_build_shell()
	_build_floor()
	_build_collision()

func _setup_noise() -> void:
	chamber_noise = _noise(90210, 0.026, 2)
	wall_noise = _noise(4711, 0.135, 4)
	crease_noise = _noise(31337, 0.44, 3)
	grain_noise = _noise(60013, 1.55, 2)
	albedo_noise = _noise(1337, 0.12, 3)

func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var result: FastNoiseLite = FastNoiseLite.new()
	result.seed = seed_value
	result.noise_type = FastNoiseLite.TYPE_SIMPLEX
	result.frequency = frequency
	result.fractal_octaves = octaves
	return result

func _setup_materials() -> void:
	var shader: Shader = load("res://static_surface.gdshader") as Shader
	var lut: Texture2D = load("res://assets/agx_medium_high.png") as Texture2D
	rock = ShaderMaterial.new()
	rock.shader = shader
	rock.set_shader_parameter("agx_lut", lut)
	rock.set_shader_parameter("metallic", 0.0)
	rock.set_shader_parameter("roughness", 0.80)
	rock.set_shader_parameter("sourced_roughness", true)
	rock.set_shader_parameter("log_irradiance", true)
	rock.set_shader_parameter("irradiance_scale", 8.0)
	rock.set_shader_parameter("indirect_floor", Vector3(0.05, 0.062, 0.082))
	# The shell is one smooth swept surface. Detail modulation gives the rock
	# strata and cracks that the approved station had from its baked texture.
	rock.set_shader_parameter("exposure_gain", 0.60)
	rock.set_shader_parameter("detail_strength", 0.65)
	rock.set_shader_parameter("detail_scale", 2.30)
	floor_material = ShaderMaterial.new()
	floor_material.shader = shader
	floor_material.set_shader_parameter("agx_lut", lut)
	floor_material.set_shader_parameter("metallic", 0.0)
	floor_material.set_shader_parameter("roughness", 0.90)
	floor_material.set_shader_parameter("sourced_roughness", true)
	floor_material.set_shader_parameter("log_irradiance", true)
	floor_material.set_shader_parameter("irradiance_scale", 8.0)
	floor_material.set_shader_parameter("indirect_floor", Vector3(0.05, 0.062, 0.082))
	floor_material.set_shader_parameter("exposure_gain", 0.60)
	floor_material.set_shader_parameter("detail_strength", 0.42)
	floor_material.set_shader_parameter("detail_scale", 1.15)

func _place_lamps() -> void:
	# Real lamps are still spawned as props, but their contribution has to be
	# baked into the vertex irradiance because the shared shader is unshaded.
	for s: float in [3.0, 15.0, 27.0, 39.0, 51.0, 63.0, 75.0, 87.0]:
		lamps.append({"s": s, "energy": 1.0, "warm": 1.0})
	for s: float in [0.0, 90.0]:
		lamps.append({"s": s, "energy": 1.9, "warm": 0.5})

# World-space centreline point at distance s and height above the rail plane.
func centre(s: float, up: float = 0.0) -> Vector3:
	return CART.route_pose(s) * Vector3(0.0, up, 0.0)

func station_weight(s: float) -> float:
	return clampf(smoothstep(11.0, 2.0, s) + smoothstep(79.0, 88.0, s), 0.0, 1.0)

# Sample stations run from -EXTEND_BACK to ROUTE_LENGTH + EXTEND_FRONT.
func sample_s(index: int, count: int) -> float:
	return lerpf(-EXTEND_BACK, ROUTE_LENGTH + EXTEND_FRONT, float(index) / float(count))

# Arc-length of the route point nearest to a world position. Diagnostics need
# this because the route bends: a world X coordinate is not the arc length.
func nearest_s(point: Vector3) -> float:
	var best: float = -EXTEND_BACK
	var best_d: float = 1e18
	var s: float = -EXTEND_BACK
	while s <= ROUTE_LENGTH + EXTEND_FRONT:
		var d: float = CART.route_pose(s).origin.distance_squared_to(Vector3(point.x, 0.0, point.z))
		if d < best_d:
			best_d = d
			best = s
		s += 0.5
	return best

func half_width(s: float) -> float:
	# Chambers open and pinch along the drive so it never reads as a pipe.
	var chamber: float = chamber_noise.get_noise_1d(s) * 1.15
	var base: float = lerpf(HALF_WIDTH, HALF_WIDTH_STATION, station_weight(s))
	return maxf(base + chamber, CLEAR_RADIUS + 0.60)

func height(s: float) -> float:
	var chamber: float = chamber_noise.get_noise_1d(s + 400.0) * 1.25
	var base: float = lerpf(HEIGHT, HEIGHT_STATION, station_weight(s))
	return maxf(base + chamber, 5.5)

# Ring parameter t in [0,1]: 0 = left floor edge, 0.5 = ceiling apex,
# 1 = right floor edge. Returns lateral offset and height above the rail plane.
func ring_point(s: float, t: float) -> Vector2:
	var w: float = half_width(s)
	var h: float = height(s)
	var angle: float = PI * t
	var lateral: float = -w * cos(angle)
	# pow < 1 keeps a wide walkable floor and a flatter ceiling than a circle.
	var profile: float = pow(maxf(sin(angle), 0.0), 0.38)
	var up: float = h * profile
	# Layered rock: broad masses, ridged creases, then fine grain.
	var mass: float = wall_noise.get_noise_2d(s, t * 6.0) * 1.55
	var crease_raw: float = crease_noise.get_noise_2d(s * 1.25, t * 15.0)
	# Ridged transform carves sharp creases instead of smooth undulation.
	var crease: float = (1.0 - absf(crease_raw)) * -0.95 + 0.34
	var grain: float = grain_noise.get_noise_2d(s * 1.9, t * 36.0) * 0.16
	var push: float = mass + crease + grain
	# Only the low-frequency mass may push the wall inwards. The high-frequency
	# creases are clamped to bulge outwards, because letting a ridged signal cross
	# zero makes the ring non-monotonic: neighbouring vertices swap order, the
	# quads fold, and a ray finds a slit that renders as background colour.
	var inward: float = minf(push, 0.0)
	var outward: float = maxf(push, 0.0)
	var allowed_in: float = maxf(0.0, absf(lateral) - CLEAR_RADIUS)
	inward = maxf(inward, -allowed_in * 0.55)
	lateral += signf(lateral) * (inward + outward)
	up += outward * profile * 0.85 + inward * 0.20
	return Vector2(lateral, maxf(up, 0.0))

func _irradiance(world: Vector3, s: float, up: float) -> Vector3:
	# Cool cave bounce. Deliberately dim, but far enough that the tunnel ahead
	# never reads as a black hole: with the old 0.115 falloff the lamps only
	# reached ~8 m and everything beyond the next bend was pure black.
	var value: Vector3 = Vector3(0.42, 0.50, 0.62) * 0.34
	for lamp: Dictionary in lamps:
		var centre_at: Vector3 = centre(float(lamp["s"]), 4.4)
		var delta: Vector3 = world - centre_at
		var falloff: float = 1.0 / (1.0 + delta.length_squared() * 0.042)
		var warm: float = float(lamp["warm"])
		var tint: Vector3 = Vector3(1.0, 0.79, 0.55).lerp(Vector3(0.70, 0.84, 1.0), 1.0 - warm)
		value += tint * (float(lamp["energy"]) * 1.55 * falloff)
	# Floor bounce keeps the walking surface readable.
	value += Vector3(0.20, 0.225, 0.255) * exp(-maxf(up, 0.0) / 2.1)
	# Crevices and the deep ceiling stay darker, but never crush to black.
	var occlusion: float = 1.0 - 0.42 * clampf((up - 3.0) / 3.8, 0.0, 1.0)
	value *= occlusion
	# Patchy mineral staining: the swept shell is smooth, so without per-vertex
	# variation every surface resolves to the same flat grey. This is lighting
	# variation baked from the same world position, not a texture decal.
	var broad: float = albedo_noise.get_noise_3d(world.x * 0.30, world.y * 0.30, world.z * 0.30) * 0.5 + 0.5
	var fine: float = grain_noise.get_noise_3d(world.x * 0.55, world.y * 0.55, world.z * 0.55) * 0.5 + 0.5
	value *= 0.80 + 0.34 * broad + 0.12 * fine
	return Vector3(maxf(value.x, 0.088), maxf(value.y, 0.098), maxf(value.z, 0.118))

func _encode(color: Vector3) -> Color:
	return Color(
		clampf(log(maxf(color.x, 0.0001) + 1.0) / log(2.0) / 8.0, 0.0, 1.0),
		clampf(log(maxf(color.y, 0.0001) + 1.0) / log(2.0) / 8.0, 0.0, 1.0),
		clampf(log(maxf(color.z, 0.0001) + 1.0) / log(2.0) / 8.0, 0.0, 1.0),
		1.0)

func _wall_vertex(st: SurfaceTool, world: Vector3, s: float, up: float) -> void:
	# Albedo: cool blue-grey schist with strata banding and mineral streaks.
	var strata: float = sin(world.y * 2.4 + albedo_noise.get_noise_2d(world.x * 0.6, world.y * 0.6) * 3.1) * 0.5 + 0.5
	var fleck: float = albedo_noise.get_noise_2d(world.x * 2.4, world.z * 2.4) * 0.5 + 0.5
	var albedo: Vector3 = Vector3(0.148, 0.158, 0.180)
	albedo = albedo.lerp(Vector3(0.222, 0.230, 0.248), strata * 0.62)
	albedo = albedo.lerp(Vector3(0.098, 0.106, 0.130), fleck * 0.46)
	# A few mineralised veins catch the lamp colour.
	if fleck > 0.80:
		albedo = albedo.lerp(Vector3(0.128, 0.226, 0.252), (fleck - 0.80) * 3.6)
	var roughness: float = clampf(0.70 + fleck * 0.20, 0.58, 0.96)
	st.set_uv(Vector2(albedo.x, 1.0 - albedo.y))
	st.set_uv2(Vector2(albedo.z, 1.0 - roughness))
	st.set_color(_encode(_irradiance(world, s, up)))
	st.add_vertex(world)

func _build_shell() -> void:
	shell = MeshInstance3D.new()
	shell.name = "CaveShell"
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = int(ceil((ROUTE_LENGTH + EXTEND_BACK + EXTEND_FRONT) / STEP))
	var grid: Array = []
	for i: int in range(rings + 1):
		var s: float = sample_s(i, rings)
		var pose: Transform3D = CART.route_pose(s)
		var row: Array = []
		for j: int in range(WALL_SEGMENTS + 1):
			var t: float = float(j) / float(WALL_SEGMENTS)
			var p: Vector2 = ring_point(s, t)
			row.append({"world": pose * Vector3(0.0, p.y, p.x), "s": s, "up": p.y})
		grid.append(row)
	for i: int in range(rings):
		for j: int in range(WALL_SEGMENTS):
			var a: Dictionary = grid[i][j]
			var b: Dictionary = grid[i][j + 1]
			var c: Dictionary = grid[i + 1][j + 1]
			var d: Dictionary = grid[i + 1][j]
			for entry: Dictionary in [a, b, c, a, c, d]:
				_wall_vertex(st, entry["world"] as Vector3, float(entry["s"]), float(entry["up"]))
	# End plugs. A flat fan across a noisy ring is not star-shaped and leaves
	# gaps, so each end converges through progressively shrunk copies of the same
	# ring. That keeps the surface closed whatever the noise does.
	_plug(st, grid[0], -1.0)
	_plug(st, grid[rings], 1.0)
	shell.mesh = st.commit()
	shell.material_override = rock
	add_child(shell)
	triangles = (shell.mesh as ArrayMesh).get_faces().size() / 3

func _plug(st: SurfaceTool, row: Array, direction: float) -> void:
	var s_end: float = float(row[0]["s"])
	# The cart's local +X is longitudinal and +Z is lateral, so the plug has to
	# travel along X. Pushing along Z offset the whole cone sideways and left a
	# slit at floor level that rendered as background colour.
	# The apex sits BELOW the floor plane. Converging at deck height left a void
	# between the floor's end edge and the underside of the cone, which is exactly
	# the slit a player sees as background colour when looking down the track.
	var anchor: Vector3 = centre(s_end, -1.30)
	var apex: Vector3 = anchor + CART.route_pose(s_end).basis * Vector3(direction * PLUG_DEPTH, 0.0, 0.0)
	var previous: Array = []
	for entry: Dictionary in row:
		previous.append(entry["world"] as Vector3)
	for step: int in range(1, PLUG_STEPS + 1):
		var blend: float = float(step) / float(PLUG_STEPS)
		var current: Array = []
		for i: int in range(previous.size()):
			var base: Vector3 = row[i]["world"] as Vector3
			# Pull towards the apex while drifting slightly off-axis so the plug
			# reads as a rock face rather than a machined cone.
			var drift: Vector3 = Vector3(
				grain_noise.get_noise_2d(float(i) * 0.7, blend * 5.0),
				grain_noise.get_noise_2d(float(i) * 0.9 + 90.0, blend * 5.0),
				grain_noise.get_noise_2d(float(i) * 1.1 + 180.0, blend * 5.0)) * 1.15 * blend
			current.append(base.lerp(apex, blend * blend) + drift)
		for j: int in range(row.size() - 1):
			var up_a: float = float(row[j]["up"])
			var up_b: float = float(row[j + 1]["up"])
			for entry: Array in [[previous[j], up_a], [previous[j + 1], up_b], [current[j + 1], up_b],
					[previous[j], up_a], [current[j + 1], up_b], [current[j], up_a]]:
				_wall_vertex(st, entry[0] as Vector3, s_end, float(entry[1]) * (1.0 - blend * 0.5))
		previous = current
	# Close the residual opening with a fan so the apex cannot be a hole.
	var last: Vector3 = apex
	for j: int in range(previous.size() - 1):
		for entry: Array in [[previous[j], float(row[j]["up"])], [previous[j + 1], float(row[j + 1]["up"])], [last, 1.0]]:
			_wall_vertex(st, entry[0] as Vector3, s_end, float(entry[1]) * 0.4)

func _build_floor() -> void:
	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "CaveFloor"
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = int(ceil((ROUTE_LENGTH + EXTEND_BACK + EXTEND_FRONT) / STEP))
	var rows: Array = []
	for i: int in range(rings + 1):
		var s: float = sample_s(i, rings)
		var pose: Transform3D = CART.route_pose(s)
		var w: float = half_width(s)
		var row: Array = []
		for j: int in range(FLOOR_SEGMENTS + 1):
			var u: float = lerpf(-w, w, float(j) / float(FLOOR_SEGMENTS))
			# Gentle crown so the ballast is not a flat painted plane.
			var rise: float = 0.05 * (1.0 - pow(absf(u) / maxf(w, 0.01), 2.0))
			rise += grain_noise.get_noise_2d(s * 3.0, u * 3.0) * 0.030
			row.append({"world": pose * Vector3(0.0, rise - 0.02, u), "s": s, "u": u})
		# Snap the outer edge onto the actual wall base so no seam can open, then
		# push a 0.55 m lip outwards and 0.18 m below the wall base. The wall base
		# is noisy and can sit a few centimetres above the floor; the lip always
		# tucks underneath it, so no gap between floor and wall can show the clear
		# colour even where the noise pushes the base up.
		var left: Vector2 = ring_point(s, 0.0)
		var right: Vector2 = ring_point(s, 1.0)
		row[0]["world"] = pose * Vector3(0.0, left.y - 0.18, left.x - 0.55)
		row[FLOOR_SEGMENTS]["world"] = pose * Vector3(0.0, right.y - 0.18, right.x + 0.55)
		rows.append(row)
	for i: int in range(rings):
		for j: int in range(FLOOR_SEGMENTS):
			var a: Dictionary = rows[i][j]
			var b: Dictionary = rows[i][j + 1]
			var c: Dictionary = rows[i + 1][j + 1]
			var d: Dictionary = rows[i + 1][j]
			for entry: Dictionary in [a, b, c, a, c, d]:
				var world: Vector3 = entry["world"] as Vector3
				var s: float = float(entry["s"])
				var u: float = float(entry["u"])
				var fleck: float = albedo_noise.get_noise_2d(world.x * 2.6, world.z * 2.6) * 0.5 + 0.5
				# Compacted mineral ballast, matching the approved palette.
				var albedo: Vector3 = Vector3(0.082, 0.090, 0.100)
				albedo = albedo.lerp(Vector3(0.138, 0.144, 0.150), fleck * 0.64)
				var edge: float = clampf(1.0 - absf(u) / maxf(half_width(s), 0.1), 0.0, 1.0)
				var light: Vector3 = _irradiance(world, s, 0.0) * lerpf(0.70, 1.0, edge)
				st.set_uv(Vector2(albedo.x, 1.0 - albedo.y))
				st.set_uv2(Vector2(albedo.z, 1.0 - 0.93))
				st.set_color(_encode(light))
				st.add_vertex(world)
	floor_mesh.mesh = st.commit()
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	triangles += (floor_mesh.mesh as ArrayMesh).get_faces().size() / 3

func _build_collision() -> void:
	collision = StaticBody3D.new()
	collision.name = "CaveCollision"
	collision.collision_layer = 6
	collision.collision_mask = 0
	for source: MeshInstance3D in [shell, floor_mesh]:
		var shape: ConcavePolygonShape3D = (source.mesh as ArrayMesh).create_trimesh_shape()
		shape.backface_collision = true
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		collision.add_child(collider)
	add_child(collision)
