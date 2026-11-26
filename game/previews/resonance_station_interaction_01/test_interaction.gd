extends SceneTree

var scene: Node3D
var player: CharacterBody3D
var device: Node3D
var output: String
var checks: Array[Dictionary]=[]
var route: Array[Dictionary]=[]
var samples: Array[Dictionary]=[]
var actions: Array[Dictionary]=[]
var camera_hits: int=0
var orbit_hits: int=0
var orbit_samples: int=0
var failed: int=0
var held_overlap_frames: int=0

func _initialize() -> void:run.call_deferred()
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

func press(action: String) -> void:
    actions.append({"action":action,"before":device.call("stage_snapshot"),"player_position":[player.position.x,player.position.y,player.position.z]})
    Input.action_press(action);await frames(2);Input.action_release(action);await frames(3)
    actions[-1]["after"]=device.call("stage_snapshot")

func shot(label: String,settle: int=22,yaw: float=PI*.5) -> void:
    player.set("_camera_yaw_target",yaw);player.set("_camera_pitch_target",-.08)
    await frames(settle);await RenderingServer.frame_post_draw
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

func run() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    scene=(load("res://station.tscn") as PackedScene).instantiate() as Node3D;root.add_child(scene)
    await frames(35);player=scene.get("player") as CharacterBody3D;device=scene.get("device") as Node3D
    check(device!=null and device.get("core")!=null,"真实核心和设备已生成")
    var entry: bool=await travel("entry",Vector2(-9.25,-1.82))
    var aisle: bool=await travel("maintenance_aisle",Vector2(-5,-1.2))
    var align: bool=await travel("align_steps",Vector2(1,-1.1))
    await shot("00_approach",30,PI)
    var board: bool=await travel("physical_boarding",Vector2(1,1.42))
    check(entry and aisle and align and board and player.position.y>1.75 and player.is_on_floor(),"沿台阶真实登车并站立甲板")
    await shot("01_boarded");orbit()
    if not board or player.position.y<1.7:
        await finish();return
    await travel("empty_console",Vector2(-.75,1.85))
    await press("repair")
    check(str(device.get("feedback_code"))=="MISSING_CORE" and int(device.get("activation_count"))==0,"空槽激活被拒绝并说明缺芯")
    await shot("02_missing_core")
    await travel("core_tray",Vector2(.20,1.42))
    await press("pickup")
    check(str(device.get("phase"))=="held" and int(player.get("carrying"))==3,"F 拾取唯一能源核心并使用原携带字段")
    await shot("03_carrying");orbit()
    await travel("carry_and_turn",Vector2(.65,2.62))
    var core: RigidBody3D=device.get("core") as RigidBody3D
    check(core.position.distance_to(player.position)<1.6,"携带移动与转身时核心跟随玩家")
    await press("deposit")
    check(str(device.get("phase"))=="held" and str(device.get("feedback_code"))=="WRONG_SOCKET","错误位置 G 安装被拒绝且核心仍在手中")
    await shot("04_wrong_socket")
    player.set("_camera_yaw_target",-PI*.5);await frames(35)
    await press("drop");await frames(35)
    check(str(device.get("phase"))=="free" and int(player.get("carrying"))==0,"X 在支撑面放下核心且恢复自由状态")
    await shot("05_placed")
    await press("pickup")
    check(str(device.get("phase"))=="held","放下的同一核心可以重新拾取")
    await travel("socket_approach",Vector2(-1.22,2.20))
    var rev: int=int(device.get("revision"))
    device.call("handle_stage_action",2,"deposit",701,rev)
    check(str(device.get("phase"))=="held" and str(device.get("feedback_code"))=="NO_PLAYER","未登记玩家不能抢占或安装核心")
    device.call("handle_stage_action",1,"deposit",701,rev-1)
    check(str(device.get("phase"))=="held" and str(device.get("feedback_code"))=="STALE_REVISION","过期状态请求不改变核心归属")
    await press("deposit");check(str(device.get("phase"))=="inserting","G 在正确插槽开始连续定位动画")
    await frames(72)
    check(str(device.get("phase"))=="locked" and int(player.get("carrying"))==0 and core.position.distance_to(Vector3(-2.5,1.9646444,2.2))<.01,"安装完成、夹具锁定并清空手持状态")
    await shot("06_locked");orbit()
    await press("deposit");check(str(device.get("feedback_code"))=="SOCKET_LOCKED","重复安装被拒绝且不复制核心")
    await press("drop");check(str(device.get("phase"))=="locked","锁定后不能用 X 移走核心")
    await travel("operate_console",Vector2(-.75,1.85));player.set("_camera_yaw_target",PI*.5);await frames(30)
    await press("repair");check(str(device.get("phase"))=="starting","E 从车上控制台触发上电序列")
    await shot("07_lock_check",3)
    await frames(65);await shot("08_core_charge",3)
    await frames(65);await shot("09_ring_wave",3)
    await press("repair");check(str(device.get("feedback_code"))=="BUSY","上电过程中重复操作不会重启序列")
    await frames(155)
    check(str(device.get("phase"))=="active" and int(device.get("activation_count"))==1,"核心→环体→控制台按顺序进入已激活")
    await shot("10_active");orbit()
    await press("repair");check(str(device.get("phase"))=="active" and int(device.get("activation_count"))==1 and str(device.get("feedback_code"))=="ALREADY_ACTIVE","重复激活被拒绝、成功事件仅一次")
    var cross: bool=await travel("deck_walk_turn",Vector2(1,2.5))
    var exit_align: bool=await travel("deck_exit_align",Vector2(1,1.35))
    var off: bool=await travel("physical_disembark",Vector2(1,-1.75))
    check(cross and exit_align and off and player.position.y<.45 and player.is_on_floor(),"开放甲板可移动转身并完全离开踏步、回到站台")
    await shot("11_disembarked");orbit()
    check(camera_hits==0 and orbit_hits==0,"整条输入路线和甲板旋转检查未检测到相机穿模")
    check(held_overlap_frames==0,"携带移动时核心的碰撞包络未穿入栏杆或矿车")
    await finish()

func finish() -> void:
    var data: Dictionary={"passed":failed==0,"failures":failed,"checks":checks,"route":route,"samples":samples,"actions":actions,"events":device.get("events"),"final_state":device.call("stage_snapshot"),"camera_overlap_frames":camera_hits,"orbit_samples":orbit_samples,"orbit_overlaps":orbit_hits,"held_overlap_frames":held_overlap_frames,"note":"Player moves only via Input actions and CharacterBody3D physics. No player teleport or direct placement on cart. Direct adapter calls are only negative actor/revision tests."}
    var file: FileAccess=FileAccess.open(output.path_join("interaction-test.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
    print("INTERACTION_TEST_RESULT ",JSON.stringify({"passed":failed==0,"failures":failed,"checks":checks.size(),"camera_overlaps":camera_hits,"orbit_overlaps":orbit_hits}))
    scene.queue_free();await frames(3);quit(0 if failed==0 else 1)
