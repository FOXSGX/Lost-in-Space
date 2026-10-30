extends "res://tests/test_pacing.gd"

func run() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    process_frame.connect(collect)
    await boot()
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
    environment={"gpu":RenderingServer.get_video_adapter_name(),"window":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"fps_cap":Engine.max_fps,"interpolation":physics_interpolation,"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"debug_build":OS.is_debug_build(),"editor_hint":Engine.is_editor_hint(),"user_data_dir":OS.get_user_data_dir()}
    await travel("entry",Vector2(-9.25,-1.82));await travel("aisle",Vector2(-5,-1.2));await travel("stairs",Vector2(1,-1.42));await travel("board",Vector2(1,1.42))
    await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(35)
    await travel("carry",Vector2(.65,2.62));player.set("_camera_yaw_target",-PI*.5);await frames(115)
    await press("drop");await frames(60);await press("pickup");await frames(35)
    await travel("socket",Vector2(-1.22,2.20));await press("deposit");await frames(115)
    check(str(device.get("phase"))=="locked","补充基线：正常流程实际安装核心")
    await travel("preload_console",Vector2(-1.35,1.74));await press("repair")
    check(str(player.get("operating_role"))=="preload","补充基线：实际打开操作界面")
    await measure("interface",15)
    await press("cancel_operation")
    await calibration_pass(false);await frames(250)
    check(str(device.get("phase"))=="stable","补充基线：实际运行装置")
    await measure("mechanism",15)
    var file: FileAccess=FileAccess.open(output.path_join("pacing.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"environment":environment,"frames":trace,"checks":checks,"failed":failed}));file.close()
    await finish()
