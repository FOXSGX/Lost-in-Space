extends RefCounted

static func create_theme(font: Font) -> Theme:
    var result: Theme = Theme.new()
    result.default_font = font
    result.default_font_size = 20
    for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
        var style: StyleBoxFlat = StyleBoxFlat.new()
        style.bg_color = Color("#193544") if state == "normal" else Color("#285569")
        if state == "disabled": style.bg_color = Color("#14232d")
        style.set_corner_radius_all(10)
        style.content_margin_left = 20
        style.content_margin_right = 20
        style.content_margin_top = 12
        style.content_margin_bottom = 12
        if state == "focus":
            style.bg_color = Color.TRANSPARENT
            style.border_color = Color("#ffc37b")
            style.set_border_width_all(3)
        result.set_stylebox(state, "Button", style)
        result.set_stylebox(state, "LineEdit", style)
    var panel: StyleBoxFlat = StyleBoxFlat.new()
    panel.bg_color = Color(0.025, 0.055, 0.075, 0.97)
    panel.border_color = Color("#3a7281")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(20)
    panel.content_margin_left = 32
    panel.content_margin_right = 32
    panel.content_margin_top = 24
    panel.content_margin_bottom = 24
    result.set_stylebox("panel", "PanelContainer", panel)
    result.set_color("font_color", "Label", Color("#def1ee"))
    result.set_color("font_color", "Button", Color("#def1ee"))
    result.set_color("font_disabled_color", "Button", Color("#708b94"))
    result.set_constant("separation", "VBoxContainer", 12)
    result.set_constant("separation", "HBoxContainer", 12)
    return result
