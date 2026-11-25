extends SceneTree

## 只做一件事：把每个 shader 挂到可见网格上真实渲染几帧，让 Godot 的
## SHADER ERROR 出现在 stdout 里。没有报错才继续后面的美术接入。

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var names: PackedStringArray = ["frost_panel", "frost_rock", "frost_snow", "frost_ice", "frost_bone"]
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 0, 6)
	root.add_child(camera)
	camera.make_current()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(light)
	var x: float = -4.0
	for name: String in names:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://shaders/" + name + ".gdshader") as Shader
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.3, 1.3, 1.3)
		mesh.mesh = box
		mesh.material_override = mat
		mesh.position = Vector3(x, 0, 0)
		holder.add_child(mesh)
		x += 1.8
	for i: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	print("FROST_SHADER_CHECK_DONE %d" % names.size())
	quit()
