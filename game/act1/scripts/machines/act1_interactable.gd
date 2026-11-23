class_name Act1Interactable
extends StaticBody3D

## A physically hittable interaction point for Act 01. The point itself is a
## collision body on the interactable layer; the owning station routes the
## request through the host-authoritative state machine. Visual geometry and a
## focus ring are added by the station builder.
##
## Integration note: source project class_name `Interactable` renamed to
## `Act1Interactable` (the base project has its own interaction semantics).

var interaction_id := ""
var prompt_text := ""
var hold_mode := false
var enabled := true
var stage: Node = null
var focus_mesh: MeshInstance3D = null
var prompt_callable: Callable
var _focus := false
var _focus_time := 0.0


func setup(p_id: String, p_prompt: String, p_size: Vector3, p_hold: bool = false) -> void:
	interaction_id = p_id
	prompt_text = p_prompt
	hold_mode = p_hold
	name = "Interact_" + p_id
	collision_layer = 8
	collision_mask = 0
	add_to_group("interactable")
	var shape := BoxShape3D.new()
	shape.size = p_size
	var col := CollisionShape3D.new()
	col.name = "InteractionShape"
	col.shape = shape
	add_child(col)


func add_focus_marker(radius := 0.19) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.78
	torus.outer_radius = radius
	torus.rings = 16
	torus.ring_segments = 6
	focus_mesh = MeshInstance3D.new()
	focus_mesh.name = "FocusRing"
	focus_mesh.mesh = torus
	focus_mesh.material_override = Act1MatLib.emissive(Color(0.30, 0.95, 1.0), 1.8, true)
	focus_mesh.visible = false
	focus_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(focus_mesh)


func get_prompt(player: Node = null) -> String:
	if not enabled:
		return ""
	if prompt_callable.is_valid():
		return str(prompt_callable.call(player))
	return prompt_text


func set_focused(value: bool) -> void:
	if _focus == value:
		return
	_focus = value
	if focus_mesh != null:
		focus_mesh.visible = value


func set_interaction_enabled(value: bool) -> void:
	enabled = value
	collision_layer = 8 if value else 0
	if focus_mesh != null and not value:
		focus_mesh.visible = false


func interact(player: Node) -> void:
	if not enabled or stage == null:
		return
	stage.request_interaction(interaction_id, player, "press")


func begin_hold(player: Node) -> void:
	if not enabled or stage == null:
		return
	stage.request_interaction(interaction_id, player, "begin")


func end_hold(player: Node) -> void:
	if not enabled or stage == null:
		return
	stage.request_interaction(interaction_id, player, "end")


func _process(delta: float) -> void:
	if focus_mesh == null or not focus_mesh.visible:
		return
	_focus_time += delta
	focus_mesh.rotation.y += delta * 1.6
	var s := 1.0 + sin(_focus_time * 4.0) * 0.08
	focus_mesh.scale = Vector3.ONE * s