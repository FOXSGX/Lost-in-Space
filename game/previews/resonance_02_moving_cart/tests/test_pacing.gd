extends "res://tests/test_solo.gd"

# Real wall-clock experiment. No movie writer, fixed timestep or FPS override by default.
var trace: Array = []
var active: String = "startup"
var last_us: int = Time.get_ticks_usec()
var last_camera: Transform3D = Transform3D.IDENTITY
var last_physics: int = 0
var start_us: int = Time.get_ticks_usec()
var environment: Dictionary = {}
var duration: float = 15.0

func collect() -> void:
    var now: int = Time.get_ticks_usec()
    if player == null or not is_instance_valid(player):
        last_us = now
        return
    var cam: Camera3D = player.get("camera") as Camera3D
    var rid: RID = root.get_viewport_rid()
    var render_transform: Transform3D = cam.get_global_transform_interpolated()
    var changed: float = render_transform.origin.distance_to(last_camera.origin)
    var rotation_step: float = last_camera.basis.z.distance_to(render_transform.basis.z)
    trace.append([float(now-start_us)/1000000.0, active, float(now-last_us)/1000.0,
        Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
        Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
        RenderingServer.viewport_get_measured_render_time_cpu(rid),
        RenderingServer.viewport_get_measured_render_time_gpu(rid),
        RenderingServer.get_frame_setup_time_cpu(),
        Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
        Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
        Engine.get_physics_frames()-last_physics, changed, rotation_step,
        player.position.x, player.position.y, player.position.z,
        cam.global_position.x, cam.global_position.y, cam.global_position.z,
        Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
        str(device.get("phase"))])
    last_us=now;last_camera=render_transform;last_physics=Engine.get_physics_frames()

func measure(label: String, seconds: float, turning: bool = false) -> void:
    # Image readback/PNG writing is a separate QA operation, outside samples.
    active="warmup_"+label
    await create_timer(1.0).timeout
    active=label
    var begin: int = Time.get_ticks_msec()
    while Time.get_ticks_msec()-begin < int(seconds*1000.0):
        if turning:
            player.set("_camera_yaw_target", -PI*.5 + sin(float(Time.get_ticks_msec()-begin)*.0015)*1.9)
        await process_frame
    print("PACING_SEGMENT ",label)
    active="setup"

func walk_loop(label: String, points: Array[Vector2], seconds: float) -> void:
    active=label
    var begin: int=Time.get_ticks_msec()
    var index: int=0
    while Time.get_ticks_msec()-begin < int(seconds*1000.0):
        await travel(label, points[index%points.size()])
        index+=1
    active="setup"

func run() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--duration="):duration=float(arg.get_slice("=",1))
    process_frame.connect(collect)
    var load_start: int=Time.get_ticks_usec()
    await boot()
    var load_ms: float=float(Time.get_ticks_usec()-load_start)/1000.0
    if OS.get_cmdline_user_args().has("--cap60"):Engine.max_fps=60
    if OS.get_cmdline_user_args().has("--uncapped"):
        Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
    environment={"version":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),
        "vendor":RenderingServer.get_video_adapter_vendor(),"renderer":RenderingServer.get_current_rendering_method(),
        "driver":RenderingServer.get_current_rendering_driver_name(),"cpu":OS.get_processor_name(),
        "debug_build":OS.is_debug_build(),"editor_hint":Engine.is_editor_hint(),"editor_feature":OS.has_feature("editor"),
        "standalone_window":not OS.get_cmdline_args().has("--embedded"),"args":OS.get_cmdline_args(),
        "window":str(DisplayServer.window_get_size()),"viewport":str(root.size),
        "screen":DisplayServer.window_get_current_screen(),"refresh_hz":DisplayServer.screen_get_refresh_rate(),
        "screen_size":str(DisplayServer.screen_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),
        "fps_cap":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"interpolation":physics_interpolation,
        "physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"user_data_dir":OS.get_user_data_dir(),
        "pid":OS.get_process_id(),"load_ms":load_ms,"recording":false,"fixed_fps":false}
    print("PACING_ENVIRONMENT ",JSON.stringify(environment))
    await measure("first_loaded",3.0)
    await shot("entry",2,-PI*.5)
    await measure("idle",duration)
    await walk_loop("walk",[Vector2(-8.9,-1.8),Vector2(-10.4,-1.8)],duration)
    await measure("turn",duration,true)
    await travel("entry",Vector2(-9.25,-1.82))
    await walk_loop("platform",[Vector2(-5,-1.2),Vector2(-8,-1.2)],duration)
    await travel("stairs",Vector2(1,-1.42))
    await walk_loop("boarding",[Vector2(1,1.42),Vector2(1,-1.42)],duration)
    await travel("board",Vector2(1,1.42));await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(40)
    check(str(device.get("phase"))=="held","性能场景：真实拾取核心")
    await walk_loop("carry_walk",[Vector2(.65,2.62),Vector2(.2,1.42)],duration)
    await measure("carry_turn",duration,true)
    player.set("_camera_yaw_target",-PI*.5);await frames(120)
    await travel("socket",Vector2(-1.22,2.20));await frames(120);await press("deposit");await frames(115)
    check(str(device.get("phase"))=="locked","性能场景：核心实际安装")
    await travel("preload_console",Vector2(-1.35,1.74));await press("repair")
    await measure("interface",duration)
    stop();await press("cancel_operation");await frames(5)
    # The installed core is kept. Start the existing solo input procedure.
    await calibration_pass(false)
    await frames(250)
    check(str(device.get("phase"))=="stable","性能场景：实际运行共振装置")
    await shot("stable",2,PI*.5)
    await measure("mechanism",duration)
    active="finished"
    var data: Dictionary={"environment":environment,"columns":["time_s","scenario","frame_ms","main_monitor_ms","physics_monitor_ms","render_cpu_ms","gpu_ms","setup_cpu_ms","draw_calls","triangles","physics_steps","camera_m","camera_rad","x","y","z","cam_x","cam_y","cam_z","active_physics","phase"],"frames":trace,"checks":checks,"failed":failed}
    var file: FileAccess=FileAccess.open(output.path_join("pacing.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(data));file.close()
    if OS.get_cmdline_user_args().has("--profile-sections"):
        var sections: FileAccess=FileAccess.open(output.path_join("sections.json"),FileAccess.WRITE)
        sections.store_string(JSON.stringify({"start_us":start_us,"player":player.get("perf_events"),"device":device.get("perf_events")}));sections.close()
    print("PACING_DONE ",trace.size()," failures=",failed)
    await finish()
