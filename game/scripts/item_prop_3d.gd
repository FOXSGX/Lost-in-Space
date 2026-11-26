extends Node3D
class_name ItemProp3D

## 《迷失太空》精细化 3D 物品表现（全面接入 Blender 4.5 英雄 GLB + ArtPbrLib 2K PBR）
const CASE: PackedScene = preload("res://assets/ship-hub/kenney/space-station/container.glb")
const WIDE_CASE: PackedScene = preload("res://assets/ship-hub/kenney/space-station/container-wide.glb")

const HERO_MODELS: Dictionary = {
	"oxygen": preload("res://assets/models/rebuild/hero_oxygen_bottle.glb"),
	"medical": preload("res://assets/models/rebuild/hero_medkit.glb"),
	"battery": preload("res://assets/models/rebuild/hero_battery_pack.glb"),
	"cell": preload("res://assets/models/rebuild/hero_battery_pack.glb"),
	"fuel": preload("res://assets/models/rebuild/hero_battery_pack.glb"),
	"sample": preload("res://assets/models/rebuild/hero_sample_crystal.glb"),
	"heater": preload("res://assets/models/rebuild/hero_heat_lance.glb"),
	"suction": preload("res://assets/models/rebuild/hero_suction_gun.glb"),
	"chips": preload("res://assets/models/rebuild/hero_snack_pack.glb"),
	"keepsake": preload("res://assets/models/rebuild/hero_keepsake_mug.glb"),
	"crate": preload("res://assets/models/rebuild/hero_cargo_crate.glb"),
	"bounce_pad": preload("res://assets/models/rebuild/hero_bounce_pad.glb"),
	"flare": preload("res://assets/models/rebuild/hero_flare_stick.glb"),
	"boombox": preload("res://assets/models/rebuild/hero_boombox.glb"),
	"bumper_orb": preload("res://assets/models/rebuild/hero_bumper_orb.glb"),
	"thermos": preload("res://assets/models/rebuild/hero_thermos.glb"),
}

const HERO_SCALE: Dictionary = {
	"oxygen": 0.92,
	"medical": 1.05,
	"battery": 1.05,
	"cell": 0.92,
	"fuel": 1.0,
	"sample": 1.10,
	"heater": 1.02,
	"suction": 1.02,
	"chips": 1.15,
	"keepsake": 1.15,
	"crate": 0.72,
	"bounce_pad": 0.56,
	"flare": 1.0,
	"boombox": 0.95,
	"bumper_orb": 0.95,
	"thermos": 1.05,
}

const COLORS: Dictionary = {
	"medical": "#ed777a", "oxygen": "#77d7f3", "battery": "#79edce", "sample": "#b49cff",
	"penguin": "#8de9ff", "bubble": "#c5a4ff", "board": "#ffd36e", "hologram": "#ff9bd7", "smoke": "#ff7fd1",
	"bounce_pad": "#ff9642", "flare": "#ff5d47", "boombox": "#58e0f0", "bumper_orb": "#78f0ff", "thermos": "#f0a24a",
}

static var _filtered_materials: Dictionary = {}
static var _shared_pbr: ArtPbrLib = null

static func create(kind: String) -> ItemProp3D:
	var prop: ItemProp3D = ItemProp3D.new()
	prop.name = "Item_" + kind
	prop._build(kind)
	return prop

static func _pbr() -> ArtPbrLib:
	if _shared_pbr == null:
		_shared_pbr = ArtPbrLib.new()
	return _shared_pbr

func _build(kind: String) -> void:
	if HERO_MODELS.has(kind):
		var scene: PackedScene = HERO_MODELS[kind] as PackedScene
		var inst: Node3D = scene.instantiate() as Node3D
		var sc: float = float(HERO_SCALE.get(kind, 1.0))
		inst.scale = Vector3.ONE * sc
		_pbr().bind_glb(inst, "ship", true)
		for child: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		return

	var color: Color = Color(COLORS.get(kind, "#ffc779"))
	_native(WIDE_CASE if kind == "battery" else CASE, Vector3(0.42, 0.38, 0.3))
	_detail(Vector3(0, 0.24, 0.155), Vector3(0.28, 0.2, 0.025), color)
	if ShipSession3D.GEAR_ITEMS.has(kind):
		var badge: MeshInstance3D = MeshInstance3D.new()
		var face: QuadMesh = QuadMesh.new()
		face.size = Vector2(0.29, 0.27)
		badge.mesh = face
		badge.position = Vector3(0, 0.24, 0.176)
		var picture: StandardMaterial3D = _material(Color.WHITE)
		picture.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		picture.albedo_texture = CrewItems3D.ICONS[kind] as Texture2D
		badge.material_override = picture
		add_child(badge)

func _native(scene: PackedScene, target: Vector3) -> void:
	var model: Node3D = scene.instantiate() as Node3D
	var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
	var fit: Vector3 = target / bounds.size
	var wrapper: Node3D = Node3D.new()
	wrapper.scale = fit
	wrapper.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
	add_child(wrapper)
	wrapper.add_child(model)
	linear_materials(model)
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func linear_materials(model: Node3D) -> void:
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = child as MeshInstance3D
		for surface: int in instance.mesh.get_surface_count():
			var source: StandardMaterial3D = instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var key: int = source.get_instance_id()
			if not _filtered_materials.has(key):
				var filtered: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				filtered.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
				_filtered_materials[key] = filtered
			instance.set_surface_override_material(surface, _filtered_materials[key])

static func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var here: Transform3D = parent_transform * node.transform
	var result: AABB = here * (node as MeshInstance3D).get_aabb() if node is MeshInstance3D else AABB()
	for child: Node in node.get_children():
		if child is Node3D:
			var next: AABB = _bounds(child as Node3D, here)
			if next.size.length_squared() > 0.0:
				result = result.merge(next) if result.size.length_squared() > 0.0 else next
	return result

func _detail(point: Vector3, size: Vector3, color: Color) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = point
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	return material
