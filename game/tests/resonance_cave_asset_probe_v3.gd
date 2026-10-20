extends SceneTree

func _initialize() -> void:
    call_deferred("probe")

func probe() -> void:
    var packed := ResourceLoader.load("res://assets/resonance/models/resonance_cave_vertical_slice_v3.glb") as PackedScene
    if packed == null:
        print("ASSET_PROBE missing")
        quit(1)
        return
    var instance := packed.instantiate() as Node3D
    root.add_child(instance)
    await process_frame
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(instance, meshes)
    print("ASSET_PROBE meshes=%d root_transform=%s" % [meshes.size(), instance.global_transform])
    for index in mini(meshes.size(), 18):
        var mesh := meshes[index]
        var surface_mat: Material = mesh.mesh.surface_get_material(0) if mesh.mesh != null and mesh.mesh.get_surface_count() > 0 else null
        var albedo: Color = surface_mat.albedo_color if surface_mat is StandardMaterial3D else Color.TRANSPARENT
        print("MESH %d name=%s origin=%s scale=%s aabb=%s mat=%s albedo=%s" % [index, mesh.name, mesh.global_position, mesh.global_scale, mesh.get_aabb(), surface_mat, albedo])
    quit(0)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, out)
