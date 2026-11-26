extends Node3D

# A single stage-device adapter using the formal project's action contract.
# State belongs to the host/device; the character only stores carrying kind/id.
const CORE_ID: int=701
const SOCKET: Vector3=Vector3(-2.5,1.9646444,2.2)
const CONSOLE: Vector3=Vector3(-1.4,2.60,1.15)
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

func setup(owner_node: Node3D,actor: CharacterBody3D,ui_font: Font) -> void:
    controller=owner_node;player=actor;font=ui_font

func _ready() -> void:
    var imported: Node3D=(load("res://assets/device_parts.glb") as PackedScene).instantiate() as Node3D
    add_child(imported)
    core=RigidBody3D.new();core.name="EnergyCore_701";core.mass=8
    core.freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC
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
        material.set_shader_parameter("dynamic_lighting",role=="core" or role.begins_with("claw") or role=="lever")
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
    sound=AudioStreamPlayer3D.new();sound.name="DeviceFeedback";sound.position=SOCKET+Vector3.UP*.5;sound.max_distance=14;sound.volume_db=-7;add_child(sound)
    hum=AudioStreamPlayer3D.new();hum.position=SOCKET+Vector3.UP*.5;hum.volume_db=-14;hum.max_distance=10;add_child(hum)
    socket_label=_label("能源插槽 · 未安装",SOCKET+Vector3(0,1.1,0))
    console_label=_label("E · 共振控制台",CONSOLE+Vector3(0,.48,0))
    core_label=_label("F · 能源核心",Vector3.ZERO)
    _record("spawn",{"object_id":CORE_ID,"source":"V2.3 extracted core x0.72"})

func _label(text: String,at: Vector3) -> Label3D:
    var label: Label3D=Label3D.new();label.text=text;label.font=font;label.font_size=28;label.pixel_size=.0032;label.outline_size=6
    label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("#b2f2f2");label.position=at;add_child(label);return label

func on_deck() -> bool:
    return player.position.y>1.58 and absf(player.position.x)<3.7 and player.position.z>.62 and player.position.z<3.7 and player.is_on_floor()

func _reach(at: Vector3,limit: float=1.65) -> bool:
    var from: Vector3=player.global_position+Vector3.UP*.85
    if from.distance_to(at)>limit:return false
    var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(from,at,2,[player.get_rid(),core.get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
    # The selected target's own housing may be the last 0.3m of the ray.
    return hit.is_empty() or (hit["position"] as Vector3).distance_to(at)<.30

func get_stage_action_target(peer_id: int,action: String) -> Dictionary:
    if peer_id!=int(player.get("peer_id")):return {}
    if action=="pickup" and phase=="free" and _reach(core.global_position+Vector3.UP*.48):return {"puzzle_id":"energy_core","target_id":CORE_ID,"kind":"core"}
    if action=="deposit" and _reach(SOCKET+Vector3.UP*.45):return {"puzzle_id":"station_socket","target_id":CORE_ID,"kind":"socket"}
    if action=="repair" and _reach(CONSOLE,1.5):return {"puzzle_id":"station_resonator","target_id":1,"kind":"console"}
    if action=="drop":return {"puzzle_id":"carry","target_id":CORE_ID,"kind":"drop"}
    return {}

func handle_stage_action(peer_id: int,action: String,target_id: int=0,expected_revision: int=-1) -> bool:
    if not multiplayer.is_server():return _reject("AUTHORITY_REQUIRED","设备状态由主机维护")
    if peer_id!=int(player.get("peer_id")):return _reject("NO_PLAYER","未登记的操作玩家")
    if action in ["pickup","deposit"] and target_id!=0 and target_id!=CORE_ID:return _reject("WRONG_OBJECT","能源核心标识与插槽不匹配")
    if expected_revision>=0 and expected_revision!=revision:return _reject("STALE_REVISION","设备状态已改变，请重新操作")
    if action=="drop":return _drop(peer_id)
    if action=="pickup" and phase=="held":return _reject("ALREADY_CARRYING","正在搬运核心 · G 安装 / X 安全放下")
    # Installation and controls belong to the cart; a dropped portable core
    # remains recoverable from the floor under the same reach/occlusion checks.
    if not on_deck() and action!="pickup":return _reject("BOARD_FIRST","请沿台阶登车后操作能源设备")
    var target: Dictionary=get_stage_action_target(peer_id,action)
    if action=="repair" and (phase=="starting" or phase=="active"):
        return _reject("ALREADY_ACTIVE","共振装置正在运行，无需重复激活") if phase=="active" else _reject("BUSY","上电序列进行中，请等待稳定")
    if action=="deposit":
        if phase in ["inserting","locked","starting","active"]:return _reject("SOCKET_LOCKED","能源核心已锁定，禁止重复安装")
        if phase!="held" or carrier_id!=peer_id:return _reject("NOT_CARRYING","请先按 F 拿起托盘上的能源核心")
        if target.is_empty():return _reject("WRONG_SOCKET","此处不是能源插槽 · 将核心送到共振环下方")
        _insert_start=core.global_position;phase="inserting";elapsed=0;revision+=1
        _feedback("INSERTING","对准插槽 · 核心下降定位");_play("latch");_record("insert_begin",{"target_id":target_id});return true
    if target.is_empty():return _reject("OUT_OF_REACH","请靠近设备，保持高度和操作路线无遮挡")
    if action=="pickup" and phase=="free":
        if int(player.get("carrying"))!=0:return _reject("HANDS_BUSY","双手正在占用")
        phase="held";carrier_id=peer_id;revision+=1;core.freeze=true;core.collision_layer=0;core.linear_velocity=Vector3.ZERO;core.angular_velocity=Vector3.ZERO
        player.set("carrying",3);player.set("carrying_id",CORE_ID)
        _feedback("PICKED_UP","核心已接入握把 · G 安装到指定插槽 / X 放下");_play("latch");_record("pickup",{"peer_id":peer_id});return true
    if action=="repair":
        if phase!="locked":return _reject("MISSING_CORE","插槽缺少已锁定的核心 · 先 F 拾取，再 G 安装")
        phase="starting";elapsed=0;revision+=1;_last_bank=-1
        _feedback("STARTING","① 锁止检查 · 正在确认机械夹具");_play("latch");_record("activation_begin",{});return true
    return _reject("INVALID_ACTION","当前设备状态不支持这项操作")

func _drop(peer_id: int) -> bool:
    if phase!="held" or carrier_id!=peer_id:return _reject("NOT_HELD","当前没有可放下的核心；已锁定核心不能移动")
    var forward: Vector3=-player.global_basis.z
    var spot: Vector3=player.global_position+forward*.85
    var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(spot+Vector3.UP*1.3,spot-Vector3.UP*1.1,2,[player.get_rid(),core.get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty():return _reject("UNSAFE_DROP","前方没有可放置表面 · 核心继续由你持有")
    var at: Vector3=hit["position"] as Vector3
    var normal: Vector3=hit["normal"] as Vector3
    if absf(normal.y)<.75 or absf(at.y-player.position.y)>.45:return _reject("UNSAFE_DROP","放置高度或坡度不安全 · 换一处平整位置")
    var shape: CapsuleShape3D=CapsuleShape3D.new();shape.radius=.25;shape.height=.99
    var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.515);query.collision_mask=2;query.exclude=[player.get_rid(),core.get_rid()]
    if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return _reject("BLOCKED_DROP","放置空间被机械结构占用 · 核心继续由你持有")
    core.global_position=at+Vector3.UP*.025;core.global_rotation=Vector3(0,player.rotation.y,0);core.freeze=false;core.collision_layer=8;core.sleeping=false;core.linear_velocity=Vector3.ZERO
    phase="free";carrier_id=0;revision+=1;player.set("carrying",0);player.set("carrying_id",0)
    _feedback("PLACED","核心已放在支撑面 · 靠近按 F 可重新拾取");_play("latch");_record("drop",{"position":_array(core.position)});return true

func _physics_process(delta: float) -> void:
    if core==null:return
    clock+=delta;elapsed+=delta
    if phase=="held":
        var desired: Vector3=_safe_carry_target()
        var motion: Vector3=core.global_position.lerp(desired,1-exp(-12*delta))-core.global_position
        var query: PhysicsShapeQueryParameters3D=_carry_query(core.global_position)
        query.motion=motion
        var cast: PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(query)
        var fraction: float=cast[0] if not cast.is_empty() else 1.0
        core.global_position+=motion*maxf(0.0,fraction-.005)
        core.global_rotation=Vector3(0,player.rotation.y,0)
    elif phase=="inserting":
        var t: float=clampf(elapsed/1.05,0,1);var eased: float=t*t*(3-2*t)
        core.global_position=_insert_start.lerp(SOCKET,eased)+Vector3.UP*sin(t*PI)*.20
        core.global_rotation=core.global_rotation.lerp(Vector3.ZERO,minf(1,delta*9))
        if t>=1:
            core.global_position=SOCKET;core.global_rotation=Vector3.ZERO;core.collision_layer=6
            phase="locked";elapsed=0;carrier_id=0;revision+=1;player.set("carrying",0);player.set("carrying_id",0)
            _feedback("LOCKED","核心已锁定 · 前往共振控制台按 E 上电");_play("latch");_record("core_locked",{})
    elif phase=="starting":
        if elapsed>=.6 and _last_bank<0:
            _last_bank=0;_feedback("CHARGING","② 核心充能 · 能量流入环体底座");_play("charge");_record("core_charge",{})
        if elapsed>=2.05:
            var bank: int=mini(4,int((elapsed-2.05)/.45)+1)
            if bank>_last_bank:
                _last_bank=bank;_feedback("RING_BANK","③ 环体响应 · %d / 4 区段接通" % bank);_play("segment");_record("ring_bank",{"bank":bank})
        if elapsed>=4.5:
            phase="active";activation_count+=1;revision+=1;elapsed=0
            _feedback("ACTIVE","共振装置已激活 · 核心锁定，能量输出稳定");_play("ready");_record("active",{"activation_count":activation_count})
            var stream: AudioStreamWAV=load("res://assets/audio/hum.wav") as AudioStreamWAV
            stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=96000;hum.stream=stream;hum.play()
    _visuals()
    core_label.position=core.global_position+Vector3.UP*1.22
    core_label.visible=phase=="free" and player.position.distance_to(core.position)<3.5
    socket_label.visible=on_deck() and phase in ["held","inserting","locked"]
    console_label.visible=on_deck() and phase!="held" and phase!="inserting"

func _carry_query(at: Vector3) -> PhysicsShapeQueryParameters3D:
    var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new()
    query.shape=_carry_shape;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.495);query.collision_mask=2;query.margin=.005;query.exclude=[player.get_rid(),core.get_rid()]
    return query

func _safe_carry_target() -> Vector3:
    for offset: Vector2 in [Vector2(.36,.45),Vector2(.05,.58),Vector2(0,.45)]:
        var at: Vector3=player.global_position-player.global_basis.z*offset.y+player.global_basis.x*offset.x+Vector3.UP*.35
        if get_world_3d().direct_space_state.intersect_shape(_carry_query(at),1).is_empty():return at
    carry_blocked_frames+=1
    return core.global_position

func held_overlaps() -> bool:
    return phase=="held" and not get_world_3d().direct_space_state.intersect_shape(_carry_query(core.global_position),1).is_empty()

func _visuals() -> void:
    var charge: float=clampf((elapsed-.6)/1.4,0,1) if phase=="starting" else (1.0 if phase=="active" else 0.0)
    for mat: ShaderMaterial in _core_materials:mat.set_shader_parameter("emission_gain",.22+charge*2.0+(.12*sin(clock*2.5) if phase=="held" else 0.0))
    for i: int in range(_ring_materials.size()):
        var gain: float=.015
        if phase=="active":gain=1.7+.2*sin(clock*2.8-float(i)*1.4)
        elif phase=="starting":gain=.015+1.8*clampf((elapsed-2.05-float(i)*.45)/.35,0,1)
        if _ring_materials[i]!=null:_ring_materials[i].set_shader_parameter("emission_gain",gain)
        if _ring_materials[i]!=null:_ring_materials[i].set_shader_parameter("power_level",clampf((gain-.015)/1.7,0,1))
    for mat: ShaderMaterial in _socket_materials:
        mat.set_shader_parameter("emission_gain",.65 if phase in ["locked","starting","active"] else .03)
        mat.set_shader_parameter("power_level",.65 if phase in ["locked","starting","active"] else .03)
    for mat: ShaderMaterial in _conduit_materials:
        mat.set_shader_parameter("emission_gain",charge*1.7+.015);mat.set_shader_parameter("power_level",charge)
    for mat: ShaderMaterial in _screen_materials:mat.set_shader_parameter("emission_gain",1.2 if phase=="active" else .14)
    var closed: float=clampf(elapsed/.5,0,1) if phase=="locked" else (1.0 if phase in ["starting","active"] else 0.0)
    for raw: Variant in _claw_starts:
        var mesh: MeshInstance3D=raw as MeshInstance3D;var row: Dictionary=_claw_starts[mesh] as Dictionary;var start: Vector3=row["position"] as Vector3
        var center: Vector3=row["center"] as Vector3
        var delta: Vector3=Vector3(SOCKET.x-center.x,0,SOCKET.z-center.z).normalized()*.10
        mesh.position=start+delta*closed
    if parts.has("lever"):(parts["lever"] as Node3D).basis=_lever_start*Basis(Vector3.FORWARD,-.26*(1 if phase in ["starting","active"] else 0))
    socket_label.text="能源插槽 · "+("已锁定" if phase in ["locked","starting","active"] else "G 安装核心")
    console_label.text="共振控制台 · "+("已激活" if phase=="active" else ("上电中" if phase=="starting" else "E 操作"))

func prompt() -> String:
    if not on_deck():
        if phase=="free" and _reach(core.position+Vector3.UP*.48):return "F 重新拾取能源核心 · 上车后可 G 安装"
        if phase=="held":return "核心可随身携带 · 上车后 G 安装 / X 安全放下"
        return "沿黄色踏步登车 · WASD 移动 / 鼠标转身"
    if phase=="held":return "G 安装到指定插槽    X 安全放下    F 查看搬运状态"
    if phase=="inserting":return "正在定位并锁定核心 · 请等待夹具闭合"
    if phase=="starting":return "上电序列进行中 · 机械锁止 → 核心充能 → 环体接通"
    if phase=="active":return "操作完成 · 设备已稳定    可沿台阶下车"
    if not get_stage_action_target(1,"repair").is_empty():return "E 操作共振控制台"+(" · 核心已锁定" if phase=="locked" else " · 插槽缺少核心")
    if not get_stage_action_target(1,"pickup").is_empty():return "F 拿起能源核心"
    return "靠近托盘按 F 拿核心，再将核心送入共振环底座"

func objective() -> String:
    if phase=="active":return "✓ 共振输出稳定"
    if phase in ["locked","starting"]:return "③ 在车上控制台启动共振装置"
    if phase in ["held","inserting"]:return "② 将核心安装到共振环下方的插槽"
    return "① 找回地面上的能源核心" if core.position.y<1.4 else "① 沿台阶登车，拿起托盘上的能源核心"

func stage_snapshot() -> Dictionary:
    return {"object_id":CORE_ID,"phase":phase,"carrier_id":carrier_id,"revision":revision,"elapsed":elapsed,"core_position":_array(core.position),"activation_count":activation_count,"player_carrying":player.get("carrying"),"feedback_code":feedback_code}

func _array(v: Vector3) -> Array:return [v.x,v.y,v.z]
func _feedback(code: String,text: String) -> void:feedback_code=code;feedback=text
func _reject(code: String,text: String) -> bool:
    _feedback(code,text);_record("rejected",{"reason":code});_play("error");return false
func _record(event: String,details: Dictionary) -> void:
    events.append({"t":clock,"frame":Engine.get_frames_drawn(),"event":event,"phase":phase,"revision":revision,"details":details})
func _play(name_text: String) -> void:
    sound.stream=load("res://assets/audio/"+name_text+".wav") as AudioStreamWAV;sound.play();_record("sound",{"cue":name_text,"playing":sound.playing})
