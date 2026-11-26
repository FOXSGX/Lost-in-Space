extends "res://station_base.gd"

var input_blocked: bool = false
var device: Node3D
var hud: CanvasLayer
var ui_font: SystemFont
var session: Node
var session_status: String="单人 · 另一端由副控补偿"
var actors: Dictionary={}

func _ready() -> void:
    super._ready();title.visible=false
    actors[1]=player
    ui_font=SystemFont.new();ui_font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
    device=(load("res://scripts/energy_device.gd") as Script).new() as Node3D
    device.call("setup",self,player,ui_font);add_child(device)
    hud=(load("res://scripts/coop_hud.gd") as Script).new() as CanvasLayer
    hud.call("configure",self,device,player,ui_font);add_child(hud)
    session=(load("res://scripts/coop_session.gd") as Script).new() as Node
    session.name="CoopSession";session.call("setup",self);add_child(session)

func _inputs() -> void:
    super._inputs()
    var map: Dictionary={"repair":KEY_E,"pickup":KEY_F,"drop":KEY_X,"deposit":KEY_G,"mute_preview":KEY_M,"reset_preview":KEY_F6,"brace":KEY_H,"cancel_operation":KEY_C,"toggle_debug":KEY_F9,"host_preview":KEY_F7,"join_preview":KEY_F8,"show_help":KEY_F1}
    for action: String in map:
        if not InputMap.has_action(action):InputMap.add_action(action)
        var key: InputEventKey=InputEventKey.new();key.physical_keycode=int(map[action]) as Key;InputMap.action_add_event(action,key)

func _unhandled_input(_event: InputEvent) -> void:
    pass

func request_action(action: String) -> bool:
    var id: int=int(player.get("peer_id"))
    var target: Dictionary=device.call("get_stage_action_target",id,action) as Dictionary
    if session!=null:return bool(session.call("send_action",action,int(target.get("target_id",0)),int(device.get("revision"))))
    return bool(device.call("handle_stage_action",id,action,int(target.get("target_id",0))))

func _physics_process(_delta: float) -> void:
    if device==null:return
    if input_blocked:
        session.call("send_axis", 0.0)
        return
    if Input.is_action_just_pressed("host_preview"):session.call("start_host")
    if Input.is_action_just_pressed("join_preview"):session.call("join_host","127.0.0.1")
    var role: String=str(player.get("operating_role"))
    player.set("input_enabled",role=="")
    session.call("send_axis", 0.0)
    if role!="":
        var value: float=Input.get_axis("move_left","move_right") if role=="frequency" else Input.get_axis("move_down","move_up")
        if session!=null:session.call("send_axis",value)
        else:device.call("submit_axis",int(player.get("peer_id")),value)
    for action: String in ["repair","pickup","drop","deposit"]:
        if Input.is_action_just_pressed(action):request_action(action)
    if Input.is_action_just_pressed("cancel_operation"):request_action("cancel")
    if Input.is_action_just_pressed("reset_preview"):request_action("reset")
    if Input.is_action_just_pressed("mute_preview"):AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0))
    if Input.is_action_just_pressed("show_help"):hud.call("toggle_help")
    if Input.is_action_just_pressed("toggle_debug"):hud.set("debug_visible",not bool(hud.get("debug_visible")))

func clamp_cave_camera_position(target: Vector3,desired: Vector3) -> Vector3:
    var result: Vector3=super.clamp_cave_camera_position(target,desired)
    if target.y>2.4 and absf(target.x)<4 and target.z>.3 and target.z<4.2:
        var delta: Vector3=result-target
        if delta.length()>4.2:result=target+delta.normalized()*4.2
    return result
