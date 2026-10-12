extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition and not failures.has(message):
        failures.append(message)

func verify_ground(visual: ProtagonistVisual, state: String) -> void:
    var lowest := INF
    for mesh in visual._meshes:
        var arrays := mesh.mesh.surface_get_arrays(0)
        for vertex in arrays[Mesh.ARRAY_VERTEX]:
            lowest = minf(lowest, (mesh.global_transform * vertex).y)
        var material := mesh.material_override as StandardMaterial3D
        check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(material.albedo_color.a, 1.0), state + "：角色材质不应透明")
        check(is_zero_approx(mesh.transparency), state + "：角色节点不应淡出")
    check(lowest >= 0.005 - 0.0001, state + "：模型穿过主舱地面")
    check(lowest <= 0.055, state + "：模型离地过高")

func run() -> void:
    var visual := preload("res://scenes/protagonist_visual.tscn").instantiate() as ProtagonistVisual
    root.add_child(visual)
    await process_frame
    var helmet := visual.get_node("Body/Helmet") as MeshInstance3D
    var arrays := helmet.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    for index in range(0, vertices.size(), 3):
        var face_normal := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
        var outward := (normals[index] + normals[index + 1] + normals[index + 2]).normalized()
        check(face_normal.dot(outward) < 0.0, "头盔网格不符合 Godot 的顺时针正面规则")
    var modes: Array[String] = ["站立", "行走", "扫描", "救援", "受伤", "倒地", "救起"]
    for mode in modes:
        visual.set_rescuing(mode == "救援")
        for frame in 180:
            var moving := mode == "行走"
            var downed := mode == "倒地"
            visual.update_state(1.0 / 60.0, Vector2.RIGHT * 5.8 if moving else Vector2.ZERO, downed, mode == "扫描", false, 2 if mode in ["受伤", "救起"] else 5)
            verify_ground(visual, mode)
    print("PROTAGONIST_GROUNDING: %d checks, %d failures" % [checks, failures.size()])
    for failure in failures:
        push_error(failure)
    quit(0 if failures.is_empty() else 1)
