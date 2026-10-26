extends SceneTree

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args()
    var output: String=args[0]
    DirAccess.make_dir_recursive_absolute(output)
    var scene: Node3D=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(scene)
    for _frame: int in range(30):await process_frame
    assert(bool(scene.get("loaded")))
    for view: String in ["A_entry","B_cart_side","C_mineral","D_return"]:
        scene.call("set_reference_view",view)
        for _frame: int in range(8):await process_frame
        await RenderingServer.frame_post_draw
        var image: Image=root.get_texture().get_image()
        image.save_png(output.path_join("fp_"+view+".png"))
    print("P11_REFERENCE_CAPTURE_OK")
    scene.queue_free()
    for _frame: int in range(3):await process_frame
    quit(0)
