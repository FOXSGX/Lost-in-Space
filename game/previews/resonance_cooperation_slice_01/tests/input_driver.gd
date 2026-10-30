extends SceneTree

var scene: Node3D
var player: CharacterBody3D
var device: Node3D
var output: String
var checks: Array[Dictionary]=[]
var route: Array[Dictionary]=[]
var samples: Array[Dictionary]=[]
var actions: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var camera_hits: int=0
var orbit_hits: int=0
var orbit_samples: int=0
var failed: int=0
var held_overlap_frames: int=0

func _initialize() -> void:run.call_deferred()
func run() -> void:pass

func boot() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    scene=(load("res://station.tscn") as PackedScene).instantiate() as Node3D;root.add_child(scene);current_scene=scene
    await frames(35)
    if OS.get_cmdline_user_args().has("--realtime-capture"):Engine.max_fps=60
    player=scene.get("player") as CharacterBody3D;device=scene.get("device") as Node3D
func frames(count: int) -> void:
    for _i: int in range(count):await physics_frame

func check(ok: bool,label: String) -> void:
    checks.append({"ok":ok,"label":label,"state":device.call("stage_snapshot")})
    if not ok:failed+=1;print("INTERACTION_CHECK_FAILED ",label)
    else:print("INTERACTION_CHECK_OK ",label)

func stop() -> void:
    for action: String in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)

func travel(label: String,target: Vector2,timeout_frames: int=420) -> bool:
    var start: Vector3=player.position;var success: bool=false;var highest: float=start.y;var max_rise: float=0
    var touched: Dictionary={};var previous: Vector3=player.position
    for i: int in range(timeout_frames):
        var at: Vector2=Vector2(player.position.x,player.position.z);var distance: float=at.distance_to(target)
        if distance<.045:success=true;break
        var direction: Vector2=(target-at).normalized();player.set("_camera_yaw_target",atan2(-direction.x,-direction.y))
        var yaw: float=float(player.get("_camera_yaw"));var forward: Vector2=Vector2(-sin(yaw),-cos(yaw));var right: Vector2=Vector2(cos(yaw),-sin(yaw))
        var strength: float=clampf(distance/.65,.56,1);var horizontal: float=direction.dot(right)*strength;var vertical: float=-direction.dot(forward)*strength
        stop()
        Input.action_press("move_right" if horizontal>0 else "move_left",absf(horizontal))
        Input.action_press("move_down" if vertical>0 else "move_up",absf(vertical))
        await physics_frame
        highest=maxf(highest,player.position.y);max_rise=maxf(max_rise,player.position.y-previous.y);previous=player.position
        var overlap: bool=bool(player.call("camera_overlap"));if overlap:camera_hits+=1
        if bool(device.call("held_overlaps")):held_overlap_frames+=1
        for j: int in range(player.get_slide_collision_count()):
            var body: Node=player.get_slide_collision(j).get_collider() as Node
            if body!=null:touched[str(body.name)]=true
        samples.append({"phase":label,"position":[player.position.x,player.position.y,player.position.z],"floor":player.is_on_floor(),"camera_overlap":overlap,"carrying":player.get("carrying")})
    stop();await frames(4)
    var row: Dictionary={"phase":label,"success":success,"start":[start.x,start.y,start.z],"end":[player.position.x,player.position.y,player.position.z],"target":[target.x,target.y],"highest_y":highest,"max_vertical_step":max_rise,"touched":touched.keys()}
    route.append(row);print("INTERACTION_ROUTE ",JSON.stringify(row));return success

func face(at: Vector3) -> void:
    var direction: Vector3=at-player.position
    player.set("_camera_yaw_target",atan2(-direction.x,-direction.z));await frames(35)

func press(action: String) -> void:
    if action=="pickup":await face((device.get("core") as Node3D).global_position)
    if action=="deposit":await face(Vector3(-2.5,2.4,2.2))
    if action=="repair":
        var a: Vector3=device.call("control_anchor","frequency") as Vector3
        var b: Vector3=device.call("control_anchor","preload") as Vector3
        await face(a if player.position.distance_to(a)<player.position.distance_to(b) else b)
    actions.append({"action":action,"before":device.call("stage_snapshot"),"player_position":[player.position.x,player.position.y,player.position.z]})
    Input.action_press(action);await frames(2);Input.action_release(action);await frames(3)
    actions[-1]["after"]=device.call("stage_snapshot")

func shot(label: String,settle: int=22,yaw: float=PI*.5) -> void:
    player.set("_camera_yaw_target",yaw);player.set("_camera_pitch_target",-.08)
    await frames(settle)
    if DisplayServer.get_name()=="headless":
        print("INTERACTION_SCREENSHOT_SKIPPED_HEADLESS ",label)
        return
    await RenderingServer.frame_post_draw
    captures.append({"name":label,"frame":Engine.get_frames_drawn(),"device_clock":device.get("clock"),"phase":device.get("phase")})
    root.get_texture().get_image().save_png(output.path_join(label+".png"))
    print("INTERACTION_SCREENSHOT ",label)

func orbit() -> void:
    var yaw: float=float(player.get("_camera_yaw"));var pitch: float=float(player.get("_camera_pitch"))
    for p: float in [-.4,-.18,.18]:
        for index: int in range(12):
            player.set("_camera_yaw",float(index)*TAU/12);player.set("_camera_pitch",p);player.call("update_camera",1.0,true)
            orbit_samples+=1
            if bool(player.call("camera_overlap")):orbit_hits+=1
    player.set("_camera_yaw",yaw);player.set("_camera_pitch",pitch);player.call("update_camera",1.0,true)

func finish() -> void:
    var data: Dictionary={"passed":failed==0,"failures":failed,"checks":checks,"route":route,"samples":samples,"actions":actions,"events":device.get("events"),"final_state":device.call("stage_snapshot"),"camera_overlap_frames":camera_hits,"orbit_samples":orbit_samples,"orbit_overlaps":orbit_hits,"held_overlap_frames":held_overlap_frames,"captures":captures,"note":"Player moves only via Input actions and CharacterBody3D physics. No player teleport or direct placement on cart. Direct adapter calls are only negative actor/revision tests."}
    var file: FileAccess=FileAccess.open(output.path_join("interaction-test.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
    print("INTERACTION_TEST_RESULT ",JSON.stringify({"passed":failed==0,"failures":failed,"checks":checks.size(),"camera_overlaps":camera_hits,"orbit_overlaps":orbit_hits}))
    var timeline: FileAccess=FileAccess.open(output.path_join("capture-timestamps.json"),FileAccess.WRITE);timeline.store_string(JSON.stringify(captures,"  "));timeline.close()
    current_scene=null;scene.queue_free();await frames(3)
    await process_frame;quit(0 if failed==0 else 1)
