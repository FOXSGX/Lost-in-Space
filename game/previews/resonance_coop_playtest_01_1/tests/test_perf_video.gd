extends "res://tests/test_pacing.gd"

# 性能验证录像（新）。走真实台阶、真实搬芯、真启动共振装置，
# 同时在画面上叠一条逐帧曲线 —— 不是角落里一个 FPS 数字。
#
# 录像模式下 Godot 用固定步长并尽快出帧，墙钟帧间隔主要由 AVI 编码器决定，
# 所以叠加层画的是"引擎内每帧实际工作耗时"（process + physics + render），
# 编码器开销被排除在外。真实墙钟曲线的证据另见 m4-pacing 的 pacing.json。
#
# 运行：--write-movie <out.avi> --fixed-fps 60 --script res://tests/test_perf_video.gd -- <outdir>

var overlay: Control
var overlay_layer: CanvasLayer

func _make_overlay() -> void:
    overlay_layer = CanvasLayer.new()
    overlay_layer.layer = 30
    root.add_child(overlay_layer)
    overlay = (load("res://tests/perf_overlay.gd") as Script).new() as Control
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay_layer.add_child(overlay)

func _overlay_tick() -> void:
    if overlay == null or trace.is_empty():
        return
    var row: Array = trace[-1]
    # 实时抓屏录制，画的是真实墙钟帧间隔（不是引擎内计时）。
    overlay.call("push", float(row[2]), str(row[1]))

func run() -> void:
    output = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    process_frame.connect(collect)
    process_frame.connect(_overlay_tick)
    await boot()
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    environment = {
        "recording": true, "fixed_fps": true,
        "physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
        "interpolation": physics_interpolation,
        "window": str(DisplayServer.window_get_size()),
        "gpu": RenderingServer.get_video_adapter_name(),
    }
    print("PERF_VIDEO_ENV ", JSON.stringify(environment))
    _make_overlay()

    await frames(90)
    await measure("idle", 2.0)
    await walk_loop("walk", [Vector2(-8.9, -1.8), Vector2(-10.4, -1.8)], 6.0)
    await measure("turn", 6.0, true)
    await travel("entry", Vector2(-9.25, -1.82))
    await walk_loop("platform", [Vector2(-5, -1.2), Vector2(-8, -1.2)], 6.0)
    await travel("stairs", Vector2(1, -1.42))
    await walk_loop("boarding", [Vector2(1, 1.42), Vector2(1, -1.42)], 6.0)
    await travel("board", Vector2(1, 1.42))
    await travel("tray", Vector2(.2, 1.42))
    await press("pickup")
    await frames(40)
    check(str(device.get("phase")) == "held", "录像：真实拾取核心")
    await walk_loop("carry_walk", [Vector2(.65, 2.62), Vector2(.2, 1.42)], 6.0)
    await measure("carry_turn", 6.0, true)
    player.set("_camera_yaw_target", -PI * .5)
    await frames(60)
    await travel("socket", Vector2(-1.22, 2.20))
    await press("deposit")
    await frames(115)
    check(str(device.get("phase")) == "locked", "录像：核心安装")
    await travel("frequency_console", Vector2(2.10, 1.90))
    await press("repair")
    await drive("frequency", 2800)
    await frames(120)
    check(str(device.get("phase")) in ["charging", "stable"], "录像：共振装置真实启动")
    await measure("mechanism", 4.0)
    active = "finished"
    await frames(30)

    var data: Dictionary = {
        "environment": environment,
        "columns": ["time_s", "scenario", "frame_ms", "main_monitor_ms", "physics_monitor_ms",
            "render_cpu_ms", "gpu_ms", "setup_cpu_ms", "draw_calls", "triangles",
            "physics_steps", "camera_m", "camera_rad", "x", "y", "z",
            "cam_x", "cam_y", "cam_z", "active_physics", "phase"],
        "frames": trace, "checks": checks, "failed": failed,
    }
    var f: FileAccess = FileAccess.open(output.path_join("pacing.json"), FileAccess.WRITE)
    f.store_string(JSON.stringify(data))
    f.close()
    print("PERF_VIDEO_DONE frames=", trace.size(), " failures=", failed)
    await finish()
