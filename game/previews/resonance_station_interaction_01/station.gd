extends "res://station_base.gd"

var device: Node3D
var objective_label: Label
var prompt_label: Label
var feedback_label: Label
var stage_progress: ProgressBar
var ui_font: SystemFont

func _ready() -> void:
    super._ready()
    title.visible=false
    ui_font=SystemFont.new();ui_font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
    device=(load("res://scripts/energy_device.gd") as Script).new() as Node3D
    device.call("setup",self,player,ui_font);add_child(device)
    _hud()

func _inputs() -> void:
    super._inputs()
    var map: Dictionary={"repair":KEY_E,"pickup":KEY_F,"drop":KEY_X,"deposit":KEY_G,"mute_preview":KEY_M,"reset_preview":KEY_F6}
    for action: String in map:
        if not InputMap.has_action(action):InputMap.add_action(action)
        var key: InputEventKey=InputEventKey.new();key.physical_keycode=int(map[action]) as Key;InputMap.action_add_event(action,key)

func _hud() -> void:
    var canvas: CanvasLayer=CanvasLayer.new();add_child(canvas)
    var task_panel: Panel=Panel.new();task_panel.position=Vector2(20,18);task_panel.size=Vector2(680,100);_panel(task_panel);canvas.add_child(task_panel)
    objective_label=_label(task_panel,Vector2(16,12),Vector2(648,32),23)
    var controls: Label=_label(task_panel,Vector2(16,52),Vector2(648,28),16)
    controls.text="能源操作样板 01   WASD / Shift · 鼠标转身 · Tab 近看 · M 静音 · F6 重置"
    var panel: Panel=Panel.new();panel.position=Vector2(150,667);panel.size=Vector2(980,112);_panel(panel);canvas.add_child(panel)
    prompt_label=_label(panel,Vector2(18,10),Vector2(944,31),21)
    feedback_label=_label(panel,Vector2(18,49),Vector2(944,50),18);feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    stage_progress=ProgressBar.new();stage_progress.position=Vector2(150,655);stage_progress.size=Vector2(980,7);stage_progress.max_value=4.5;stage_progress.show_percentage=false;canvas.add_child(stage_progress)

func _label(parent: Control,at: Vector2,dimensions: Vector2,font_size: int) -> Label:
    var label: Label=Label.new();label.position=at;label.size=dimensions;label.add_theme_font_override("font",ui_font);label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("#e4f6f6"));parent.add_child(label);return label

func _panel(panel: Panel) -> void:
    var style: StyleBoxFlat=StyleBoxFlat.new();style.bg_color=Color(.025,.045,.065,.93);style.border_color=Color(.16,.45,.48,.95);style.set_border_width_all(1);style.set_corner_radius_all(10);panel.add_theme_stylebox_override("panel",style)

func _physics_process(_delta: float) -> void:
    if device==null:return
    for action: String in ["repair","pickup","drop","deposit"]:
        if Input.is_action_just_pressed(action):
            var target: Dictionary=device.call("get_stage_action_target",1,action) as Dictionary
            device.call("handle_stage_action",1,action,int(target.get("target_id",0)))
    if Input.is_action_just_pressed("mute_preview"):AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0))
    if Input.is_action_just_pressed("reset_preview"):get_tree().reload_current_scene()

func _process(delta: float) -> void:
    super._process(delta)
    if device==null or objective_label==null:return
    objective_label.text=str(device.call("objective"));prompt_label.text=str(device.call("prompt"));feedback_label.text=str(device.get("feedback"))
    var state: String=str(device.get("phase"));stage_progress.visible=state=="starting";stage_progress.value=float(device.get("elapsed"))

func clamp_cave_camera_position(target: Vector3,desired: Vector3) -> Vector3:
    var result: Vector3=super.clamp_cave_camera_position(target,desired)
    if target.y>2.4 and absf(target.x)<4 and target.z>.3 and target.z<4.2:
        var delta: Vector3=result-target
        if delta.length()>4.2:result=target+delta.normalized()*4.2
    return result
