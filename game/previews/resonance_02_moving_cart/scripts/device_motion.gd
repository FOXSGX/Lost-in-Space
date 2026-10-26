extends Node3D

# Presentation only. The stage device owns the state and calibration model.
const RING_CENTER: Vector3 = Vector3(-2.5, 3.0146444, 2.2)
var device: Node3D
var rotor: AnimatableBody3D
var flow: MultiMeshInstance3D
var local_light: OmniLight3D
var _lever: Node3D
var _lever_basis: Basis
var _angle: float = 0.0
var _environment_timer: float = 0.0
var _last_environment_gain: float = -1.0
var enabled: bool = true
var animation_enabled: bool = true

func setup(owner_device: Node3D) -> void:
    device = owner_device

func _ready() -> void:
    rotor = AnimatableBody3D.new()
    rotor.name = "ResonanceRotor"
    rotor.position = RING_CENTER
    rotor.collision_layer = 6
    rotor.collision_mask = 0
    rotor.sync_to_physics = false
    add_child(rotor)
    for child: Node in device.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        if not str(mesh.name).begins_with("DYN_rotor") and not str(mesh.name).begins_with("DYN_ring_"):
            continue
        mesh.reparent(rotor, true)
        var shape: CollisionShape3D = CollisionShape3D.new()
        shape.shape = mesh.mesh.create_trimesh_shape()
        shape.transform = mesh.transform
        rotor.add_child(shape)
    var parts: Dictionary = device.get("parts") as Dictionary
    _lever = parts.get("lever") as Node3D
    if _lever != null:
        _lever_basis = _lever.basis
    local_light = OmniLight3D.new()
    local_light.position = Vector3(-2.5, 2.9, 2.2)
    local_light.light_color = Color(0.14, 0.78, 1.0)
    local_light.omni_range = 3.5
    local_light.light_energy = 0.0
    local_light.shadow_enabled = false
    add_child(local_light)
    flow = MultiMeshInstance3D.new()
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    var bead: SphereMesh = SphereMesh.new()
    bead.radius = 0.017
    bead.height = 0.07
    bead.radial_segments = 8
    bead.rings = 4
    multimesh.mesh = bead
    multimesh.instance_count = 12
    flow.multimesh = multimesh
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.vertex_color_use_as_albedo = true
    material.albedo_color = Color(0.20, 0.87, 1.0)
    material.emission_enabled = true
    material.emission = Color(0.12, 0.65, 0.90)
    flow.material_override = material
    flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(flow)

func tick(delta: float) -> void:
    var phase: String = str(device.get("phase"))
    var elapsed: float = float(device.get("elapsed"))
    var clock: float = float(device.get("clock"))
    var calibration: RefCounted = device.get("calibration") as RefCounted
    var progress: float = float(calibration.get("progress"))
    var target_angle: float = 0.0
    var power: float = 0.0
    if phase == "calibrating":
        var ex: float = float(calibration.call("error_x"))
        var ey: float = float(calibration.call("error_y"))
        var instability: float = clampf(absf(ex) + absf(ey), 0.0, 1.0)
        # 环体角度同时被两条偏差推动：谁动一下环体都会歪。
        # 失稳时抖动更快更乱，两条偏差收窄时抖动收敛、运动趋同。
        target_angle = clampf(ex * 1.0 + ey * 0.45, -0.50, 0.50) \
            + sin(clock * (2.2 + instability * 7.0)) * (0.02 + instability * 0.12)
        power = 0.18 + progress * 0.24 + instability * 0.16 * absf(sin(clock * (6.0 + instability * 8.0)))
    elif phase == "charging":
        target_angle = _angle + delta * 0.85 * smoothstep(0.0, 1.2, elapsed)
        power = 0.42 + smoothstep(0.0, 2.0, elapsed) * 0.50
    elif phase == "stable":
        target_angle = _angle + delta * 0.35
        power = 0.80 + 0.035 * sin(clock * 1.8)
    _angle = lerpf(_angle, target_angle, 1.0 - exp(-7.0 * delta)) if phase not in ["charging", "stable"] else target_angle
    if animation_enabled:rotor.rotation.x = _angle
    if _lever != null:
        var input_level: float = float(calibration.get("preload_value"))
        var lever_angle: float = -0.42 * input_level if phase in ["calibrating", "charging", "stable"] else 0.0
        _lever.basis = _lever.basis.slerp(_lever_basis * Basis(Vector3.FORWARD, lever_angle), 1.0 - exp(-8.0 * delta))
    local_light.light_energy = power * 0.75 if enabled else 0.0
    # 警示灯：两条偏差越大，光色越往琥珀偏；稳下来回到青色。
    var warn: float = clampf(absf(float(calibration.call("error_x"))) + absf(float(calibration.call("error_y"))), 0.0, 1.0) if phase == "calibrating" else 0.0
    local_light.light_color = Color(0.14, 0.78, 1.0).lerp(Color(1.0, 0.55, 0.22), warn)
    flow.visible = enabled and (phase in ["charging", "stable"] or (phase == "calibrating" and progress > 0.20))
    if flow.visible:
        for i: int in range(12):
            var t: float = fposmod(clock * 0.55 + float(i) / 12.0, 1.0)
            var angle: float = t * TAU + float(i) * 0.8
            var point: Vector3 = Vector3(-2.5 + cos(angle) * 0.17, 2.60 + t * 0.83, 2.2 + sin(angle) * 0.17)
            flow.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.7 + sin(t * PI) * 0.6)), point))
            flow.multimesh.set_instance_color(i, Color(0.15 + 0.35 * t, 0.80, 1.0))
    _environment_timer += delta
    if _environment_timer > 0.10:
        _environment_timer = 0.0
        var gain: float = power * 0.18 if enabled else 0.0
        if absf(gain - _last_environment_gain) > 0.003:
            _last_environment_gain = gain
            var stage: Node3D = device.get("controller") as Node3D
            for material: ShaderMaterial in stage.get("materials"):
                material.set_shader_parameter("resonance_response", gain)

func snapshot() -> Dictionary:
    return {"rotor_pivot": [RING_CENTER.x, RING_CENTER.y, RING_CENTER.z],
        "rotor_angle": _angle, "rotor_collision_shapes": int(float(rotor.get_child_count()) / 2.0),
        "flow_instances": 12, "local_light_energy": local_light.light_energy}

func apply_motion_snapshot(data: Dictionary,first: bool) -> void:
    var value: float=float(data.get("rotor_angle",0))
    _angle=value if first else lerp_angle(_angle,value,.65)
