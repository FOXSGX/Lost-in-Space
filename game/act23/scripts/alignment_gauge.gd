extends Control

# Physical-state readout for the severed-track repair. The old build only exposed
# the exact angle in the F3 debug panel, so a keyboard player had no way to see
# the lock window approaching; the automated test could poll `lockable` at 60 Hz
# but a human could not. This gauge reads the rail's real hinge angle and paints
# the receiver's actual +/-5 deg guide slot (green) and the +/-2 deg direct-pin
# core (bright). It never writes state.

const SPAN_DEG: float = 9.0

var stage: Node3D
var font: Font
var _shown: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -232.0
	offset_right = 232.0
	offset_top = -196.0
	offset_bottom = -118.0
	font = stage.get("ui_font") as Font if stage != null else ThemeDB.fallback_font
	set_process(true)

func _rig() -> Node3D:
	if stage == null:
		return null
	var yard: Node3D = stage.get("yard") as Node3D
	if yard == null:
		return null
	return yard.get("rig") as Node3D

func _process(_delta: float) -> void:
	var rig: Node3D = _rig()
	var show: bool = false
	if rig != null:
		var winch: Dictionary = rig.call("tension_state") as Dictionary
		var rail: Dictionary = rig.call("alignment_state") as Dictionary
		show = bool(winch.get("attached", false)) and not bool(rail.get("locked", false))
		if bool(rail.get("guiding", false)):
			show = true
	if show != _shown:
		_shown = show
		visible = show
	if show:
		queue_redraw()

func _draw() -> void:
	var rig: Node3D = _rig()
	if rig == null:
		return
	var winch: Dictionary = rig.call("tension_state") as Dictionary
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	var degrees: float = float(rail.get("angle_deg", 0.0))
	var capture: float = float(rail.get("capture_deg", 5.0))
	var guiding: bool = bool(rail.get("guiding", false))
	var in_slot: bool = bool(rail.get("captureable", false))
	var payload: Color = Color(0.03, 0.045, 0.055, 0.78)
	draw_rect(Rect2(Vector2.ZERO, size), payload, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.72, 0.76, 0.45), false, 1.0)
	var bar_left: float = 26.0
	var bar_right: float = size.x - 26.0
	var bar_y: float = 54.0
	var bar_h: float = 9.0
	var center: float = (bar_left + bar_right) * 0.5
	var half: float = (bar_right - bar_left) * 0.5
	draw_rect(Rect2(Vector2(bar_left, bar_y), Vector2(bar_right - bar_left, bar_h)),
		Color(0.10, 0.13, 0.15, 0.95), true)
	# +/-5 deg guide slot
	var slot: float = clampf(capture / SPAN_DEG, 0.0, 1.0) * half
	draw_rect(Rect2(Vector2(center - slot, bar_y), Vector2(slot * 2.0, bar_h)),
		Color(0.20, 0.66, 0.42, 0.85), true)
	# +/-2 deg direct-pin core
	var core: float = clampf(2.0 / SPAN_DEG, 0.0, 1.0) * half
	draw_rect(Rect2(Vector2(center - core, bar_y - 2.0), Vector2(core * 2.0, bar_h + 4.0)),
		Color(0.45, 1.0, 0.62, 0.55), true)
	# Needle: clamp to the painted scale, but say the true value in text.
	var needle_x: float = center + clampf(degrees / SPAN_DEG, -1.0, 1.0) * half
	var needle_color: Color = Color(0.55, 1.0, 0.65) if in_slot else Color(1.0, 0.72, 0.32)
	if degrees < -capture:
		needle_color = Color(1.0, 0.42, 0.32)
	draw_line(Vector2(needle_x, bar_y - 7.0), Vector2(needle_x, bar_y + bar_h + 7.0), needle_color, 2.4)
	draw_line(Vector2(center, bar_y - 4.0), Vector2(center, bar_y + bar_h + 4.0), Color(0.85, 0.95, 1.0, 0.75), 1.2)
	var status: String = ""
	if guiding:
		status = "导向槽校正中 %d%%" % int(float(rail.get("guide_progress", 0.0)) * 100.0)
	elif in_slot:
		status = "在导向槽内 · 去锁定座按 E 插销"
	elif degrees > capture:
		status = "继续按 W 收缆"
	else:
		status = "拉过头了 · 按 S 放线"
	var color: Color = Color(0.62, 0.95, 0.68) if in_slot else Color(1.0, 0.80, 0.50)
	if degrees < -capture:
		color = Color(1.0, 0.58, 0.42)
	draw_string(font, Vector2(24.0, 24.0), "断轨对齐  %+.1f°   %s" % [degrees, status],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, color)
	draw_string(font, Vector2(24.0, 44.0),
		"按住 W 收缆 / S 放线 · 绿区 ±%.0f° 可机械锁定 · 张力 %.0f%%" % [
			capture, float(winch.get("tension_ratio", 0.0)) * 100.0],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.74, 0.86, 0.88))
	draw_string(font, Vector2(bar_left, size.y - 6.0), "-%.0f°" % SPAN_DEG,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.55, 0.66, 0.68))
	draw_string(font, Vector2(bar_right - 32.0, size.y - 6.0), "+%.0f°" % SPAN_DEG,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.55, 0.66, 0.68))
