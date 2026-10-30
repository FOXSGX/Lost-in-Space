extends SceneTree

class Sampler extends Node:
    var enabled: bool=false
    var times: Array[float]=[]
    var last_tick: int=0
    var draws: Array[float]=[]
    var primitives: Array[float]=[]
    var physics: Array[float]=[]
    func _process(_delta: float) -> void:
        var now: int=Time.get_ticks_usec()
        if enabled and last_tick>0:
            times.append(float(now-last_tick)/1000.0)
            draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
            primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
            physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
        last_tick=now if enabled else 0

var scene: Node3D
var player: CharacterBody3D
var sampler: Sampler

func _initialize() -> void:run.call_deferred()

func frames(count: int) -> void:
    for _i: int in range(count):await physics_frame

func drive_to(target: Vector2) -> bool:
    var start: int=Time.get_ticks_msec()
    while Time.get_ticks_msec()-start<5500:
        var at: Vector2=Vector2(player.position.x,player.position.z)
        var delta: Vector2=target-at
        if delta.length()<.16:break
        var direction: Vector2=delta.normalized()
        player.set("_camera_yaw_target",atan2(-direction.x,-direction.y))
        var yaw: float=float(player.get("_camera_yaw"))
        var forward: Vector2=Vector2(-sin(yaw),-cos(yaw));var right: Vector2=Vector2(cos(yaw),-sin(yaw))
        var strength: float=clampf(delta.length()/.65,.66,1)
        var x: float=direction.dot(right)*strength;var y: float=-direction.dot(forward)*strength
        release()
        if x>0:Input.action_press("move_right",x)
        else:Input.action_press("move_left",-x)
        if y<0:Input.action_press("move_up",-y)
        else:Input.action_press("move_down",y)
        await physics_frame
    release()
    return Vector2(player.position.x,player.position.z).distance_to(target)<.25

func release() -> void:
    for key: String in ["move_left","move_right","move_up","move_down"]:Input.action_release(key)

func summarize(values: Array[float]) -> Dictionary:
    var sorted: Array[float]=values.duplicate();sorted.sort()
    var total: float=0
    for value: float in sorted:total+=value
    return {"frames":sorted.size(),"median_ms":sorted[int(sorted.size()*.5)],"p95_ms":sorted[int(sorted.size()*.95)],"p99_ms":sorted[int(sorted.size()*.99)],"max_ms":sorted[-1],"mean_ms":total/sorted.size()}

func run() -> void:
    var output: String=OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    scene=(load("res://station.tscn") as PackedScene).instantiate() as Node3D;root.add_child(scene)
    await frames(60)
    player=scene.get("player") as CharacterBody3D
    sampler=Sampler.new();root.add_child(sampler)
    var rows: Array[Dictionary]=[]
    for config: String in ["full","no_realtime_shadows","no_realtime_lights_specular","no_crystal_geometry","pulse_off","full_repeat"]:
        scene.call("set_realtime",config!="no_realtime_lights_specular")
        scene.set("pulse_enabled",config!="pulse_off")
        for light: OmniLight3D in scene.get("runtime_lights"):
            light.shadow_enabled=config!="no_realtime_shadows" and light==((scene.get("runtime_lights") as Array)[0])
        # Full profile uses three character shadow pools, matching the scene.
        if config!="no_realtime_shadows":
            var lights: Array=scene.get("runtime_lights") as Array
            for i: int in range(mini(3,lights.size())):(lights[i] as OmniLight3D).shadow_enabled=true
        for mesh: MeshInstance3D in scene.get("mineral_meshes"):mesh.visible=config!="no_crystal_geometry"
        player.position=Vector3(-10.8,.1,-1.8);player.velocity=Vector3.ZERO
        player.set("_camera_yaw",-PI*.5);player.set("_camera_yaw_target",-PI*.5)
        await frames(45)
        sampler.times.clear();sampler.draws.clear();sampler.primitives.clear();sampler.physics.clear();sampler.enabled=true
        var reached: Array[bool]=[]
        var segments: Array[Dictionary]=[]
        for point: Vector2 in [Vector2(-9.25,-1.82),Vector2(-7,-1.2),Vector2(-5,-1.2),Vector2(-.7,-1.2),Vector2(3,-2.12),Vector2(5.15,-1.2),Vector2(8.15,-1.2),Vector2(9.35,-.72)]:
            var first: int=sampler.times.size()
            reached.append(await drive_to(point))
            if sampler.times.size()>first:
                var segment: Dictionary=summarize(sampler.times.slice(first))
                segment["target"]=[point.x,point.y];segments.append(segment)
        sampler.enabled=false
        var row: Dictionary=summarize(sampler.times)
        row["config"]=config;row["waypoint_results"]=reached
        row["segments"]=segments
        row["draw_calls_min"]=sampler.draws.min();row["draw_calls_max"]=sampler.draws.max()
        row["submitted_primitives_min"]=sampler.primitives.min();row["submitted_primitives_max"]=sampler.primitives.max()
        row["physics_monitor_median_ms"]=summarize(sampler.physics)["median_ms"]
        row["draw_calls_end"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
        row["physics_ms_end"]=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
        row["process_ms_end"]=Performance.get_monitor(Performance.TIME_PROCESS)*1000
        row["vram_bytes"]=Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
        row["frame_setup_cpu_ms"]=RenderingServer.get_frame_setup_time_cpu()
        rows.append(row);print("BENCH_ROW ",JSON.stringify(row))
    var data: Dictionary={"resolution":[1280,800],"vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"collision_triangles":scene.get("collision_triangles"),"material_profiles":(scene.get("materials") as Array).size(),"static_meshes":(scene.get("meshes") as Array).size(),"rows":rows,"limit":"Moving character and camera; uncapped frame intervals, not GPU timestamps. Static irradiance remains when realtime lights are disabled. No combat, network or exported-build workload."}
    var file: FileAccess=FileAccess.open(output.path_join("moving-performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
    scene.queue_free();await frames(3);quit(0)
