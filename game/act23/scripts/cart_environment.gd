extends Node3D

const Cart := preload("res://act23/scripts/moving_cart.gd")
# The repair yard builds its own track from 86.6 m to 99.4 m (approach stub,
# swing section, receiver). Leaving this range to the yard keeps the gauge and
# the rail height identical instead of stacking two track meshes in one place.
const YARD_TRACK_START: float = 86.40
const YARD_TRACK_END: float = 99.60

var stage: Node3D
var source: Node3D
var rail_material: StandardMaterial3D
var dark: StandardMaterial3D
var amber: StandardMaterial3D
var cave: Node3D
var rock_cave: Node3D
var glow_texture: GradientTexture2D

func build(controller: Node3D, imported: Node3D) -> void:
	stage = controller
	source = imported
	rail_material = material(Color("9aa9ab"), 0.55)
	# Compatibility renderer has no reflection probe here, so a high metallic
	# value resolves to pure black. Keep these surfaces dielectric and lift the
	# base colour so the boarding landing and sleepers read as painted steel.
	dark = material(Color("5d6d70"), 0.08)
	amber = material(Color("be863f"), 0.5)
	# The old approach cropped a 43 m straight diorama into a 90 m bent corridor.
	# That crop deleted the cave floor and ceiling and left the cut edges open, so
	# the player looked straight into the background colour. The corridor is now
	# generated as one closed shell that follows the real route.
	cave = preload("res://act23/scripts/cave_tunnel.gd").new() as Node3D
	cave.name = "CaveShell"
	add_child(cave)
	cave.call("build", stage)
	_make_glow_texture()
	# Authored 3D rock kit covers the old swept tube. The shell remains as a dark
	# backing/collision volume so no seam can ever reveal the clear colour.
	rock_cave = preload("res://act23/scripts/rock_cave.gd").new() as Node3D
	rock_cave.name = "RockCave"
	add_child(rock_cave)
	rock_cave.call("build", stage, cave)
	var ballast: StandardMaterial3D = material(Color("8a7663"), 0.0)
	var index: int = 0
	var cursor: float = 0.0
	while cursor <= 105.8:
		if cursor < YARD_TRACK_START or cursor > YARD_TRACK_END:
			var pose_at: Transform3D = Cart.route_pose(cursor)
			var bed: MeshInstance3D = box(self, Vector3(0.84,0.10,4.3),ballast,Vector3.ZERO)
			bed.transform = pose_at.translated_local(Vector3(0,0.01,2.2))
			var sleeper: MeshInstance3D = box(self, Vector3(0.18, 0.13, 3.3), dark, Vector3.ZERO)
			sleeper.transform = pose_at.translated_local(Vector3(0, 0.14, 2.2))
			for z: float in [1.03, 3.37]:
				var rail: MeshInstance3D = box(self, Vector3(0.84, 0.07, 0.12), rail_material, Vector3.ZERO)
				rail.transform = pose_at.translated_local(Vector3(0, 0.275, z))
				if index % 3 == 0:
					var clamp_mesh: MeshInstance3D = box(self, Vector3(0.13, 0.16, 0.28), amber, Vector3.ZERO)
					clamp_mesh.transform = pose_at.translated_local(Vector3(0, 0.13, z))
		index += 1
		cursor += 0.8
	# The cave floor is real generated geometry now, so no flat slab is needed to
	# hide a missing surface. A thin collider keeps the player from catching on
	# individual floor triangles. It now reaches the crystal-mine dock at 106 m.
	ground(Vector3(50, -0.18, 4), Vector3(126, 0.3, 24))
	for s: float in [0.0, 88.0, 106.0]:
		var dock: Node3D = Node3D.new()
		dock.transform = Cart.route_pose(s)
		add_child(dock)
		_build_stairs(dock, not (s > 87.0 and s < 89.0))
		_build_landing(dock)
		_dock_sign(dock, s)
		ground(dock.to_global(Vector3(1, 0.20, -2.0)), Vector3(4.6, 0.44, 2.6))
		ground(dock.to_global(Vector3(3.66, 0.105, -2.0)), Vector3(0.74, 0.21, 2.40))
		if s > 87.0 and s < 89.0:
			_egress_ramp(dock)
	# Work lamps hang over the track. They are real props, but the shared static
	# shader is unshaded, so cave_tunnel bakes the same lamp positions into the
	# vertex irradiance. These lights only shape the cart, cargo and character.
	for s: float in [4.0, 12.0, 20.0, 28.0, 36.0, 44.0, 52.0, 60.0, 68.0, 76.0, 84.0, 92.0, 100.0, 104.0]:
		# Hanging work lamps. Shadowless omnis keep the long tunnel readable;
		# the authored geometry, baked vertex AO and normal maps carry the form.
		var at: Vector3 = Vector3(s, 5.55, 2.2 + Cart.bend(s))
		stage.call("_light", at, Color("ffd0a0"), 8.0, 15.0, false)
		_lamp_fixture(at)
		_glow(at + Vector3(0.0, -0.08, 0.0), Color(1.0, 0.72, 0.42), 3.0, 0.34)
	# Broad station pools lift the boarding / arrival platforms out of the tunnel
	# dark without flattening the whole corridor.
	for s: float in [0.0, 88.0, 106.0]:
		var at: Vector3 = Vector3(s, 4.2, 2.2 + Cart.bend(s))
		stage.call("_light", at, Color("ffd2a6"), 3.4, 14.0, false)
		stage.call("_light", at + Vector3(0.0, 1.5, 3.3), Color("8fdde6"), 0.9, 7.0, false)
		_glow(at + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.78, 0.52), 5.0, 0.24)
	# Cool pit fill between the warm lamps keeps deep rock from crushing to black.
	for s: float in [12.0, 32.0, 52.0, 72.0, 92.0, 104.0]:
		var at: Vector3 = Vector3(s, 3.2, 2.2 + Cart.bend(s))
		stage.call("_light", at, Color("7fa8d4"), 1.05, 10.5, false)
	# Warm wall washes on the side away from the lamp mast break the left/right
	# warm-vs-blue split that otherwise reads as two different rock materials.
	for s: float in [15.0, 39.0, 63.0, 87.0]:
		var at: Vector3 = Vector3(s, 4.0, 2.2 + Cart.bend(s) + 3.55)
		stage.call("_light", at, Color("ffb878"), 2.6, 8.0, false)
	# The deck sits inside the open-topped cart shell, so the tunnel lights only
	# reach it from above. Without a local work light the cargo bay reads as a
	# black void even though the geometry is present.
	for s: float in [6.0, 30.0, 54.0, 78.0]:
		var at: Vector3 = Vector3(s, 3.9, 2.2 + Cart.bend(s))
		stage.call("_light", at, Color("ffd9a8"), 2.05, 8.5, false)
	# Three heavy gantries give the natural rock a believable industrial scale
	# and break the 90 m run into readable chambers.
	for s: float in [16.0, 46.0, 76.0]:
		_build_gantry(s)

func _build_gantry(s: float) -> void:
	var pose_at: Transform3D = preload("res://act23/scripts/moving_cart.gd").route_pose(s)
	var steel: StandardMaterial3D = material(Color("3f4b50"), 0.0)
	steel.roughness = 0.62
	var safety: StandardMaterial3D = material(Color("c98a3f"), 0.0)
	safety.roughness = 0.55
	for side: float in [-1.0, 1.0]:
		var post: MeshInstance3D = box(self, Vector3(0.30, 5.70, 0.36), steel, Vector3.ZERO)
		post.transform = pose_at * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.85, side * 4.10))
		var foot: MeshInstance3D = box(self, Vector3(0.72, 0.34, 0.82), steel, Vector3.ZERO)
		foot.transform = pose_at * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.17, side * 4.10))
		var stripe: MeshInstance3D = box(self, Vector3(0.34, 0.55, 0.40), safety, Vector3.ZERO)
		stripe.transform = pose_at * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.52, side * 4.10))
		var brace: MeshInstance3D = box(self, Vector3(0.17, 1.75, 0.17), steel, Vector3.ZERO)
		brace.transform = pose_at * Transform3D(
			Basis(Vector3.RIGHT, side * 0.68), Vector3(0.0, 5.02, side * 3.20))
	var beam: MeshInstance3D = box(self, Vector3(0.36, 0.48, 8.65), steel, Vector3.ZERO)
	beam.transform = pose_at * Transform3D(Basis.IDENTITY, Vector3(0.0, 5.78, 0.0))
	var beam_hi: MeshInstance3D = box(self, Vector3(0.39, 0.08, 8.50), safety, Vector3.ZERO)
	beam_hi.transform = pose_at * Transform3D(Basis.IDENTITY, Vector3(0.0, 5.54, 0.0))
	var lamp_at: Vector3 = pose_at * Vector3(0.0, 5.48, 0.0)
	stage.call("_light", lamp_at, Color("8fe3ea"), 1.0, 6.0, false)

func _make_glow_texture() -> void:
	# Compatibility has no bloom, so a soft additive-look sprite supplies the
	# warm/cool halo around practical lights without changing the renderer.
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0, 0.32),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	glow_texture = GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.width = 128
	glow_texture.height = 128
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)

func _glow(at: Vector3, color: Color, diameter: float, alpha: float) -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = "LampGlow"
	sprite.texture = glow_texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.modulate = Color(color.r, color.g, color.b, alpha)
	sprite.pixel_size = diameter / 128.0
	sprite.position = at
	sprite.render_priority = 2
	add_child(sprite)

func _build_stairs(parent: Node3D, with_collision: bool = true) -> void:
	# Solid stepped blocks, not six floating slabs. Each block reaches the floor,
	# so a ray never passes between the old 0.03 m gaps and the silhouette reads
	# Step tops must still reach the cart deck (local y 1.91) from the landing
	# (local y 0.40). A first version used 0.22 m steps and topped out 0.6 m below
	# the deck, which broke boarding; these keep the original final height.
	var landing_top: float = 0.40
	var deck_top: float = 1.91
	var step_count: int = 6
	var step_d: float = 0.30
	for i: int in range(step_count):
		var height: float = landing_top + (deck_top - landing_top) * float(i + 1) / float(step_count)
		var at: Vector3 = Vector3(1.0, height * 0.5, -0.66 + step_d * float(i))
		var size: Vector3 = Vector3(0.90, height, step_d)
		box(parent, size, amber, at)
		if not with_collision:
			continue
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = at
		body.add_child(shape)
		parent.add_child(body)
	# Handrail on the outboard side of the stairs.
	for i: int in [0, 2, 4]:
		var top: float = landing_top + (deck_top - landing_top) * float(i + 1) / float(step_count) + 0.52
		box(parent, Vector3(0.05, 0.62, 0.05), rail_material,
			Vector3(1.47, top - 0.31, -0.66 + step_d * float(i)))
	box(parent, Vector3(0.05, 0.05, 1.55), rail_material, Vector3(1.47, 1.62, -0.06))
	box(parent, Vector3(0.05, 0.05, 1.55), rail_material, Vector3(1.47, 0.91, -0.06))

# The s = 88 service stop is the chapter's only on-foot way out of the cart. Its
# six steps have 0.30 m treads and 0.25 m risers, i.e. both are narrower than the
# 0.76 m character capsule. Descending therefore always drives the rear of the
# capsule into the riser of the step above, and a capsule that comes to rest on a
# step corner can lock there: the 4-player acceptance runs measured zero
# displacement for 4 s while holding W, with the body at y = 1.097 (not on the
# deck, not in the yard, and with no teammate within 1 m). This collision-only
# ramp spans the same 0.9 m lane from the landing lip (local y 0.40 at z -0.81)
# to the top step (y 1.91 at z 0.99). At this one dock the six step colliders are
# skipped (_build_stairs(dock, false)) so the chord is the only surface; the step
# meshes, the other two docks and every authored mesh stay exactly as they are.
func _egress_ramp(dock: Node3D) -> void:
	var rise: float = 1.51
	var run: float = 1.80
	var length: float = sqrt(rise * rise + run * run)
	var slope: float = atan2(rise, run)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "EgressRamp"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.90, 0.10, length)
	shape.shape = box
	# A box rotated about +X tilts +Z downwards, so the rise (towards +z) needs
	# the negative angle. The 0.05 m half-thickness is taken out of the centre so
	# the walkable face sits on the ideal line.
	shape.transform = Transform3D(Basis(Vector3.RIGHT, -slope),
		Vector3(1.0, (0.40 + 1.91) * 0.5 - 0.05 * cos(slope), (-0.81 + 0.99) * 0.5))
	body.add_child(shape)
	dock.add_child(body)

func _build_landing(parent: Node3D) -> void:
	# The boarding landing used to be a single 4.4 x 0.40 x 2.5 dark box: a flat
	# untextured slab that read as a black hole under the player. It is now a
	# framed platform (base, four deck plates, amber trim, hazard stripes, bolts,
	# legs) so its scale and construction are legible from the player camera.

	var base: MeshInstance3D = box(parent, Vector3(4.6, 0.38, 2.6), dark, Vector3(1.0, 0.19, -2.0))
	base.name = "DockLanding"
	var plate_a: StandardMaterial3D = material(Color("5a6b6e"), 0.04)
	var plate_b: StandardMaterial3D = material(Color("4a595c"), 0.04)
	for i: int in range(4):
		var plate: StandardMaterial3D = plate_a if i % 2 == 0 else plate_b
		box(parent, Vector3(1.08, 0.045, 2.42), plate,
			Vector3(1.0 - 1.73 + 1.15 * float(i), 0.40, -2.0))
	# Amber kerb around the perimeter.
	for z: float in [-0.72, -3.28]:
		box(parent, Vector3(4.62, 0.055, 0.10), amber, Vector3(1.0, 0.41, z))
	for x: float in [-1.28, 3.28]:
		box(parent, Vector3(0.10, 0.055, 2.42), amber, Vector3(x, 0.41, -2.0))
	# Hazard stripes on the edge the player steps over.
	for k: int in range(10):
		var stripe: StandardMaterial3D = amber if k % 2 == 0 else dark
		box(parent, Vector3(0.34, 0.02, 0.20), stripe,
			Vector3(-1.06 + 0.46 * float(k), 0.425, -0.92))
	# Corner and edge bolts.
	for x: float in [-1.12, 1.0, 3.12]:
		for z: float in [-1.0, -3.0]:
			var bolt: MeshInstance3D = MeshInstance3D.new()
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = 0.045
			mesh.bottom_radius = 0.045
			mesh.height = 0.03
			mesh.radial_segments = 8
			bolt.mesh = mesh
			bolt.material_override = rail_material
			bolt.position = Vector3(x, 0.43, z)
			parent.add_child(bolt)
	# Support legs so the platform is not a floating slab.
	for x: float in [-1.18, 3.18]:
		for z: float in [-0.95, -3.05]:
			box(parent, Vector3(0.16, 0.40, 0.16), dark, Vector3(x, 0.12, z))
	# Boarding step on the outboard edge. The landing deck is 0.42 m high, just
	# above the character's 0.36 m step assist, so a player who walked around the
	# outside of the dock could not get back onto it. One 0.21 m step splits the
	# rise into two climbable halves.
	box(parent, Vector3(0.74, 0.21, 2.40), plate_a, Vector3(3.66, 0.105, -2.0))
	box(parent, Vector3(0.80, 0.05, 2.44), amber, Vector3(3.66, 0.215, -2.0))
	for z: float in [-0.95, -3.05]:
		box(parent, Vector3(0.14, 0.21, 0.14), dark, Vector3(3.66, 0.105, z))

func _dock_sign(parent: Node3D, s: float) -> void:
	var label: Label3D = Label3D.new()
	if s < 1.0:
		label.text = "01 · 登车口\nDOCK A"
	elif s < 95.0:
		label.text = "02 · 维修停车\nSERVICE STOP"
	else:
		label.text = "03 · 晶体矿区入口\nCRYSTAL GATE"
	label.font = stage.get("ui_font") as Font
	label.font_size = 24
	label.pixel_size = 0.0019
	label.outline_size = 4
	label.modulate = Color("a9d8de")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(2.9, 1.15, -1.05)
	parent.add_child(label)

func _lamp_fixture(at: Vector3) -> void:
	# A bare light with nothing above it reads as a floating glow. Hang each lamp
	# from the cave roof on a visible stem with a housing.
	var housing: StandardMaterial3D = material(Color("2f3a3f"), 0.0)
	housing.roughness = 0.6
	var lens: StandardMaterial3D = material(Color("ffd9a8"), 0.0, 0.9)
	var anchor_y: float = 6.55
	var stem_length: float = maxf(0.35, anchor_y - at.y)
	box(self, Vector3(0.045, stem_length, 0.045), housing, Vector3(at.x, at.y + stem_length * 0.5, at.z))
	box(self, Vector3(0.62, 0.10, 0.34), housing, at + Vector3(0, 0.10, 0))
	box(self, Vector3(0.50, 0.035, 0.26), lens, at + Vector3(0, 0.04, 0))

func ground(at: Vector3, dimensions: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 6
	body.collision_mask = 0
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	body.position = at
	body.add_child(collider)
	add_child(body)

static func material(color: Color, metal: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = 0.55
	result.emission_enabled = emission > 0.0
	result.emission = color
	result.emission_energy_multiplier = emission
	return result

static func box(parent: Node3D, dimensions: Vector3, mat: Material, at: Vector3) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	result.mesh = mesh
	result.material_override = mat
	result.position = at
	parent.add_child(result)
	return result
