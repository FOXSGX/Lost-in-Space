extends CanvasLayer

var stage: Node3D
var device: Node3D
var actor: CharacterBody3D
var font: Font
var task: Label
var prompt: Label
var feedback: Label
var debug: Label
var panel: Panel
var debug_visible: bool = false
var _timer: float = 0.0

func configure(owner_stage: Node3D, stage_device: Node3D, player: CharacterBody3D, ui_font: Font) -> void:
    stage=owner_stage;device=stage_device;actor=player;font=ui_font

func _ready() -> void:
    task=_label(Vector2(24,18),Vector2(800,28),18)
    panel=Panel.new();panel.position=Vector2(360,714);panel.size=Vector2(560,66)
    var style: StyleBoxFlat=StyleBoxFlat.new();style.bg_color=Color(.02,.035,.05,.85);style.set_corner_radius_all(10)
    panel.add_theme_stylebox_override("panel",style);add_child(panel)
    prompt=_label(Vector2(376,724),Vector2(536,25),19)
    feedback=_label(Vector2(376,751),Vector2(536,23),15)
    feedback.modulate=Color("#acbfc3")
    debug=_label(Vector2(20,62),Vector2(700,300),16);debug.visible=false
    var meter: Control=(load("res://scripts/calibration_meter.gd") as Script).new() as Control
    meter.position=Vector2(440,564);meter.size=Vector2(400,137)
    meter.call("configure",device,actor,font);add_child(meter)

func _label(at: Vector2,dimensions: Vector2,points: int) -> Label:
    var node: Label=Label.new();node.position=at;node.size=dimensions
    node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",points)
    node.add_theme_color_override("font_color",Color("#deeeed"));node.add_theme_color_override("font_shadow_color",Color.BLACK)
    node.add_theme_constant_override("shadow_offset_x",1);node.add_theme_constant_override("shadow_offset_y",1)
    node.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(node);return node

func _process(delta: float) -> void:
    _timer+=delta
    if _timer<.10:return
    _timer=0
    task.text=str(device.call("objective"))
    var text: String=str(device.call("prompt",int(actor.get("peer_id"))))
    var transient: String=str(device.get("feedback")) if float(device.get("feedback_until"))>float(device.get("clock")) else ""
    panel.visible=text!="" or transient!="";prompt.text=text;feedback.text=transient
    debug.visible=debug_visible
    if debug_visible:
        debug.text="DEBUG · F9 隐藏\nphase %s · revision %s · carrier %s\nrole %s · actors %s\nphysics %.2f ms · render calls %d · objects %d\nF6 主机复位 · C 停机 · M 静音 · H 抓扶\n%s" % [device.get("phase"),device.get("revision"),device.get("carrier_id"),actor.get("operating_role"),(device.get("actors") as Dictionary).size(),Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.OBJECT_COUNT),stage.get("session_status")]
