extends Node

# Bounded ENet adapter for the independent preview. Same ownership split as
# Main3D/SpacePlayer3D: peer movement, host-owned objects and stage commands.
var stage: Node3D
var mode: String = "offline"
var port: int = 26741
var loopback_only: bool=false
var sequence: int = 0
var snapshots_received: int = 0
var snapshots_sent: int = 0
var acknowledgements: Array[Dictionary] = []
var commands: Array[Dictionary] = []
var rejected_poses: int = 0
var _last_nonce: Dictionary = {}
var _last_pose_time: Dictionary = {}
var _timer: float = 0.0
var _axis: float = 0.0

func setup(owner_stage: Node3D) -> void:
    stage = owner_stage

func _ready() -> void:
    multiplayer.peer_connected.connect(_peer_connected)
    multiplayer.peer_disconnected.connect(_peer_disconnected)
    multiplayer.connected_to_server.connect(_connected)
    multiplayer.connection_failed.connect(_connection_failed)
    multiplayer.server_disconnected.connect(_server_disconnected)
    _tag_actor(stage.get("player") as CharacterBody3D)
    var args: PackedStringArray = OS.get_cmdline_user_args()
    var selected: String = ""
    var address: String = "127.0.0.1"
    for i: int in range(args.size()):
        if args[i] == "--port" and i + 1 < args.size():port = int(args[i + 1])
        if args[i] == "--host":selected = "host"
        if args[i] == "--join":
            selected = "client"
            if i + 1 < args.size():address = args[i + 1]
    loopback_only=args.has("--loopback-test")
    if selected == "host":start_host()
    elif selected == "client":join_host(address)

func start_host() -> bool:
    if mode != "offline":return false
    var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
    if loopback_only:peer.set_bind_ip("127.0.0.1")
    var error: Error = peer.create_server(port,3)
    if error != OK:
        stage.set("session_status","主机创建失败：" + error_string(error));return false
    multiplayer.multiplayer_peer = peer;mode = "host"
    stage.set("session_status","ENet 主机 · 端口 %d" % port)
    print("COOP_HOST_READY ",port);return true

func join_host(address: String="127.0.0.1") -> bool:
    if mode != "offline":return false
    var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
    var error: Error = peer.create_client(address,port)
    if error != OK:
        stage.set("session_status","连接失败：" + error_string(error));return false
    multiplayer.multiplayer_peer = peer;mode = "connecting"
    stage.set("session_status","正在连接 " + address);return true

func _connected() -> void:
    mode = "client"
    var id: int = multiplayer.get_unique_id()
    var actor: CharacterBody3D = stage.get("player") as CharacterBody3D
    var actors: Dictionary = stage.get("actors") as Dictionary
    actors.clear();actors[id] = actor;actor.set("peer_id",id);actor.set_multiplayer_authority(id)
    _tag_actor(actor)
    # This is the initial spawn for the joining peer, never a boarding shortcut.
    actor.position = Vector3(-11.4,0.1,-2.25)
    var device: Node3D = stage.get("device") as Node3D
    (device.get("actors") as Dictionary).clear();device.call("register_actor",actor)
    stage.set("session_status","ENet 客户端 · 船员 %d" % id)
    print("COOP_CLIENT_CONNECTED ",id)

func _peer_connected(id: int) -> void:
    if mode != "host":return
    _spawn_remote(id)
    var ids: Array = [1]
    for peer: int in multiplayer.get_peers():ids.append(peer)
    sync_roster.rpc(ids)
    sync_coop_state.rpc_id(id,(stage.get("device") as Node3D).call("stage_snapshot"),_poses())

func _spawn_remote(id: int) -> void:
    var actors: Dictionary = stage.get("actors") as Dictionary
    if actors.has(id):return
    var actor: CharacterBody3D = (load("res://scripts/station_player.gd") as Script).new() as CharacterBody3D
    actor.name = "Actor_" + str(id);actor.set("peer_id",id);actor.set("is_local_actor",false)
    actor.position = Vector3(-11.4,0.1,-2.25);actor.set("remote_position",actor.position)
    actor.set_multiplayer_authority(id);stage.add_child(actor)
    actors[id] = actor
    _tag_actor(actor)
    (actor.get("camera") as Camera3D).current = false
    ((stage.get("player") as Node3D).get("camera") as Camera3D).current = true
    (stage.get("device") as Node3D).call("register_actor",actor)

@rpc("authority","call_remote","reliable")
func sync_roster(ids: Array) -> void:
    var actors: Dictionary = stage.get("actors") as Dictionary
    for id: int in ids:_spawn_remote(id)
    for id: int in actors.keys():
        if not ids.has(id):
            (stage.get("device") as Node3D).call("unregister_actor",id)
            (actors[id] as Node).queue_free();actors.erase(id)

func _peer_disconnected(id: int) -> void:
    if mode != "host":return
    var actors: Dictionary = stage.get("actors") as Dictionary
    (stage.get("device") as Node3D).call("unregister_actor",id)
    if actors.has(id):(actors[id] as Node).queue_free();actors.erase(id)
    _last_nonce.erase(id);_last_pose_time.erase(id)
    var ids: Array = [1]
    for peer: int in multiplayer.get_peers():ids.append(peer)
    if ids.size()>1:sync_roster.rpc(ids)
    stage.set("session_status","队友已离开 · 可按单人方式继续")
    print("COOP_PEER_LEFT ",id)

func _connection_failed() -> void:
    mode="offline";multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
    stage.set("session_status","连接失败 · 仍可单人操作")

func _server_disconnected() -> void:
    mode="offline";multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
    var actor: CharacterBody3D=stage.get("player") as CharacterBody3D
    var actors: Dictionary=stage.get("actors") as Dictionary
    for id: int in actors:
        if actors[id]!=actor:(actors[id] as Node).queue_free()
    actors.clear();actor.set("peer_id",1);actor.set_multiplayer_authority(1);actors[1]=actor
    var device: Node3D=stage.get("device") as Node3D
    (device.get("actors") as Dictionary).clear();device.call("register_actor",actor);device.call("reset_device")
    stage.set("session_status","主机断开 · 已恢复本地可重试样板")

func _tag_actor(actor: CharacterBody3D) -> void:
    var tag: Label3D=actor.get_node_or_null("OperatorTag") as Label3D
    if tag==null:
        tag=Label3D.new();tag.name="OperatorTag";tag.font=stage.get("ui_font") as Font
        tag.font_size=24;tag.pixel_size=.0028;tag.position.y=1.65;tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED;actor.add_child(tag)
    var tint: Color=Color("#ffc27b") if int(actor.get("peer_id"))==1 else Color("#8fe4f1")
    tag.modulate=tint
    var visual: Node3D=actor.get("visual") as Node3D
    var stripe: MeshInstance3D=visual.find_child("PlayerIdentifier",true,false) as MeshInstance3D
    if stripe!=null:
        var material: StandardMaterial3D=stripe.material_override as StandardMaterial3D
        if material!=null:material.albedo_color=tint;material.emission=tint

func send_action(action: String,target_id: int,revision: int) -> bool:
    var id: int=int((stage.get("player") as Node).get("peer_id"))
    if mode in ["offline","host"]:
        return bool((stage.get("device") as Node3D).call("handle_stage_action",id,action,target_id,revision))
    if mode!="client":return false
    sequence+=1;request_stage_action.rpc_id(1,action,target_id,revision,sequence)
    return true

@rpc("any_peer","call_remote","reliable")
func request_stage_action(action: String,target_id: int,revision: int,nonce: int) -> void:
    if mode!="host":return
    var sender: int=multiplayer.get_remote_sender_id()
    if not (stage.get("actors") as Dictionary).has(sender):return
    if nonce<=int(_last_nonce.get(sender,0)):
        action_result.rpc_id(sender,nonce,false,"REPLAYED_COMMAND",int((stage.get("device") as Node).get("revision")))
        commands.append({"peer_id":sender,"nonce":nonce,"ok":false,"code":"REPLAYED_COMMAND","action":action})
        if commands.size()>256:commands.pop_front()
        return
    _last_nonce[sender]=nonce
    if action not in ["repair","pickup","deposit","drop","cancel","reset"]:return
    var device: Node3D=stage.get("device") as Node3D
    var ok: bool=bool(device.call("handle_stage_action",sender,action,target_id,revision))
    commands.append({"peer_id":sender,"nonce":nonce,"action":action,"ok":ok,"code":device.get("feedback_code"),"revision":device.get("revision")})
    if commands.size()>256:commands.pop_front()
    action_result.rpc_id(sender,nonce,ok,str(device.get("feedback_code")),int(device.get("revision")))

@rpc("authority","call_remote","reliable")
func action_result(nonce: int,ok: bool,code: String,revision: int) -> void:
    acknowledgements.append({"nonce":nonce,"ok":ok,"code":code,"revision":revision})
    if acknowledgements.size()>256:acknowledgements.pop_front()

func send_axis(value: float) -> void:_axis=clampf(value,-1,1)

@rpc("any_peer","call_remote","unreliable_ordered")
func request_control_axis(value: float) -> void:
    if mode=="host":(stage.get("device") as Node3D).call("submit_axis",multiplayer.get_remote_sender_id(),value)

func _physics_process(delta: float) -> void:
    _timer+=delta
    if _timer<.05:return
    _timer=0
    var actor: CharacterBody3D=stage.get("player") as CharacterBody3D
    var actors: Dictionary=stage.get("actors") as Dictionary
    for id: int in actors:
        var tag: Label3D=(actors[id] as Node).get_node_or_null("OperatorTag") as Label3D
        if tag!=null:
            var role: String=str((actors[id] as Node).get("operating_role"))
            tag.visible=actors.size()>1
            tag.text=("A · 调频" if role=="frequency" else ("B · 预载" if role=="preload" else "船员"))+ (" 1" if id==1 else " 2")
    if mode=="client":
        sync_transform.rpc_id(1,actor.position,actor.rotation.y,actor.velocity,bool(actor.get("brace_active")),actor.get("brace_target"))
        if str(actor.get("operating_role"))!="":request_control_axis.rpc_id(1,_axis)
    elif mode in ["offline","host"]:
        (stage.get("device") as Node3D).call("submit_axis",int(actor.get("peer_id")),_axis)
        if mode=="host" and multiplayer.get_peers().size()>0:
            sync_coop_state.rpc((stage.get("device") as Node3D).call("stage_snapshot"),_poses());snapshots_sent+=1

@rpc("any_peer","call_remote","unreliable_ordered")
func sync_transform(at: Vector3,yaw: float,motion: Vector3,brace: bool,grip: Vector3) -> void:
    if mode!="host":return
    var sender: int=multiplayer.get_remote_sender_id()
    var actor: CharacterBody3D=(stage.get("actors") as Dictionary).get(sender) as CharacterBody3D
    if actor==null:return
    var now: float=Time.get_ticks_msec()/1000.0
    var interval: float=clampf(now-float(_last_pose_time.get(sender,now-.05)),.016,.30)
    if not at.is_finite() or not is_finite(yaw) or absf(at.x)>22 or absf(at.z)>16 or at.y< -3 or at.y>7 or actor.position.distance_to(at)>10.5*interval+.65:
        rejected_poses+=1;return
    _last_pose_time[sender]=now
    actor.set("remote_position",at);actor.set("remote_yaw",yaw);actor.set("remote_motion",motion.limit_length(12))
    actor.position=at;actor.rotation.y=yaw;actor.set("brace_active",brace);actor.set("brace_target",grip)

func _poses() -> Array:
    var result: Array=[]
    var actors: Dictionary=stage.get("actors") as Dictionary
    for id: int in actors:
        var actor: CharacterBody3D=actors[id] as CharacterBody3D
        result.append([id,actor.position,actor.rotation.y,actor.velocity,bool(actor.get("brace_active")),actor.get("brace_target")])
    return result

@rpc("authority","call_remote","unreliable_ordered")
func sync_coop_state(snapshot: Dictionary,poses: Array) -> void:
    if mode!="client":return
    for row: Array in poses:
        var id: int=int(row[0]);_spawn_remote(id)
        var actor: CharacterBody3D=(stage.get("actors") as Dictionary)[id] as CharacterBody3D
        if id!=multiplayer.get_unique_id():
            actor.set("remote_position",row[1]);actor.set("remote_yaw",row[2]);actor.set("remote_motion",row[3]);actor.set("brace_active",row[4]);actor.set("brace_target",row[5])
    (stage.get("device") as Node3D).call("apply_stage_snapshot",snapshot)
    snapshots_received+=1

func _exit_tree() -> void:
    # Close the transport before its RPC target disappears. Leaving ENet alive
    # for the next frame would deliver snapshots to a freed scene path.
    set_physics_process(false)
    multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
