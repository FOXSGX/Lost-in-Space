extends Node3D

# -----------------------------------------------------------------------------
# WinchAnchor - a mechanical attachment point for the winch hook.
#
# This is the "connection point interface" the mission exposes. Any node that
# wants to accept the cable places one of these as a child; the mission only
# looks at `group` membership ("winch_anchor") and never at a hard-coded path.
#
# Contract
#   attach_point() -> Vector3   world position of the hook eye
#   is_pullable()  -> bool      true only for anchors that belong to a movable
#                               structure; fixed anchors refuse the hook
#   describe()     -> String    short human label used by HUD + feedback
#
# `kind`:
#   "track"   the hook can be attached; the owning structure is pulled
#   "fixed"   a real eye on a fixed structure: the hook is refused with a reason
#   "decoy"   reserved for future unusable scrap; refused like "fixed"
# -----------------------------------------------------------------------------

signal hook_attached(anchor: Node3D)
signal hook_detached(anchor: Node3D)

@export var anchor_id: StringName = &"anchor"
@export var display_name: String = "机械锚点"
@export var kind: String = "track"
@export var leverage_note: String = ""
@export var hook_local: Vector3 = Vector3.ZERO
@export var attachment_range: float = 2.2

var occupied: bool = false
var highlight: MeshInstance3D

func _ready() -> void:
	add_to_group("winch_anchor")
	_build_highlight()

func _build_highlight() -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.17
	torus.outer_radius = 0.24
	torus.rings = 16
	torus.ring_segments = 18
	highlight = MeshInstance3D.new()
	highlight.name = "InteractHighlight"
	highlight.mesh = torus
	highlight.rotation.x = PI * 0.5
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 1.0, 0.60, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	highlight.material_override = mat
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	add_child(highlight)

func _process(_delta: float) -> void:
	if highlight != null and highlight.visible:
		var pulse: float = 1.0 + 0.07 * sin(Time.get_ticks_msec() * 0.008)
		highlight.scale = Vector3.ONE * pulse

func set_highlight(on: bool) -> void:
	if highlight != null:
		highlight.visible = on and not occupied

func attach_point() -> Vector3:
	return to_global(hook_local)

func is_pullable() -> bool:
	return kind == "track"

func can_attach() -> bool:
	return is_pullable() and not occupied

func refusal_reason() -> String:
	if kind == "fixed":
		return "%s 固定在岩体上，绞盘拉不动" % display_name
	if kind == "decoy":
		return "%s 已经锈死，无法承力" % display_name
	if occupied:
		return "%s 已经挂着缆绳" % display_name
	return ""

func describe() -> String:
	if leverage_note.is_empty():
		return display_name
	return "%s（%s）" % [display_name, leverage_note]

func mark_attached() -> void:
	occupied = true
	set_highlight(false)
	hook_attached.emit(self)

func mark_detached() -> void:
	occupied = false
	hook_detached.emit(self)
