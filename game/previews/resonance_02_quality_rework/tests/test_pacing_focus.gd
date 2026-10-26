extends "res://tests/test_pacing.gd"

func run() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    process_frame.connect(collect)
    await boot()
    if OS.get_cmdline_user_args().has("--interpolate"):physics_interpolation=true
    if OS.get_cmdline_user_args().has("--sync-cap"):Engine.max_fps=0
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
    environment={"interpolation":physics_interpolation,"fps_cap":Engine.max_fps,"refresh":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),"gpu":RenderingServer.get_video_adapter_name(),"window":str(DisplayServer.window_get_size()),"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine")}
    await frames(120)
    await measure("idle",15)
    await walk_loop("walk",[Vector2(-8.9,-1.8),Vector2(-10.4,-1.8)],15)
    await measure("turn",15,true)
    var file: FileAccess=FileAccess.open(output.path_join("pacing.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"environment":environment,"frames":trace}));file.close()
    await finish()
