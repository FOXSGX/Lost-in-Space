extends Node3D

## Runtime, art-only feedback layer for the six cave cooperation mechanisms.
## It never owns puzzle state: the chapter remains authoritative and calls this
## layer only after the host has accepted an action or a snapshot has arrived.
## All nodes are created under the cave root (not inside the imported GLB), so
## RES_ anchors and the v3 asset stay untouched.

const STATE_IDLE := 0
const STATE_ACTIVATING := 1
const STATE_ARMED := 2
const STATE_COMPLETED := 3
const STATE_NAMES := ["IDLE", "ACTIVATING", "ARMED", "COMPLETED"]

const MECH_KINDS: Array[String] = [
    "power", "clamp", "relay_entry", "relay_exit", "freight", "stabilizer"
]
const MECH_COLORS := {
    "power": Color("#46e3ff"),
    "clamp": Color("#ffb347"),
    "relay_entry": Color("#78f0ff"),
    "relay_exit": Color("#ffd166"),
    "freight": Color("#ffc857"),
    "stabilizer": Color("#63ffb0")
}
const MECH_LABELS := {
    "power": "E 供能",
    "clamp": "E 定场",
    "relay_entry": "E 入口中继",
    "relay_exit": "E 出口中继",
    "freight": "E 货箱",
    "stabilizer": "E 接收"
}
const TOOL_COLORS := {
    "conduit": Color("#46e3ff"),
    "hook": Color("#ffb347"),
    "scanner": Color("#7dffc0"),
    "shield": Color("#9fc4ff"),
    "manual": Color("#ffd28a"),
    "drone": Color("#b9c9ff")
}
const TOOL_LABELS := {
    "conduit": "导能枪",
    "hook": "磁力钩索",
    "scanner": "广域扫描仪",
    "shield": "便携护盾",
    "manual": "应急操作",
    "drone": "共振无人机"
}

var mechanisms: Dictionary = {}
var gates: Array[Dictionary] = []
var cart_marker: MeshInstance3D
var activation_count: int = 0
var completion_count: int = 0
var flow_count: int = 0
var tool_action_count: int = 0
var manual_pulse_count: int = 0
var evacuation_count: int = 0
var last_tool_action: Dictionary = {}
var tool_usage: Dictionary = {}
var world_props: Dictionary = {}
var last_event: Dictionary = {}
var last_animation_msec: int = 0

var _built: bool = false
var _flow_root: Node3D
var _clock: float = 0.0
var _completed_tasks: Dictionary = {}

func build(positions: Dictionary, gate_positions: Array[Vector3]) -> void:
    if _built:
        return
    _built = true
    _flow_root = Node3D.new()
    _flow_root.name = "CaveFeedbackFlows"
    add_child(_flow_root)
    for kind in MECH_KINDS:
        if positions.has(kind):
            var at: Vector3 = positions[kind]
            _create_mechanism(kind, at)
    for index in gate_positions.size():
        _create_gate(index, gate_positions[index])
    _create_cart_marker()
    set_meta("feedback_built", true)

func _create_cart_marker() -> void:
    cart_marker = MeshInstance3D.new()
    cart_marker.name = "MovingCartTarget"
    var mesh := TorusMesh.new()
    mesh.inner_radius = 0.42
    mesh.outer_radius = 0.52
    mesh.rings = 24
    mesh.ring_segments = 8
    cart_marker.mesh = mesh
    cart_marker.material_override = _make_material(Color("#ffd166"), 1.0, 0.75, true)
    cart_marker.position = Vector3(24.0, 1.15, 0.0)
    cart_marker.visible = false
    cart_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(cart_marker)

func update_cart_target(at_x: float, visible_state: bool) -> void:
    if cart_marker == null:
        return
    cart_marker.visible = visible_state
    cart_marker.position = Vector3(at_x, 1.15, 0.0)
    cart_marker.rotation.y += 0.04

func bind_world_props(visual: Node3D) -> void:
    if visual == null:
        return
    var names := [
        "Task01_Power_Orb", "Task01_Power_OrbRing", "Task01_Power_OrbPost",
        "Task01_Clamp_Jaw_1", "Task01_Clamp_Jaw_-1", "Task01_Clamp_BeaconRing",
        "Task02_FreightCrate", "Task02_HoistClamp", "Task02_HoistJaw_1",
        "Task02_HoistJaw_-1", "Task02_Socket_FloatRing", "Task02_Socket_FloatRing2",
        "Task02_Socket_Stabilizer", "TunnelExit_Header"
    ]
    for node_name in names:
        var node := visual.find_child(node_name, true, false)
        if node != null:
            world_props[node_name] = node

func _kick_world_prop(kind: String) -> void:
    match kind:
        "power":
            _animate_prop("Task01_Power_Orb", 0.16, 0.18)
            _spin_prop("Task01_Power_OrbRing", 0.42)
        "clamp":
            _animate_prop("Task01_Clamp_Jaw_1", 0.20, 0.16)
            _animate_prop("Task01_Clamp_Jaw_-1", 0.20, 0.16)
            _spin_prop("Task01_Clamp_BeaconRing", 0.4)
        "freight":
            _animate_prop("Task02_FreightCrate", -0.10, 0.15)
            _animate_prop("Task02_HoistClamp", 0.12, 0.16)
        "stabilizer":
            _spin_prop("Task02_Socket_FloatRing", 0.7)
            _spin_prop("Task02_Socket_FloatRing2", -0.7)
            _animate_prop("Task02_Socket_Stabilizer", 0.16, 0.22)
        "relay_entry", "relay_exit":
            _animate_prop("TunnelExit_Header", 0.05, 0.18)

func _animate_prop(prop_name: String, offset_y: float, duration: float) -> void:
    var prop := world_props.get(prop_name) as Node3D
    if prop == null:
        return
    var base := prop.position
    var tween := create_tween()
    tween.tween_property(prop, "position", base + Vector3(0.0, offset_y, 0.0), duration * 0.45)
    tween.tween_property(prop, "position", base, duration * 0.55)

func _spin_prop(prop_name: String, amount: float) -> void:
    var prop := world_props.get(prop_name) as Node3D
    if prop == null:
        return
    var base := prop.rotation
    var tween := create_tween()
    tween.tween_property(prop, "rotation", base + Vector3(0.0, amount, 0.0), 0.42)
    tween.tween_property(prop, "rotation", base, 0.22)

func mechanism_count() -> int:
    return mechanisms.size()

func gate_count() -> int:
    return gates.size()

func has_mechanism(kind: String) -> bool:
    return mechanisms.has(kind)

func get_state(kind: String) -> int:
    var m: Dictionary = mechanisms.get(kind, {})
    if m.is_empty():
        return STATE_IDLE
    return int(m.state)

func get_state_name(kind: String) -> String:
    return String(STATE_NAMES[clampi(get_state(kind), 0, STATE_NAMES.size() - 1)])

func get_peer(kind: String) -> int:
    var m: Dictionary = mechanisms.get(kind, {})
    if m.is_empty():
        return 0
    return int(m.peer)

func color_for(kind: String) -> Color:
    return MECH_COLORS.get(kind, Color.WHITE)

func gate_is_opening(index: int) -> bool:
    if index < 0 or index >= gates.size():
        return false
    return bool(gates[index].opening)

func gate_is_open(index: int) -> bool:
    if index < 0 or index >= gates.size():
        return false
    return bool(gates[index].open)

func gate_curtain_scale(index: int) -> float:
    if index < 0 or index >= gates.size():
        return 0.0
    var curtain: MeshInstance3D = gates[index].curtain
    return curtain.scale.y

func update_camera_occlusion(camera_position: Vector3, target: Vector3) -> void:
    var view := (target - camera_position).normalized()
    for gate in gates:
        var root: Node3D = gate.root
        var header: MeshInstance3D = gate.header
        var curtain: MeshInstance3D = gate.curtain
        var gate_offset := root.global_position + Vector3(0.0, 2.7, 0.0) - camera_position
        # Once the lens has passed a gate, the open frame is behind the player;
        # keeping its transparent curtain/header alive can veil the next room.
        root.visible = gate_offset.dot(view) > -0.15
        for part in [header, curtain]:
            if part == null or not is_instance_valid(part):
                continue
            var center: Vector3 = part.global_transform * part.get_aabb().get_center()
            var offset := center - camera_position
            var close := offset.length() < 4.2 and offset.normalized().dot(view) > 0.45
            var want := 0.65 if close else 0.0
            part.transparency = lerpf(part.transparency, want, 0.25)
            if part == header:
                header.visible = not (offset.length() < 3.4 and offset.normalized().dot(view) > 0.45)

func _create_mechanism(kind: String, at: Vector3) -> void:
    var color: Color = color_for(kind)
    var root := Node3D.new()
    root.name = "CaveFeedback_%s" % kind
    root.position = at + Vector3(0.0, 0.35, 0.0)
    add_child(root)
    root.set_meta("feedback_kind", kind)
    root.set_meta("feedback_state", STATE_IDLE)
    root.set_meta("feedback_peer", 0)

    var ring_mat := _make_material(color, 0.55, 1.0, false)
    var ring := MeshInstance3D.new()
    ring.name = "IdleRing"
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 1.05
    ring_mesh.outer_radius = 1.18
    ring_mesh.rings = 36
    ring_mesh.ring_segments = 8
    ring.mesh = ring_mesh
    ring.material_override = ring_mat
    ring.position.y = 0.08
    ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(ring)

    var halo_mat := _make_material(color, 0.65, 1.0, false)
    var halo := MeshInstance3D.new()
    halo.name = "Halo"
    var halo_mesh := TorusMesh.new()
    halo_mesh.inner_radius = 0.48
    halo_mesh.outer_radius = 0.56
    halo_mesh.rings = 32
    halo_mesh.ring_segments = 8
    halo.mesh = halo_mesh
    halo.material_override = halo_mat
    halo.position.y = 2.15
    halo.rotation_degrees.x = 90.0
    halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(halo)

    var core_mat := _make_material(color, 1.0, 1.0, false)
    var core := MeshInstance3D.new()
    core.name = "Core"
    var core_mesh := SphereMesh.new()
    core_mesh.radius = 0.22
    core_mesh.height = 0.44
    core_mesh.radial_segments = 12
    core_mesh.rings = 6
    core.mesh = core_mesh
    core.material_override = core_mat
    core.position.y = 1.35
    core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(core)

    var marker_mat := _make_material(Color.WHITE, 1.4, 0.85, true)
    var marker := MeshInstance3D.new()
    marker.name = "PlayerMarker"
    var marker_mesh := SphereMesh.new()
    marker_mesh.radius = 0.13
    marker_mesh.height = 0.26
    marker_mesh.radial_segments = 10
    marker_mesh.rings = 5
    marker.mesh = marker_mesh
    marker.material_override = marker_mat
    marker.position.y = 2.9
    marker.visible = false
    marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(marker)

    var beam_mat := _make_material(Color.WHITE, 0.9, 0.42, true)
    var beam := MeshInstance3D.new()
    beam.name = "PlayerBeam"
    var beam_mesh := CylinderMesh.new()
    beam_mesh.top_radius = 0.035
    beam_mesh.bottom_radius = 0.055
    beam_mesh.height = 2.35
    beam_mesh.radial_segments = 8
    beam.mesh = beam_mesh
    beam.material_override = beam_mat
    beam.position.y = 1.65
    beam.visible = false
    beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(beam)

    var label := Label3D.new()
    label.name = "HintLabel"
    label.text = String(MECH_LABELS.get(kind, "E"))
    label.font_size = 34
    label.pixel_size = 0.006
    label.position = Vector3(0.0, 3.05, 0.0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = color.lightened(0.28)
    label.outline_size = 6
    label.outline_modulate = Color(0.02, 0.03, 0.05, 0.92)
    label.shaded = false
    label.no_depth_test = false
    root.add_child(label)

    var light := OmniLight3D.new()
    light.name = "FeedbackLight"
    light.light_color = color
    light.light_energy = 0.48
    light.omni_range = 5.0
    light.position = Vector3(0.0, 1.3, 0.0)
    light.shadow_enabled = false
    root.add_child(light)

    var index: int = mechanisms.size()
    var entry := {
        "root": root,
        "ring": ring,
        "ring_mat": ring_mat,
        "halo": halo,
        "halo_mat": halo_mat,
        "core": core,
        "core_mat": core_mat,
        "marker": marker,
        "marker_mat": marker_mat,
        "beam": beam,
        "beam_mat": beam_mat,
        "label": label,
        "light": light,
        "state": STATE_IDLE,
        "peer": 0,
        "phase": float(index) * 1.3,
        "activation_tweens": []
    }
    mechanisms[kind] = entry
    _apply_state_visual(entry, STATE_IDLE, 0)

func _create_gate(index: int, at: Vector3) -> void:
    var root := Node3D.new()
    root.name = "CaveFeedbackGate_%d" % index
    root.position = at
    add_child(root)

    var frame_color := Color("#58d9e8") if index == 0 else Color("#ffc766")
    var post_mat := _make_material(frame_color.darkened(0.2), 0.75, 1.0, false)
    var post_l := MeshInstance3D.new()
    post_l.name = "PostL"
    var post_mesh := BoxMesh.new()
    post_mesh.size = Vector3(0.22, 5.4, 0.34)
    post_l.mesh = post_mesh
    post_l.material_override = post_mat
    post_l.position = Vector3(0.0, 2.7, -4.15)
    post_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(post_l)
    var post_r := MeshInstance3D.new()
    post_r.name = "PostR"
    post_r.mesh = post_mesh
    post_r.material_override = post_mat
    post_r.position = Vector3(0.0, 2.7, 4.15)
    post_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(post_r)

    var curtain_mat := _make_material(frame_color, 1.0, 0.34, true)
    var curtain := MeshInstance3D.new()
    curtain.name = "EnergyCurtain"
    var curtain_mesh := BoxMesh.new()
    curtain_mesh.size = Vector3(0.12, 5.25, 8.2)
    curtain.mesh = curtain_mesh
    curtain.material_override = curtain_mat
    curtain.position = Vector3(0.0, 2.7, 0.0)
    curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(curtain)

    var panel_mat := _make_material(frame_color, 1.0, 0.26, true)
    var panel_l := MeshInstance3D.new()
    panel_l.name = "ShutterL"
    var panel_mesh := BoxMesh.new()
    panel_mesh.size = Vector3(0.10, 5.1, 2.3)
    panel_l.mesh = panel_mesh
    panel_l.material_override = panel_mat
    panel_l.position = Vector3(-0.04, 2.7, -2.1)
    panel_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(panel_l)
    var panel_r := MeshInstance3D.new()
    panel_r.name = "ShutterR"
    panel_r.mesh = panel_mesh
    panel_r.material_override = panel_mat
    panel_r.position = Vector3(-0.04, 2.7, 2.1)
    panel_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(panel_r)

    var header := MeshInstance3D.new()
    header.name = "Header"
    var header_mesh := BoxMesh.new()
    header_mesh.size = Vector3(0.28, 0.28, 8.8)
    header.mesh = header_mesh
    header.material_override = post_mat
    header.position = Vector3(0.0, 5.4, 0.0)
    header.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(header)

    var label := Label3D.new()
    label.name = "GateLabel"
    label.text = "LOCKED"
    label.font_size = 40
    label.pixel_size = 0.008
    label.position = Vector3(0.0, 3.4, 2.2)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = frame_color
    label.outline_size = 8
    label.outline_modulate = Color(0.02, 0.03, 0.05, 0.92)
    label.shaded = false
    root.add_child(label)

    var light := OmniLight3D.new()
    light.name = "GateLight"
    light.light_color = frame_color
    light.light_energy = 0.55
    light.omni_range = 7.0
    light.position = Vector3(0.0, 2.8, 0.0)
    light.shadow_enabled = false
    root.add_child(light)

    gates.append({
        "root": root,
        "curtain": curtain,
        "curtain_mat": curtain_mat,
        "post_l": post_l,
        "post_r": post_r,
        "panel_l": panel_l,
        "panel_r": panel_r,
        "header": header,
        "label": label,
        "light": light,
        "opening": false,
        "open": false,
        "base_color": frame_color
    })

func _make_material(color: Color, energy: float, alpha: float, transparent: bool) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(color.r, color.g, color.b, alpha)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = energy
    mat.roughness = 0.3
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    if transparent:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return mat

func _process(delta: float) -> void:
    _clock += delta
    for kind in MECH_KINDS:
        var m: Dictionary = mechanisms.get(kind, {})
        if m.is_empty():
            continue
        var state: int = int(m.state)
        var ring: MeshInstance3D = m.ring
        var core: MeshInstance3D = m.core
        var light: OmniLight3D = m.light
        var halo: MeshInstance3D = m.halo
        if state == STATE_IDLE:
            var wave: float = sin(_clock * 2.1 + float(m.phase))
            ring.scale = Vector3.ONE * (1.0 + wave * 0.045)
            core.position.y = 1.35 + wave * 0.07
            light.light_energy = 0.48 + wave * 0.12
            halo.rotation.y += delta * 0.7
        elif state == STATE_ARMED:
            ring.scale = Vector3.ONE * 1.04
            core.position.y = 1.35
            halo.rotation.y += delta * 1.4
            var marker: MeshInstance3D = m.marker
            marker.position.y = 2.9 + sin(_clock * 3.0 + float(m.phase)) * 0.06
        elif state == STATE_COMPLETED:
            halo.rotation.y += delta * 1.0

func play_activation(kind: String, peer_id: int) -> bool:
    var m: Dictionary = mechanisms.get(kind, {})
    if m.is_empty() or int(m.state) != STATE_IDLE:
        return false
    activation_count += 1
    last_animation_msec = Time.get_ticks_msec()
    last_event = {"type": "activation", "kind": kind, "peer": peer_id, "msec": last_animation_msec}
    m.peer = peer_id
    _apply_state_visual(m, STATE_ACTIVATING, peer_id)
    _kick_world_prop(kind)
    var root: Node3D = m.root
    var core: MeshInstance3D = m.core
    var ring: MeshInstance3D = m.ring
    var light: OmniLight3D = m.light
    var color: Color = _peer_color(peer_id, color_for(kind))

    var press := create_tween()
    press.set_parallel(true)
    press.tween_property(core, "scale", Vector3(1.8, 1.8, 1.8), 0.12)
    press.tween_property(core, "position:y", 1.68, 0.12)
    press.tween_property(ring, "scale", Vector3(1.38, 1.0, 1.38), 0.18)
    press.tween_property(light, "light_energy", 1.35, 0.12)
    m.activation_tweens.append(press)

    var settle := create_tween()
    settle.tween_interval(0.18)
    settle.set_parallel(true)
    settle.tween_property(core, "scale", Vector3.ONE, 0.16)
    settle.tween_property(core, "position:y", 1.35, 0.16)
    settle.tween_property(ring, "scale", Vector3.ONE, 0.18)
    settle.tween_property(light, "light_energy", 0.85, 0.18)
    m.activation_tweens.append(settle)

    _spawn_shock(root.global_position + Vector3(0.0, 0.12, 0.0), color)
    _spawn_sparks(root.global_position + Vector3(0.0, 1.3, 0.0), color, 10)
    _flash_gate_for_kind(kind, color)

    get_tree().create_timer(0.36).timeout.connect(func() -> void:
        if not is_inside_tree():
            return
        var current: Dictionary = mechanisms.get(kind, {})
        if not current.is_empty() and int(current.state) == STATE_ACTIVATING:
            _apply_state_visual(current, STATE_ARMED, int(current.peer))
    )
    return true

func play_tool_action(tool: String, kind: String, from: Vector3, at: Vector3, peer_id: int, drone: bool = false) -> void:
    var color: Color = TOOL_COLORS.get(tool, Color.WHITE)
    if drone:
        color = TOOL_COLORS.drone
    tool_action_count += 1
    tool_usage[tool] = int(tool_usage.get(tool, 0)) + 1
    last_tool_action = {
        "tool": tool,
        "kind": kind,
        "peer": peer_id,
        "drone": drone,
        "msec": Time.get_ticks_msec()
    }
    match tool:
        "conduit":
            _tool_conduit(from, at, color)
        "hook":
            _tool_hook(from, at, color)
        "scanner":
            _tool_scanner(at, color)
        "shield":
            _tool_shield(at, color)
        _:
            _spawn_shock(at + Vector3(0, 0.1, 0), color)
    if drone:
        _spawn_drone_marker(from, at, color)

func _tool_conduit(from: Vector3, at: Vector3, color: Color) -> void:
    var start := from + Vector3(0.0, 1.2, 0.0)
    var end := at + Vector3(0.0, 1.35, 0.0)
    _beam_between(start, end, color, 0.06, 0.52, 1.1)
    for index in 2:
        _delayed_packet(start, end, color, float(index) * 0.12)
    _spawn_shock(at + Vector3(0.0, 0.1, 0.0), color)

func _tool_hook(from: Vector3, at: Vector3, color: Color) -> void:
    var start := from + Vector3(0.0, 1.1, 0.0)
    var end := at + Vector3(0.0, 1.1, 0.0)
    _beam_between(start, end, color, 0.03, 0.42, 1.0)
    var hook := MeshInstance3D.new()
    hook.name = "HookHead"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.22, 0.22, 0.5)
    hook.mesh = mesh
    hook.material_override = _make_material(color, 1.3, 0.9, true)
    hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(hook)
    hook.global_position = start
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(hook, "global_position", end, 0.28)
    tween.tween_property(hook, "rotation:y", TAU, 0.28)
    tween.finished.connect(hook.queue_free)
    _spawn_shock(at + Vector3(0.0, 0.1, 0.0), color)
    _spawn_world_label(at + Vector3(0.0, 2.7, 0.0), "HOOK", color, 1.0)

func _tool_scanner(at: Vector3, color: Color) -> void:
    for wave in 3:
        var ring := MeshInstance3D.new()
        ring.name = "ScanWave"
        var mesh := TorusMesh.new()
        mesh.inner_radius = 0.85
        mesh.outer_radius = 0.97
        mesh.rings = 28
        mesh.ring_segments = 8
        ring.mesh = mesh
        ring.material_override = _make_material(color, 1.1, 0.5, true)
        ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _flow_root.add_child(ring)
        ring.global_position = at + Vector3(0.0, 0.12, 0.0)
        ring.scale = Vector3.ONE * 0.35
        var tween := create_tween()
        tween.set_parallel(true)
        var radius: float = 3.2 + float(wave) * 1.3
        tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.7 + float(wave) * 0.12)
        tween.tween_property(ring, "position:y", at.y + 1.0, 0.7 + float(wave) * 0.12)
        tween.finished.connect(ring.queue_free)
    var route_end := at + Vector3(18.0, 0.2, 0.0)
    _beam_between(at + Vector3(0.0, 0.9, 0.0), route_end + Vector3(0.0, 0.9, 0.0), color, 0.04, 0.32, 2.0)
    for index in 3:
        _delayed_packet(at + Vector3(0.0, 0.9, 0.0), route_end + Vector3(0.0, 0.9, 0.0), color, float(index) * 0.18)
    _spawn_world_label(at + Vector3(2.0, 3.0, 0.0), "SCAN · 隐藏路线", color, 1.5)

func _tool_shield(at: Vector3, color: Color) -> void:
    var dome := MeshInstance3D.new()
    dome.name = "ShieldDome"
    var mesh := SphereMesh.new()
    mesh.radius = 2.2
    mesh.height = 4.4
    mesh.radial_segments = 20
    mesh.rings = 10
    dome.mesh = mesh
    dome.material_override = _make_material(color, 0.55, 0.10, true)
    dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(dome)
    dome.global_position = at + Vector3(0.0, 1.1, 0.0)
    dome.scale = Vector3(0.2, 0.2, 0.2)
    var tween := create_tween()
    tween.tween_property(dome, "scale", Vector3.ONE, 0.25)
    var label := _spawn_world_label(at + Vector3(0.0, 3.5, 0.0), "SHIELD 4s", color, 4.1)
    if label != null:
        var countdown := create_tween()
        countdown.tween_method(_set_shield_countdown.bind(label), 4.0, 0.0, 4.0)
        countdown.finished.connect(label.queue_free)
    get_tree().create_timer(4.2).timeout.connect(func() -> void:
        if is_instance_valid(dome):
            dome.queue_free()
    )

func _set_shield_countdown(value: float, label: Label3D) -> void:
    if is_instance_valid(label):
        label.text = "SHIELD %ds" % int(ceil(value))

func _spawn_drone_marker(from: Vector3, at: Vector3, color: Color) -> void:
    var drone := MeshInstance3D.new()
    drone.name = "DroneProxy"
    var mesh := SphereMesh.new()
    mesh.radius = 0.18
    mesh.height = 0.36
    mesh.radial_segments = 10
    mesh.rings = 5
    drone.mesh = mesh
    drone.material_override = _make_material(color, 1.5, 0.8, true)
    drone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(drone)
    drone.global_position = from + Vector3(1.0, 1.6, 0.0)
    var tween := create_tween()
    tween.tween_property(drone, "global_position", at + Vector3(0.0, 2.2, 0.0), 0.28)
    var pulse := create_tween()
    pulse.set_loops(3)
    pulse.tween_property(drone, "scale", Vector3(1.4, 1.4, 1.4), 0.12)
    pulse.tween_property(drone, "scale", Vector3.ONE, 0.12)
    get_tree().create_timer(1.2).timeout.connect(func() -> void:
        if is_instance_valid(drone):
            drone.queue_free()
    )
    _spawn_world_label(at + Vector3(0.0, 2.9, 0.0), "DRONE", color, 1.2)

func play_manual_pulse(kind: String, progress: int, required: int, at: Vector3) -> void:
    manual_pulse_count += 1
    last_event = {"type": "manual", "kind": kind, "progress": progress, "required": required, "msec": Time.get_ticks_msec()}
    var color: Color = TOOL_COLORS.manual
    var ring := MeshInstance3D.new()
    ring.name = "ManualPulse"
    var mesh := TorusMesh.new()
    mesh.inner_radius = 0.65
    mesh.outer_radius = 0.75
    mesh.rings = 24
    mesh.ring_segments = 8
    ring.mesh = mesh
    ring.material_override = _make_material(color, 0.9, 0.55, true)
    ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(ring)
    ring.global_position = at + Vector3(0.0, 0.12, 0.0)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(ring, "scale", Vector3(1.8, 1.0, 1.8), 0.28)
    tween.tween_property(ring, "position:y", at.y + 0.8, 0.28)
    tween.finished.connect(ring.queue_free)
    _spawn_world_label(at + Vector3(0.0, 2.4, 0.0), "应急 %d/%d" % [progress, required], color, 0.8)

func play_evacuation(exit_position: Vector3, duration: float = 3.0) -> void:
    evacuation_count += 1
    last_event = {"type": "evacuation", "msec": Time.get_ticks_msec()}
    _beam_between(Vector3(54.0, 1.2, 0.0), exit_position + Vector3(0.0, 1.2, 0.0), Color("#ff9d6a"), 0.08, 0.35, duration)
    for index in 14:
        var debris := MeshInstance3D.new()
        debris.name = "CaveDebris"
        var mesh := SphereMesh.new()
        mesh.radius = randf_range(0.12, 0.32)
        mesh.height = mesh.radius * 2.0
        mesh.radial_segments = 6
        mesh.rings = 3
        debris.mesh = mesh
        debris.material_override = _make_material(Color("#c77a52"), 0.15, 1.0, false)
        debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _flow_root.add_child(debris)
        debris.global_position = Vector3(randf_range(54.0, 88.0), randf_range(8.0, 13.0), randf_range(-4.0, 4.0))
        var tween := create_tween()
        tween.tween_property(debris, "global_position:y", 0.2, randf_range(1.0, 1.8))
        tween.finished.connect(debris.queue_free)
    _spawn_world_label(Vector3(72.0, 5.0, 0.0), "EVACUATE +X", Color("#ffb07a"), duration)
    _spawn_shock(exit_position + Vector3(0.0, 0.2, 0.0), Color("#ff9d6a"))

func _spawn_world_label(at: Vector3, text: String, color: Color, lifetime: float) -> Label3D:
    if _flow_root == null:
        return null
    var label := Label3D.new()
    label.name = "ToolWorldLabel"
    label.text = text
    label.font_size = 34
    label.pixel_size = 0.006
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = color.lightened(0.2)
    label.outline_size = 6
    label.outline_modulate = Color(0.02, 0.03, 0.05, 0.92)
    label.shaded = false
    _flow_root.add_child(label)
    label.global_position = at
    get_tree().create_timer(lifetime).timeout.connect(func() -> void:
        if is_instance_valid(label):
            label.queue_free()
    )
    return label

func complete_mechanism(kind: String, peer_id: int = 0) -> bool:
    var m: Dictionary = mechanisms.get(kind, {})
    if m.is_empty() or int(m.state) == STATE_COMPLETED:
        return false
    completion_count += 1
    last_animation_msec = Time.get_ticks_msec()
    last_event = {"type": "completion", "kind": kind, "peer": peer_id, "msec": last_animation_msec}
    if peer_id != 0:
        m.peer = peer_id
    _kill_activation_tweens(m)
    _apply_state_visual(m, STATE_COMPLETED, int(m.peer))
    _kick_world_prop(kind)
    var root: Node3D = m.root
    var ring: MeshInstance3D = m.ring
    var ring_mat: StandardMaterial3D = m.ring_mat
    var light: OmniLight3D = m.light
    var color: Color = _peer_color(int(m.peer), color_for(kind)) if int(m.peer) != 0 else color_for(kind)

    var pulse := create_tween()
    pulse.set_parallel(true)
    pulse.tween_property(ring, "scale", Vector3(2.15, 1.0, 2.15), 0.18)
    pulse.tween_property(ring_mat, "emission_energy_multiplier", 2.0, 0.18)
    pulse.tween_property(light, "light_energy", 1.8, 0.18)
    var settle := create_tween()
    settle.tween_interval(0.24)
    settle.set_parallel(true)
    settle.tween_property(ring, "scale", Vector3.ONE * 1.06, 0.42)
    settle.tween_property(ring_mat, "emission_energy_multiplier", 1.05, 0.42)
    settle.tween_property(light, "light_energy", 0.9, 0.42)
    _spawn_shock(root.global_position + Vector3(0.0, 0.12, 0.0), color)
    _spawn_sparks(root.global_position + Vector3(0.0, 1.3, 0.0), Color(color.r, color.g, color.b, 1.0), 14)
    return true

func play_task_complete(task: int, peers: Dictionary = {}) -> void:
    if _completed_tasks.has(task):
        return
    _completed_tasks[task] = true
    var kinds: Array[String] = []
    if task == 1:
        kinds = ["power", "clamp"]
    elif task == 2:
        kinds = ["relay_entry", "relay_exit"]
    elif task == 3:
        kinds = ["freight", "stabilizer"]
    for kind in kinds:
        complete_mechanism(kind, int(peers.get(kind, 0)))
    flow_count += 1
    last_event = {"type": "task_complete", "task": task, "msec": Time.get_ticks_msec()}
    _play_task_flow(task)

func apply_snapshot_state(states: Dictionary, peers: Dictionary, gates_open: Array[bool]) -> void:
    for kind in MECH_KINDS:
        var m: Dictionary = mechanisms.get(kind, {})
        if m.is_empty():
            continue
        var target: int = int(states.get(kind, STATE_IDLE))
        var peer: int = int(peers.get(kind, 0))
        if int(m.state) == STATE_ACTIVATING and target == STATE_ARMED:
            continue
        if int(m.state) == target and int(m.peer) == peer:
            continue
        _apply_state_visual(m, target, peer)
    for index in gates.size():
        var want_open: bool = index < gates_open.size() and bool(gates_open[index])
        var gate: Dictionary = gates[index]
        if want_open:
            if not bool(gate.open) and not bool(gate.opening):
                set_gate_open_instant(index)
        else:
            if bool(gate.open) and not bool(gate.opening):
                set_gate_closed(index)

func _apply_state_visual(m: Dictionary, state: int, peer: int) -> void:
    m.state = state
    m.peer = peer
    var root: Node3D = m.root
    root.set_meta("feedback_state", state)
    root.set_meta("feedback_state_name", String(STATE_NAMES[clampi(state, 0, 3)]))
    root.set_meta("feedback_peer", peer)
    var base: Color = color_for(String(root.get_meta("feedback_kind", "")))
    var color: Color = _peer_color(peer, base) if peer != 0 and state == STATE_ARMED else base
    var ring_mat: StandardMaterial3D = m.ring_mat
    var halo_mat: StandardMaterial3D = m.halo_mat
    var core_mat: StandardMaterial3D = m.core_mat
    var marker: MeshInstance3D = m.marker
    var marker_mat: StandardMaterial3D = m.marker_mat
    var beam: MeshInstance3D = m.beam
    var beam_mat: StandardMaterial3D = m.beam_mat
    var label: Label3D = m.label
    var light: OmniLight3D = m.light
    var ring: MeshInstance3D = m.ring

    if state == STATE_IDLE:
        ring_mat.albedo_color = Color(base.r, base.g, base.b, 1.0)
        ring_mat.emission = base
        ring_mat.emission_energy_multiplier = 0.55
        halo_mat.emission = base
        halo_mat.emission_energy_multiplier = 0.65
        core_mat.albedo_color = Color(base.r, base.g, base.b, 1.0)
        core_mat.emission = base
        core_mat.emission_energy_multiplier = 1.0
        label.text = String(MECH_LABELS.get(String(root.get_meta("feedback_kind", "")), "E"))
        label.modulate = base.lightened(0.28)
        marker.visible = false
        beam.visible = false
        light.light_energy = 0.48
        ring.scale = Vector3.ONE
    elif state == STATE_ARMED:
        ring_mat.albedo_color = Color(base.r, base.g, base.b, 1.0)
        ring_mat.emission = color
        ring_mat.emission_energy_multiplier = 0.95
        halo_mat.emission = color
        halo_mat.emission_energy_multiplier = 1.1
        core_mat.emission = color
        core_mat.emission_energy_multiplier = 1.35
        label.text = "P%d 已接通" % peer
        label.modulate = color.lightened(0.2)
        marker.visible = true
        marker_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
        marker_mat.emission = color
        beam.visible = true
        beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.38)
        beam_mat.emission = color
        light.light_energy = 0.88
        ring.scale = Vector3.ONE * 1.04
    elif state == STATE_COMPLETED:
        ring_mat.albedo_color = Color(base.r, base.g, base.b, 1.0)
        ring_mat.emission = base.lerp(Color.WHITE, 0.22)
        ring_mat.emission_energy_multiplier = 1.05
        halo_mat.emission = base
        halo_mat.emission_energy_multiplier = 1.2
        core_mat.emission = base
        core_mat.emission_energy_multiplier = 1.5
        label.text = "完成"
        label.modulate = base.lightened(0.35)
        marker.visible = false
        beam.visible = false
        light.light_energy = 0.92
        ring.scale = Vector3.ONE * 1.06
    else:
        # ACTIVATING keeps the idle colour until the settle tween; the label
        # and light make the press readable even before the pulse resolves.
        label.text = "接通中"
        label.modulate = base.lightened(0.45)
        marker.visible = false
        beam.visible = false
        light.light_energy = 1.35
        ring.scale = Vector3.ONE

func _peer_color(peer_id: int, fallback: Color) -> Color:
    if peer_id <= 0:
        return fallback
    var colors: Array = Main3D.PLAYER_COLORS
    if colors.is_empty():
        return fallback
    return colors[(peer_id - 1) % colors.size()]

func _kill_activation_tweens(m: Dictionary) -> void:
    var tweens: Array = m.get("activation_tweens", [])
    for tween_value in tweens:
        var tween: Tween = tween_value
        if tween != null and tween.is_valid():
            tween.kill()
    tweens.clear()

func _flash_gate_for_kind(kind: String, color: Color) -> void:
    var gate_index: int = -1
    if kind in ["power", "clamp"]:
        gate_index = 0
    elif kind in ["relay_entry", "relay_exit"]:
        gate_index = 1
    elif kind in ["freight", "stabilizer"]:
        return
    if gate_index < 0 or gate_index >= gates.size():
        return
    var light: OmniLight3D = gates[gate_index].light
    var tween := create_tween()
    tween.tween_property(light, "light_energy", 1.55, 0.12)
    tween.tween_property(light, "light_energy", 0.7, 0.3)

func _spawn_shock(at: Vector3, color: Color) -> void:
    var shock := MeshInstance3D.new()
    shock.name = "FeedbackShock"
    var mesh := TorusMesh.new()
    mesh.inner_radius = 1.05
    mesh.outer_radius = 1.2
    mesh.rings = 28
    mesh.ring_segments = 8
    shock.mesh = mesh
    shock.material_override = _make_material(color, 1.2, 0.5, true)
    add_child(shock)
    shock.global_position = at
    shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(shock, "scale", Vector3(3.0, 1.0, 3.0), 0.42)
    tween.tween_property(shock, "position:y", at.y + 1.0, 0.42)
    tween.finished.connect(shock.queue_free)

func _spawn_sparks(at: Vector3, color: Color, count: int) -> void:
    var root: Node3D = _flow_root if _flow_root != null else self
    for index in count:
        var spark := MeshInstance3D.new()
        spark.name = "FeedbackSpark"
        var mesh := SphereMesh.new()
        mesh.radius = 0.045
        mesh.height = 0.09
        mesh.radial_segments = 8
        mesh.rings = 4
        spark.mesh = mesh
        spark.material_override = _make_material(color, 1.3, 0.9, true)
        root.add_child(spark)
        spark.global_position = at + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.3), randf_range(-0.35, 0.35))
        var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.2), randf_range(-1.0, 1.0)).normalized()
        var tween := create_tween()
        tween.set_parallel(true)
        tween.tween_property(spark, "global_position", spark.global_position + direction * randf_range(0.55, 1.3), 0.45)
        tween.tween_property(spark, "scale", Vector3.ZERO, 0.45)
        tween.finished.connect(spark.queue_free)

func _play_task_flow(task: int) -> void:
    if _flow_root == null:
        return
    if task == 1:
        var gate: Vector3 = gates[0].root.global_position + Vector3(0.0, 2.5, 0.0)
        var power: Vector3 = mechanisms["power"].root.global_position + Vector3(0.0, 1.4, 0.0)
        var clamp_pos: Vector3 = mechanisms["clamp"].root.global_position + Vector3(0.0, 1.4, 0.0)
        _beam_between(power, gate, color_for("power"), 0.055, 0.38, 1.2)
        _beam_between(clamp_pos, gate, color_for("clamp"), 0.055, 0.38, 1.2)
        for index in 3:
            _delayed_packet(power, gate, color_for("power"), float(index) * 0.08)
            _delayed_packet(clamp_pos, gate, color_for("clamp"), 0.04 + float(index) * 0.08)
        _pulse_gate_light(0)
    elif task == 2:
        var entry: Vector3 = mechanisms["relay_entry"].root.global_position + Vector3(0.0, 1.2, 0.0)
        var exit_pos: Vector3 = mechanisms["relay_exit"].root.global_position + Vector3(0.0, 1.2, 0.0)
        var gate: Vector3 = gates[1].root.global_position + Vector3(0.0, 2.4, 0.0)
        _beam_between(entry, exit_pos, color_for("relay_entry"), 0.05, 0.35, 1.3)
        _beam_between(exit_pos, gate, color_for("relay_exit"), 0.05, 0.35, 1.3)
        for index in 4:
            _delayed_packet(entry, exit_pos, color_for("relay_entry"), float(index) * 0.1)
            _delayed_packet(exit_pos, gate, color_for("relay_exit"), 0.32 + float(index) * 0.1)
        _pulse_gate_light(1)
    elif task == 3:
        var freight: Vector3 = mechanisms["freight"].root.global_position + Vector3(0.0, 1.4, 0.0)
        var socket: Vector3 = mechanisms["stabilizer"].root.global_position + Vector3(0.0, 1.4, 0.0)
        var exit_point := Vector3(88.0, 1.4, 0.0)
        _beam_between(freight, socket, color_for("freight"), 0.055, 0.38, 1.4)
        _beam_between(socket, exit_point, color_for("stabilizer"), 0.05, 0.32, 1.4)
        for index in 3:
            _delayed_packet(freight, socket, color_for("freight"), float(index) * 0.1)
            _delayed_packet(socket, exit_point, color_for("stabilizer"), 0.35 + float(index) * 0.1)
        _pulse_chamber_crystals()

func _beam_between(from: Vector3, to: Vector3, color: Color, width: float, alpha: float, lifetime: float) -> void:
    var root: Node3D = _flow_root
    var length: float = from.distance_to(to)
    if length < 0.05:
        return
    var beam := MeshInstance3D.new()
    beam.name = "FeedbackBeam"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, width, length)
    beam.mesh = mesh
    beam.material_override = _make_material(color, 1.0, alpha, true)
    beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(beam)
    beam.global_position = (from + to) * 0.5
    var direction := (to - from).normalized()
    var up := Vector3.UP
    if absf(direction.dot(up)) > 0.97:
        up = Vector3.RIGHT
    beam.look_at(to, up)
    beam.scale = Vector3(1.0, 1.0, 0.02)
    var tween := create_tween()
    tween.tween_property(beam, "scale:z", 1.0, 0.18)
    get_tree().create_timer(lifetime).timeout.connect(beam.queue_free)

func _delayed_packet(from: Vector3, to: Vector3, color: Color, delay: float) -> void:
    get_tree().create_timer(delay).timeout.connect(func() -> void:
        _spawn_packet(from, to, color)
    )

func _spawn_packet(from: Vector3, to: Vector3, color: Color) -> void:
    if _flow_root == null or not is_inside_tree():
        return
    var packet := MeshInstance3D.new()
    packet.name = "FeedbackPacket"
    var mesh := SphereMesh.new()
    mesh.radius = 0.15
    mesh.height = 0.3
    mesh.radial_segments = 10
    mesh.rings = 5
    packet.mesh = mesh
    packet.material_override = _make_material(color, 1.7, 0.9, true)
    packet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(packet)
    packet.global_position = from
    var tween := create_tween()
    var duration: float = clampf(from.distance_to(to) / 18.0, 0.28, 0.65)
    tween.tween_property(packet, "global_position", to, duration)
    tween.finished.connect(packet.queue_free)

func _pulse_gate_light(index: int) -> void:
    if index < 0 or index >= gates.size():
        return
    var light: OmniLight3D = gates[index].light
    var tween := create_tween()
    tween.tween_property(light, "light_energy", 1.9, 0.15)
    tween.tween_property(light, "light_energy", 0.8, 0.55)

func _pulse_chamber_crystals() -> void:
    if _flow_root == null:
        return
    # Use a compact rising ring plus a light.  A large translucent shell read
    # as a grey veil over the whole chamber in the review camera.
    var light := OmniLight3D.new()
    light.name = "FeedbackCrystalLight"
    light.light_color = Color("#74ffd0")
    light.light_energy = 1.8
    light.omni_range = 10.0
    light.position = Vector3(72.0, 4.0, 2.0)
    light.shadow_enabled = false
    _flow_root.add_child(light)
    var ring := MeshInstance3D.new()
    ring.name = "FeedbackCrystalRing"
    var mesh := TorusMesh.new()
    mesh.inner_radius = 0.8
    mesh.outer_radius = 1.0
    mesh.rings = 32
    mesh.ring_segments = 8
    ring.mesh = mesh
    ring.material_override = _make_material(Color("#74ffd0"), 0.9, 0.35, true)
    ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _flow_root.add_child(ring)
    ring.global_position = Vector3(72.0, 1.45, 2.0)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(ring, "scale", Vector3(2.2, 1.0, 2.2), 0.5)
    tween.tween_property(ring, "position:y", 3.2, 0.5)
    tween.finished.connect(ring.queue_free)
    var light_tween := create_tween()
    light_tween.tween_property(light, "light_energy", 0.0, 1.0)
    light_tween.finished.connect(light.queue_free)

func play_gate_open(index: int, instant: bool = false) -> void:
    if index < 0 or index >= gates.size():
        return
    var gate: Dictionary = gates[index]
    if bool(gate.open):
        return
    if bool(gate.opening) and not instant:
        return
    if instant:
        set_gate_open_instant(index)
        return
    gate.opening = true
    var label: Label3D = gate.label
    label.text = "OPENING"
    label.modulate = Color("#9ff5cf")
    var curtain: MeshInstance3D = gate.curtain
    var post_l: MeshInstance3D = gate.post_l
    var post_r: MeshInstance3D = gate.post_r
    var panel_l: MeshInstance3D = gate.panel_l
    var panel_r: MeshInstance3D = gate.panel_r
    var light: OmniLight3D = gate.light
    _spawn_shock(gate.root.global_position + Vector3(0.0, 3.0, 0.0), Color("#8ceeff"))
    _spawn_sparks(gate.root.global_position + Vector3(0.0, 3.2, 0.0), Color("#8ceeff"), 12)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(curtain, "scale:y", 0.02, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(post_l, "position:z", -5.2, 1.0)
    tween.tween_property(post_r, "position:z", 5.2, 1.0)
    tween.tween_property(panel_l, "position:z", -4.6, 0.65)
    tween.tween_property(panel_r, "position:z", 4.6, 0.65)
    tween.tween_property(light, "light_energy", 1.9, 0.15)
    var settle := create_tween()
    settle.tween_interval(0.8)
    settle.tween_property(light, "light_energy", 0.25, 0.35)
    tween.finished.connect(func() -> void:
        gate.open = true
        gate.opening = false
        curtain.visible = false
        panel_l.visible = false
        panel_r.visible = false
        label.text = "OPEN"
        label.modulate = Color("#9ff5cf")
    )

func set_gate_open_instant(index: int) -> void:
    if index < 0 or index >= gates.size():
        return
    var gate: Dictionary = gates[index]
    if bool(gate.open) and not bool(gate.opening):
        return
    gate.open = true
    gate.opening = false
    var curtain: MeshInstance3D = gate.curtain
    var post_l: MeshInstance3D = gate.post_l
    var post_r: MeshInstance3D = gate.post_r
    var panel_l: MeshInstance3D = gate.panel_l
    var panel_r: MeshInstance3D = gate.panel_r
    var label: Label3D = gate.label
    var light: OmniLight3D = gate.light
    curtain.visible = false
    curtain.scale.y = 0.02
    panel_l.visible = false
    panel_r.visible = false
    post_l.position.z = -5.2
    post_r.position.z = 5.2
    label.text = "OPEN"
    label.modulate = Color("#9ff5cf")
    light.light_energy = 0.25

func set_gate_closed(index: int) -> void:
    if index < 0 or index >= gates.size():
        return
    var gate: Dictionary = gates[index]
    gate.open = false
    gate.opening = false
    var curtain: MeshInstance3D = gate.curtain
    var post_l: MeshInstance3D = gate.post_l
    var post_r: MeshInstance3D = gate.post_r
    var panel_l: MeshInstance3D = gate.panel_l
    var panel_r: MeshInstance3D = gate.panel_r
    var label: Label3D = gate.label
    var light: OmniLight3D = gate.light
    curtain.visible = true
    curtain.scale.y = 1.0
    panel_l.visible = true
    panel_r.visible = true
    panel_l.position.z = -2.1
    panel_r.position.z = 2.1
    post_l.position.z = -4.15
    post_r.position.z = 4.15
    label.text = "LOCKED"
    label.modulate = gate.base_color
    light.light_energy = 0.55

func reset_all() -> void:
    for kind in MECH_KINDS:
        var m: Dictionary = mechanisms.get(kind, {})
        if m.is_empty():
            continue
        _kill_activation_tweens(m)
        _apply_state_visual(m, STATE_IDLE, 0)
    for index in gates.size():
        set_gate_closed(index)
    if _flow_root != null:
        for child in _flow_root.get_children():
            child.queue_free()
    if cart_marker != null:
        cart_marker.visible = false
    activation_count = 0
    completion_count = 0
    flow_count = 0
    tool_action_count = 0
    manual_pulse_count = 0
    evacuation_count = 0
    last_tool_action = {}
    tool_usage.clear()
    last_event = {}
    _completed_tasks.clear()
