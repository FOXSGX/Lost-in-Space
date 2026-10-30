extends Node3D

# A single stage-device adapter using the formal project's action contract.
# State belongs to the host/device; the character only stores carrying kind/id.
const CORE_ID: int=701
const SOCKET: Vector3=Vector3(-2.5,1.9646444,2.2)
const CONSOLE: Vector3=Vector3(2.48,2.64,1.08)
const PRELOAD: Vector3=Vector3(-1.55,2.64,1.08)
const CORE_SCALE: float=0.72
var controller: Node3D
var player: CharacterBody3D
var core: RigidBody3D
var phase: String="free"
var carrier_id: int=0
var revision: int=0
var elapsed: float=0
var clock: float=0
var activation_count: int=0
var feedback: String="沿黄色踏步登车，取出检修托盘上的能源核心"
var feedback_code: String="WELCOME"
var events: Array[Dictionary]=[]
var parts: Dictionary={}
var sound: AudioStreamPlayer3D
var hum: AudioStreamPlayer3D
var font: Font
var socket_label: Label3D
var core_label: Label3D
var console_label: Label3D
var _insert_start: Vector3
var _core_materials: Array[ShaderMaterial]=[]
var _ring_materials: Array[ShaderMaterial]=[]
var _socket_materials: Array[ShaderMaterial]=[]
var _conduit_materials: Array[ShaderMaterial]=[]
var _screen_materials: Array[ShaderMaterial]=[]
var _claw_starts: Dictionary={}
var _lever_start: Basis
var _last_bank: int=-1
var _carry_shape: CapsuleShape3D
var carry_blocked_frames: int=0
var motion: RefCounted
var pending_place: Vector3
var actors: Dictionary={}
var calibration: RefCounted
var fx: Node3D
var event_id: int=0
var feedback_until: float=0
var snapshot_core: Transform3D
var received_snapshot: bool=false
var seen_event_id: int=0
var _hum_loaded: bool=false
var epoch: int=0

func setup(owner_node: Node3D,actor: CharacterBody3D,ui_font: Font) -> void:
    controller=owner_node;player=actor;font=ui_font

func _ready() -> void:
    var imported: Node3D=(load("res://assets/device_parts.glb") as PackedScene).instantiate() as Node3D
    add_child(imported)
    core=RigidBody3D.new();core.name="EnergyCore_701";core.mass=8
    core.freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC
    core.continuous_cd=true
    var physical: PhysicsMaterial=PhysicsMaterial.new();physical.friction=.9;physical.bounce=0.0;core.physics_material_override=physical
    core.collision_layer=8;core.collision_mask=2;core.linear_damp=4;core.angular_damp=6
    add_child(core)
    var shape: CapsuleShape3D=CapsuleShape3D.new();shape.radius=.245;shape.height=.99
    _carry_shape=shape
    var collider: CollisionShape3D=CollisionShape3D.new();collider.shape=shape;collider.position.y=.495;core.add_child(collider)
    var core_visual: Node3D=Node3D.new();core_visual.name="ApprovedV23Core";core_visual.scale=Vector3.ONE*CORE_SCALE;core.add_child(core_visual)
    for child: Node in imported.find_children("*","MeshInstance3D",true,false):
        var mesh: MeshInstance3D=child as MeshInstance3D
        var name_text: String=str(mesh.name)
        var role: String=name_text.trim_prefix("DYN_").split("__")[0]
        if role=="core":mesh.reparent(core_visual,false)
        parts[role]=mesh if not parts.has(role) else parts[role]
        var source: Material=mesh.get_active_material(0)
        var key: String=source.resource_name.trim_prefix("P11_")
        var profile: Dictionary=(controller.get("profiles") as Dictionary)[key] as Dictionary
        var material: ShaderMaterial=ShaderMaterial.new();material.shader=load("res://static_surface.gdshader") as Shader
        material.set_shader_parameter("agx_lut",load("res://assets/agx_medium_high.png"))
        material.set_shader_parameter("metallic",float(profile["metallic"]))
        material.set_shader_parameter("roughness",float(profile["roughness"]))
        material.set_shader_parameter("sourced_roughness",true)
        material.set_shader_parameter("log_irradiance",true)
        material.set_shader_parameter("emission_tint",Vector3.ONE)
        material.set_shader_parameter("dynamic_lighting",role=="core" or role.begins_with("claw") or role=="lever" or role=="rotor")
        material.set_shader_parameter("emission_gain",0.02)
        mesh.material_override=material
        if role=="core" and ("Core" in key or "Energy" in key):_core_materials.append(material)
        if role.begins_with("ring_"):
            material.set_shader_parameter("energy_surface",true)
            # Every quadrant owns one material, so the response travels around
            # the ring instead of recoloring the whole machine at once.
            var index: int=int(role.trim_prefix("ring_"))
            while _ring_materials.size()<=index:_ring_materials.append(null)
            _ring_materials[index]=material
        if role=="socket_light":
            _socket_materials.append(material);material.set_shader_parameter("energy_surface",true)
        if role=="conduit":
            _conduit_materials.append(material);material.set_shader_parameter("energy_surface",true)
        if role=="screen":_screen_materials.append(material)
        if role.begins_with("claw"):
            var center: Vector3=mesh.position+mesh.mesh.get_aabb().get_center()
            _claw_starts[mesh]={"position":mesh.position,"center":center}
        if role=="lever":
            var pivot: Node3D=Node3D.new();pivot.position=Vector3(2.37,2.422,1.15);add_child(pivot)
            mesh.reparent(pivot,false);mesh.position-=pivot.position;parts[role]=pivot;_lever_start=pivot.basis
    core.position=Vector3(.15,1.90,2.2)
    motion=(load("res://scripts/carry_motion.gd") as Script).new() as RefCounted;motion.call("setup",core,player)
    sound=AudioStreamPlayer3D.new();sound.name="DeviceFeedback";sound.position=SOCKET+Vector3.UP*.5;sound.max_distance=14;sound.volume_db=-7;add_child(sound)
    hum=AudioStreamPlayer3D.new();hum.position=SOCKET+Vector3.UP*.5;hum.volume_db=-14;hum.max_distance=10;add_child(hum)
    socket_label=_label("能源插槽 · 未安装",SOCKET+Vector3(0,1.1,0))
    console_label=_label("E · 共振控制台",CONSOLE+Vector3(0,.48,0))
    core_label=_label("F · 能源核心",Vector3.ZERO)
    actors[int(player.get("peer_id"))]=player
    calibration=(load("res://scripts/resonance_calibration.gd") as Script).new() as RefCounted
    fx=(load("res://scripts/device_motion.gd") as Script).new() as Node3D
    fx.call("setup",self);add_child(fx)
    snapshot_core=core.global_transform
    _feedback("WELCOME","WASD 移动 · 单击转身 · 沿黄色踏步登车");feedback_until=7.0
    _record("spawn",{"object_id":CORE_ID,"source":"V2.3 extracted core x0.72"})

func _label(text: String,at: Vector3) -> Label3D:
    var label: Label3D=Label3D.new();label.text=text;label.font=font;label.font_size=25;label.pixel_size=.0024;label.outline_size=5
    label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("#b2f2f2");label.position=at;add_child(label);return label

func register_actor(actor: CharacterBody3D) -> void:
    actors[int(actor.get("peer_id"))]=actor

func unregister_actor(peer_id: int) -> void:
    if not actors.has(peer_id):return
    calibration.call("release",peer_id)
    if carrier_id==peer_id:
        core.freeze=false;core.collision_layer=8;core.linear_velocity=Vector3.ZERO
        phase="free";carrier_id=0;elapsed=0;revision+=1;_record("carrier_disconnected",{"peer_id":peer_id})
    actors.erase(peer_id)
    _sync_actor_fields()

func on_deck(actor: CharacterBody3D=null) -> bool:
    if actor==null:actor=player
    var supported: bool=actor.is_on_floor()
    if not bool(actor.get("is_local_actor")):
        var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.18,actor.position-Vector3.UP*.22,2,[actor.get_rid()])
        supported=not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
    return actor.position.y>1.58 and absf(actor.position.x)<3.7 and actor.position.z>.62 and actor.position.z<3.7 and supported

func can_reach(actor: CharacterBody3D,at: Vector3,limit: float=1.65) -> bool:
    var from: Vector3=actor.global_position+Vector3.UP*.85
    if from.distance_to(at)>limit:return false
    var flat: Vector3=at-actor.global_position;flat.y=0
    if flat.length()>.15 and (-actor.global_basis.z).dot(flat.normalized())<.10:return false
    var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(from,at,2,[actor.get_rid(),core.get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
    return hit.is_empty() or (hit["position"] as Vector3).distance_to(at)<.30

func _facing(actor: CharacterBody3D,at: Vector3,threshold: float=.45) -> bool:
    var direction: Vector3=at-actor.global_position;direction.y=0
    return direction.length()<.15 or (-actor.global_basis.z).dot(direction.normalized())>threshold

func control_anchor(role: String) -> Vector3:
    return CONSOLE if role=="frequency" else PRELOAD

func _near_control(actor: CharacterBody3D) -> String:
    var best: float=100.0;var selected: String=""
    for role: String in ["frequency","preload"]:
        var anchor: Vector3=control_anchor(role)
        var distance: float=(actor.position+Vector3.UP*.85).distance_to(anchor)
        if distance<best and can_reach(actor,anchor,1.55):best=distance;selected=role
    return selected

func get_stage_action_target(peer_id: int,action: String) -> Dictionary:
    var actor: CharacterBody3D=actors.get(peer_id) as CharacterBody3D
    if actor==null:return {}
    if action=="pickup" and phase=="free" and can_reach(actor,core.global_position+Vector3.UP*.48):return {"target_id":CORE_ID,"kind":"core"}
    if action=="deposit" and can_reach(actor,SOCKET+Vector3.UP*.45):return {"target_id":CORE_ID,"kind":"socket"}
    if action=="repair":
        var role: String=_near_control(actor)
        if role!="":return {"target_id":1 if role=="frequency" else 2,"kind":role}
    if action=="drop":return {"target_id":CORE_ID,"kind":"drop"}
    return {}

func handle_stage_action(peer_id: int,action: String,target_id: int=0,expected_revision: int=-1) -> bool:
    if not multiplayer.is_server():return _reject("AUTHORITY_REQUIRED","等待主机确认")
    var actor: CharacterBody3D=actors.get(peer_id) as CharacterBody3D
    if actor==null:return _reject("NO_PLAYER","未登记的操作者")
    if expected_revision>=0 and expected_revision!=revision:return _reject("STALE_REVISION","状态已更新，请重试")
    if action in ["pickup","deposit"] and target_id!=0 and target_id!=CORE_ID:return _reject("WRONG_OBJECT","核心身份不匹配")
    if action=="reset":
        if peer_id!=1:return _reject("HOST_RESET_ONLY","由主机复位设备")
        reset_device();return true
    if action=="cancel":
        if str(calibration.call("role_of",peer_id))=="" and _near_control(actor)=="":return _reject("OUT_OF_REACH","靠近控制端才能停机")
        calibration.call("release",peer_id)
        if phase in ["calibrating","charging"]:
            calibration=(load("res://scripts/resonance_calibration.gd") as Script).new() as RefCounted
            _set_phase("locked");_feedback("CANCELLED","已停机，核心保持锁定");_record("calibration_cancelled",{"peer_id":peer_id})
        _sync_actor_fields();return true
    if action=="drop":return _drop(peer_id,actor)
    if action=="pickup":
        if phase!="free":return _reject("ALREADY_CARRYING" if phase=="held" else "CORE_LOCKED","核心已被持有或锁定")
        if not can_reach(actor,core.position+Vector3.UP*.48):return _reject("OUT_OF_REACH","面向核心并靠近握把")
        if int(actor.get("carrying"))!=0:return _reject("HANDS_BUSY","双手正在占用")
        carrier_id=peer_id;_set_phase("held");core.freeze=true;core.collision_layer=0;core.linear_velocity=Vector3.ZERO;core.angular_velocity=Vector3.ZERO
        motion.set("actor",actor);motion.call("begin_hold");_sync_actor_fields()
        _feedback("PICKED_UP","核心有重量 · 转身时留出空间");_play("latch");_record("pickup",{"peer_id":peer_id});return true
    if action=="deposit":
        if phase in ["inserting","locking","locked","calibrating","charging","stable"]:return _reject("SOCKET_LOCKED","插槽已占用")
        if phase!="held" or carrier_id!=peer_id:return _reject("NOT_CARRYING","先拿起能源核心")
        if not on_deck(actor) or not can_reach(actor,SOCKET+Vector3.UP*.45):return _reject("WRONG_SOCKET","将核心送到共振环底座")
        if not _facing(actor,SOCKET,.45):return _reject("WRONG_ANGLE","面向插槽再送入核心")
        _insert_start=core.global_position;_set_phase("inserting");_sync_actor_fields()
        _feedback("INSERTING","导轨定位");_play("latch");_record("insert_begin",{"peer_id":peer_id});return true
    if action=="repair":
        if phase in ["inserting","locking"]:return _reject("NOT_LOCKED","等待锁爪闭合")
        if phase=="charging":return _reject("BUSY","正在充能")
        if phase=="stable":return _reject("ALREADY_ACTIVE","系统已经稳定")
        var previous: String=str(calibration.call("role_of",peer_id))
        if previous!="":
            calibration.call("release",peer_id);revision+=1;_sync_actor_fields()
            _feedback("SOLO_HOLD" if float(calibration.get("solo_hold_until"))>float(calibration.get("clock")) else "CONTROL_RELEASED","预载暂时锁存 · 前往前端调频" if previous=="preload" and actors.size()==1 else "已离开控制位")
            _record("control_released",{"peer_id":peer_id,"role":previous});return true
        var role: String=_near_control(actor)
        if role=="" or not on_deck(actor):return _reject("OUT_OF_REACH","面向控制设备并靠近")
        if phase not in ["locked","calibrating"]:return _reject("MISSING_CORE","先安装并锁定核心")
        if phase=="locked":calibration.call("begin",actors.size());_set_phase("calibrating");_record("calibration_begin",{})
        if not bool(calibration.call("claim",peer_id,role)):return _reject("CONTROL_BUSY","另一位船员正在操作此端")
        revision+=1;_sync_actor_fields();_feedback("CONTROL_CLAIMED","A/D 调频" if role=="frequency" else "W/S 调预载 · 单人调好后 E 锁存")
        _play("latch");_record("control_claimed",{"peer_id":peer_id,"role":role});return true
    return _reject("INVALID_ACTION","当前状态不能执行")

func submit_axis(peer_id: int,value: float) -> bool:
    if not multiplayer.is_server():return false
    var actor: CharacterBody3D=actors.get(peer_id) as CharacterBody3D
    var role: String=str(calibration.call("role_of",peer_id))
    if actor==null or role=="" or phase!="calibrating":return false
    if (actor.position+Vector3.UP*.85).distance_to(control_anchor(role))>1.8:
        calibration.call("release",peer_id);_sync_actor_fields();return false
    return bool(calibration.call("input_axis",peer_id,value))

func _drop(peer_id: int,actor: CharacterBody3D) -> bool:
    if phase!="held" or carrier_id!=peer_id:return _reject("NOT_HELD","没有可放下的核心")
    var spot: Vector3=actor.global_position-actor.global_basis.z*.85
    var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(spot+Vector3.UP*1.3,spot-Vector3.UP*1.1,2,[actor.get_rid(),core.get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty():return _reject("UNSAFE_DROP","前方没有支撑面")
    var at: Vector3=hit["position"] as Vector3;var normal: Vector3=hit["normal"] as Vector3
    if absf(normal.y)<.75 or absf(at.y-actor.position.y)>.45:return _reject("UNSAFE_DROP","放置坡度或落差过大")
    if not bool(motion.call("prepare_place",at)):return _reject("BLOCKED_DROP","放置路径被挡住 · 等待核心到位再试")
    pending_place=at;_set_phase("placing");_sync_actor_fields();_feedback("PLACING","缓缓放下");_record("place_begin",{"peer_id":peer_id});return true

func _set_phase(next: String) -> void:
    phase=next;elapsed=0;revision+=1

func _sync_actor_fields() -> void:
    for id: int in actors:
        var actor: CharacterBody3D=actors[id] as CharacterBody3D
        var held: bool=carrier_id==id and phase in ["held","placing","inserting"]
        actor.set("carrying",3 if held else 0);actor.set("carrying_id",CORE_ID if held else 0)
        actor.set("operating_role",str(calibration.call("role_of",id)))
        actor.set("interaction_locked",held and phase in ["placing","inserting"])

func _physics_process(delta: float) -> void:
    if core==null:return
    clock+=delta;elapsed+=delta
    if not multiplayer.is_server():
        core.freeze=true;core.global_transform=core.global_transform.interpolate_with(snapshot_core,1-exp(-18*delta))
        _visuals(delta);return
    if phase=="held":motion.call("tick_hold",delta)
    elif phase=="placing":
        if bool(motion.call("tick_place",delta)):
            carrier_id=0;_set_phase("free");_sync_actor_fields();_feedback("PLACED","已放下 · 可重新拾取");_play("latch");_record("drop",{"position":_array(core.position)})
    elif phase=="free":
        core.linear_velocity=core.linear_velocity.limit_length(6);core.angular_velocity=core.angular_velocity.limit_length(3)
        if core.position.y< -3 or absf(core.position.x)>21 or absf(core.position.z)>14:
            core.position=Vector3(.15,1.90,2.2);core.linear_velocity=Vector3.ZERO;core.angular_velocity=Vector3.ZERO;revision+=1;_record("recovered",{})
    elif phase=="inserting":
        var t: float=clampf(elapsed/1.05,0,1);var eased: float=t*t*(3-2*t)
        core.global_position=_insert_start.lerp(SOCKET,eased)+Vector3.UP*sin(t*PI)*.20
        core.global_rotation=core.global_rotation.lerp(Vector3.ZERO,minf(1,delta*9))
        if t>=1:
            core.global_position=SOCKET;core.global_rotation=Vector3.ZERO;core.collision_layer=6;carrier_id=0
            _set_phase("locking");_sync_actor_fields();_feedback("LOCKING","锁爪闭合");_play("latch");_record("core_inserted",{})
    elif phase=="locking":
        if elapsed>.65:_set_phase("locked");_feedback("LOCKED","锁定完成 · 两端校准");_record("core_locked",{})
    elif phase=="calibrating":
        if bool(calibration.call("tick",delta,actors.size())):
            for id: int in actors:calibration.call("release",id)
            _set_phase("charging");_sync_actor_fields();_last_bank=-1;_feedback("CHARGING","校准通过 · 能量接通");_play("charge");_record("charging_begin",{})
    elif phase=="charging":
        var bank: int=clampi(int((elapsed-.85)/.45)+1,0,4) if elapsed>=.85 else 0
        if bank>_last_bank and bank>0:_last_bank=bank;_play("segment");_record("ring_bank",{"bank":bank})
        if elapsed>=3.6:
            _set_phase("stable");activation_count+=1;_feedback("STABLE","共振稳定 · 矿车系统就绪");_play("ready");_record("stable",{"activation_count":activation_count})
    _visuals(delta)

func _visuals(delta: float) -> void:
    var progress: float=float(calibration.get("progress"))
    var charge: float=clampf(elapsed/1.6,0.0,1.0) if phase=="charging" else (1.0 if phase=="stable" else progress*.35)
    for mat: ShaderMaterial in _core_materials:mat.set_shader_parameter("emission_gain",.18+charge*1.8+(.08*sin(clock*2.5) if phase=="held" else 0.0))
    for i: int in range(_ring_materials.size()):
        var power: float=.0
        if phase=="stable":power=.85+.06*sin(clock*2-float(i)*1.3)
        elif phase=="charging":power=clampf((elapsed-.85-float(i)*.45)/.45,0,1)
        elif phase=="calibrating":power=.10+progress*.25+.04*sin(clock*3+float(i))
        if _ring_materials[i]!=null:
            _ring_materials[i].set_shader_parameter("emission_gain",.01+power*1.7);_ring_materials[i].set_shader_parameter("power_level",power)
    var locked: bool=phase in ["locked","calibrating","charging","stable"]
    for mat: ShaderMaterial in _socket_materials:
        mat.set_shader_parameter("emission_gain",.65 if locked else .03);mat.set_shader_parameter("power_level",.65 if locked else .03)
    for mat: ShaderMaterial in _conduit_materials:
        mat.set_shader_parameter("emission_gain",charge*1.5+.015);mat.set_shader_parameter("power_level",charge)
    for mat: ShaderMaterial in _screen_materials:mat.set_shader_parameter("emission_gain",.65 if phase=="stable" else .12+progress*.35)
    var closed: float=smoothstep(0.0,.65,elapsed) if phase=="locking" else (1.0 if locked else 0.0)
    for raw: Variant in _claw_starts:
        var mesh: MeshInstance3D=raw as MeshInstance3D;var row: Dictionary=_claw_starts[mesh] as Dictionary;var start: Vector3=row["position"] as Vector3
        var center: Vector3=row["center"] as Vector3
        mesh.position=start+Vector3(SOCKET.x-center.x,0,SOCKET.z-center.z).normalized()*.10*closed
    core_label.position=core.position+Vector3.UP*1.08
    core_label.visible=phase=="free" and can_reach(player,core.position+Vector3.UP*.48)
    core_label.text="F · 核心"
    socket_label.visible=phase=="held" and can_reach(player,SOCKET+Vector3.UP*.45)
    socket_label.text="G · 导轨对齐"
    console_label.visible=false
    if phase in ["calibrating","charging","stable"]:
        if not _hum_loaded:
            var stream: AudioStreamWAV=load("res://assets/audio/hum.wav") as AudioStreamWAV
            stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=96000;hum.stream=stream;_hum_loaded=true
        if not hum.playing:hum.play()
        hum.pitch_scale=.65+charge*.45;hum.volume_db=-24+charge*8
    elif hum.playing:hum.stop()
    if fx!=null:fx.call("tick",delta)

func carry_facing_yaw(actor: CharacterBody3D,desired: float) -> float:
    if phase!="held" or int(actor.get("peer_id"))!=carrier_id:return desired
    var bearing: Vector3=core.position-actor.position;bearing.y=0
    if bearing.length()<.25:return desired
    var yaw: float=atan2(-bearing.x,-bearing.z)
    return yaw+clampf(wrapf(desired-yaw,-PI,PI),-.50,.50)

func carrier_motion_fraction(actor: CharacterBody3D,displacement: Vector3) -> float:
    if phase!="held" or int(actor.get("peer_id"))!=carrier_id:return 1
    var query: PhysicsShapeQueryParameters3D=motion.call("query",core.position) as PhysicsShapeQueryParameters3D;query.motion=displacement
    var cast: PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(query)
    return maxf(0.0,cast[0]-.006) if not cast.is_empty() else 1.0

func held_overlaps() -> bool:return phase=="held" and bool(motion.call("overlaps"))

func prompt(peer_id: int=0) -> String:
    if peer_id==0:peer_id=int(player.get("peer_id"))
    var role: String=str(calibration.call("role_of",peer_id))
    if role!="":return ("A / D 调频率" if role=="frequency" else "W / S 调预载")+"   E 离开   C 停机"
    if phase=="held" and carrier_id==peer_id:return ("G 安装   " if not get_stage_action_target(peer_id,"deposit").is_empty() else "")+"X 放下"
    if phase in ["placing","inserting","locking"]:return "正在定位 / 锁止"
    if phase=="stable":return "共振稳定 · 系统就绪"
    var target: Dictionary=get_stage_action_target(peer_id,"repair")
    if not target.is_empty():return "E 调谐频率" if str(target["kind"])=="frequency" else "E 调整锁爪预载"
    if not get_stage_action_target(peer_id,"pickup").is_empty():return "F 拾取核心"
    if phase=="calibrating" and actors.size()==1 and float(calibration.get("solo_hold_until"))>float(calibration.get("clock")):return "预载已锁存 · 前往矿车前端调频"
    return ""

func objective() -> String:
    if phase=="stable":return "共振稳定 · 矿车系统就绪"
    if phase in ["locked","calibrating"]:return "协调频率与锁爪预载"
    if phase=="charging":return "能量接通"
    return "将核心送入共振环底座"

func reset_device() -> void:
    calibration=(load("res://scripts/resonance_calibration.gd") as Script).new() as RefCounted
    carrier_id=0;activation_count=0;epoch+=1;_set_phase("free");_sync_actor_fields()
    core.freeze=false;core.collision_layer=8;core.position=Vector3(.15,1.90,2.2);core.rotation=Vector3.ZERO;core.linear_velocity=Vector3.ZERO;core.angular_velocity=Vector3.ZERO
    sound.stop();hum.stop();_feedback("RESET","设备已复位");_record("reset",{"epoch":epoch})

func stage_snapshot() -> Dictionary:
    var carried: Dictionary={}
    for id: int in actors:carried[id]=[actors[id].get("carrying"),actors[id].get("carrying_id"),actors[id].get("operating_role")]
    return {"object_id":CORE_ID,"phase":phase,"carrier_id":carrier_id,"revision":revision,"epoch":epoch,"clock":clock,"elapsed":elapsed,"core_position":_array(core.position),"core_rotation":_array(core.rotation),"activation_count":activation_count,"feedback_code":feedback_code,"feedback":feedback,"feedback_until":feedback_until,"calibration":calibration.call("snapshot"),"actors":carried,"event_id":event_id,"recent_events":events.slice(maxi(0,events.size()-8)),"mechanics":fx.call("snapshot")}

func apply_stage_snapshot(data: Dictionary) -> void:
    if int(data.get("revision",-1))<revision:return
    phase=str(data["phase"]);carrier_id=int(data["carrier_id"]);revision=int(data["revision"]);epoch=int(data["epoch"])
    clock=float(data["clock"]);elapsed=float(data["elapsed"]);activation_count=int(data["activation_count"])
    feedback_code=str(data["feedback_code"]);feedback=str(data["feedback"]);feedback_until=float(data["feedback_until"])
    calibration.call("apply_snapshot",data["calibration"])
    fx.call("apply_motion_snapshot",data["mechanics"],not received_snapshot)
    snapshot_core=Transform3D(Basis.from_euler(_vec(data["core_rotation"])),_vec(data["core_position"]))
    core.collision_layer=6 if phase in ["locking","locked","calibrating","charging","stable"] else (0 if phase in ["held","placing","inserting"] else 8)
    if not received_snapshot:core.global_transform=snapshot_core;seen_event_id=int(data["event_id"]);received_snapshot=true
    for raw: Dictionary in data["recent_events"]:
        if int(raw["id"])>seen_event_id and str(raw["event"])=="sound":_play(str((raw["details"] as Dictionary)["cue"]),false)
    seen_event_id=int(data["event_id"]);event_id=seen_event_id
    _sync_actor_fields()

func _array(v: Vector3) -> Array:return [v.x,v.y,v.z]
func _vec(v: Array) -> Vector3:return Vector3(float(v[0]),float(v[1]),float(v[2]))
func _feedback(code: String,text: String) -> void:feedback_code=code;feedback=text;feedback_until=clock+2.8
func _reject(code: String,text: String) -> bool:
    _feedback(code,text);_record("rejected",{"reason":code});_play("error");return false
func _record(event: String,details: Dictionary) -> void:
    event_id+=1;events.append({"id":event_id,"t":clock,"frame":Engine.get_frames_drawn(),"event":event,"phase":phase,"revision":revision,"details":details})
    if events.size()>512:events.pop_front()
func _play(cue: String,record: bool=true) -> void:
    sound.stream=load("res://assets/audio/"+cue+".wav") as AudioStreamWAV;sound.play()
    if record:_record("sound",{"cue":cue})
