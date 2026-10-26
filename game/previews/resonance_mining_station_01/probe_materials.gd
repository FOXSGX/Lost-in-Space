extends SceneTree

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var scene: PackedScene = load("res://assets/mining_station_01.glb") as PackedScene
    var node: Node = scene.instantiate()
    root.add_child(node)
    scan(node)
    node.queue_free()
    await process_frame
    quit(0)

func scan(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh: MeshInstance3D = node as MeshInstance3D
        for index: int in range(mesh.mesh.get_surface_count()):
            var m: StandardMaterial3D = mesh.get_active_material(index) as StandardMaterial3D
            if m != null and ("resonant mineral" in m.resource_name or "deep cleavage" in m.resource_name):
                print("MATERIAL ", m.resource_name, " vertex=",m.vertex_color_use_as_albedo," color=",m.albedo_color," emission=",m.emission," energy=",m.emission_energy_multiplier," op=",m.emission_operator)
    for child: Node in node.get_children():
        scan(child)
