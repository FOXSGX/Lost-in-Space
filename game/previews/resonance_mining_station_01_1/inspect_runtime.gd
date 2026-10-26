extends SceneTree

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var scene: Node3D=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(scene)
    for _frame: int in range(20):await process_frame
    var unique: Dictionary={}
    var visible_meshes: int=0
    var surfaces: int=0
    var triangles: int=0
    for node: Node in scene.find_children("*","MeshInstance3D",true,false):
        var mesh: MeshInstance3D=node as MeshInstance3D
        if not mesh.is_visible_in_tree():continue
        visible_meshes+=1
        triangles+=int(float(mesh.mesh.get_faces().size())/3.0)
        for surface: int in range(mesh.mesh.get_surface_count()):
            var mat: Material=mesh.get_active_material(surface)
            if mat!=null:unique[mat.get_rid().get_id()]=true
            surfaces+=1
    var data: Dictionary={"visible_mesh_instances_spawn":visible_meshes,"visible_triangles_spawn":triangles,"surfaces_spawn":surfaces,"distinct_live_material_rids_spawn":unique.size(),"static_mesh_instances":(scene.get("meshes") as Array).size(),"shared_static_material_profiles":(scene.get("materials") as Array).size(),"lights":(scene.get("runtime_lights") as Array).size(),"collision_triangles":scene.get("collision_triangles"),"processor":OS.get_processor_name(),"note":"Visible in scene tree, not frustum occlusion. Includes existing character and contact shadow. Draw submissions are separately measured by moving benchmark."}
    var file: FileAccess=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    file.store_string(JSON.stringify(data,"  "));file.close()
    print("P11_RUNTIME_AUDIT ",JSON.stringify(data))
    scene.queue_free()
    for _frame: int in range(3):await process_frame
    quit(0)
