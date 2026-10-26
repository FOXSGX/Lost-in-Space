extends "res://tests/test_pacing.gd"

# Dedicated hitch probe (new file, existing tests untouched).
#
# Question: is the 238-296 ms "first pass of the platform" stall
#   (a) a real first-use cost inside the game (shader compile / resource upload),
#   (b) a steady per-pass cost, or
#   (c) the test harness' own screenshot readback (get_image + save_png)?
#
# Method: one process, no screenshots during the walk, the identical platform
# stretch walked six times with identical inputs. Each pass is its own scenario
# label, so pass 1 can be compared with passes 2-6 directly. Separately, three
# diagnostic screenshots are timed in the same process.
#
# Run with: --script res://tests/test_hitch.gd -- <out> --loopback-test

var passes: int = 6
var pass_seconds: float = 5.0
var shot_costs: Array = []

func time_shot(label: String) -> float:
    active = "shot_cost"
    var t0: int = Time.get_ticks_msec()
    await shot(label, 2)
    var cost: float = float(Time.get_ticks_msec() - t0)
    shot_costs.append({"label": label, "ms": cost})
    print("HITCH_SHOT_COST ", label, " ", cost)
    await frames(10)
    return cost

func run() -> void:
    output = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--passes="):
            passes = int(arg.get_slice("=", 1))
        if arg.begins_with("--pass="):
            pass_seconds = float(arg.get_slice("=", 1))
    process_frame.connect(collect)
    await boot()
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    environment = {
        "interpolation": physics_interpolation,
        "fps_cap": Engine.max_fps,
        "vsync": DisplayServer.window_get_vsync_mode(),
        "physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
        "shader_cache": ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled"),
        "gpu": RenderingServer.get_video_adapter_name(),
        "window": str(DisplayServer.window_get_size()),
        "passes": passes, "pass_seconds": pass_seconds,
    }
    print("HITCH_ENVIRONMENT ", JSON.stringify(environment))
    await frames(120)

    # Screenshot cost, measured in isolation, before any world traversal.
    await time_shot("cost_a")
    await time_shot("cost_b")
    await time_shot("cost_c")

    # Walk to the platform edge with the camera pointing at the corridor.
    active = "approach"
    await travel("entry", Vector2(-9.25, -1.82))
    await frames(60)

    var points: Array[Vector2] = [Vector2(-5, -1.2), Vector2(-7, -1.0), Vector2(-9.25, -1.82), Vector2(-4.2, -1.3)]
    for pass_index: int in range(passes):
        active = "plat%d" % (pass_index + 1)
        var begin: int = Time.get_ticks_msec()
        var step: int = 0
        while Time.get_ticks_msec() - begin < int(pass_seconds * 1000.0):
            await travel(active, points[step % points.size()])
            step += 1
        print("HITCH_PASS_DONE ", pass_index + 1, " steps=", step)
        active = "gap%d" % (pass_index + 1)
        await frames(30)

    active = "finished"
    var data: Dictionary = {
        "environment": environment,
        "columns": ["time_s", "scenario", "frame_ms", "main_monitor_ms", "physics_monitor_ms",
            "render_cpu_ms", "gpu_ms", "setup_cpu_ms", "draw_calls", "triangles",
            "physics_steps", "camera_m", "camera_rad", "x", "y", "z",
            "cam_x", "cam_y", "cam_z", "active_physics", "phase"],
        "frames": trace, "checks": checks, "failed": failed,
        "shot_costs": shot_costs,
    }
    var f: FileAccess = FileAccess.open(output.path_join("pacing.json"), FileAccess.WRITE)
    f.store_string(JSON.stringify(data)); f.close()
    print("HITCH_DONE frames=", trace.size(), " shots=", JSON.stringify(shot_costs))
    await finish()
