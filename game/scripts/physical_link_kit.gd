extends RefCounted
class_name HubPhysicalLinkKit

## 物理因果连线套件（零悬浮文字：用贴地/贴墙装甲导管 + 遮光状态灯表达状态与路径）

const CONDUIT_SHADER: Shader = preload("res://shaders/hub_conduit_flow.gdshader")

## 沿多段路径铺设贴地装甲能量导管（带金属卡箍法兰，返回 ShaderMaterial 供实时切换通电状态）
static func build_conduit_path(parent: Node3D, points: Array[Vector3], radius: float = 0.085, flow_color: Color = Color("#28dbff")) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = CONDUIT_SHADER
	mat.set_shader_parameter("flow_color", flow_color)
	mat.set_shader_parameter("active_state", 0.0)
	mat.set_shader_parameter("ready_state", 0.35)

	var flange_mat: StandardMaterial3D = StandardMaterial3D.new()
	flange_mat.albedo_color = Color("#232d36")
	flange_mat.metallic = 0.65
	flange_mat.roughness = 0.42

	var holder: Node3D = Node3D.new()
	holder.name = "ArmoredConduit"
	parent.add_child(holder)

	for i: int in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var diff: Vector3 = b - a
		var length: float = diff.length()
		if length < 0.05:
			continue
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = length
		cyl.radial_segments = 8
		var seg: MeshInstance3D = MeshInstance3D.new()
		seg.mesh = cyl
		seg.material_override = mat
		seg.position = (a + b) * 0.5
		seg.quaternion = Quaternion(Vector3.UP, diff.normalized())
		holder.add_child(seg)

		# 端头与中段加固法兰卡箍
		var steps: int = maxi(1, int(length / 4.5))
		for s: int in range(steps + 1):
			var t: float = float(s) / float(steps)
			var ring: CylinderMesh = CylinderMesh.new()
			ring.top_radius = radius * 1.42
			ring.bottom_radius = radius * 1.42
			ring.height = 0.14
			ring.radial_segments = 8
			var fl: MeshInstance3D = MeshInstance3D.new()
			fl.mesh = ring
			fl.material_override = flange_mat
			fl.position = a.lerp(b, t)
			fl.quaternion = seg.quaternion
			holder.add_child(fl)
	return mat

## 遮光实体状态灯（锁定=告警红 / 就绪=琥珀 / 激活=青绿，严控柔和发光）
static func build_status_lamp(parent: Node3D, pos: Vector3) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "StatusLamp"
	root.position = pos
	parent.add_child(root)

	var hood_mesh: CylinderMesh = CylinderMesh.new()
	hood_mesh.top_radius = 0.16
	hood_mesh.bottom_radius = 0.20
	hood_mesh.height = 0.12
	hood_mesh.radial_segments = 10
	var hood_mat: StandardMaterial3D = StandardMaterial3D.new()
	hood_mat.albedo_color = Color("#242f38")
	hood_mat.metallic = 0.6
	hood_mat.roughness = 0.45
	var hood: MeshInstance3D = MeshInstance3D.new()
	hood.mesh = hood_mesh
	hood.material_override = hood_mat
	hood.position.y = 0.08
	root.add_child(hood)

	var bulb_mesh: SphereMesh = SphereMesh.new()
	bulb_mesh.radius = 0.11
	bulb_mesh.height = 0.22
	bulb_mesh.radial_segments = 10
	bulb_mesh.rings = 6
	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color("#ff3b24")
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color("#ff3b24")
	bulb_mat.emission_energy_multiplier = 1.4
	var bulb: MeshInstance3D = MeshInstance3D.new()
	bulb.mesh = bulb_mesh
	bulb.material_override = bulb_mat
	root.add_child(bulb)

	var omni: OmniLight3D = OmniLight3D.new()
	omni.light_color = Color("#ff4c32")
	omni.light_energy = 0.95
	omni.omni_range = 4.5
	omni.shadow_enabled = false
	root.add_child(omni)
	return {"root": root, "mat": bulb_mat, "light": omni}

static func set_lamp_state(lamp: Dictionary, state: String) -> void:
	var c: Color = Color("#ff3824")
	if state == "ready":
		c = Color("#f4a432")
	elif state == "active":
		c = Color("#28dbff")
	var mat: StandardMaterial3D = lamp.get("mat") as StandardMaterial3D
	var light: OmniLight3D = lamp.get("light") as OmniLight3D
	if mat != null:
		mat.albedo_color = c
		mat.emission = c
	if light != null:
		light.light_color = c
