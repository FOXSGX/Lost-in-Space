extends SceneTree

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    for path in [
        "res://assets/resonance/models/resonance_module_hero.glb",
        "res://assets/resonance/models/resonance_processing_zone.glb",
        "res://assets/resonance/models/resonance_reactor_tower.glb",
    ]:
        var packed: PackedScene = load(path) as PackedScene
        var instance: Node = packed.instantiate() if packed != null else null
        if instance == null:
            print("ART_INSPECT missing ", path)
            continue
        root.add_child(instance)
        var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
        var names: Dictionary = {}
        if not meshes.is_empty():
            print("ART_INSPECT_FIRST %s node=%s transform=%s" % [path, meshes[0].name, (meshes[0] as MeshInstance3D).transform])
        var min_bounds: Vector3 = Vector3(INF, INF, INF)
        var max_bounds: Vector3 = Vector3(-INF, -INF, -INF)
        for node in meshes:
            var mesh_node: MeshInstance3D = node as MeshInstance3D
            if mesh_node == null or mesh_node.mesh == null:
                continue
            var bounds: AABB = mesh_node.get_aabb()
            var corners: Array[Vector3] = [bounds.position, bounds.position + Vector3(bounds.size.x, 0, 0), bounds.position + Vector3(0, bounds.size.y, 0), bounds.position + Vector3(0, 0, bounds.size.z), bounds.end]
            for corner in corners:
                var world_corner: Vector3 = mesh_node.to_global(corner)
                min_bounds = min_bounds.min(world_corner)
                max_bounds = max_bounds.max(world_corner)
            for surface in mesh_node.mesh.get_surface_count():
                var material: Material = mesh_node.get_active_material(surface)
                if material is StandardMaterial3D:
                    var standard: StandardMaterial3D = material as StandardMaterial3D
                    names[String(standard.resource_name)] = str(standard.albedo_color)
        print("ART_INSPECT %s root_transform=%s meshes=%d mats=%s bounds=%s..%s" % [path, instance.transform, meshes.size(), names, min_bounds, max_bounds])
        instance.queue_free()
    quit(0)
