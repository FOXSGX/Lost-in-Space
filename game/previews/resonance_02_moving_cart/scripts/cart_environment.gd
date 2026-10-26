extends Node3D

var stage: Node3D
var source: Node3D
var rail_material: StandardMaterial3D
var dark: StandardMaterial3D
var amber: StandardMaterial3D

func build(controller: Node3D, imported: Node3D) -> void:
	stage = controller
	source = imported
	rail_material = material(Color("87999c"), 0.75)
	# Compatibility renderer has no reflection probe here, so a high metallic
	# value resolves to pure black. Keep these surfaces dielectric and lift the
	# base colour so the boarding landing and sleepers read as painted steel.
	dark = material(Color("4a5a5d"), 0.08)
	amber = material(Color("be863f"), 0.5)
	# Cropped derivative clears the actual swept corridor through approved cave
	# meshes, instead of letting the moving cart drive through old gallery caps.
	var tunnel: Node3D = (load("res://assets/moving_tunnel.scn") as PackedScene).instantiate() as Node3D
	stage.call("_adapt_materials", tunnel, {})
	add_child(tunnel)
	var ballast: StandardMaterial3D = material(Color("493e36"), 0.0)
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
	# Simple ground collision; moving vehicle never inherits the old cave trimesh.
	# The corridor crop removes the cave floor, so the walkable slab also needs a
	# visible surface — collision alone left a black void under the player.
	ground(Vector3(44, -0.18, 4), Vector3(114, 0.3, 20))
	var slab_material: StandardMaterial3D = material(Color("6b6259"), 0.0)
	slab_material.roughness = 0.92
	box(self, Vector3(114, 0.3, 20), slab_material, Vector3(44, -0.18, 4))
	for s: float in [0.0, 90.0]:
		var dock: Node3D = Node3D.new()
		dock.transform = preload("res://scripts/moving_cart.gd").route_pose(s)
		add_child(dock)
		for i: int in range(6):
			var at: Vector3 = Vector3(1, 0.5425 + float(i) * 0.2625, -0.66 + float(i) * 0.29)
			box(dock, Vector3(0.88, 0.22, 0.31), amber, at)
			var body: StaticBody3D = StaticBody3D.new()
			body.collision_layer = 2
			body.collision_mask = 0
			var shape: CollisionShape3D = CollisionShape3D.new()
			var box_shape: BoxShape3D = BoxShape3D.new()
			box_shape.size = Vector3(0.88, 0.22, 0.31)
			shape.shape = box_shape
			shape.position = at
			body.add_child(shape)
			dock.add_child(body)
		var landing: MeshInstance3D = box(dock, Vector3(4.4, 0.40, 2.5), dark, Vector3(1, 0.20, -2.0))
		landing.name = "DockLanding"
		ground(dock.to_global(Vector3(1, 0.20, -2.0)), Vector3(4.4, 0.40, 2.5))
		var label: Label3D = Label3D.new()
		label.text = "01 · 矿车登乘 / 终点回程" if s == 0 else "02 · 到站 / 沿黄色踏步下车"
		label.font = stage.get("ui_font") as Font
		label.font_size = 42
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(1, 3.3, -1.8)
		dock.add_child(label)
	for s: float in [8, 24, 40, 56, 72, 88]:
		var at: Vector3 = Vector3(s, 4.2, 3.0 + preload("res://scripts/moving_cart.gd").bend(s))
		stage.call("_light", at, Color("f5b673"), 0.9, 10.0, false)
	# The deck sits inside the open-topped cart shell, so the tunnel lights only
	# reach it from above. Without a local work light the cargo bay reads as a
	# black void even though the geometry is present.
	for s: float in [6.0, 30.0, 54.0, 78.0]:
		var at: Vector3 = Vector3(s, 3.9, 2.2 + preload("res://scripts/moving_cart.gd").bend(s))
		stage.call("_light", at, Color("ffd9a8"), 0.55, 7.5, false)

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
