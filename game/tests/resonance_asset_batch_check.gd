extends SceneTree

## Loads every Resonance Star runtime GLB and reports mesh/material bounds.

const ASSETS: Array[String] = [
    "res://assets/resonance/models/resonance_module_hero.glb",
    "res://assets/resonance/models/resonance_rail_system.glb",
    "res://assets/resonance/models/resonance_processing_zone.glb",
    "res://assets/resonance/models/resonance_reactor_tower.glb",
    "res://assets/resonance/models/resonance_energy_core.glb",
    "res://assets/resonance/models/resonance_drone_dock.glb",
    "res://assets/resonance/models/resonance_helper_drone.glb",
    "res://assets/resonance/models/resonance_extraction_platform.glb",
    "res://assets/resonance/models/resonance_surface_set.glb",
    "res://assets/resonance/models/resonance_support_safety_gate.glb",
    "res://assets/resonance/models/resonance_maintenance_facility.glb",
    "res://assets/resonance/models/resonance_cavern_shell.glb",
    "res://assets/resonance/models/resonance_factory_spine.glb",
    "res://assets/resonance/models/resonance_master_scene.glb"
]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run() -> void:
    var rows: Array[Dictionary] = []
    for path in ASSETS:
        check(ResourceLoader.exists(path), "缺少运行时资产：%s" % path)
        var packed: PackedScene = ResourceLoader.load(path) as PackedScene
        check(packed != null, "GLB 未导入为 PackedScene：%s" % path)
        if packed == null:
            continue
        var instance: Node3D = packed.instantiate() as Node3D
        check(instance != null, "GLB 实例化失败：%s" % path)
        if instance == null:
            continue
        root.add_child(instance)
        await process_frame
        var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
        var materials: Dictionary = {}
        var min_bounds: Vector3 = Vector3(INF, INF, INF)
        var max_bounds: Vector3 = Vector3(-INF, -INF, -INF)
        for node in meshes:
            var mesh_node: MeshInstance3D = node as MeshInstance3D
            if mesh_node == null or mesh_node.mesh == null:
                continue
            var aabb: AABB = mesh_node.get_aabb()
            var corners: Array[Vector3] = [aabb.position, aabb.end, aabb.position + Vector3(aabb.size.x, 0, 0), aabb.position + Vector3(0, aabb.size.y, 0), aabb.position + Vector3(0, 0, aabb.size.z)]
            for corner in corners:
                var world_corner: Vector3 = mesh_node.to_global(corner)
                min_bounds = min_bounds.min(world_corner)
                max_bounds = max_bounds.max(world_corner)
            for surface in mesh_node.mesh.get_surface_count():
                var material: Material = mesh_node.get_active_material(surface)
                if material != null:
                    materials[material.resource_name] = true
        check(meshes.size() >= 8, "资产网格过少：%s (%d)" % [path, meshes.size()])
        check(materials.size() >= 3, "资产材质过少：%s (%d)" % [path, materials.size()])
        check(max_bounds.y > min_bounds.y, "资产没有有效 Y 轴纵深：%s" % path)
        rows.append({"path": path, "meshes": meshes.size(), "materials": materials.size(), "bounds": "%s..%s" % [min_bounds, max_bounds]})
        instance.queue_free()
    print("RESONANCE_ASSET_BATCH: %d checks, %d failures" % [checks, failures.size()])
    for row in rows:
        print("ASSET %s meshes=%d materials=%d bounds=%s" % [row["path"], row["meshes"], row["materials"], row["bounds"]])
    quit(0 if failures.is_empty() else 1)
