extends Control

var device: Node3D
var actor: CharacterBody3D
var font: Font
var _timer: float = 0.0
var panel: StyleBoxFlat

func configure(stage_device: Node3D, player: CharacterBody3D, ui_font: Font) -> void:
    device = stage_device;actor = player;font = ui_font
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel=StyleBoxFlat.new();panel.bg_color=Color(.025,.045,.065,.88);panel.set_corner_radius_all(12)

func _process(delta: float) -> void:
    visible = str(actor.get("operating_role")) != ""
    _timer += delta
    if visible and _timer > 0.033:
        _timer = 0.0;queue_redraw()

func _draw() -> void:
    if device == null or font == null:return
    var model: RefCounted = device.get("calibration") as RefCounted
    var role: String = str(actor.get("operating_role"))
    var value: float = float(model.get("frequency" if role=="frequency" else "preload_value"))
    var goal: float = float(model.call("frequency_goal" if role == "frequency" else "preload_goal"))
    var window: float = float(model.call("frequency_window" if role == "frequency" else "preload_window"))
    draw_style_box(panel,Rect2(Vector2.ZERO,size))
    draw_string(font,Vector2(18,27),"频率调谐" if role == "frequency" else "锁爪预载",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("#d8eeec"))
    draw_line(Vector2(22,62),Vector2(378,62),Color("#405665"),8,true)
    draw_line(Vector2(22+(goal-window)*356,62),Vector2(22+(goal+window)*356,62),Color("#75c8b0"),13,true)
    for i: int in range(11):
        var x: float=22+float(i)*35.6
        draw_line(Vector2(x,75),Vector2(x,81),Color("#678791"),1,true)
    var needle: float=22+value*356
    draw_colored_polygon(PackedVector2Array([Vector2(needle-6,43),Vector2(needle+6,43),Vector2(needle,54)]),Color("#ffc37b"))
    draw_line(Vector2(needle,53),Vector2(needle,72),Color("#ffc37b"),3,true)
    draw_line(Vector2(22,103),Vector2(378,103),Color("#223e49"),5,true)
    draw_line(Vector2(22,103),Vector2(22+float(model.get("progress"))*356,103),Color("#8ce3ce"),5,true)
    draw_string(font,Vector2(18,126),str(model.get("reason")),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#9fb6bd"))
