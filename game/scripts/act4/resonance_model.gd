class_name ResonanceModel
extends RefCounted
## Pure resonance graph logic.
##
## A crystal emits into a cone in front of its focus axis. A receiver does not
## need to point back: this makes a chain readable in 3D (each crystal has one
## visible "forward" facet) and makes the carryable relay's yaw meaningful.
##
## The model is deliberately not an acoustic solver. It is a deterministic,
## inspectable graph with travel delays and distance attenuation, so tests can
## assert exact propagation and gaps instead of guessing from visuals.

const WAVE_SPEED := 4.2
const ATTENUATION_PER_M := 0.95
const MIN_AMPLITUDE := 0.06
const DEFAULT_RANGE := 6.8
const DEFAULT_CONE_DEG := 42.0
const MEMORY_THRESHOLD := 0.25

var nodes: Dictionary = {}


func reset() -> void:
	nodes.clear()


func add_node(
	id: String,
	position: Vector3,
	focus: Vector3,
	channel: String,
	kind: String,
	radius: float = DEFAULT_RANGE,
	cone_deg: float = DEFAULT_CONE_DEG
) -> void:
	var focus_dir: Vector3 = focus.normalized() if focus.length_squared() > 0.0001 else Vector3.FORWARD
	nodes[id] = {
		"id": id,
		"position": position,
		"focus": focus_dir,
		"channel": channel,
		"kind": kind,
		"radius": radius,
		"cone_cos": cos(deg_to_rad(cone_deg)),
		"cone_deg": cone_deg,
		"enabled": true,
	}


func remove_node(id: String) -> void:
	nodes.erase(id)


func has_node(id: String) -> bool:
	return nodes.has(id)


func set_enabled(id: String, enabled: bool) -> void:
	if not nodes.has(id):
		return
	var data: Dictionary = nodes[id]
	data["enabled"] = enabled
	nodes[id] = data


func set_transform(id: String, position: Vector3, focus: Vector3) -> void:
	if not nodes.has(id):
		return
	var data: Dictionary = nodes[id]
	data["position"] = position
	if focus.length_squared() > 0.0001:
		data["focus"] = focus.normalized()
	nodes[id] = data


func set_focus(id: String, focus: Vector3) -> void:
	if not nodes.has(id):
		return
	var data: Dictionary = nodes[id]
	if focus.length_squared() > 0.0001:
		data["focus"] = focus.normalized()
	nodes[id] = data


func get_node_data(id: String) -> Dictionary:
	return nodes.get(id, {})


func get_position(id: String) -> Vector3:
	var data: Dictionary = nodes.get(id, {})
	return data.get("position", Vector3.ZERO)


func get_focus(id: String) -> Vector3:
	var data: Dictionary = nodes.get(id, {})
	return data.get("focus", Vector3.FORWARD)


func get_kind(id: String) -> String:
	var data: Dictionary = nodes.get(id, {})
	return str(data.get("kind", ""))


func get_channel(id: String) -> String:
	var data: Dictionary = nodes.get(id, {})
	return str(data.get("channel", ""))


func _channels_bridge(from_data: Dictionary, to_data: Dictionary) -> bool:
	var from_channel: String = str(from_data.get("channel", ""))
	var to_channel: String = str(to_data.get("channel", ""))
	if from_channel == to_channel:
		return true
	if from_channel == "hub" or to_channel == "hub":
		return true
	if str(from_data.get("kind", "")) == "relay":
		return true
	if str(to_data.get("kind", "")) == "relay":
		return true
	return false


func can_emit_to(from_id: String, to_id: String) -> bool:
	if from_id == to_id:
		return false
	if not nodes.has(from_id) or not nodes.has(to_id):
		return false
	var from_data: Dictionary = nodes[from_id]
	var to_data: Dictionary = nodes[to_id]
	if not bool(from_data.get("enabled", true)) or not bool(to_data.get("enabled", true)):
		return false
	if not _channels_bridge(from_data, to_data):
		return false
	var from_pos: Vector3 = from_data["position"]
	var to_pos: Vector3 = to_data["position"]
	var delta: Vector3 = to_pos - from_pos
	var distance: float = delta.length()
	if distance <= 0.05 or distance > float(from_data["radius"]):
		return false
	var direction: Vector3 = delta / distance
	var focus: Vector3 = from_data["focus"]
	# The hammer bell is a rough omni radiator: it feeds every vein.
	if str(from_data.get("kind", "")) != "hub" and direction.dot(focus) < float(from_data["cone_cos"]):
		return false
	return true


## Explains a rejected link. Used by the probe and by the in-game dead-end hint.
func rejection_reason(from_id: String, to_id: String) -> String:
	if from_id == to_id:
		return "self"
	if not nodes.has(from_id) or not nodes.has(to_id):
		return "missing"
	var from_data: Dictionary = nodes[from_id]
	var to_data: Dictionary = nodes[to_id]
	if not bool(from_data.get("enabled", true)) or not bool(to_data.get("enabled", true)):
		return "disabled"
	if not _channels_bridge(from_data, to_data):
		return "channel"
	var delta: Vector3 = (to_data["position"] as Vector3) - (from_data["position"] as Vector3)
	var distance: float = delta.length()
	if distance <= 0.05:
		return "overlap"
	if distance > float(from_data["radius"]):
		return "range"
	var direction: Vector3 = delta / distance
	if str(from_data.get("kind", "")) != "hub" and direction.dot(from_data["focus"] as Vector3) < float(from_data["cone_cos"]):
		return "cone"
	return "ok"


func edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = nodes.keys()
	for i: int in range(ids.size()):
		for j: int in range(ids.size()):
			if i == j:
				continue
			var from_id: String = str(ids[i])
			var to_id: String = str(ids[j])
			if can_emit_to(from_id, to_id):
				var from_data: Dictionary = nodes[from_id]
				var to_data: Dictionary = nodes[to_id]
				out.append({
					"from": from_id,
					"to": to_id,
					"distance": (to_data["position"] as Vector3).distance_to(from_data["position"] as Vector3),
				})
	return out


## Returns time-ordered events for one strike.
## types: "travel" (start/end), "arrive" (time), "dead_end" (time), "weak" (time).
func propagate(source_id: String, amplitude: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not nodes.has(source_id):
		return events
	var best: Dictionary = {}
	best[source_id] = {"amp": amplitude, "time": 0.0, "parent": ""}
	var pending: Array[String] = [source_id]
	while not pending.is_empty():
		var current_id: String = ""
		var current_time: float = INF
		for candidate: String in pending:
			var candidate_data: Dictionary = best[candidate]
			if float(candidate_data["time"]) < current_time:
				current_time = float(candidate_data["time"])
				current_id = candidate
		pending.erase(current_id)
		if current_id == "":
			continue
		var current: Dictionary = best[current_id]
		# A memory crystal stores the wave instead of passing it on in the same
		# strike. Its later echo is propagated as a new source, which is what
		# makes the three memories happen one after another.
		if str((nodes[current_id] as Dictionary).get("kind", "")) == "memory" and current_id != source_id:
			continue
		var ids: Array = nodes.keys()
		for other: Variant in ids:
			var other_id: String = str(other)
			if not can_emit_to(current_id, other_id):
				continue
			var from_data: Dictionary = nodes[current_id]
			var to_data: Dictionary = nodes[other_id]
			var distance: float = (to_data["position"] as Vector3).distance_to(from_data["position"] as Vector3)
			var travel_time: float = distance / WAVE_SPEED
			var next_amp: float = float(current["amp"]) * pow(ATTENUATION_PER_M, distance)
			if next_amp < MIN_AMPLITUDE:
				continue
			var next_time: float = float(current["time"]) + travel_time
			if best.has(other_id):
				var existing: Dictionary = best[other_id]
				if float(existing["amp"]) >= next_amp:
					continue
			best[other_id] = {"amp": next_amp, "time": next_time, "parent": current_id}
			pending.append(other_id)

	for reached_id: Variant in best.keys():
		var reached: String = str(reached_id)
		if reached == source_id:
			continue
		var reached_data: Dictionary = best[reached]
		var parent_id: String = str(reached_data["parent"])
		if not best.has(parent_id):
			continue
		var parent_data: Dictionary = best[parent_id]
		events.append({
			"type": "travel",
			"from": parent_id,
			"to": reached,
			"start": float(parent_data["time"]),
			"end": float(reached_data["time"]),
			"amp_from": float(parent_data["amp"]),
			"amp_to": float(reached_data["amp"]),
			"distance": (get_position(reached) - get_position(parent_id)).length(),
		})

	for arrived_id: Variant in best.keys():
		var arrived: String = str(arrived_id)
		if arrived == source_id:
			continue
		var arrived_data: Dictionary = best[arrived]
		var node_data: Dictionary = nodes[arrived]
		var kind: String = str(node_data.get("kind", ""))
		var arrival_amp: float = float(arrived_data["amp"])
		var arrival_time: float = float(arrived_data["time"])
		events.append({
			"type": "arrive",
			"id": arrived,
			"time": arrival_time,
			"amp": arrival_amp,
			"parent": str(arrived_data["parent"]),
			"kind": kind,
		})
		if kind == "memory":
			if arrival_amp < float(node_data.get("memory_threshold", MEMORY_THRESHOLD)):
				events.append({"type": "weak", "id": arrived, "time": arrival_time, "amp": arrival_amp})
		else:
			var has_outgoing: bool = false
			for other: Variant in nodes.keys():
				if can_emit_to(arrived, str(other)):
					has_outgoing = true
					break
			if not has_outgoing:
				events.append({"type": "dead_end", "id": arrived, "time": arrival_time, "amp": arrival_amp})

	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = float(a.get("start", a.get("time", 0.0)))
		var tb: float = float(b.get("start", b.get("time", 0.0)))
		return ta < tb
	)
	return events


## Convenience for tests and the HUD objective: is there any path?
func reaches(source_id: String, target_id: String, amplitude: float = 1.0) -> bool:
	if not nodes.has(source_id) or not nodes.has(target_id):
		return false
	var events: Array[Dictionary] = propagate(source_id, amplitude)
	for event: Dictionary in events:
		if str(event.get("type", "")) == "arrive" and str(event.get("id", "")) == target_id:
			return true
	return false


func reached_amplitude(source_id: String, target_id: String, amplitude: float = 1.0) -> float:
	if not nodes.has(source_id) or not nodes.has(target_id):
		return 0.0
	var events: Array[Dictionary] = propagate(source_id, amplitude)
	for event: Dictionary in events:
		if str(event.get("type", "")) == "arrive" and str(event.get("id", "")) == target_id:
			return float(event.get("amp", 0.0))
	return 0.0
