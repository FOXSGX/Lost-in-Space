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

const CART := preload("res://act23/scripts/moving_cart.gd")

const STEP: float = 0.45
const WALL_SEGMENTS: int = 104
const FLOOR_SEGMENTS: int = 32
# Resonance 02+03: the shell follows the extended route (moving_cart.LENGTH), so
# the repaired section, the receiver and the crystal-mine dock all sit inside the
# same closed corridor instead of in a void past the old end plug.
const ROUTE_LENGTH: float = 106.0
# The shell and floor run past both stops so the end plugs never sit on an open
# edge and no ray can slip underneath them. 12 m, not 6: the third-person camera
# sits 5 m behind the player, and at the boarding dock that put the lens outside
# the old -6 m end, looking at the plug from behind. From there the missing floor
# outside the corridor showed the clear colour between the plug base and the
# invisible ground collider.
const EXTEND_BACK: float = 22.0
const EXTEND_FRONT: float = 18.0
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
# Authored strata profile. Heights are fractions of the local cave height; the
# radii and lip depths are metres. Six real ledges replace the old smooth tube.
const BAND_Y := [0.0, 0.145, 0.295, 0.455, 0.615, 0.780, 0.900]
const BAND_FRAC := [0.995, 0.985, 0.970, 0.950, 0.925, 0.890, 0.870]
const BAND_LIP := [0.52, 0.42, 0.58, 0.46, 0.62, 0.72]

var stage: Node3D
var rock: StandardMaterial3D
var ceiling_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var chamber_noise: FastNoiseLite
var wall_noise: FastNoiseLite
var crease_noise: FastNoiseLite
var grain_noise: FastNoiseLite
var albedo_noise: FastNoiseLite
var lamps: Array[Dictionary] = []
var shell: MeshInstance3D
var ceiling_shell: MeshInstance3D
var floor_mesh: MeshInstance3D
var collision: StaticBody3D
var triangles: int = 0

func build(controller: Node3D) -> void:
	stage = controller
	_setup_noise()
	_setup_materials()
	_place_lamps()
	_build_strata_shell()
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
	# The swept shell is now only the concealed backing behind the authored rock
	# kit. It stays deliberately dark and matte so any sliver visible through a
	# kit seam reads as a deep crevice, never as a lit smooth tube.
	rock = StandardMaterial3D.new()
	rock.albedo_texture = load("res://act23/assets/rocks/textures/rock_limestone_base.png") as Texture2D
	rock.albedo_color = Color(1.24, 1.11, 0.95)
	rock.normal_enabled = true
	rock.normal_texture = load("res://act23/assets/rocks/textures/rock_limestone_normal.png") as Texture2D
	rock.normal_scale = 0.42
	rock.roughness = 0.98
	rock.metallic = 0.0
	rock.uv1_triplanar = true
	rock.uv1_world_triplanar = true
	rock.uv1_scale = Vector3(0.40, 0.40, 0.40)
	rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# The generated shell is viewed from inside but its winding was authored for
	# the old cull_disabled shader. Keep that contract with PBR.
	rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	rock.vertex_color_use_as_albedo = true
	rock.vertex_color_is_srgb = false

	# The vault uses a quieter material than the walls: the base-colour map's
	# broad patches read as stains when projected across a 90 m ceiling, so the
	# ceiling keeps the normal/roughness detail and a near-uniform stone colour.
	ceiling_material = StandardMaterial3D.new()
	# The vault used to be colour-only, which is why it read as a bright plaster
	# plate between the hanging rocks. It now carries the same rock albedo as the
	# walls at a coarser world scale, so the ceiling has grain without the large
	# colour patches that made the old version look stained.
	ceiling_material.albedo_texture = load("res://act23/assets/rocks/textures/rock_limestone_base.png") as Texture2D
	ceiling_material.albedo_color = Color(0.62, 0.58, 0.52)
	ceiling_material.normal_enabled = true
	ceiling_material.normal_texture = load("res://act23/assets/rocks/textures/rock_limestone_normal.png") as Texture2D
	ceiling_material.normal_scale = 0.45
	ceiling_material.roughness = 0.98
	ceiling_material.metallic = 0.0
	ceiling_material.vertex_color_use_as_albedo = true
	ceiling_material.vertex_color_is_srgb = false
	ceiling_material.uv1_triplanar = true
	ceiling_material.uv1_world_triplanar = true
	ceiling_material.uv1_scale = Vector3(0.30, 0.30, 0.30)
	ceiling_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ceiling_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	floor_material = StandardMaterial3D.new()
	floor_material.albedo_texture = load("res://act23/assets/rocks/textures/gravel_ballast_base.png") as Texture2D
	floor_material.albedo_color = Color(1.0, 0.98, 0.94)
	floor_material.normal_enabled = true
	floor_material.normal_texture = load("res://act23/assets/rocks/textures/gravel_ballast_normal.png") as Texture2D
	floor_material.normal_scale = 0.58
	floor_material.roughness = 0.90
	floor_material.metallic = 0.0
	floor_material.uv1_scale = Vector3(1.0, 1.0, 1.0)
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	floor_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _place_lamps() -> void:
	# Real lamps are still spawned as props, but their contribution has to be
	# baked into the vertex irradiance because the shared shader is unshaded.
	for s: float in [3.0, 15.0, 27.0, 39.0, 51.0, 63.0, 75.0, 87.0, 98.0, 110.0]:
		lamps.append({"s": s, "energy": 1.0, "warm": 1.0})
	for s: float in [0.0, 88.0, 106.0]:
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

# Resonance 02+03: the repair bay needs a real working floor on the north side of
# the line (winch at 3.4 m, walkway to 5 m). The cave ring is authored 2.2 m south
# of the route, so that side only reaches ~4.4 m at station width; this pushes the
# north wall out over the bay and fades back before the crystal gate.
func bay_extra(s: float) -> float:
	return 2.80 * smoothstep(82.0, 86.0, s) * (1.0 - smoothstep(99.0, 103.0, s))

# The south (winch) side overhung the floor: at s=90 the wall surface reached
# z ~4.6 at chest height while the mid-wall ring was at 6.4, so a 2 m winch plus
# an operator did not fit and the old build let the player stand inside the drum.
# This cuts the lower south wall back to a vertical working face. It is applied
# only below ~4 m, so the upper vault keeps its authored shape.
func bay_south_extra(s: float) -> float:
	return 1.85 * smoothstep(82.0, 86.0, s) * (1.0 - smoothstep(99.0, 103.0, s))

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
	# Bay widening applies after the noise push, so the north wall of the repair
	# bay keeps its extra clearance instead of letting an inward mass cancel it.
	# The ramp is zero at the centreline and smooth in between: a hard `lateral > 0`
	# test put a 2 m discontinuity through the ceiling apex, and the folded quads
	# became a rock ledge hanging inside the corridor.
	if lateral > 0.0:
		lateral += bay_extra(s) * smoothstep(0.0, 1.6, lateral)
		if up < 4.2:
			# Vertical working face on the winch side, fading out under the vault.
			var lower_weight: float = 1.0 - smoothstep(2.4, 4.2, up)
			lateral += bay_south_extra(s) * lower_weight * smoothstep(0.0, 1.6, lateral)
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

func _band_offset(s: float, band: int) -> float:
	# Broad chambers, designed alcoves and buttresses. These are metres of real
	# radial displacement, not shader noise, so the silhouette changes with the
	# route instead of repeating a module.
	var off: float = wall_noise.get_noise_1d(s * 0.42 + float(band) * 17.0) * 0.38
	off += chamber_noise.get_noise_1d(s * 0.105 + float(band) * 5.0) * 0.52
	off += 0.72 * exp(-pow((s - 17.0) / 4.8, 2.0))
	off += 0.82 * exp(-pow((s - 45.0) / 5.6, 2.0))
	off += 0.58 * exp(-pow((s - 71.0) / 4.2, 2.0))
	off -= 0.46 * exp(-pow((s - 27.0) / 2.8, 2.0))
	off -= 0.40 * exp(-pow((s - 58.0) / 2.6, 2.0))
	off += 0.42 * smoothstep(35.85, 36.15, s)
	off += 0.30 * smoothstep(62.85, 63.10, s)
	off += 0.16 * sin(s * 0.31 + float(band) * 1.9)
	off += 0.20 * sin(s * 0.74 + float(band) * 2.4)
	off += 0.13 * wall_noise.get_noise_1d(s * 2.15 + float(band) * 31.0)
	return off * lerpf(0.72, 1.10, float(band) / 5.0)

func _add_v(st: SurfaceTool, point: Vector3, normal: Vector3, shade: float,
		uv_scale: float = 0.25, tint: Color = Color.WHITE) -> void:
	var speck: float = grain_noise.get_noise_3d(point.x * 1.15, point.y * 1.15, point.z * 1.15) * 0.5 + 0.5
	var value: float = clampf(shade * (0.86 + 0.22 * speck), 0.25, 1.0)
	st.set_normal(normal.normalized())
	st.set_color(Color(
		clampf(value * tint.r, 0.0, 1.0),
		clampf(value * tint.g, 0.0, 1.0),
		clampf(value * tint.b, 0.0, 1.0), 1.0))
	st.set_uv(Vector2(point.x, point.z) * uv_scale)
	st.add_vertex(point)

func _emit_band(st: SurfaceTool, rows: Array, band: int) -> void:
	# Wall strip: several height samples per band so the face can belly in and
	# out. Every strip owns its vertices, which keeps the ledger edges hard.
	var up_n: Vector3 = (rows[0] as Dictionary)["up"] as Vector3
	# Alternating warm/cool band tints used to be the only separation between
	# ledges, and they read as tan-versus-blue horizontal stripes on a flat wall.
	# The distinction is now carried by real ledge geometry and by the authored
	# rock modules in front of it, so the tint only drifts a little, and it drifts
	# with a noise instead of alternating.
	var drift: float = grain_noise.get_noise_1d(float(band) * 4.7) * 0.5
	var band_tint: Color = Color(
		1.0 + 0.020 * drift, 1.0 + 0.008 * drift, 1.0 - 0.018 * drift)
	for i: int in range(rows.size() - 1):
		var r0: Dictionary = rows[i]
		var r1: Dictionary = rows[i + 1]
		var p0: Array = r0["points"] as Array
		var p1: Array = r1["points"] as Array
		var n0: Array = r0["normals"] as Array
		var n1: Array = r1["normals"] as Array
		for j: int in range(p0.size() - 1):
			var a: Vector3 = p0[j] as Vector3
			var b: Vector3 = p0[j + 1] as Vector3
			var c: Vector3 = p1[j + 1] as Vector3
			var d: Vector3 = p1[j] as Vector3
			var shade0: float = 0.90 + 0.015 * float(band)
			var shade1: float = 0.93 + 0.015 * float(band)
			for entry: Array in [[a, n0[j], shade0], [b, n0[j + 1], shade0],
					[c, n1[j + 1], shade1], [a, n0[j], shade0],
					[c, n1[j + 1], shade1], [d, n1[j], shade1]]:
				_add_v(st, entry[0] as Vector3, entry[1] as Vector3, float(entry[2]), 0.25, band_tint)
	# Shelf top.
	for i: int in range(rows.size() - 1):
		var r0: Dictionary = rows[i]
		var r1: Dictionary = rows[i + 1]
		var p0: Array = r0["points"] as Array
		var p1: Array = r1["points"] as Array
		var a: Vector3 = p0[p0.size() - 1] as Vector3
		var b: Vector3 = r0["lip"] as Vector3
		var c: Vector3 = r1["lip"] as Vector3
		var d: Vector3 = p1[p1.size() - 1] as Vector3
		for entry: Array in [[a, 1.00], [b, 1.00], [c, 1.00],
				[a, 1.00], [c, 1.00], [d, 1.00]]:
			_add_v(st, entry[0] as Vector3, up_n, float(entry[1]))
	# Underside of the shelf: dark, so the ledge reads even in ambient light.
	if band < 5:
		for i: int in range(rows.size() - 1):
			var r0: Dictionary = rows[i]
			var r1: Dictionary = rows[i + 1]
			var a: Vector3 = r0["lip"] as Vector3
			var b: Vector3 = r0["next"] as Vector3
			var c: Vector3 = r1["next"] as Vector3
			var d: Vector3 = r1["lip"] as Vector3
			for entry: Array in [[a, 0.62], [d, 0.62], [c, 0.62],
					[a, 0.62], [c, 0.62], [b, 0.62]]:
				_add_v(st, entry[0] as Vector3, -up_n, float(entry[1]))

func _build_strata_shell() -> void:
	shell = MeshInstance3D.new()
	shell.name = "CaveStrataShell"
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = int(ceil((ROUTE_LENGTH + EXTEND_BACK + EXTEND_FRONT) / STEP))
	var profiles: Array = []
	for i: int in range(rings + 1):
		var s: float = sample_s(i, rings)
		var pose_at: Transform3D = CART.route_pose(s)
		var cap: float = 1.0
		if s > 95.0:
			cap = maxf(0.055, 1.0 - smoothstep(95.0, 108.0, s) * 0.945)
		elif s < -7.0:
			cap = maxf(0.055, 1.0 - smoothstep(-7.0, -22.0, s) * 0.945)
		var w: float = half_width(s) * cap
		var h: float = height(s) * lerpf(0.28, 1.0, cap)
		var bands: Array = []
		var next_bottom: float = w * 0.995 + _band_offset(s, 0) * cap
		for band: int in range(6):
			var wob0: float = 0.085 * sin(s * 0.55 + float(band) * 1.7)
			wob0 += wall_noise.get_noise_1d(s * 1.35 + float(band) * 11.0) * 0.075
			var wob1: float = 0.085 * sin(s * 0.55 + float(band + 1) * 1.7)
			wob1 += wall_noise.get_noise_1d(s * 1.35 + float(band + 1) * 11.0) * 0.075
			var y0: float = h * BAND_Y[band] + wob0
			var y1: float = h * BAND_Y[band + 1] + wob1
			var top: float = w * BAND_FRAC[band + 1] + _band_offset(s, band + 1) * cap
			var bottom: float = next_bottom
			var lip_depth: float = (BAND_LIP[band] + 0.20 * wall_noise.get_noise_1d(s * 0.9 + float(band) * 7.0)) * cap
			var lip_inner: float = top - lip_depth
			if band == 5:
				lip_inner = w * 0.72 + 0.12 * sin(s * 0.48) * cap
			var next_r: float = lip_inner + 0.10 * cap
			var clear: float = (3.55 if band < 5 else 3.20) * cap
			bottom = maxf(bottom, clear)
			top = maxf(top, clear)
			lip_inner = maxf(lip_inner, clear - 0.10)
			bands.append({"y0": y0, "y1": y1, "bottom_r": bottom, "top_r": top,
				"lip_r": lip_inner, "next_r": next_r})
			next_bottom = next_r
		profiles.append({"s": s, "pose": pose_at, "w": w, "h": h, "cap": cap, "bands": bands})

	for side: float in [-1.0, 1.0]:
		for band: int in range(6):
			var rows: Array = []
			for i: int in range(profiles.size()):
				var pr: Dictionary = profiles[i]
				var bd: Dictionary = (pr["bands"] as Array)[band] as Dictionary
				var pose_at: Transform3D = pr["pose"] as Transform3D
				var s: float = float(pr["s"])
				var cap: float = float(pr["cap"])
				var y0: float = float(bd["y0"])
				var y1: float = float(bd["y1"])
				var bottom_r: float = float(bd["bottom_r"])
				var top_r: float = float(bd["top_r"])
				var lip_r: float = float(bd["lip_r"])
				var next_r: float = float(bd["next_r"])
				var bottom: Vector3 = pose_at * Vector3(0.0, y0, side * bottom_r)
				var top: Vector3 = pose_at * Vector3(0.0, y1, side * top_r)
				# A bellied mid sample breaks the straight vertical wall. The
				# amplitude is metres, so the silhouette changes, not just shading.
				var mid_y: float = (y0 + y1) * 0.5 + 0.055 * sin(s * 0.85 + float(band) * 1.6)
				var bulge: float = 0.26 * sin(s * 1.45 + float(band) * 2.1)
				bulge += wall_noise.get_noise_1d(s * 2.7 + float(band) * 43.0) * 0.18
				var mid_r: float = clampf(lerpf(bottom_r, top_r, 0.5) + bulge * cap,
				maxf(0.08, (3.55 * cap) - 0.45), maxf(bottom_r, top_r) + 0.55 * cap)
				var mid: Vector3 = pose_at * Vector3(0.0, mid_y, side * mid_r)
				var lip: Vector3 = pose_at * Vector3(0.0, y1, side * lip_r)
				var next: Vector3 = pose_at * Vector3(0.0, y1, side * next_r)
				var inward: Vector3 = pose_at.basis * Vector3(0.0, 0.0, -side)
				var up_axis: Vector3 = pose_at.basis * Vector3.UP
				var n_bottom: Vector3 = (inward * maxf(mid_y - y0, 0.05) - up_axis * (mid_r - bottom_r)).normalized()
				var n_mid: Vector3 = (inward * maxf(y1 - y0, 0.05) - up_axis * (top_r - bottom_r)).normalized()
				var n_top: Vector3 = (inward * maxf(y1 - mid_y, 0.05) - up_axis * (top_r - mid_r)).normalized()
				rows.append({"points": [bottom, mid, top],
					"normals": [n_bottom, n_mid, n_top], "lip": lip,
					"next": next, "up": up_axis})
			_emit_band(st, rows, band)

	st.generate_tangents()
	shell.mesh = st.commit()
	shell.material_override = rock
	add_child(shell)
	triangles = (shell.mesh as ArrayMesh).get_faces().size() / 3

	# Ceiling: a continuous folded vault tied under the top cornice.
	var st_ceil: SurfaceTool = SurfaceTool.new()
	st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = 26
	var ceil_rows: Array = []
	for i: int in range(rings + 1):
		var pr: Dictionary = profiles[i]
		var pose_at: Transform3D = pr["pose"] as Transform3D
		var w: float = float(pr["w"])
		var h: float = float(pr["h"])
		var half: float = w * 0.80
		var row: Array = []
		var s: float = float(pr["s"])
		for j: int in range(cols + 1):
			var u: float = lerpf(-half, half, float(j) / float(cols))
			var edge: float = 1.0 - absf(u) / maxf(half, 0.1)
			var arch: float = h * BAND_Y[6] - 0.05 + 0.32 * edge
			# A simple smooth barrel with only gentle low-frequency variation.
			# Large sharp folds made quads self-intersect from below, which read
			# as jagged holes in the vault.
			arch += 0.07 * sin(u * 1.45 + s * 0.075) * edge
			arch += grain_noise.get_noise_2d(s * 1.4, u * 1.9) * 0.045
			arch += 0.10 * exp(-pow((s - 33.0) / 2.6, 2.0)) * edge
			arch += 0.09 * exp(-pow((s - 69.0) / 2.8, 2.0)) * edge
			row.append(pose_at * Vector3(0.0, arch, u))
		ceil_rows.append(row)

	# A smooth barrel's normals should all point down into the tunnel. The
	# former central-difference normals flipped on shallow folds and produced a
	# camouflage of light and dark patches; a stable down normal plus real lamp
	# pools reads as a vault instead.
	var ceil_normals: Array = []
	for i: int in range(rings + 1):
		var nrow: Array = []
		for j: int in range(cols + 1):
			nrow.append(Vector3.DOWN)
		ceil_normals.append(nrow)
	for i: int in range(rings):
		for j: int in range(cols):
			var a: Vector3 = (ceil_rows[i] as Array)[j] as Vector3
			var b: Vector3 = (ceil_rows[i] as Array)[j + 1] as Vector3
			var c: Vector3 = (ceil_rows[i + 1] as Array)[j + 1] as Vector3
			var d: Vector3 = (ceil_rows[i + 1] as Array)[j] as Vector3
			var na: Vector3 = (ceil_normals[i] as Array)[j] as Vector3
			var nb: Vector3 = (ceil_normals[i] as Array)[j + 1] as Vector3
			var nc: Vector3 = (ceil_normals[i + 1] as Array)[j + 1] as Vector3
			var nd: Vector3 = (ceil_normals[i + 1] as Array)[j] as Vector3
			for entry: Array in [[a, na], [c, nc], [b, nb],
					[a, na], [d, nd], [c, nc]]:
				_add_v(st_ceil, entry[0] as Vector3, entry[1] as Vector3, 0.92)

	st_ceil.generate_tangents()
	ceiling_shell = MeshInstance3D.new()
	ceiling_shell.name = "CaveCeiling"
	ceiling_shell.mesh = st_ceil.commit()
	ceiling_shell.material_override = ceiling_material
	add_child(ceiling_shell)
	triangles += (ceiling_shell.mesh as ArrayMesh).get_faces().size() / 3


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
	# The old unshaded shader ignored NORMAL/TANGENT. PBR does not: without
	# these the shell renders pitch black from inside. Flip the generated
	# normals so they face the tunnel interior.
	st.generate_normals(true)
	st.generate_tangents()
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
		var cap: float = 1.0
		if s > 112.0:
			cap = maxf(0.09, 1.0 - smoothstep(112.0, 124.0, s) * 0.91)
		elif s < -7.0:
			cap = maxf(0.09, 1.0 - smoothstep(-7.0, -22.0, s) * 0.91)
		var w: float = (half_width(s) + 1.75) * cap
		var extra: float = bay_extra(s)
		var row: Array = []
		for j: int in range(FLOOR_SEGMENTS + 1):
			var u: float = lerpf(-w, w, float(j) / float(FLOOR_SEGMENTS))
			# The north half follows the widened bay wall so the floor never ends
			# short of the rock and leaves a visible slot under the winch platform.
			if u > 0.0:
				u += extra * smoothstep(0.0, w * 0.35, u)
			# Gentle crown so the ballast is not a flat painted plane.
			var rise: float = 0.05 * (1.0 - pow(absf(u) / maxf(w + extra, 0.01), 2.0))
			rise += grain_noise.get_noise_2d(s * 3.0, u * 3.0) * 0.030
			row.append({"world": pose * Vector3(0.0, rise - 0.02, u), "s": s, "u": u})
		# The continuous strata wall can step outward into an alcove by more than
		# a metre, so the floor lip runs under it rather than stopping at the
		# nominal radius.
		row[0]["world"] = pose * Vector3(0.0, -0.20, -w)
		row[FLOOR_SEGMENTS]["world"] = pose * Vector3(0.0, -0.20, w + extra + bay_south_extra(s))
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
				# Real PBR ballast. UVs are world-sized so the 4 m gravel tile can
				# never stretch into long smears through the bend.
				var edge: float = clampf(1.0 - absf(u) / maxf(half_width(s), 0.1), 0.0, 1.0)
				st.set_uv(Vector2(world.x, world.z) * 0.35)
				st.set_color(Color(0.94 + 0.06 * fleck, 0.92 + 0.05 * fleck, 0.88 + 0.05 * edge, 1.0))
				st.add_vertex(world)
	st.generate_normals(true)
	st.generate_tangents()
	floor_mesh.mesh = st.commit()
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	triangles += (floor_mesh.mesh as ArrayMesh).get_faces().size() / 3

func _build_collision() -> void:
	collision = StaticBody3D.new()
	collision.name = "CaveCollision"
	collision.collision_layer = 7 # WORLD (1) | act23 player wall (2) | camera (4)
	collision.collision_mask = 0
	var shapes: Dictionary = _shell_collision_shapes()
	var shell_collider: CollisionShape3D = CollisionShape3D.new()
	shell_collider.shape = shapes["kept"] as ConcavePolygonShape3D
	collision.add_child(shell_collider)
	var floor_shape: ConcavePolygonShape3D = (floor_mesh.mesh as ArrayMesh).create_trimesh_shape()
	floor_shape.backface_collision = true
	var floor_collider: CollisionShape3D = CollisionShape3D.new()
	floor_collider.shape = floor_shape
	collision.add_child(floor_collider)
	add_child(collision)
	# The triangles removed from the player collider are exactly the ones the
	# camera needs. Without them the corridor's collision has a 6.6 m x 5.2 m
	# hole, so the chase lens left the tunnel and ended up inside the visible
	# rock at the resonance bend (02_bend_grip.png in the delivered build).
	# They stay solid for camera-only queries on layer 3 (mask value 4), where
	# neither the player nor the cart can ever be trapped by them.
	var camera_body: StaticBody3D = StaticBody3D.new()
	camera_body.name = "CaveCameraShell"
	camera_body.collision_layer = 4
	camera_body.collision_mask = 0
	var camera_collider: CollisionShape3D = CollisionShape3D.new()
	camera_collider.shape = shapes["dropped"] as ConcavePolygonShape3D
	camera_body.add_child(camera_collider)
	add_child(camera_body)

# The wall shell is a noisy ring; a fold (or the bay widening ramp) can leave a
# triangle hanging inside the corridor at chest height. Visually it is a thin
# sliver, but as collision it is an invisible wall across the line - it scraped a
# rider off the deck at 104 m. The shell's *player* collision therefore excludes
# every triangle inside the driving envelope, but those triangles are kept as a
# camera-only body so the lens cannot escape through the resulting hole.
func _shell_collision_shapes() -> Dictionary:
	var faces: PackedVector3Array = (shell.mesh as ArrayMesh).get_faces()
	var kept: PackedVector3Array = PackedVector3Array()
	var dropped: PackedVector3Array = PackedVector3Array()
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		if _inside_envelope(a) and _inside_envelope(b) and _inside_envelope(c):
			# Camera-only replacement is for the UPPER shell only: those are the
			# surfaces the lens could escape through at the bend. Low folds at
			# rider height must not become invisible blockers around the player's
			# head (that made the lens collapse to 1.2 m at the arrival).
			if minf(a.y, minf(b.y, c.y)) > 3.50:
				dropped.append(a)
				dropped.append(b)
				dropped.append(c)
			continue
		kept.append(a)
		kept.append(b)
		kept.append(c)
	var kept_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	kept_shape.backface_collision = true
	kept_shape.set_faces(kept)
	var dropped_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	dropped_shape.backface_collision = true
	dropped_shape.set_faces(dropped)
	const Log := preload("res://scripts/core/log.gd")
	Log.d("CAVE_SHELL", "envelope_triangles_dropped=%d camera_only_triangles=%d" % [
		int(float(dropped.size()) / 3.0), int(float(dropped.size()) / 3.0)])
	return {"kept": kept_shape, "dropped": dropped_shape}

func _inside_envelope(point: Vector3) -> bool:
	if point.y > 4.60 or point.y < -0.60:
		return false
	# The route centreline in world space: x is the arc length and the lateral
	# bend is a pure function of it, so no search is needed.
	var centre_z: float = 2.2 + CART.bend(point.x)
	return absf(point.z - centre_z) < 3.30
