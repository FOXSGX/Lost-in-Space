extends Node3D

var stage: Node3D
var source: Node3D
var rail_material: StandardMaterial3D
var dark: StandardMaterial3D
var amber: StandardMaterial3D
var cave: Node3D

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
	cave = preload("res://scripts/cave_tunnel.gd").new() as Node3D
	cave.name = "CaveShell"
	add_child(cave)
	cave.call("build", stage)
	var ballast: StandardMaterial3D = material(Color("8a7663"), 0.0)
	for index: int in range(121):
		var s: float = float(index) * 0.8
		var pose_at: Transform3D = preload("res://scripts/moving_cart.gd").route_pose(s)
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
	# The cave floor is real generated geometry now, so no flat slab is needed to
	# hide a missing surface. A thin collider keeps the player from catching on
	# individual floor triangles.
	ground(Vector3(44, -0.18, 4), Vector3(114, 0.3, 20))
	for s: float in [0.0, 90.0]:
		var dock: Node3D = Node3D.new()
		dock.transform = preload("res://scripts/moving_cart.gd").route_pose(s)
		add_child(dock)
		_build_stairs(dock)
		_build_landing(dock)
		_dock_sign(dock, s)
		ground(dock.to_global(Vector3(1, 0.20, -2.0)), Vector3(4.6, 0.44, 2.6))
	# Work lamps hang over the track. They are real props, but the shared static
	# shader is unshaded, so cave_tunnel bakes the same lamp positions into the
	# vertex irradiance. These lights only shape the cart, cargo and character.
	for s: float in [8.0, 24.0, 40.0, 56.0, 72.0, 88.0]:
		# Hanging lamps sit at 5.55 m, not 4.2 m: the third-person camera trails at
		# 4.6-5.1 m, and at 4.2 m it passed straight through the emissive lens,
		# which blew out a full-screen white plane (videos/frames_01_full_run,
		# frame 0392). Above the lens height they read as ceiling fixtures again.
		var at: Vector3 = Vector3(s, 5.55, 3.0 + preload("res://scripts/moving_cart.gd").bend(s))
		stage.call("_light", at, Color("f5b673"), 0.9, 10.0, false)
		_lamp_fixture(at)
	# The deck sits inside the open-topped cart shell, so the tunnel lights only
	# reach it from above. Without a local work light the cargo bay reads as a
	# black void even though the geometry is present.
	for s: float in [6.0, 30.0, 54.0, 78.0]:
		var at: Vector3 = Vector3(s, 3.9, 2.2 + preload("res://scripts/moving_cart.gd").bend(s))
		stage.call("_light", at, Color("ffd9a8"), 0.55, 7.5, false)

func _build_stairs(parent: Node3D) -> void:
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

func _dock_sign(parent: Node3D, s: float) -> void:
	var label: Label3D = Label3D.new()
	label.text = "01 · 登车口\nDOCK A" if s == 0.0 else "02 · 到站\nDOCK B"
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
