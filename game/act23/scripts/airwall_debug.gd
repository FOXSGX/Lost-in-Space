extends Node

# -----------------------------------------------------------------------------
# AirWallDebug - the F3 inspector for "I can see through it but I cannot walk".
#
# The complaint this exists for is not "a wall exists". It is "a wall exists that
# the player cannot see". So every report answers, in one record:
#
#   * which object blocked, its node path and class
#   * which collision shape (type + size) belongs to it
#   * the collision layer / mask, decoded with this project's layer meanings
#   * the contact position and normal in world space
#   * where the player is and which way they asked to go
#   * whether any VISIBLE mesh surface exists at the contact point, which is the
#     actual definition of an air wall
#
# Two ways to trigger it:
#   F3  toggles the inspector. While on, every slide collision is recorded, a
#       red ghost box is drawn around the blocking shape for 3 s, and Godot's own
#       collision-shape overlay is enabled (SceneTree.debug_collisions_hint).
#   F4  runs an immediate 8-direction capsule sweep around the player and lists
#       every blocker within 1.6 m, so a suspicious spot can be measured without
#       having to walk into it.
#
# Nothing here changes physics. No collider is disabled, moved or re-layered.
# -----------------------------------------------------------------------------

const SWEEP_DISTANCE: float = 1.6
const SWEEP_DIRECTIONS: int = 8
const LOG_COOLDOWN: float = 0.75
const MARKER_LIFE: float = 3.0
const MAX_RECORDS: int = 24
const MAX_MARKERS: int = 24

# bit value -> what this project means by it (verified against the scripts).
const LAYER_MEANING: Dictionary = {
	1: "world-props",
	2: "player-solid",
	4: "camera-only",
	8: "cargo",
	16: "players",
	32: "moving-platform",
}

var stage: Node3D
var player: CharacterBody3D
var cart: AnimatableBody3D
var enabled: bool = false
var records: Array[Dictionary] = []
var record_count: int = 0
var stuck_frames: int = 0
var blocked_now: bool = false
var last_block: Dictionary = {}
var scan_result: Array[Dictionary] = []
var scan_at: float = 0.0

var _last_position: Vector3 = Vector3.ZERO
var _cooldown: Dictionary = {}
var _markers: Array[MeshInstance3D] = []
var _marker_age: Array[float] = []
var _marker_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _meshes_at: float = -1.0
var _clock: float = 0.0

func setup(stage_node: Node3D, player_node: CharacterBody3D, cart_node: AnimatableBody3D) -> void:
	name = "AirWallDebug"
	stage = stage_node
	player = player_node
	cart = cart_node
	_last_position = player.global_position
	_marker_material = StandardMaterial3D.new()
	_marker_material.albedo_color = Color(1.0, 0.32, 0.22, 0.20)
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_material.no_depth_test = true
	_marker_material.render_priority = 10

func toggle() -> void:
	enabled = not enabled
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.debug_collisions_hint = enabled
	if not enabled:
		_clear_markers()
	print("AIRWALL_DEBUG ", "ON" if enabled else "OFF",
		"  collisions_overlay=", enabled)

# --- per-frame detection ---------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_fade_markers(delta)
	if not enabled or player == null:
		return
	var intent: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var yaw: float = float(player.get("_camera_yaw"))
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var wanted: Vector3 = right * intent.x + forward * -intent.y
	var moved: Vector3 = player.global_position - _last_position
	_last_position = player.global_position
	var travelled: float = Vector2(moved.x, moved.z).length()
	if intent.length() > 0.25 and wanted.length() > 0.1 and travelled < 0.012 and player.is_on_floor():
		stuck_frames += 1
	else:
		stuck_frames = 0
	blocked_now = false
	var slides: int = player.get_slide_collision_count()
	for index: int in range(slides):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		var record: Dictionary = _describe(collision, wanted, intent)
		if record.is_empty():
			continue
		blocked_now = true
		last_block = record
		var key: String = str(record["path"]) + "|" + str(record["normal"])
		var last_time: float = float(_cooldown.get(key, -99.0))
		if _clock - last_time < LOG_COOLDOWN:
			continue
		_cooldown[key] = _clock
		_push(record)
	if blocked_now and stuck_frames == 6:
		# Six physics frames of "asked to move, did not move": that is the exact
		# frame where a human says "the game is stuck". Record the context even if
		# the contact itself was not new.
		push_warning("AIRWALL_STUCK " + JSON.stringify(_stuck_record(wanted)))

func _push(record: Dictionary) -> void:
	record["t"] = _clock
	records.append(record)
	if records.size() > MAX_RECORDS:
		records.pop_front()
	record_count += 1
	print("AIRWALL_BLOCK ", JSON.stringify(record))
	_marker_for(record)

# --- describing one collision ----------------------------------------------

func _describe(collision: KinematicCollision3D, wanted: Vector3, intent: Vector2) -> Dictionary:
	var collider: Node = collision.get_collider() as Node
	if collider == null:
		return {}
	var point: Vector3 = collision.get_position()
	var normal: Vector3 = collision.get_normal()
	var shape_index: int = int(collision.get_collider_shape_index())
	var shape_info: Dictionary = _shape_of(collider, shape_index)
	var layer: int = 0
	var mask: int = 0
	if collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
		mask = (collider as CollisionObject3D).collision_mask
	return {
		"object": str(collider.name),
		"class": collider.get_class(),
		"path": str(collider.get_path()),
		"layer": layer,
		"layer_names": _decode(layer),
		"mask": mask,
		"mask_names": _decode(mask),
		"shape": shape_info,
		"contact": _v(point),
		"normal": _v(normal),
		"player": _v(player.global_position),
		"intended": _v(wanted),
		"intent": [intent.x, intent.y],
		"on_floor": player.is_on_floor(),
		"stuck_frames": stuck_frames,
		"visual": _visual_at(point),
	}

func _stuck_record(wanted: Vector3) -> Dictionary:
	var feet: Vector3 = player.global_position + Vector3.UP * 0.05
	# The capsule bottom is what catches a hidden lip; probe a short capsule cast
	# in the intended direction to find what is actually refusing the motion.
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.40
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.75)
	query.motion = wanted.normalized() * 0.45
	query.collision_mask = int(player.collision_mask)
	query.exclude = [player.get_rid()]
	var cast: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = cast[0] if not cast.is_empty() else 1.0
	query.motion = Vector3.ZERO
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.75 + wanted.normalized() * maxf(0.12, 0.45 * fraction))
	var hits: Array = player.get_world_3d().direct_space_state.intersect_shape(query, 8)
	var names: Array[String] = []
	for hit: Dictionary in hits:
		var node: Node = hit.get("collider") as Node
		if node != null:
			names.append(str(node.get_path()))
	return {
		"t": _clock,
		"player": _v(player.global_position),
		"intended": _v(wanted),
		"fraction": fraction,
		"blockers": names,
		"visual": _visual_at(player.global_position + Vector3.UP * 0.8 + wanted.normalized() * 0.4),
	}

func _shape_of(collider: Node, shape_index: int) -> Dictionary:
	if not (collider is CollisionObject3D):
		return {"type": "none"}
	var body: CollisionObject3D = collider as CollisionObject3D
	var offset: int = 0
	for owner_id: int in body.get_shape_owners():
		var count: int = body.shape_owner_get_shape_count(owner_id)
		if shape_index >= offset and shape_index < offset + count:
			var shape: Shape3D = body.shape_owner_get_shape(owner_id, shape_index - offset)
			var node: Node = body.shape_owner_get_owner(owner_id)
			var out: Dictionary = {
				"type": shape.get_class() if shape != null else "null",
				"owner_path": str(node.get_path()) if node != null else "",
				"index": shape_index,
			}
			if shape is BoxShape3D:
				out["size"] = _v((shape as BoxShape3D).size)
			elif shape is SphereShape3D:
				out["radius"] = (shape as SphereShape3D).radius
			elif shape is CapsuleShape3D:
				out["radius"] = (shape as CapsuleShape3D).radius
				out["height"] = (shape as CapsuleShape3D).height
			elif shape is ConcavePolygonShape3D:
				out["triangles"] = int(float((shape as ConcavePolygonShape3D).get_faces().size()) / 3.0)
			if node is Node3D:
				out["transform"] = str((node as Node3D).global_transform.origin)
			return out
		offset += count
	return {"type": "unresolved", "index": shape_index, "owner_path": str(body.get_path())}

# Is there a rendered surface where the collision says there is a wall?
# This is the actual air-wall test: the contact point is compared against every
# visible mesh AABB in the stage, grown by 12 cm (mesh bounds are conservative).
func _visual_at(point: Vector3) -> Dictionary:
	_refresh_meshes()
	var best: String = ""
	var best_distance: float = 99.0
	var player_prefix: String = str(player.get_path())
	for mesh: MeshInstance3D in _meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		# The player's own body and viewmodel always contain the probe point.
		if str(mesh.get_path()).begins_with(player_prefix):
			continue
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		if aabb.grow(0.12).has_point(point):
			var distance: float = aabb.get_center().distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = str(mesh.get_path())
	return {
		"visible_surface_at_contact": best,
		"air_wall": best == "",
		"meshes_scanned": _meshes.size(),
	}

func _refresh_meshes() -> void:
	if _clock - _meshes_at < 2.0 and not _meshes.is_empty():
		return
	_meshes_at = _clock
	_meshes.clear()
	for node: Node in stage.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh != null:
			_meshes.append(mesh)

func _decode(bits: int) -> String:
	var names: Array[String] = []
	for bit: int in LAYER_MEANING:
		if bits & bit:
			names.append(str(bit) + ":" + str(LAYER_MEANING[bit]))
	return "|".join(names) if not names.is_empty() else "0:none"

func _v(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

# --- immediate sweep -------------------------------------------------------

func scan() -> void:
	if player == null:
		return
	scan_at = _clock
	scan_result.clear()
	var origin: Vector3 = player.global_position + Vector3.UP * 0.95
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.40
	for index: int in range(SWEEP_DIRECTIONS):
		var angle: float = TAU * float(index) / float(SWEEP_DIRECTIONS)
		var direction: Vector3 = Vector3(sin(angle), 0.0, cos(angle))
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, origin)
		query.motion = direction * SWEEP_DISTANCE
		query.collision_mask = int(player.collision_mask)
		query.exclude = [player.get_rid()]
		var cast: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(query)
		var fraction: float = cast[0] if not cast.is_empty() else 1.0
		var entry: Dictionary = {"direction": _v(direction), "free_m": SWEEP_DISTANCE * fraction}
		if fraction < 0.999:
			var at: Vector3 = origin + direction * (SWEEP_DISTANCE * fraction + 0.05)
			var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			shape_query.shape = capsule
			shape_query.transform = Transform3D(Basis.IDENTITY, at)
			shape_query.collision_mask = int(player.collision_mask)
			shape_query.exclude = [player.get_rid()]
			var hits: Array = player.get_world_3d().direct_space_state.intersect_shape(shape_query, 8)
			var blockers: Array[String] = []
			var air_wall: bool = true
			for hit: Dictionary in hits:
				var node: Node = hit.get("collider") as Node
				if node == null:
					continue
				var layer: int = 0
				if node is CollisionObject3D:
					layer = (node as CollisionObject3D).collision_layer
				blockers.append("%s [%s] %s" % [str(node.name), _decode(layer), str(node.get_path())])
			var visual: Dictionary = _visual_at(at)
			air_wall = bool(visual["air_wall"])
			entry["stop_at"] = _v(at)
			entry["blockers"] = blockers
			entry["air_wall"] = air_wall
			entry["visible_surface"] = str(visual["visible_surface_at_contact"])
			_marker_box(at, 0.45)
		scan_result.append(entry)
	print("AIRWALL_SCAN ", JSON.stringify({"at": _v(origin), "results": scan_result}))

# --- markers ---------------------------------------------------------------

func _marker_for(record: Dictionary) -> void:
	# Place the ghost on the contact point rather than on the shape origin: for a
	# 106 m cave shell a shape-sized box would fill the screen.
	var contact: String = str(record["contact"])
	var values: PackedStringArray = contact.trim_prefix("(").trim_suffix(")").split(", ")
	if values.size() != 3:
		return
	var at: Vector3 = Vector3(float(values[0]), float(values[1]), float(values[2]))
	_marker_box(at, 0.30)

func _marker_box(at: Vector3, size: float) -> void:
	var marker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE * size
	marker.mesh = box
	marker.material_override = _marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position = at
	stage.add_child(marker)
	_markers.append(marker)
	_marker_age.append(0.0)
	while _markers.size() > MAX_MARKERS:
		var oldest: MeshInstance3D = _markers.pop_front()
		_marker_age.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func _fade_markers(delta: float) -> void:
	if _markers.is_empty():
		return
	for index: int in range(_markers.size() - 1, -1, -1):
		_marker_age[index] += delta
		if _marker_age[index] > MARKER_LIFE:
			var marker: MeshInstance3D = _markers[index]
			_markers.remove_at(index)
			_marker_age.remove_at(index)
			if is_instance_valid(marker):
				marker.queue_free()

func _clear_markers() -> void:
	for marker: MeshInstance3D in _markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()
	_marker_age.clear()

# --- HUD -------------------------------------------------------------------

func recent_text(limit: int = 4) -> String:
	var lines: Array[String] = []
	var start: int = maxi(0, records.size() - limit)
	for index: int in range(start, records.size()):
		var record: Dictionary = records[index]
		var visual: Dictionary = record.get("visual", {}) as Dictionary
		var tag: String = "空气墙" if bool(visual.get("air_wall", false)) else "可见表面"
		lines.append("%s · %s [%s] %s" % [tag, str(record.get("object", "")),
			str(record.get("layer_names", "")), str(record.get("path", ""))])
	return "\n".join(lines)

func summary() -> String:
	if not enabled:
		return "F3 空气墙检查：关闭"
	if last_block.is_empty():
		return "F3 空气墙检查：开启 · 尚未受阻"
	var visual: Dictionary = last_block.get("visual", {}) as Dictionary
	var verdict: String = "可见几何一致" if not bool(visual.get("air_wall", false)) else "无可见几何（空气墙）"
	return "F3 受阻：%s [%s] %s" % [str(last_block.get("object", "")),
		str(last_block.get("layer_names", "")), verdict]
