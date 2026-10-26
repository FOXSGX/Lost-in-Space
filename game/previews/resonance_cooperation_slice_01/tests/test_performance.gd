extends "res://tests/test_solo.gd"

var measurements: Dictionary={}
var active_label: String=""
var last_tick: int=0

func begin_sample(label: String) -> void:
    active_label=label;measurements[label]=[];last_tick=Time.get_ticks_usec()

func frame_sample() -> void:
    if active_label=="":return
    var now: int=Time.get_ticks_usec()
    (measurements[active_label] as Array).append({"frame_ms":float(now-last_tick)/1000.0,
        "process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,
        "physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,
        "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
        "primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
        "static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),
        "video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
        "nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
        "objects":Performance.get_monitor(Performance.OBJECT_COUNT),
        "orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)})
    last_tick=now

func measure(label: String,seconds: float,orbiting: bool=false) -> void:
    begin_sample(label)
    var start: int=Time.get_ticks_msec()
    while Time.get_ticks_msec()-start<int(seconds*1000):
        if orbiting:player.set("_camera_yaw_target",PI*.5+sin(float(Time.get_ticks_msec()-start)*.0025)*1.4)
        await process_frame
    active_label=""
    print("PERFORMANCE_SAMPLES ",label," ",(measurements[label] as Array).size())

func run() -> void:
    await boot()
    Engine.max_fps=0
    process_frame.connect(frame_sample)
    await frames(100)
    await measure("sleeping_core_entry",3.0)
    await travel("entry",Vector2(-9.25,-1.82));await travel("aisle",Vector2(-5,-1.2))
    await travel("stairs",Vector2(1,-1.42));await travel("board",Vector2(1,1.42))
    await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(40)
    begin_sample("carried_core_walking")
    await travel("carry_measured",Vector2(.65,2.62));await frames(30);active_label=""
    await measure("carried_core_turning",3.0,true)
    await travel("socket",Vector2(-1.22,2.20));await press("deposit");await frames(115)
    check(await calibration_pass(false),"性能采样使用实际操作通过校准")
    await frames(240)
    check(str(device.get("phase"))=="stable","实际稳定状态开始性能采样")
    player.set("_camera_yaw_target",PI*.5);await frames(80)
    await measure("stable_full_feedback",4.0)
    var fx: Node3D=device.get("fx") as Node3D
    fx.set("enabled",false);fx.set("animation_enabled",false);await frames(60)
    await measure("stable_feedback_disabled_same_camera",4.0)
    fx.set("enabled",true);fx.set("animation_enabled",true);await frames(60)
    var before: Dictionary={"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
    for _i: int in range(10):scene.call("request_action","reset");await frames(20)
    var after: Dictionary={"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
    check(int(after["nodes"])==int(before["nodes"]) and int(after["orphans"])<=int(before["orphans"]),"十次设备复位后节点数与孤儿节点未增长")
    var report: Dictionary={"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"gpu":RenderingServer.get_video_adapter_name(),"gpu_vendor":RenderingServer.get_video_adapter_vendor(),"engine":Engine.get_version_info(),"viewport":[root.size.x,root.size.y],"renderer":"gl_compatibility","vsync":false,"fps_cap":0,"movie_recording":false,"fixed_fps":false,"measurements":measurements,"reset_before":before,"reset_after":after,"note":"Actual rendered process-frame intervals and Godot monitors on this machine. CPU monitors are not GPU timings. Feedback comparison freezes only rotor animation and disables local light/flow/environment response; material state updates remain."}
    var file: FileAccess=FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    await finish()
