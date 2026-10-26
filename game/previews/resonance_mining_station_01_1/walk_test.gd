extends SceneTree

var scene: Node3D
var player: CharacterBody3D
var output: String
var records: Array[Dictionary]=[]
var all_samples: Array[Dictionary]=[]
var camera_hits: int=0
var screenshots: Dictionary={}
var orbit_samples: int=0
var orbit_hits: int=0

func _initialize() -> void:
    run.call_deferred()

func frames(count: int) -> void:
    for _i: int in range(count):await physics_frame

func input(action: String,pressed: bool,strength: float=1.0) -> void:
    if pressed:Input.action_press(action,strength)
    else:Input.action_release(action)

func stop_input() -> void:
    for key: String in ["move_up","move_down","move_left","move_right"]:Input.action_release(key)

func travel(label: String,target: Vector2,timeout: float=7.0) -> bool:
    var start: Vector3=player.global_position
    var started: int=Time.get_ticks_usec()
    var frames_used: int=0
    var highest: float=-100
    var lowest: float=100
    var last_distance: float=100
    var stuck_frames: int=0
    var touched: Dictionary={}
    while float(Time.get_ticks_usec()-started)/1000000.0 < timeout:
        var at: Vector2=Vector2(player.position.x,player.position.z)
        var direction: Vector2=(target-at).normalized()
        var distance: float=at.distance_to(target)
        if distance<0.16:break
        player.set("_camera_yaw_target",atan2(-direction.x,-direction.y))
        var yaw: float=float(player.get("_camera_yaw"))
        var forward: Vector2=Vector2(-sin(yaw),-cos(yaw))
        var right: Vector2=Vector2(cos(yaw),-sin(yaw))
        var strength: float=clampf(distance/0.65,0.66,1.0)
        var horizontal: float=direction.dot(right)*strength
        var vertical: float=-direction.dot(forward)*strength
        stop_input()
        if horizontal>0:input("move_right",true,horizontal)
        elif horizontal<0:input("move_left",true,-horizontal)
        if vertical<0:input("move_up",true,-vertical)
        elif vertical>0:input("move_down",true,vertical)
        await physics_frame
        frames_used+=1
        for collision_index: int in range(player.get_slide_collision_count()):
            var collision: KinematicCollision3D=player.get_slide_collision(collision_index)
            var body: Node=collision.get_collider() as Node
            if body!=null:touched[str(body.name)]=true
        highest=maxf(highest,player.position.y)
        lowest=minf(lowest,player.position.y)
        if bool(player.call("camera_overlap")):camera_hits+=1
        if absf(distance-last_distance)<0.001:stuck_frames+=1
        else:stuck_frames=0
        last_distance=distance
        var sample: Dictionary={"phase":label,"position":[player.position.x,player.position.y,player.position.z],"floor":player.is_on_floor(),"camera_overlap":bool(player.call("camera_overlap")),"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
        all_samples.append(sample)
        if stuck_frames>90:break
    stop_input()
    await frames(10)
    var final_distance: float=Vector2(player.position.x,player.position.z).distance_to(target)
    var row: Dictionary={"phase":label,"start":[start.x,start.y,start.z],"end":[player.position.x,player.position.y,player.position.z],"target":[target.x,target.y],"distance_to_target":final_distance,"reached":final_distance<0.25,"highest_y":highest,"lowest_y":lowest,"physics_frames":frames_used,"floor_at_end":player.is_on_floor(),"touched_bodies":touched.keys()}
    records.append(row)
    print("WALK_SEGMENT ",JSON.stringify(row))
    return bool(row["reached"])

func shot(label: String,yaw: float) -> void:
    player.set("_camera_yaw_target",yaw)
    player.set("_camera_pitch_target",0.18 if label in ["tp_B_side","tp_C_mineral"] else -0.18)
    await frames(45)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join(label+".png"))
    var cam: Camera3D=player.get("camera") as Camera3D
    var b: Basis=cam.global_basis
    screenshots[label]={"camera_position":[cam.global_position.x,cam.global_position.y,cam.global_position.z],"basis_x":[b.x.x,b.x.y,b.x.z],"basis_y":[b.y.x,b.y.y,b.y.z],"basis_z":[b.z.x,b.z.y,b.z.z],"fov_vertical":cam.fov,"player_position":[player.position.x,player.position.y,player.position.z],"player_yaw":player.rotation.y}
    var doc: GLTFDocument=GLTFDocument.new()
    var state: GLTFState=GLTFState.new()
    var visual: Node3D=player.get("visual") as Node3D
    screenshots[label]["visual_lowest_local_y"]=visual.call("lowest_vertex_y")
    screenshots[label]["visual_world_lowest_y"]=player.position.y+float(visual.call("lowest_vertex_y"))*visual.scale.y
    var appended: Error=doc.append_from_scene(visual,state)
    if appended==OK:
        var saved: Error=doc.write_to_filesystem(state,output.path_join(label+"_actor.glb"))
        screenshots[label]["actor_export_ok"]=saved==OK
    # Same physical station point, full yaw sweep and three allowed pitches.
    var old_yaw: float=float(player.get("_camera_yaw"));var old_pitch: float=float(player.get("_camera_pitch"))
    for pitch: float in [-0.4,-0.18,0.18]:
        for index: int in range(12):
            player.set("_camera_yaw",float(index)*TAU/12)
            player.set("_camera_pitch",pitch)
            player.call("update_camera",1.0,true)
            orbit_samples+=1
            if bool(player.call("camera_overlap")):orbit_hits+=1
    player.set("_camera_yaw",old_yaw);player.set("_camera_pitch",old_pitch)
    player.call("update_camera",1.0,true)

func run() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args()
    output=args[0]
    DirAccess.make_dir_recursive_absolute(output)
    scene=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(scene)
    await frames(20)
    player=scene.get("player") as CharacterBody3D
    player.set("step_assist_enabled",args.has("steps"))
    player.set("camera_sweep_enabled",not args.has("baseline_camera"))
    var a: bool=await travel("A_entry",Vector2(-9.25,-1.82))
    await shot("tp_A_entry",-PI*.5)
    await travel("west_ramp_approach",Vector2(-7.0,-1.2))
    var ramp: bool=await travel("west_ramp_up",Vector2(-5.0,-1.2))
    var b: bool=await travel("B_side_aisle",Vector2(-.7,-1.2))
    await shot("tp_B_side",-0.65)
    var c: bool=await travel("C_mineral",Vector2(3.0,-2.12))
    await shot("tp_C_mineral",0.0)
    await travel("east_platform",Vector2(5.25,-1.2))
    var down: bool=await travel("east_ramp_down",Vector2(8.15,-1.2))
    var d: bool=await travel("D_return",Vector2(9.35,-.72))
    await shot("tp_D_return",PI*.5)
    await travel("east_return_approach",Vector2(7.2,-1.2))
    var back: bool=await travel("east_ramp_return",Vector2(5.1,-1.2))
    await travel("track_test_approach",Vector2(8.3,-.72))
    var rail: bool=await travel("rail_crossing",Vector2(8.3,4.15),5.0)
    # Controlled negative tests: the body must not walk through cart / wall.
    var before: Vector3=player.position
    await travel("cart_block_expected",Vector2(3.0,1.5),3.2)
    var cart_block: bool=not bool(records[-1]["reached"]) and (records[-1]["touched_bodies"] as Array).has("COLLIDER_solid")
    player.position=before
    await frames(5)
    await travel("wall_block_expected",Vector2(3.0,-7.0),3.2)
    var wall_block: bool=player.position.z>-5.3
    var result: Dictionary={"route_core_pass":a and ramp and b and c and down and d and back,"rail_crossing_pass":rail,"cart_block":cart_block,"wall_block":wall_block,"camera_overlap_frames":camera_hits,"orbit_samples":orbit_samples,"orbit_overlaps":orbit_hits,"segments":records,"samples":all_samples,"screenshots":screenshots,"step_assist":player.get("step_assist_enabled"),"step_count":player.get("step_count"),"collision_triangles":scene.get("collision_triangles"),"note":"Only the final controlled negative test resets to its recorded start; A-to-D and the return ramp use actual inputs and move_and_slide."}
    var file: FileAccess=FileAccess.open(output.path_join("walk-audit.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "));file.close()
    print("WALK_TEST_DONE ",JSON.stringify({"core":result["route_core_pass"],"overlaps":camera_hits,"return_ramp":back}))
    scene.queue_free()
    await frames(3)
    quit(0)
