extends SceneTree

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var scene: Node3D=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(scene)
    for _i: int in range(20):await process_frame
    scene.call("set_reference_view","A_entry")
    var output: String=OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    for channel: int in [1,2]:
        for material: ShaderMaterial in scene.get("materials"):material.set_shader_parameter("debug_channel",channel)
        for _i: int in range(5):await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(output.path_join("channel_"+str(channel)+".png"))
    scene.queue_free()
    for _i: int in range(3):await process_frame
    quit(0)
