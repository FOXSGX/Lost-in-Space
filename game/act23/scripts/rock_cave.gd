extends Node3D

# Resonance 02 art dressing, rebuilt on the approved Mining Station 01.1 rock and
# crystal geometry.
#
# Historical note (why the first reuse attempt failed and why this one works):
# the shipped station GLB carries `P11_*` materials whose albedo/normal/roughness
# are a single AGX-exposure bake, and the mineral meshes also carry a
# `BakedIrradiance` vertex colour solved for the station light rig.  Dropping
# those surfaces into a differently lit cave multiplied two lighting solutions
# and produced the dark blotches.  `pipeline/build_kit.py` therefore keeps the
# approved geometry and discards the baked shading: fresh decimation to a triangle
# budget, no UV map, no baked colour, a rebuilt per-vertex AO layer, and a
# normalised bounding-box origin.  This script then applies ONE shared triplanar
# PBR rock material (the same texture, world scale and roughness as the cave wall)
# plus dedicated crystal materials, so the reused assets read as the same rock as
# the tunnel instead of as imported props.
#
# Placement is authored per art beat, not scattered by a loop: the crystals follow
# the route rhythm from an industrial rock-only start, through sparse roots, into
# the resonance bend climax, then a held beat and a final chamber.

const CART := preload("res://act23/scripts/moving_cart.gd")

const KIT_DIR := "res://act23/assets/rocks/station/"
const KIT_MANIFEST := "res://act23/assets/rocks/station_kit.json"

# Big folded wall shells: real sediment folds and cavities that break the
# continuous horizontal strata of the swept shell.
const WALL_MODULES: Array[String] = ["schist_shell_a", "schist_shell_b", "schist_shell_c"]
# Broken rock masses: replaces the round boulder kit of the previous round.
const OUTCROP_MODULES: Array[String] = [
	"thrust_a", "shelf_a", "cap_a", "knuckle_a", "folded_vault_a", "vault_slab_a", "vault_slab_b",
]
# Wall-foot debris and small broken blocks.
const DEBRIS_MODULES: Array[String] = ["apron_a", "tongue_a", "lip_a"]
# Ceiling: hanging caps, folded shale slabs and broken roof plates.
const CEILING_MODULES: Array[String] = ["cap_a", "shale_fold_a", "knuckle_a", "cap_a", "knuckle_a"]

const CRYSTAL_CYAN: Array[String] = ["crystal_cyan_a", "crystal_cyan_b", "crystal_shard_a"]
const CRYSTAL_VIOLET: Array[String] = ["crystal_violet_a", "crystal_violet_b"]
const CRYSTAL_GLOW: Array[String] = ["crystal_axial_a"]
const VEIN_CYAN := "vein_cyan_a"
const VEIN_VIOLET := "vein_violet_a"
const VEIN_GLOW := "vein_axial_a"

const START_EXTEND: float = 16.0
const END_EXTEND: float = 12.0
const COLLISION_WIDTH: float = 3.75

var stage: Node3D
var cave: Node3D
var rock_material: StandardMaterial3D
var ceiling_rock_material: StandardMaterial3D
var crystal_material: StandardMaterial3D
var crystal_violet_material: StandardMaterial3D
var crystal_glow_material: StandardMaterial3D
var ground_shadow_material: StandardMaterial3D
var crystal_glow_texture: GradientTexture2D

var kit_scenes: Dictionary = {}
var kit_sizes: Dictionary = {}
var kit_facing: Dictionary = {}
var crystal_meshes: Array[MeshInstance3D] = []
var crystal_materials: Array[StandardMaterial3D] = []
var crystal_lights: Array[OmniLight3D] = []
var crystal_light_base: Array[float] = []
var rng := RandomNumberGenerator.new()
var rock_nodes: int = 0
var rock_triangles: int = 0
var rock_instances: Array[Node3D] = []
var _rock_bodies: int = 0
var _tri_cache: Dictionary = {}
# Footprint of every placed wall rock. Crystal sites use it to sit on the
# outermost rock face instead of sinking behind a module that protrudes further.
var rock_marks: Array[Dictionary] = []


func build(controller: Node3D, cave_node: Node3D) -> void:
	stage = controller
	cave = cave_node
	rng.seed = 0x5EED_2026
	_load_kit()
	_build_materials()
	_build_wall_relief()
	_build_outcrops()
	_build_ceiling()
	_build_debris()
	_build_crystals()
	_build_end_structure()
	_build_collision()
	_build_module_collision()
	print("ROCK_CAVE nodes=%d rock_triangles=%d marks=%d lights=%d bodies=%d"
		% [rock_nodes, rock_triangles, rock_marks.size(), crystal_lights.size(), _rock_bodies])


# ---------------------------------------------------------------- asset loading

func _load_kit() -> void:
	# Triangle budgets and Godot-space sizes come from the Blender export manifest,
	# so placement maths never guesses a module's depth.
	var manifest_text: String = ""
	if FileAccess.file_exists(KIT_MANIFEST):
		var file: FileAccess = FileAccess.open(KIT_MANIFEST, FileAccess.READ)
		if file != null:
			manifest_text = file.get_as_text()
			file.close()
	if manifest_text != "":
		var parsed: Variant = JSON.parse_string(manifest_text)
		if parsed is Dictionary:
			var modules: Array = (parsed as Dictionary).get("modules", []) as Array
			for entry: Variant in modules:
				if entry is Dictionary:
					var record: Dictionary = entry as Dictionary
					var name: String = str(record.get("name", ""))
					var dims: Array = record.get("dims", []) as Array
					if name == "" or dims.size() < 3:
						continue
					# Blender (X, Y, Z) maps to Godot (X, Z, Y) on a +Y-up GLB export.
					kit_sizes[name] = Vector3(
						float(dims[0]), float(dims[2]), float(dims[1]))
					var facing: Array = record.get("facing", []) as Array
					if facing.size() >= 3:
						var vector: Vector3 = Vector3(
							float(facing[0]), float(facing[1]), float(facing[2]))
						if vector.length() > 0.35:
							kit_facing[name] = vector.normalized()
	for name: String in _all_module_names():
		var path: String = KIT_DIR + name + ".glb"
		if ResourceLoader.exists(path):
			var packed: PackedScene = load(path) as PackedScene
			if packed != null:
				kit_scenes[name] = packed


func _all_module_names() -> Array[String]:
	var names: Array[String] = []
	for group: Array in [WALL_MODULES, OUTCROP_MODULES, DEBRIS_MODULES, CEILING_MODULES,
			CRYSTAL_CYAN, CRYSTAL_VIOLET, CRYSTAL_GLOW]:
		for name: String in group:
			if not names.has(name):
				names.append(name)
	for name: String in [VEIN_CYAN, VEIN_VIOLET, VEIN_GLOW]:
		if not names.has(name):
			names.append(name)
	return names


func _kit_size(name: String) -> Vector3:
	if kit_sizes.has(name):
		return kit_sizes[name] as Vector3
	return Vector3.ONE


# Local-space direction the module's rock face looks along. Closed rock masses have
# no dominant normal and keep the exported +Z depth axis.
func _kit_facing(name: String) -> Vector3:
	if kit_facing.has(name):
		return (kit_facing[name] as Vector3).normalized()
	return Vector3(0.0, 0.0, 1.0)


# Half-extent of the module's bounding box measured along `axis`, i.e. how far the
# rock reaches from its own origin in that direction.
func _kit_reach(name: String, axis: Vector3, scale_factor: float) -> float:
	var size: Vector3 = _kit_size(name) * scale_factor
	return 0.5 * (absf(axis.x) * size.x + absf(axis.y) * size.y + absf(axis.z) * size.z)


# -------------------------------------------------------------------- materials

func _build_materials() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.22),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	crystal_glow_texture = GradientTexture2D.new()
	crystal_glow_texture.gradient = gradient
	crystal_glow_texture.width = 128
	crystal_glow_texture.height = 128
	crystal_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	crystal_glow_texture.fill_from = Vector2(0.5, 0.5)
	crystal_glow_texture.fill_to = Vector2(0.5, 0.0)

	ground_shadow_material = StandardMaterial3D.new()
	ground_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_shadow_material.albedo_texture = crystal_glow_texture
	ground_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.20)
	ground_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_shadow_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	# Same family as the swept shell (same texture, same world triplanar scale,
	# same roughness) so a reused station rock cannot read as a foreign prop. The
	# small albedo lift compensates for the AO layer the reused meshes carry.
	rock_material = _rock_material(Color(1.18, 1.06, 0.92), 0.42)
	ceiling_rock_material = _rock_material(Color(1.10, 1.02, 0.93), 0.50)

	crystal_material = _crystal_material(Color("2b7d90"), Color("3ec2d4"), 0.16)
	crystal_violet_material = _crystal_material(Color("4a3a86"), Color("6f5dd2"), 0.15)
	crystal_glow_material = _crystal_material(Color("37a8bd"), Color("5fdcf0"), 0.42)


func _rock_material(tint: Color, normal_scale: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load("res://act23/assets/rocks/textures/rock_limestone_base.png") as Texture2D
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = load("res://act23/assets/rocks/textures/rock_limestone_normal.png") as Texture2D
	material.normal_scale = normal_scale
	material.roughness = 0.92
	material.metallic = 0.0
	material.rim_enabled = true
	material.rim = 0.14
	material.rim_tint = 0.30
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.38, 0.38, 0.38)
	return material


func _crystal_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.13
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	# Crystals are read by their facet highlights: a strong grazing rim plus a
	# tight specular lobe is what makes them look like mineral instead of glass.
	material.rim_enabled = true
	material.rim = 0.46
	material.rim_tint = 0.55
	material.metallic_specular = 0.90
	material.clearcoat_enabled = false
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# ------------------------------------------------------------------- placement

func _station_weight(s: float) -> float:
	return clampf(smoothstep(12.0, 2.0, s) + smoothstep(78.0, 90.0, s), 0.0, 1.0)


func _frame(s: float) -> Transform3D:
	return CART.route_pose(s)


# Exact point on the swept shell at a given height (wall) so a module is anchored
# to the rock it is supposed to grow out of, not to the floor-edge half width.
func _wall_point(s: float, up: float, side: float) -> Vector3:
	var lo: float = 0.0 if side < 0.0 else 0.5
	var hi: float = 0.5 if side < 0.0 else 1.0
	for _i: int in range(14):
		var mid: float = (lo + hi) * 0.5
		var rp: Vector2 = cave.call("ring_point", s, mid)
		if side < 0.0:
			if rp.y < up:
				lo = mid
			else:
				hi = mid
		else:
			if rp.y > up:
				hi = mid
			else:
				lo = mid
	var p: Vector2 = cave.call("ring_point", s, (lo + hi) * 0.5)
	return _frame(s) * Vector3(0.0, p.y, p.x)


# Exact point on the vault at a given lateral offset.
func _ceiling_point(s: float, lateral: float) -> Vector3:
	# A binary search assumed the ring's lateral coordinate is monotonic in t.
	# With the layered folds it is not: at lateral 2.4 the search could land on
	# the low wall foot, and a "ceiling" cap was anchored at y ~1 m, hanging
	# through the deck. Scan the vault half instead and keep the HIGHEST point
	# that is laterally close to the requested offset.
	var best: Vector2 = cave.call("ring_point", s, 0.5) as Vector2
	var best_score: float = -1.0
	var lo: float = 0.5 if lateral >= 0.0 else 0.0
	var hi: float = 1.0 if lateral >= 0.0 else 0.5
	for index: int in range(48):
		var t: float = lerpf(lo, hi, float(index) / 47.0)
		var p: Vector2 = cave.call("ring_point", s, t) as Vector2
		var error: float = absf(p.x - lateral)
		if error > 1.1:
			continue
		var score: float = p.y - error * 0.35
		if score > best_score:
			best_score = score
			best = p
	return _frame(s) * Vector3(0.0, best.y, best.x)


# Anchor a module on the wall. `protrude` is the fraction of the module's measured
# reach that stays inside the tunnel; the rest is buried in the wall so no module
# can read as a loose stone standing against a flat surface, and so an open wall
# shell cannot swallow the camera.
func _anchor(s: float, surface: Vector3, facing_local: Vector3, facing_parent: Vector3,
		protrude: float, module: String, scale_factor: float, material: Material,
		roll: float = 0.0, upright: bool = false, up_hint: float = 0.0) -> Node3D:
	var route: Basis = _frame(s).basis
	var local_facing: Vector3 = _kit_facing(module)
	var rotation: Basis
	if upright:
		# Crystal clusters must keep growing upward: only yaw them into the wall
		# normal and roll them inside the wall plane, never pitch them over.
		rotation = Basis(Vector3.UP, atan2(facing_parent.x, facing_parent.z)) \
			* Basis(Vector3(0.0, 0.0, 1.0), roll)
		local_facing = Vector3(0.0, 0.0, 1.0)
	else:
		rotation = Basis(Quaternion(local_facing, facing_parent.normalized()))
		rotation = rotation * Basis(local_facing, roll)
	var basis: Basis = route * rotation
	var reach: float = _kit_reach(module, local_facing, scale_factor)
	# Hard clearance budget: no wall rock may reach closer than this to the route
	# centreline, which is what keeps the deck, the player and the chase camera out
	# of the rock even if a module or a hand-tuned protrusion is oversized.
	if not upright:
		var limit: float = maxf(0.35, float(cave.call("half_width", s)) - 2.55)
		var wanted: float = reach * 2.0 * protrude
		if wanted > limit and reach > 0.001:
			protrude = limit / (2.0 * reach)
	var facing_world: Vector3 = route * facing_parent.normalized()
	var center: Vector3 = surface + facing_world * reach * (2.0 * protrude - 1.0)
	# Wall modules are buried by their BACK, not their visible face. A large
	# module with protrude 0.3 still reached ~1.7 m from the centreline with its
	# rear tip, straight into the deck. Push the whole module out so its inner
	# tip keeps the same 1.55 m clearance the hull contract promises.
	if absf(facing_parent.z) > 0.5:
		var lat_unit: Vector3 = route.z.normalized()
		var route_center: Vector3 = _frame(s) * Vector3(0.0, 0.0, 2.2)
		var inner: Vector3 = center - facing_world * reach
		var lat_inner: float = (inner - route_center).dot(lat_unit)
		var need: float = 1.55
		if lat_inner > 0.0 and lat_inner < need:
			center += lat_unit * (need - lat_inner)
		elif lat_inner < 0.0 and lat_inner > -need:
			center -= lat_unit * (need + lat_inner)
	if not upright and absf(facing_parent.z) > 0.5:
		var size: Vector3 = _kit_size(module) * scale_factor
		rock_marks.append({
			"s": s,
			"side": -signf(facing_parent.z),
			"up": up_hint,
			"along": 0.5 * sqrt(size.x * size.x + size.z * size.z) * 0.8,
			"height": size.y * 0.5,
			"visible": maxf(0.0, reach * 2.0 * protrude),
		})
	return _spawn(module, Transform3D(basis, center), scale_factor, material)


# How far the outermost rock at this spot already sticks out of the swept shell.
func _rock_clearance(s: float, side: float, up: float) -> float:
	var clearance: float = 0.0
	for mark: Dictionary in rock_marks:
		if not is_equal_approx(float(mark["side"]), side):
			continue
		if absf(float(mark["s"]) - s) > float(mark["along"]) + 1.1:
			continue
		if absf(float(mark["up"]) - up) > float(mark["height"]) + 1.2:
			continue
		clearance = maxf(clearance, float(mark["visible"]))
	return clearance


func _wall_anchor(s: float, side: float, up: float, protrude: float,
		module: String, scale_factor: float, material: Material,
		roll: float = 0.0, upright: bool = false, clearance: float = 0.0) -> Node3D:
	var surface: Vector3 = _wall_point(s, up, side) \
		+ _frame(s).basis * Vector3(0.0, 0.0, -side) * clearance
	return _anchor(s, surface, Vector3(0.0, 0.0, -side), Vector3(0.0, 0.0, -side),
		protrude, module, scale_factor, material, roll, upright, up)


# Anchor a module in the ceiling; its rock face looks down into the tunnel.
func _ceiling_anchor(s: float, lateral: float, up_offset: float, protrude: float,
		module: String, scale_factor: float, material: Material, roll: float = 0.0) -> Node3D:
	var surface: Vector3 = _ceiling_point(s, lateral) + _frame(s).basis * Vector3(0.0, up_offset, 0.0)
	return _anchor(s, surface, Vector3(0.0, -1.0, 0.0), Vector3(0.0, -1.0, 0.0),
		protrude, module, scale_factor, material, roll)


# Anchor a module on the floor; its rock face looks up into the tunnel.
func _floor_anchor(s: float, lateral: float, protrude: float, module: String,
		scale_factor: float, material: Material, roll: float = 0.0) -> Node3D:
	var surface: Vector3 = _frame(s) * Vector3(0.0, 0.0, lateral)
	return _anchor(s, surface, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0),
		protrude, module, scale_factor, material, roll)


func _spawn(module: String, at: Transform3D, scale_factor: float,
		material: Material) -> Node3D:
	if not kit_scenes.has(module):
		return null
	var packed: PackedScene = kit_scenes[module] as PackedScene
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		return null
	instance.transform = at
	instance.scale = Vector3.ONE * scale_factor
	add_child(instance)
	_apply_material(instance, material)
	_clear_of_cart_envelope(instance)
	rock_nodes += 1
	rock_instances.append(instance)
	return instance

# Final geometric guard: no authored module may overlap the volume the cart
# sweeps. Wall clearance was already enforced at the anchor, but large floor
# talus and end debris could still reach the deck with a rear corner. Modules
# whose bounding box crosses the hull envelope are pushed out to the nearer
# side; huge wall shells (which span the whole corridor in AABB but not in
# surface) are left alone.
func _clear_of_cart_envelope(instance: Node3D) -> void:
	var box: AABB = AABB()
	var has: bool = false
	for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var mb: AABB = mesh.global_transform * mesh.get_aabb()
		box = mb if not has else box.merge(mb)
		has = true
	if not has:
		return
	if box.size.z > 7.0 or box.size.y > 7.0:
		return
	var centre_s: float = clampf(box.get_center().x, 0.0, CART.LENGTH)
	var track_z: float = 2.2 + CART.bend(centre_s)
	var lat_min: float = box.position.z - track_z
	var lat_max: float = box.end.z - track_z
	var clear: float = 1.55
	var overlaps_height: bool = box.position.y < 3.25 and box.end.y > 0.60
	if not overlaps_height:
		return
	if lat_min < clear and lat_max > -clear:
		var push_positive: bool = absf(lat_min) <= absf(lat_max)
		if lat_min > 0.0 or lat_max < 0.0:
			push_positive = lat_min > 0.0
		if push_positive:
			instance.global_position.z += clear - lat_min
		else:
			instance.global_position.z -= clear + lat_max


func _apply_material(node: Node, material: Material) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.material_override = material
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			rock_triangles += _mesh_triangles(mesh_instance.mesh)
		_apply_material(child, material)


func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var key: String = mesh.resource_path
	if key != "" and _tri_cache.has(key):
		return int(_tri_cache[key])
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_INDEX:
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and (indices as PackedInt32Array).size() > 0:
			total += int(float((indices as PackedInt32Array).size()) / 3.0)
	if key != "":
		_tri_cache[key] = total
	return total


func _ground_shadow(world_at: Vector3, diameter: float) -> void:
	var shadow: MeshInstance3D = MeshInstance3D.new()
	shadow.name = "RockContactShadow"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	shadow.mesh = quad
	shadow.material_override = ground_shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(world_at.x, 0.045, world_at.z))
	add_child(shadow)


# ------------------------------------------------------------- wall relief layer

func _build_wall_relief() -> void:
	# Four big folded shells, two per side, alternating sides and never facing
	# themselves across the tunnel. They cover 6-8 m of wall each and their own
	# folds cross the swept shell's horizontal strata at a different angle, which
	# is what removes the "parallel painted stripes" read.
	var sites: Array[Dictionary] = [
		{"s": 13.5, "side": -1.0, "module": "schist_shell_b", "scale": 0.30, "up": 2.55, "protrude": 0.24},
		{"s": 31.0, "side": 1.0, "module": "schist_shell_a", "scale": 0.28, "up": 2.70, "protrude": 0.24},
		{"s": 49.5, "side": -1.0, "module": "schist_shell_c", "scale": 0.34, "up": 2.60, "protrude": 0.26},
		{"s": 68.0, "side": 1.0, "module": "schist_shell_b", "scale": 0.30, "up": 2.75, "protrude": 0.24},
	]
	for site: Dictionary in sites:
		var s: float = float(site["s"])
		var side: float = float(site["side"])
		_wall_anchor(s, side, float(site["up"]), float(site["protrude"]),
			str(site["module"]), float(site["scale"]), rock_material,
			rng.randf_range(-0.08, 0.08))


func _build_outcrops() -> void:
	# Broken rock masses on the wall foot and mid-wall. These replace the round
	# boulder kit entirely: every one of them is a cleaved, layered station rock,
	# buried at least a third of its depth, and supporting itself on the wall foot.
	var sites: Array[Dictionary] = [
		{"s": 7.2, "side": -1.0, "up": 1.25, "module": "thrust_a", "scale": 0.86, "protrude": 0.34},
		{"s": 16.0, "side": 1.0, "up": 1.10, "module": "knuckle_a", "scale": 0.92, "protrude": 0.32},
		{"s": 22.5, "side": -1.0, "up": 1.40, "module": "shelf_a", "scale": 0.98, "protrude": 0.30},
		{"s": 30.5, "side": 1.0, "up": 1.20, "module": "thrust_a", "scale": 0.82, "protrude": 0.36},
		{"s": 38.0, "side": -1.0, "up": 1.55, "module": "vault_slab_b", "scale": 0.94, "protrude": 0.34},
		{"s": 44.5, "side": 1.0, "up": 1.35, "module": "knuckle_a", "scale": 1.04, "protrude": 0.30},
		{"s": 52.0, "side": -1.0, "up": 1.30, "module": "shelf_a", "scale": 0.90, "protrude": 0.34},
		{"s": 59.5, "side": 1.0, "up": 1.45, "module": "thrust_a", "scale": 0.88, "protrude": 0.32},
		{"s": 66.5, "side": -1.0, "up": 1.20, "module": "vault_slab_a", "scale": 0.92, "protrude": 0.34},
		{"s": 73.5, "side": 1.0, "up": 1.35, "module": "knuckle_a", "scale": 0.96, "protrude": 0.32},
		{"s": 80.5, "side": -1.0, "up": 1.30, "module": "shelf_a", "scale": 1.00, "protrude": 0.30},
		{"s": 86.0, "side": 1.0, "up": 1.25, "module": "thrust_a", "scale": 0.94, "protrude": 0.32},
	]
	for i: int in range(sites.size()):
		var site: Dictionary = sites[i]
		var s: float = float(site["s"])
		var side: float = float(site["side"])
		var instance: Node3D = _wall_anchor(s, side, float(site["up"]), float(site["protrude"]),
			str(site["module"]), float(site["scale"]), rock_material,
			rng.randf_range(-0.12, 0.12))
		if instance != null:
			_ground_shadow(instance.transform.origin, 3.2)


func _build_ceiling() -> void:
	# The swept vault is deliberately quiet. These authored hanging masses give it
	# the geology the previous round was missing: folded shale slabs whose layers
	# run at an angle to the arch, cleaved return caps that drop 1-2 m, and broken
	# roof plates. Everything is buried at its top, so nothing floats; protrusion
	# is capped at 1.6 m so the cart, the player and the camera stay clear.
	var sites: Array[Dictionary] = [
		{"s": 6.0, "lat": -1.9, "module": "cap_a", "scale": 0.62, "protrude": 0.22, "up": 0.0},
		{"s": 17.5, "lat": 1.6, "module": "knuckle_a", "scale": 0.56, "protrude": 0.20, "up": 0.0},
		{"s": 26.0, "lat": -0.6, "module": "cap_a", "scale": 0.66, "protrude": 0.24, "up": 0.0},
		{"s": 34.5, "lat": 2.1, "module": "cap_a", "scale": 0.70, "protrude": 0.22, "up": 0.0},
		{"s": 41.0, "lat": -2.3, "module": "knuckle_a", "scale": 0.58, "protrude": 0.20, "up": 0.0},
		{"s": 47.5, "lat": 0.4, "module": "cap_a", "scale": 0.52, "protrude": 0.20, "up": 0.0},
		{"s": 55.0, "lat": 2.0, "module": "cap_a", "scale": 0.62, "protrude": 0.22, "up": 0.0},
		{"s": 63.0, "lat": -1.7, "module": "cap_a", "scale": 0.66, "protrude": 0.22, "up": 0.0},
		{"s": 71.0, "lat": 0.9, "module": "knuckle_a", "scale": 0.54, "protrude": 0.18, "up": 0.0},
		{"s": 78.0, "lat": -2.1, "module": "knuckle_a", "scale": 0.60, "protrude": 0.22, "up": 0.0},
		{"s": 85.0, "lat": 1.4, "module": "knuckle_a", "scale": 0.52, "protrude": 0.18, "up": 0.0},
		{"s": 10.5, "lat": 2.4, "module": "cap_a", "scale": 0.48, "protrude": 0.20, "up": 0.0},
		{"s": 22.0, "lat": -2.7, "module": "knuckle_a", "scale": 0.44, "protrude": 0.18, "up": 0.0},
		{"s": 38.5, "lat": 1.2, "module": "cap_a", "scale": 0.50, "protrude": 0.20, "up": 0.0},
		{"s": 59.0, "lat": 2.9, "module": "knuckle_a", "scale": 0.46, "protrude": 0.18, "up": 0.0},
		{"s": 74.5, "lat": -0.4, "module": "cap_a", "scale": 0.44, "protrude": 0.18, "up": 0.0},
	]
	for site: Dictionary in sites:
		_ceiling_anchor(float(site["s"]), float(site["lat"]), float(site["up"]),
			float(site["protrude"]), str(site["module"]), float(site["scale"]),
			ceiling_rock_material, rng.randf_range(-0.10, 0.10))


# ------------------------------------------------------------------ floor debris

func _build_debris() -> void:
	# Designed talus at the wall foot. Buried rather than resting on top of the
	# floor plane, so the wall/floor join reads as accumulated rock.
	var talus_s: float = 5.0
	var index: int = 0
	while talus_s <= 87.0:
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var module: String = DEBRIS_MODULES[index % 3]
		# Wall-foot talus: place it AT the foot, not a metre inside the line.
		# A 2.3x-scaled apron is ~5 m wide; at half_width-1.05 its rear tip
		# reached lateral 1.48 and clipped the deck.
		_floor_anchor(talus_s, side * (float(cave.call("half_width", talus_s)) - 0.65),
			rng.randf_range(0.40, 0.48), module, rng.randf_range(1.15, 1.65),
			rock_material, rng.randf_range(0.0, TAU))
		talus_s += 6.6
		index += 1
	# Small scattered fragments, deliberately sparse: a stone every 4 m reads as
	# noise, and the previous round's problem was quantity without geology.
	var placed: int = 0
	var guard: int = 0
	while placed < 16 and guard < 160:
		guard += 1
		var s: float = rng.randf_range(2.0, 88.0)
		if s < 9.0 or s > 82.0:
			if rng.randf() < 0.70:
				continue
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var dist: float = rng.randf_range(3.15, 4.30)
		if _station_weight(s) > 0.45:
			dist = rng.randf_range(4.4, 6.3)
		var module: String = DEBRIS_MODULES[rng.randi_range(0, 2)]
		_floor_anchor(s, side * dist, rng.randf_range(0.38, 0.46), module,
			rng.randf_range(0.55, 1.15), rock_material, rng.randf_range(0.0, TAU))
		placed += 1


# --------------------------------------------------------------------- crystals

func _build_crystals() -> void:
	# Route rhythm, not a uniform sprinkle:
	#   0-15 m   industrial rock, two small hints of mineral
	#   15-30 m  sparse veins growing out of fissures and rock roots
	#   30-60 m  the resonance bend: dense, with two hero chambers
	#   60-75 m  a held beat, fewer but larger
	#   75-90 m  final chamber that closes the chapter
	var sites: Array[Dictionary] = [
		# start: hints only
		{"s": 8.0, "side": -1.0, "up": 0.55, "scale": 0.72, "kind": "cyan", "hero": false},
		{"s": 12.5, "side": 1.0, "up": 0.75, "scale": 0.66, "kind": "cyan", "hero": false},
		# approach: veins on fissures and roots
		{"s": 17.5, "side": -1.0, "up": 1.35, "scale": 0.86, "kind": "cyan", "hero": false},
		{"s": 21.0, "side": 1.0, "up": 0.45, "scale": 0.78, "kind": "violet", "hero": false},
		{"s": 25.5, "side": -1.0, "up": 0.60, "scale": 0.94, "kind": "cyan", "hero": false},
		{"s": 28.5, "side": 1.0, "up": 1.55, "scale": 0.80, "kind": "glow", "hero": false},
		# resonance bend: the climax
		{"s": 33.0, "side": -1.0, "up": 0.50, "scale": 1.05, "kind": "cyan", "hero": false},
		{"s": 36.2, "side": 1.0, "up": 0.85, "scale": 1.10, "kind": "violet", "hero": false},
		{"s": 39.0, "side": -1.0, "up": 1.75, "scale": 1.55, "kind": "cyan", "hero": true},
		{"s": 41.5, "side": 1.0, "up": 0.42, "scale": 0.98, "kind": "cyan", "hero": false},
		{"s": 45.0, "side": -1.0, "up": 0.70, "scale": 1.02, "kind": "violet", "hero": false},
		{"s": 48.0, "side": 1.0, "up": 1.30, "scale": 0.92, "kind": "cyan", "hero": false},
		{"s": 51.5, "side": -1.0, "up": 0.38, "scale": 1.20, "kind": "glow", "hero": false},
		{"s": 53.2, "side": 1.0, "up": 1.90, "scale": 1.62, "kind": "cyan", "hero": true},
		{"s": 56.5, "side": -1.0, "up": 0.80, "scale": 1.00, "kind": "violet", "hero": false},
		# hold the beat
		{"s": 62.5, "side": 1.0, "up": 0.55, "scale": 0.90, "kind": "cyan", "hero": false},
		{"s": 67.5, "side": -1.0, "up": 1.20, "scale": 0.84, "kind": "cyan", "hero": false},
		{"s": 72.5, "side": 1.0, "up": 0.48, "scale": 0.96, "kind": "violet", "hero": false},
		# final chamber
		{"s": 78.5, "side": -1.0, "up": 0.70, "scale": 1.08, "kind": "cyan", "hero": false},
		{"s": 82.0, "side": 1.0, "up": 0.50, "scale": 1.18, "kind": "glow", "hero": false},
		{"s": 86.5, "side": -1.0, "up": 1.10, "scale": 1.24, "kind": "cyan", "hero": true},
	]
	for i: int in range(sites.size()):
		_place_crystal_site(sites[i] as Dictionary, i)

	# Long mineral veins seaming the fissures, at the fissure stations the wall
	# profile already has (17 / 45 / 71 m) plus one at the bend.
	var veins: Array[Dictionary] = [
		{"s": 18.0, "side": -1.0, "up": 2.30, "module": VEIN_CYAN, "scale": 0.42},
		{"s": 40.0, "side": 1.0, "up": 2.10, "module": VEIN_VIOLET, "scale": 0.46},
		{"s": 52.0, "side": -1.0, "up": 2.35, "module": VEIN_CYAN, "scale": 0.44},
		{"s": 72.0, "side": 1.0, "up": 2.20, "module": VEIN_CYAN, "scale": 0.40},
	]
	for vein: Dictionary in veins:
		var s: float = float(vein["s"])
		var side: float = float(vein["side"])
		var instance: Node3D = _wall_anchor(s, side, float(vein["up"]), 0.16,
			str(vein["module"]), float(vein["scale"]),
			crystal_material if str(vein["module"]) != VEIN_VIOLET else crystal_violet_material,
			rng.randf_range(-0.06, 0.06), false,
			_rock_clearance(s, side, float(vein["up"])))
		if instance != null:
			_mark_crystals(instance)
		_crystal_light(_frame(s) * Vector3(0.0, float(vein["up"]), side * 3.4), 0.9, 5.0)

	# A few clusters high on the corbel, so the upper wall is not the only quiet
	# band. They keep growing upward like every other cluster in the chapter.
	for i: int in range(6):
		var s: float = 18.0 + float(i) * 13.0
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var module: String = "crystal_cyan_b" if i % 2 == 0 else "crystal_violet_b"
		var node: Node3D = _wall_anchor(s, side, rng.randf_range(4.0, 4.9), 0.56, module,
			rng.randf_range(0.95, 1.45), crystal_material,
			rng.randf_range(-0.4, 0.4), true,
			_rock_clearance(s, side, 4.4))
		if node != null:
			_mark_crystals(node)
		_crystal_light(_wall_point(s, 4.2, side) + _frame(s).basis * Vector3(0.0, 0.0, -side * 0.7),
			0.55, 2.4)


func _place_crystal_site(site: Dictionary, index: int) -> void:
	var s: float = float(site["s"])
	var side: float = float(site["side"])
	var kind: String = str(site["kind"])
	var scale_factor: float = float(site["scale"])
	var up: float = float(site["up"])
	var hero: bool = bool(site["hero"])
	var module: String = CRYSTAL_CYAN[index % CRYSTAL_CYAN.size()]
	var material: StandardMaterial3D = crystal_material
	if kind == "violet":
		module = CRYSTAL_VIOLET[index % CRYSTAL_VIOLET.size()]
		material = crystal_violet_material
	elif kind == "glow":
		module = CRYSTAL_GLOW[0]
		material = crystal_glow_material

	# Rock socket: the cluster has to grow out of rock, so a small broken block is
	# buried at the same spot and the crystals are seated inside it. The socket and
	# the cluster are both pushed out to the outermost rock face, so a wall module
	# in front of the swept shell can never swallow them.
	var clearance: float = _rock_clearance(s, side, up)
	var socket_scale: float = clampf(scale_factor * 0.60, 0.55, 1.20)
	var socket_module: String = "lip_a" if index % 2 == 0 else "fissure_host_a"
	if hero or index % 3 != 1:
		_wall_anchor(s, side, up - 0.18, 0.30, socket_module, socket_scale, rock_material,
			rng.randf_range(-0.12, 0.12), true, clearance)

	var instance: Node3D = _wall_anchor(s, side, up, 0.62, module, scale_factor,
		material, rng.randf_range(-0.35, 0.35), true, clearance + 0.18 * socket_scale)
	if instance != null:
		_mark_crystals(instance)
	var light_at: Vector3 = (_frame(s) * Vector3(0.0, up + 0.55, side * 3.15))
	_crystal_light(light_at, scale_factor * (1.35 if hero else 0.85), 3.6 if hero else 2.6)
	if hero:
		_crystal_glow_sprite(light_at, 3.4 * scale_factor, 0.30)


func _mark_crystals(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			crystal_meshes.append(mesh_instance)
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mark_crystals(child)


func _crystal_light(at: Vector3, energy: float, range_m: float) -> void:
	# Lighting budget: Compatibility pays for every omni light across its whole
	# range, so the crystals share a small pool of real lights instead of one each.
	if crystal_lights.size() >= 6:
		return
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color("59dfe9").lerp(Color("8f7dff"), 0.12)
	light.light_energy = clampf(energy, 0.25, 1.9)
	light.omni_range = range_m
	light.omni_attenuation = 1.8
	light.position = at
	light.shadow_enabled = false
	add_child(light)
	crystal_lights.append(light)
	crystal_light_base.append(light.light_energy)


func _crystal_glow_sprite(at: Vector3, size: float, alpha: float) -> void:
	var glow: Sprite3D = Sprite3D.new()
	glow.name = "CrystalGlow"
	glow.texture = crystal_glow_texture
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	glow.modulate = Color(0.42, 0.95, 1.0, alpha)
	glow.pixel_size = size / 128.0
	glow.position = at
	glow.render_priority = 2
	add_child(glow)


# -------------------------------------------------------------- tunnel terminations

func _build_end_structure() -> void:
	# Both stops are closed by a collapsed face built from the same folded shells
	# as the walls, backed by a solid lit slab so no recess can read as clear colour.
	# The arrival end used to be authored at s = 102/105.8/107 for the old 90 m
	# chapter. After the route was extended to 106 m the cart's cab reaches
	# s ≈ 110.3 at the stop, so those rocks sat INSIDE the arriving vehicle and
	# the 5 m chase lens (11_arrived.png in the delivered build). Every arrival
	# landmark is now derived from CART.LENGTH with the cab's real nose clearance.
	var arrival_face: float = CART.LENGTH + 9.0
	for spec: Dictionary in [
			{"s": -13.0, "dir": 1.0, "module": "schist_shell_a", "scale": 0.50},
			{"s": arrival_face, "dir": -1.0, "module": "schist_shell_b", "scale": 0.52}]:
		var s_cap: float = float(spec["s"])
		var facing: Vector3 = Vector3(float(spec["dir"]), 0.0, 0.0)
		_anchor(s_cap, _frame(s_cap) * Vector3(0.0, 2.0, 0.0), facing, facing, 0.44,
			str(spec["module"]), float(spec["scale"]), rock_material,
			rng.randf_range(-0.05, 0.05))

	var back_material: StandardMaterial3D = rock_material.duplicate() as StandardMaterial3D
	back_material.vertex_color_use_as_albedo = false
	back_material.albedo_color = Color(0.52, 0.53, 0.55)
	back_material.uv1_scale = Vector3(0.30, 0.30, 0.30)
	for s: float in [-18.0, CART.LENGTH + 10.5]:
		var backing: MeshInstance3D = MeshInstance3D.new()
		backing.name = "EndCapBacking"
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.2, 13.0, 20.0)
		backing.mesh = box
		backing.material_override = back_material
		backing.transform = _frame(s) * Transform3D(Basis.IDENTITY, Vector3(0.0, 3.8, 0.0))
		add_child(backing)

	# Collapse choke in front of each face. The arrival chokes are pushed to the
	# wall sides (|lateral| = 3.2, outside the cart's 1.33 m hull) and past the
	# cab nose; one roof slab hangs high enough to clear the rider's head and the
	# chase camera. Nothing crosses the line the player has to drive or walk.
	var choke_sites: Array[Dictionary] = []
	for end_s: float in [-15.0, -17.6, -20.2]:
		choke_sites.append({"s": end_s, "lateral": [-2.4, 0.0, 2.4], "up": -1.0})
	for end_s: float in [CART.LENGTH + 3.0, CART.LENGTH + 5.0, CART.LENGTH + 7.0]:
		choke_sites.append({"s": end_s, "lateral": [-4.30, 4.30], "up": -1.0})
	# No free-floating central roof block: at s=112.5 the vault is ~9 m high, so
	# a rock at 4.55 m read as a boulder hovering in front of the end face
	# (11_arrived.png). The side chokes carry the collapse read.
	for site: Dictionary in choke_sites:
		var end_s: float = float(site["s"])
		var facing: Vector3 = Vector3(signf(-end_s + 45.5), 0.0, 0.0)
		for lateral: float in (site["lateral"] as Array):
			var height: float = rng.randf_range(0.2, 1.3) if float(site["up"]) < 0.0 else float(site["up"])
			_anchor(end_s, _frame(end_s) * Vector3(0.0, height, lateral),
				facing, facing, 0.44,
				DEBRIS_MODULES[int(absf(end_s) + lateral * 3.0) % 3],
				rng.randf_range(1.45, 1.95), rock_material, rng.randf_range(0.0, TAU))
	var cap_material: StandardMaterial3D = rock_material.duplicate() as StandardMaterial3D
	cap_material.vertex_color_use_as_albedo = false
	cap_material.albedo_color = Color(0.40, 0.42, 0.45)
	cap_material.uv1_scale = Vector3(0.30, 0.30, 0.30)
	cap_material.emission_enabled = true
	cap_material.emission = Color(0.04, 0.045, 0.05)
	cap_material.emission_energy_multiplier = 1.0
	for s_cap: float in [-22.6, CART.LENGTH + 11.5]:
		var cap_mesh: MeshInstance3D = MeshInstance3D.new()
		cap_mesh.name = "TunnelCap"
		var cap_box: BoxMesh = BoxMesh.new()
		cap_box.size = Vector3(0.8, 9.0, 9.0)
		cap_mesh.mesh = cap_box
		cap_mesh.material_override = cap_material
		cap_mesh.transform = _frame(s_cap) * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.8, 0.0))
		add_child(cap_mesh)
		# The visible cap is also the collider: same transform, same size, same
		# layer as the rest of the cave. Anything else would be an invisible wall
		# (or a hole) at the exact place the player walks up to and looks at.
		var cap_body: StaticBody3D = StaticBody3D.new()
		cap_body.name = "TunnelCapCollision"
		cap_body.collision_layer = 7
		cap_body.collision_mask = 0
		var cap_shape: BoxShape3D = BoxShape3D.new()
		cap_shape.size = cap_box.size
		var cap_collider: CollisionShape3D = CollisionShape3D.new()
		cap_collider.shape = cap_shape
		cap_body.add_child(cap_collider)
		cap_body.transform = cap_mesh.transform
		add_child(cap_body)
	for s_beacon: float in [-16.5, CART.LENGTH + 3.0]:
		var light_at: Vector3 = _frame(s_beacon) * Vector3(0.0, 3.0, 0.0)
		stage.call("_light", light_at, Color("8fd6e0"), 2.2, 10.0, false)
		var beacon: MeshInstance3D = MeshInstance3D.new()
		beacon.name = "EndBeacon"
		var beacon_mesh: SphereMesh = SphereMesh.new()
		beacon_mesh.radius = 0.10
		beacon_mesh.height = 0.20
		beacon_mesh.radial_segments = 10
		beacon_mesh.rings = 5
		beacon.mesh = beacon_mesh
		var beacon_mat: StandardMaterial3D = StandardMaterial3D.new()
		beacon_mat.albedo_color = Color("a8f2f6")
		beacon_mat.emission_enabled = true
		beacon_mat.emission = Color("8fe7ee")
		beacon_mat.emission_energy_multiplier = 1.6
		beacon.material_override = beacon_mat
		beacon.position = light_at
		add_child(beacon)


func _build_collision() -> void:
	# Cheap camera-visible collision ribbon. Visible rock is far more detailed than
	# the physics proxy; boxes along the route are enough, and they keep the new
	# wall relief from needing per-module collision.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "RockCaveCollision"
	body.collision_layer = 7
	body.collision_mask = 0
	add_child(body)
	var s: float = -START_EXTEND
	while s <= CART.LENGTH + END_EXTEND:
		for side: float in [-1.0, 1.0]:
			if side < 0.0:
				# The wide wall is real collision: its triangles are all outside the
				# 3.3 m envelope, so `_inside_envelope` keeps them and the modules
				# carry exact trimeshes. A proxy ribbon here buys nothing and only
				# adds an invisible lip in front of the drawn rock, so there is none.
				continue
			var pose: Transform3D = _frame(s)
			var width: float = _collision_distance(s, side)
			if side > 0.0:
				# Follow the winch-side working face cut back in cave_tunnel.
				width += float(cave.call("bay_south_extra", s))
			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = Vector3(2.55, 6.9, 0.50)
			var collider: CollisionShape3D = CollisionShape3D.new()
			collider.shape = shape
			# route_pose() already subtracts its own 2.2 m centre offset, so a box
			# that should sit `width` metres from the track centre has to be placed
			# at 2.2 + width. It used to be `side * width`, which silently pulled
			# the whole ribbon 2.2 m towards the line: invisible in the corridor,
			# fatal in the repair bay where the winch sits 3.4 m out.
			collider.transform = pose * Transform3D(Basis.IDENTITY, Vector3(2.2, 3.35, 2.2 + side * width))
			body.add_child(collider)
		s += 2.25
	# End plugs close the two ends of the corridor. They are derived from the cart
	# route: the old hard-coded 97.5 was 7.5 m past the old 90 m finish, and once
	# the line was extended it became an invisible wall across the middle of the
	# repaired section (the rider was scraped off the deck at 97.5 m).
	#
	# The arrival plug is NOT here any more: it stood at s=112.5, i.e. 5 m in
	# front of the visible TunnelCap at 117.5, and that is an invisible wall the
	# player can see straight through (air wall report, resonance 02+03). The cap
	# mesh carries an exact collider now (see _build_ends), so collision and
	# visible geometry are the same plane.
	#
	# The start plug stays, but at the first collapse-choke row (s = -14.4) rather
	# than at -9.0: behind it the floor narrows under 1 m and the low shell
	# triangles are dropped, so the corridor must stay closed - and now the
	# blocking plane sits inside visible rubble instead of open floor.
	var start_shape: BoxShape3D = BoxShape3D.new()
	start_shape.size = Vector3(1.0, 7.0, 7.5)
	var start_collider: CollisionShape3D = CollisionShape3D.new()
	start_collider.shape = start_shape
	start_collider.transform = _frame(-14.4) * Transform3D(Basis.IDENTITY, Vector3(0.0, 3.2, 0.0))
	body.add_child(start_collider)


# The old ribbon is a cheap proxy that sits ~5.7 m from the centreline at the
# stations and ~4.3 m in the gallery, while the visible authored rocks reach as
# close as `half_width - 2.55` (1.8-3.0 m). The player could therefore walk into
# a rock and the chase camera could fly through one - both were visible in the
# real playtest. Each module now gets its own static trimesh on layer 2+3
# (player + camera). It is the actual visible surface, not an AABB, so the
# corridor does not become narrower than it looks.
func _build_module_collision() -> void:
	for module: Node3D in rock_instances:
		if module == null or not is_instance_valid(module):
			continue
		var faces: PackedVector3Array = PackedVector3Array()
		for child: Node in module.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var local_faces: PackedVector3Array = mesh_instance.mesh.get_faces()
			if local_faces.is_empty():
				continue
			var xform: Transform3D = mesh_instance.global_transform
			for vertex: Vector3 in local_faces:
				faces.append(xform * vertex)
		if faces.size() < 9:
			continue
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "RockBody_" + str(module.name)
		body.collision_layer = 7
		body.collision_mask = 0
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		_rock_bodies += 1

func _collision_distance(s: float, side: float = 0.0) -> float:
	# Distance from the TRACK CENTRE, per side, because this cave is not
	# symmetric around the line: the cave ring is authored 2.2 m off the track, so
	# one wall is (half_width - 2.2) from the track and the other is
	# (half_width + 2.2).
	#
	# Two bugs lived here and both produced the reported "空气墙":
	#   1. a leftover `- 2.2` was applied to a value that is already measured from
	#      the track centre, so the clamp floor (1.55) took over for the whole
	#      gallery and the ribbon stood 1.30 m from the line, 0.5-1.7 m inside the
	#      drawn rock;
	#   2. one distance was used for both walls, so even without (1) the ribbon sat
	#      2.5 m inside the wide wall.
	# The ribbon is a backstop for the low shell triangles that
	# `_inside_envelope` drops, so it has to sit just INSIDE the surface the
	# player can see on each side: 12 cm in on the narrow wall, 5 cm on the wide.
	var half: float = float(cave.call("half_width", s))
	var station: float = _station_weight(s)
	var narrow: float = half - 2.2
	var wide: float = half + 2.2
	if side > 0.0:
		# +z is the narrow side (the winch bay was cut back into it later).
		return clampf(narrow - 0.12, 1.60, 5.20)
	if side < 0.0:
		# -z is the wide side; the low shell already has collision out here, the
		# ribbon only closes the seams between modules.
		return clampf(wide - 0.05, 4.20, 9.20)
	# Default (no side): the old symmetric answer, kept for callers that only want
	# a rough corridor width.
	return clampf(lerpf(COLLISION_WIDTH, 6.30, station), 3.40, half + 0.60)


func update_crystals(energy: float, color: Color) -> void:
	var clamped: float = clampf(energy, 0.0, 1.0)
	crystal_material.emission_energy_multiplier = 0.24 + 1.5 * clamped
	crystal_material.emission = Color("3fd0e2").lerp(color, clamped * 0.6)
	crystal_glow_material.emission_energy_multiplier = 0.58 + 2.1 * clamped
	crystal_glow_material.emission = Color("66e6f6").lerp(color, clamped * 0.7)
	crystal_violet_material.emission_energy_multiplier = 0.20 + 1.2 * clamped
	for i: int in range(crystal_lights.size()):
		crystal_lights[i].light_energy = crystal_light_base[i] * (1.0 + 0.35 * clamped)
	for mesh: MeshInstance3D in crystal_meshes:
		var pulse: float = 1.0 + 0.04 * clamped
		mesh.scale = Vector3.ONE * pulse
