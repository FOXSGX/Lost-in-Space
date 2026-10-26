extends SceneTree

var output_dir: String = ""

func _initialize() -> void:
    run.call_deferred()

func frames(count: int) -> void:
    for _index: int in range(count):
        await process_frame

func shot(label: String) -> void:
    await frames(8)
    await RenderingServer.frame_post_draw
    var image: Image = root.get_texture().get_image()
    var result: Error = image.save_png(output_dir.path_join(label + ".png"))
    assert(result == OK)

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://").path_join("evidence")
    DirAccess.make_dir_recursive_absolute(output_dir)
    root.size = Vector2i(1280, 800)
    var scene: PackedScene = load("res://station.tscn") as PackedScene
    var station: Node3D = scene.instantiate() as Node3D
    root.add_child(station)
    await frames(60)
    assert(bool(station.get("loaded")))
    var data: Dictionary = station.call("audit") as Dictionary
    var measurements: Array[Dictionary] = []
    var views: Array[String] = ["A_entry", "B_cart_side", "C_mineral", "D_return"]
    for index: int in range(4):
        var action: InputEventAction = InputEventAction.new()
        action.action = "view_" + str(index + 1)
        action.pressed = true
        Input.parse_input_event(action)
        await frames(3)
        assert(str(station.get("current_view")) == views[index])
        station.set("frozen_pulse", 0.24)
        await frames(240)
        await shot("godot_" + views[index])
        # Exclude synchronous PNG readback/save from steady scene timing.
        await frames(240)
        var timings: Array[float] = []
        for sample: int in range(90):
            var start: int = Time.get_ticks_usec()
            await process_frame
            timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
        timings.sort()
        measurements.append({"view": views[index], "cpu_process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "frame_interval_median_ms": timings[45], "frame_interval_p95_ms": timings[85], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
    station.call("set_view", "C_mineral")
    station.set("frozen_pulse", 0.10)
    await shot("godot_pulse_low")
    station.set("frozen_pulse", 0.42)
    await shot("godot_pulse_high")
    data["measurements"] = measurements
    data["resolution"] = [1280, 800]
    data["evidence"] = "Graphical runtime plus input replay: view_1..view_4; emission low/high capture"
    data["timing_limit"] = "Frame intervals include presentation/vsync; not GPU timings or exported-game performance guarantee"
    var file: FileAccess = FileAccess.open(output_dir.path_join("runtime-audit.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(data, "  "))
    file.close()
    print("STATION_PREVIEW_OK ", JSON.stringify(data))
    station.queue_free()
    await frames(3)
    quit(0)
