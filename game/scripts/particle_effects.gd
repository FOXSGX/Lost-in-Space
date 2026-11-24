class_name ParticleEffects
extends Node

## 共振星交互事件的 3D 粒子反馈。
##
## 设计约束（对应任务单“粒子不遮挡玩家视线”）：
##   * 每个特效都是一次性短命粒子（0.35—0.9 秒），播完自动 queue_free；
##   * 尺寸小（0.06—0.16 米）、使用加色混合，只做“闪一下”的提示，不作大面积遮罩；
##   * 默认保留深度测试，粒子会被墙面和设备挡住，不会浮在镜头前；
##   * 同时存活的特效数量有上限，连续校准也不会堆成一片。
##
## 用法：
##     var fx: ParticleEffects = ParticleEffects.new()
##     add_child(fx)
##     fx.spawn_heat_valve_success(device_position)

## 同时存在的特效上限；超过就丢弃最旧的一个。
const MAX_ACTIVE_EFFECTS: int = 20
## 单个特效里粒子的最大数量。屏幕上同时出现几千个加分粒子会直接糊住画面。
const MAX_PARTICLES_PER_EFFECT: int = 48

var effects_root: Node3D
var _active: Array[Node3D] = []


func _ready() -> void:
    _ensure_root()


func _ensure_root() -> void:
    if effects_root != null and is_instance_valid(effects_root):
        return
    effects_root = Node3D.new()
    effects_root.name = "ParticleEffectsRoot"
    add_child(effects_root)


# --------------------------------------------------------------------------
# 5 类交互事件
# --------------------------------------------------------------------------
func spawn_heat_valve_success(position: Vector3) -> void:
    """热阀成功：一股热汽从阀体升起，暖橙色，0.9 秒散尽。"""
    _spawn_burst(
        "HeatValveSteam",
        position + Vector3.UP * 0.35,
        {
            "amount": 22,
            "lifetime": 0.9,
            "color": Color(1.0, 0.72, 0.42),
            "mesh_size": 0.14,
            "direction": Vector3.UP,
            "spread": 38.0,
            "velocity_min": 0.35,
            "velocity_max": 1.05,
            "gravity": Vector3(0.0, 0.45, 0.0),
            "damping": 1.1,
            "scale_max": 1.9,
            "additive": false,
            "emission_shape": CPUParticles3D.EMISSION_SHAPE_SPHERE,
            "emission_radius": 0.28,
        }
    )


func spawn_power_success_particles(position: Vector3) -> void:
    """电源端成功：青白色电火花向四周弹出，0.5 秒收束。"""
    _spawn_burst(
        "PowerSparks",
        position + Vector3.UP * 0.6,
        {
            "amount": 24,
            "lifetime": 0.5,
            "color": Color(0.62, 0.94, 1.0),
            "mesh_size": 0.07,
            "direction": Vector3.UP,
            "spread": 78.0,
            "velocity_min": 1.2,
            "velocity_max": 2.6,
            "gravity": Vector3(0.0, -2.4, 0.0),
            "damping": 2.2,
            "scale_max": 1.0,
            "additive": true,
            "emission_shape": CPUParticles3D.EMISSION_SHAPE_SPHERE,
            "emission_radius": 0.16,
        }
    )


func spawn_mirror_success_beam(position: Vector3) -> void:
    """镜面对准：一道细光柱升起 + 几粒高光，0.45 秒淡出。

    光柱很窄（直径 0.1 米），只表达“这台设备的反射对上了”，
    不做全屏耀光，避免遮挡玩家看下一步路线。
    """
    _ensure_root()
    _trim_active()
    var beam: MeshInstance3D = MeshInstance3D.new()
    beam.name = "MirrorSuccessBeam"
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = 0.045
    mesh.bottom_radius = 0.075
    mesh.height = 2.4
    mesh.radial_segments = 10
    mesh.rings = 1
    beam.mesh = mesh
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.disable_receive_shadows = true
    material.albedo_color = Color(0.72, 0.95, 1.0, 0.55)
    beam.material_override = material
    beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    beam.position = position + Vector3.UP * 1.2
    effects_root.add_child(beam)
    _active.append(beam)
    var tween: Tween = beam.create_tween()
    tween.set_parallel(true)
    tween.tween_property(beam, "scale", Vector3(0.25, 1.6, 0.25), 0.45).from(Vector3(1.0, 0.2, 1.0))
    tween.tween_property(material, "albedo_color:a", 0.0, 0.45).from(0.55)
    tween.chain().tween_callback(beam.queue_free)
    _spawn_burst(
        "MirrorSparkle",
        position + Vector3.UP * 1.9,
        {
            "amount": 10,
            "lifetime": 0.42,
            "color": Color(0.85, 1.0, 1.0),
            "mesh_size": 0.06,
            "direction": Vector3.UP,
            "spread": 25.0,
            "velocity_min": 0.2,
            "velocity_max": 0.7,
            "gravity": Vector3(0.0, 0.2, 0.0),
            "damping": 0.8,
            "scale_max": 0.8,
            "additive": true,
            "emission_shape": CPUParticles3D.EMISSION_SHAPE_SPHERE,
            "emission_radius": 0.08,
        }
    )


func spawn_calibration_fail_flash(position: Vector3) -> void:
    """校准失败：一圈橙红短闪，提示“没对准”，不复用成功色。"""
    _spawn_burst(
        "CalibrationFailFlash",
        position + Vector3.UP * 0.55,
        {
            "amount": 14,
            "lifetime": 0.36,
            "color": Color(1.0, 0.42, 0.32),
            "mesh_size": 0.10,
            "direction": Vector3.UP,
            "spread": 88.0,
            "velocity_min": 0.5,
            "velocity_max": 1.4,
            "gravity": Vector3(0.0, -1.2, 0.0),
            "damping": 2.6,
            "scale_max": 1.1,
            "additive": true,
            "emission_shape": CPUParticles3D.EMISSION_SHAPE_RING,
            "emission_radius": 0.35,
        }
    )


func spawn_module_attachment_spray(position: Vector3) -> void:
    """模块/冷却座接入：冷色喷流沿接口法线散开，0.7 秒收束。"""
    _spawn_burst(
        "ModuleAttachmentSpray",
        position + Vector3.UP * 0.5,
        {
            "amount": 18,
            "lifetime": 0.7,
            "color": Color(0.56, 0.90, 0.84),
            "mesh_size": 0.09,
            "direction": Vector3.UP,
            "spread": 52.0,
            "velocity_min": 0.8,
            "velocity_max": 1.8,
            "gravity": Vector3(0.0, -0.8, 0.0),
            "damping": 1.6,
            "scale_max": 1.2,
            "additive": true,
            "emission_shape": CPUParticles3D.EMISSION_SHAPE_SPHERE,
            "emission_radius": 0.2,
        }
    )


## 按事件名分发，方便配置表驱动（难度表里的 particle_success 字段）。
func spawn_event(event: String, position: Vector3) -> bool:
    match event:
        "heat_valve_success":
            spawn_heat_valve_success(position)
            return true
        "power_success":
            spawn_power_success_particles(position)
            return true
        "mirror_success_beam":
            spawn_mirror_success_beam(position)
            return true
        "calibration_fail_flash":
            spawn_calibration_fail_flash(position)
            return true
        "module_attachment_spray":
            spawn_module_attachment_spray(position)
            return true
    return false


func active_effect_count() -> int:
    var count: int = 0
    for node in _active:
        if node != null and is_instance_valid(node):
            count += 1
    return count


func clear_all() -> void:
    for node in _active:
        if node != null and is_instance_valid(node):
            node.queue_free()
    _active.clear()


# --------------------------------------------------------------------------
# 内部
# --------------------------------------------------------------------------
func _trim_active() -> void:
    var alive: Array[Node3D] = []
    for node in _active:
        if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
            alive.append(node)
    _active = alive
    while _active.size() >= MAX_ACTIVE_EFFECTS:
        var oldest: Node3D = _active.pop_front()
        if oldest != null and is_instance_valid(oldest):
            oldest.queue_free()


func _spawn_burst(effect_name: String, position: Vector3, config: Dictionary) -> void:
    _ensure_root()
    _trim_active()
    var particles: CPUParticles3D = CPUParticles3D.new()
    particles.name = effect_name
    particles.amount = mini(int(config.get("amount", 16)), MAX_PARTICLES_PER_EFFECT)
    particles.lifetime = float(config.get("lifetime", 0.6))
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.randomness = 0.65
    particles.local_coords = false
    particles.emitting = false
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mesh: QuadMesh = QuadMesh.new()
    var mesh_size: float = float(config.get("mesh_size", 0.1))
    mesh.size = Vector2(mesh_size, mesh_size)
    particles.mesh = mesh
    var color: Color = config.get("color", Color.WHITE) as Color
    particles.color = color
    var ramp: Gradient = Gradient.new()
    ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
    ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
    particles.color_ramp = ramp
    var curve: Curve = Curve.new()
    curve.add_point(Vector2(0.0, 0.55))
    curve.add_point(Vector2(1.0, 0.0))
    particles.scale_amount_curve = curve
    particles.scale_amount_min = 0.7
    particles.scale_amount_max = float(config.get("scale_max", 1.2))
    particles.direction = config.get("direction", Vector3.UP) as Vector3
    particles.spread = float(config.get("spread", 45.0))
    particles.initial_velocity_min = float(config.get("velocity_min", 0.4))
    particles.initial_velocity_max = float(config.get("velocity_max", 1.2))
    particles.gravity = config.get("gravity", Vector3(0.0, -1.0, 0.0)) as Vector3
    particles.damping_min = float(config.get("damping", 1.0))
    particles.damping_max = float(config.get("damping", 1.0))
    particles.emission_shape = int(config.get("emission_shape", CPUParticles3D.EMISSION_SHAPE_SPHERE))
    var radius: float = float(config.get("emission_radius", 0.25))
    if particles.emission_shape == CPUParticles3D.EMISSION_SHAPE_RING:
        particles.emission_ring_radius = radius
        particles.emission_ring_inner_radius = maxf(radius - 0.12, 0.02)
        particles.emission_ring_height = 0.05
        particles.emission_ring_axis = Vector3.UP
    else:
        particles.emission_sphere_radius = radius
    particles.material_override = _particle_material(bool(config.get("additive", true)))
    particles.position = position
    effects_root.add_child(particles)
    _active.append(particles)
    particles.emitting = true
    particles.finished.connect(particles.queue_free)
    # finished 在低帧率下可能被错过，补一条超时回收。
    var tree: SceneTree = get_tree()
    if tree != null:
        var timer: SceneTreeTimer = tree.create_timer(particles.lifetime + 0.6)
        timer.timeout.connect(func() -> void:
            if particles != null and is_instance_valid(particles):
                particles.queue_free()
        )


func _particle_material(additive: bool) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
    material.vertex_color_use_as_albedo = true
    material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.disable_receive_shadows = true
    return material
