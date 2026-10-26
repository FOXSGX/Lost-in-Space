extends Node3D

## Art-direction layer for the continuous cave chapter.
##
## The v3 Blender GLB remains the geometry authority.  This layer only
## replaces the imported flat materials with stylized, triplanar shader
## families, authors the stage lighting rig, and adds restrained atmospheric
## dust.  It does not create cave geometry or move any RES_ anchor.

const ROCK_SHADER := preload("res://shaders/cave_rock.gdshader")
const FLOOR_SHADER := preload("res://shaders/cave_floor.gdshader")
const CRYSTAL_SHADER := preload("res://shaders/cave_crystal.gdshader")
const METAL_SHADER := preload("res://shaders/cave_metal.gdshader")
const ENERGY_SHADER := preload("res://shaders/cave_energy.gdshader")

const PALETTE := {
    "rock_clay": Color("#6f4032"),
    "rock_peach": Color("#b97858"),
    "rock_dark": Color("#4c3030"),
    "rock_cool": Color("#33283a"),
    "floor_slate": Color("#40332f"),
    "floor_dust": Color("#9a6b50"),
    "floor_route": Color("#2b2422"),
    "crystal_cyan": Color("#1d7f96"),
    "crystal_cyan_tip": Color("#7be7f3"),
    "crystal_warm": Color("#a65d22"),
    "crystal_warm_tip": Color("#ffc06a"),
    "energy_cyan": Color("#3ed9f2"),
    "energy_amber": Color("#ffb347"),
    "energy_pale": Color("#a8edf2"),
    "energy_green": Color("#63ffb0"),
    "metal_teal": Color("#214b50"),
    "metal_honey": Color("#9f6b31"),
    "metal_edge": Color("#d7a45c")
}

var visual_root: Node3D
var environment: Environment
var material_families: Dictionary = {}
var lights: Array[Light3D] = []
var dust_emitters: Array[CPUParticles3D] = []
var fade_meshes: Array[MeshInstance3D] = []
var applied_meshes: int = 0

func update_camera_occlusion(camera_position: Vector3, target: Vector3) -> void:
    # When the third-person lens is pushed into a task prop, dither the prop
    # instead of letting a console/pylon fill the frame.  Cave shell/floor are
    # deliberately excluded so the room never opens a hole.
    var view := (target - camera_position).normalized()
    for mesh in fade_meshes:
        if mesh == null or not is_instance_valid(mesh):
            continue
        var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
        var offset := center - camera_position
        var distance := offset.length()
        var in_front := offset.normalized().dot(view) > 0.50
        var want := 0.58 if (in_front and distance < 3.8) else 0.0
        var hide_part := false
        if mesh.name.begins_with("TunnelExit_") or mesh.name.begins_with("Transition01_") or mesh.name.begins_with("EntranceArch_") or mesh.name.begins_with("HeroGate_") or mesh.name.begins_with("HeroArch_"):
            hide_part = in_front and distance < 6.0
            want = 0.86 if hide_part else 0.0
        mesh.transparency = lerpf(mesh.transparency, want, 0.25)
        # Dithering is not enough for a header/lintel directly against the lens:
        # hide the close architectural trim so the player silhouette and the
        # next route remain readable.
        mesh.visible = not hide_part

func setup(visual: Node3D) -> void:
    visual_root = visual
    _apply_materials(visual)
    _build_environment()
    _build_lights()
    _build_dust()

func register_hero_occluders(hero: Node3D) -> void:
    if hero == null:
        return
    for node in hero.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh == null:
            continue
        if mesh.name.begins_with("Task01_") or mesh.name.begins_with("Task02_") or mesh.name.begins_with("HeroGate_") or mesh.name.begins_with("HeroArch_"):
            fade_meshes.append(mesh)

func family_count() -> int:
    return material_families.size()

func light_count() -> int:
    return lights.size()

func _apply_materials(node: Node) -> void:
    if node == null:
        return
    if node is MeshInstance3D:
        _apply_mesh(node as MeshInstance3D)
    for child in node.get_children():
        _apply_materials(child)

func _apply_mesh(mesh_instance: MeshInstance3D) -> void:
    var original := mesh_instance.get_active_material(0) as Material
    var material_name := ""
    if original != null:
        material_name = original.resource_name
    if material_name == "":
        material_name = _material_name_from_mesh(mesh_instance.name)
    var family := _family_for(material_name, mesh_instance.name)
    if family == "":
        return
    var shader_material := _shader_for_family(family, material_name, mesh_instance.name)
    if shader_material == null:
        return
    mesh_instance.material_override = shader_material
    mesh_instance.set_meta("cave_art_family", family)
    material_families[family] = int(material_families.get(family, 0)) + 1
    applied_meshes += 1
    if mesh_instance.name.begins_with("Task01_") or mesh_instance.name.begins_with("Task02_") or mesh_instance.name.begins_with("Entrance_Threshold") or mesh_instance.name.begins_with("EntranceArch_") or mesh_instance.name.begins_with("TunnelExit_") or mesh_instance.name.begins_with("Transition01_"):
        fade_meshes.append(mesh_instance)

func _material_name_from_mesh(mesh_name: String) -> String:
    var lower := mesh_name.to_lower()
    if lower.contains("floor"):
        return "Cave_Floor_Slate"
    if lower.contains("crystal"):
        return "Crystal_CyanBody"
    if lower.contains("halo") or lower.contains("node") or lower.contains("glow"):
        return "Resonance_Cyan"
    if lower.contains("rail") or lower.contains("threshold") or lower.contains("console"):
        return "Facility_TealMetal"
    return "Cave_Rock_Clay"

func _family_for(material_name: String, mesh_name: String) -> String:
    var n := material_name
    var m := mesh_name.to_lower()
    if n.begins_with("Cave_Rock"):
        return "rock"
    if n.begins_with("Cave_Floor"):
        return "floor"
    if n.begins_with("Crystal_Cyan"):
        return "crystal_cyan"
    if n.begins_with("Crystal_Warm"):
        return "crystal_warm"
    if n.begins_with("Resonance_Cyan") or n.begins_with("Resonance_Pale"):
        return "energy_cyan"
    if n.begins_with("Resonance_Amber"):
        return "energy_amber"
    if n.begins_with("Facility_Teal"):
        return "metal_teal"
    if n.begins_with("Facility_Honey"):
        return "metal_honey"
    if m.contains("floor"):
        return "floor"
    if m.contains("crystal"):
        return "crystal_cyan"
    if m.contains("halo") or m.contains("node"):
        return "energy_cyan"
    return "rock"

func _shader_for_family(family: String, material_name: String, mesh_name: String) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    var variation := float(abs(hash(mesh_name)) % 1000) / 1000.0
    var lower := mesh_name.to_lower()
    match family:
        "rock":
            mat.shader = ROCK_SHADER
            var base := PALETTE.rock_clay
            var warm := PALETTE.rock_peach
            if material_name.contains("Peach"):
                base = PALETTE.rock_peach
                warm = Color("#ca8a63")
            if lower.contains("shell") or lower.contains("pendant") or lower.contains("stalactite") or lower.contains("ceiling"):
                base = PALETTE.rock_dark
                warm = Color("#735044")
            if lower.contains("rim") or lower.contains("mouth"):
                base = Color("#5c3b34")
                warm = Color("#9a6551")
            mat.set_shader_parameter("base_color", base)
            mat.set_shader_parameter("warm_color", warm)
            mat.set_shader_parameter("cool_color", PALETTE.rock_cool)
            mat.set_shader_parameter("variation", variation)
            mat.set_shader_parameter("roughness_base", 0.82 + variation * 0.06)
            mat.set_shader_parameter("wet_strength", 0.32 + variation * 0.12)
            mat.set_shader_parameter("macro_scale", 0.075 + variation * 0.018)
            mat.set_shader_parameter("detail_scale", 0.75 + variation * 0.35)
        "floor":
            mat.shader = FLOOR_SHADER
            var base := PALETTE.floor_slate
            var dust := PALETTE.floor_dust
            if material_name.contains("Peach"):
                base = Color("#57433c")
                dust = Color("#a67a5d")
            mat.set_shader_parameter("base_color", base)
            mat.set_shader_parameter("dust_color", dust)
            mat.set_shader_parameter("route_color", PALETTE.floor_route)
            mat.set_shader_parameter("variation", variation)
            mat.set_shader_parameter("macro_scale", 0.10 + variation * 0.025)
            mat.set_shader_parameter("detail_scale", 1.35 + variation * 0.35)
        "crystal_cyan":
            mat.shader = CRYSTAL_SHADER
            mat.set_shader_parameter("base_color", PALETTE.crystal_cyan)
            mat.set_shader_parameter("tip_color", PALETTE.crystal_cyan_tip)
            mat.set_shader_parameter("emission_color", PALETTE.energy_cyan)
            mat.set_shader_parameter("emission_strength", 0.52 + variation * 0.18)
            mat.set_shader_parameter("variation", variation)
        "crystal_warm":
            mat.shader = CRYSTAL_SHADER
            mat.set_shader_parameter("base_color", PALETTE.crystal_warm)
            mat.set_shader_parameter("tip_color", PALETTE.crystal_warm_tip)
            mat.set_shader_parameter("emission_color", PALETTE.energy_amber)
            mat.set_shader_parameter("emission_strength", 0.48 + variation * 0.16)
            mat.set_shader_parameter("variation", variation)
        "energy_cyan":
            mat.shader = ENERGY_SHADER
            var c := PALETTE.energy_cyan
            if material_name.contains("Pale"):
                c = PALETTE.energy_pale
            mat.set_shader_parameter("energy_color", c)
            mat.set_shader_parameter("intensity", 0.72 + variation * 0.18)
            mat.set_shader_parameter("pulse_speed", 1.2 + variation * 0.8)
            mat.set_shader_parameter("variation", variation)
        "energy_amber":
            mat.shader = ENERGY_SHADER
            mat.set_shader_parameter("energy_color", PALETTE.energy_amber)
            mat.set_shader_parameter("intensity", 0.78 + variation * 0.16)
            mat.set_shader_parameter("pulse_speed", 1.0 + variation * 0.6)
            mat.set_shader_parameter("variation", variation)
        "metal_teal":
            mat.shader = METAL_SHADER
            mat.set_shader_parameter("base_color", PALETTE.metal_teal)
            mat.set_shader_parameter("edge_color", PALETTE.metal_edge)
            mat.set_shader_parameter("emission_color", PALETTE.energy_cyan)
            mat.set_shader_parameter("metallic_base", 0.64)
            mat.set_shader_parameter("roughness_base", 0.34)
            mat.set_shader_parameter("variation", variation)
        "metal_honey":
            mat.shader = METAL_SHADER
            mat.set_shader_parameter("base_color", PALETTE.metal_honey)
            mat.set_shader_parameter("edge_color", Color("#f2c16c"))
            mat.set_shader_parameter("emission_color", PALETTE.energy_amber)
            mat.set_shader_parameter("metallic_base", 0.58)
            mat.set_shader_parameter("roughness_base", 0.30)
            mat.set_shader_parameter("emission_strength", 0.06)
            mat.set_shader_parameter("variation", variation)
        _:
            return null
    mat.resource_name = "Art_%s" % family
    return mat

func _build_environment() -> void:
    var we := WorldEnvironment.new()
    we.name = "CaveArtEnvironment"
    environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#090812")
    environment.background_energy_multiplier = 0.8
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#5a4568")
    environment.ambient_light_energy = 0.40
    environment.fog_enabled = true
    environment.fog_light_color = Color("#352744")
    environment.fog_light_energy = 0.55
    environment.fog_density = 0.0068
    environment.fog_sky_affect = 0.0
    environment.fog_aerial_perspective = 0.20
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.tonemap_exposure = 0.92
    environment.tonemap_white = 1.0
    environment.adjustment_enabled = true
    environment.adjustment_brightness = 1.0
    environment.adjustment_contrast = 1.06
    environment.adjustment_saturation = 1.08
    environment.glow_enabled = false
    environment.ssao_enabled = false
    environment.sdfgi_enabled = false
    we.environment = environment
    add_child(we)

    var key := DirectionalLight3D.new()
    key.name = "CaveArtKey"
    key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    key.light_color = Color("#ffd0b5")
    key.light_energy = 0.62
    key.shadow_enabled = true
    key.directional_shadow_max_distance = 80.0
    key.directional_shadow_blend_splits = true
    add_child(key)
    lights.append(key)

    var fill := DirectionalLight3D.new()
    fill.name = "CaveArtCoolFill"
    fill.rotation_degrees = Vector3(-18.0, 142.0, 0.0)
    fill.light_color = Color("#7da2ff")
    fill.light_energy = 0.16
    fill.shadow_enabled = false
    add_child(fill)
    lights.append(fill)

func _build_lights() -> void:
    # Entrance: warm-to-cool task contrast with the arch as a far focus.
    _add_omni("EntrancePowerCyan", Vector3(-9.0, 3.2, 0.0), Color("#46e3ff"), 2.1, 7.0)
    _add_omni("EntranceClampAmber", Vector3(5.0, 3.2, 0.0), Color("#ffb347"), 1.9, 6.5)
    _add_omni("EntranceWarmFill", Vector3(-13.0, 4.4, 4.5), Color("#ff9a68"), 2.2, 11.0)
    _add_omni("EntranceCoolFill", Vector3(-2.0, 5.2, -6.0), Color("#78baff"), 1.7, 10.0)
    _add_omni("EntranceTopFill", Vector3(-2.0, 8.0, 0.0), Color("#ffc59a"), 3.0, 18.0)
    _add_omni("EntranceFrontRim", Vector3(8.0, 4.2, -4.0), Color("#70dfff"), 1.4, 8.0)
    _add_omni("EntranceSpawnFill", Vector3(-8.0, 3.4, 0.0), Color("#ffd6b8"), 2.2, 9.0)
    _add_spot("EntranceArchSpot", Vector3(12.0, 8.5, 0.0), Vector3(11.0, 3.0, 0.0), Color("#8ceeff"), 5.2, 24.0, 32.0, true)
    _add_omni("EntranceThresholdGlow", Vector3(10.5, 3.0, 0.0), Color("#65e5ff"), 2.2, 5.0)

    # Corridor: a rhythmic light chain along the rail; darker ends keep depth.
    var corridor_colors := [Color("#ffb066"), Color("#5fd8e8"), Color("#ffb066"), Color("#5fd8e8"), Color("#ffb066")]
    for index in 5:
        var x := 18.0 + float(index) * 6.5
        _add_omni("CorridorRail_%d" % index, Vector3(x, 3.8, 0.0), corridor_colors[index], 1.15, 4.8)
    _add_spot("CorridorForwardSpot", Vector3(28.0, 5.2, 0.0), Vector3(45.0, 2.0, 0.0), Color("#ffc081"), 3.4, 22.0, 34.0, false)
    _add_omni("CorridorGatePreheat", Vector3(48.0, 3.4, 0.0), Color("#ffb347"), 2.4, 7.0)
    _add_omni("CorridorColdPocket", Vector3(33.0, 2.6, 4.6), Color("#5c7dff"), 0.7, 5.5)

    # Cathedral: high central hero spot, cool/warm/green three-layer staging.
    _add_spot("ChamberHeroSpot", Vector3(72.0, 15.5, 0.0), Vector3(72.0, 3.2, 0.0), Color("#a8eff4"), 7.2, 30.0, 38.0, true)
    _add_omni("ChamberCyanSide", Vector3(62.0, 7.5, -8.0), Color("#46cfff"), 3.4, 12.0)
    _add_omni("ChamberAmberSide", Vector3(82.0, 7.5, 7.0), Color("#ffb35a"), 3.0, 11.0)
    _add_omni("ChamberStabilizerGreen", Vector3(75.0, 4.8, 4.0), Color("#63ffb0"), 2.2, 8.0)
    _add_omni("ChamberExitGreen", Vector3(87.0, 4.5, 0.0), Color("#7dffc0"), 3.5, 12.0)
    _add_omni("ChamberColdFill", Vector3(60.0, 4.0, 8.0), Color("#6f8dff"), 1.4, 10.0)
    _add_omni("ChamberBackPurple", Vector3(72.0, 8.0, 14.0), Color("#8c5cff"), 1.1, 12.0)

    # Task station rim lights keep the character silhouette readable.
    _add_omni("StationRelayEntryCyan", Vector3(28.0, 3.0, -1.7), Color("#78f0ff"), 1.3, 5.0)
    _add_omni("StationRelayExitAmber", Vector3(42.0, 3.0, 1.7), Color("#ffd166"), 1.3, 5.0)
    _add_omni("StationFreightWarm", Vector3(65.0, 3.2, 0.0), Color("#ffc857"), 1.6, 6.0)
    _add_omni("StationSocketGreen", Vector3(75.0, 3.2, 4.0), Color("#63ffb0"), 1.5, 6.0)

func _add_omni(node_name: String, at: Vector3, color: Color, energy: float, radius: float, shadows: bool = false) -> OmniLight3D:
    var light := OmniLight3D.new()
    light.name = node_name
    light.position = at
    light.light_color = color
    light.light_energy = energy
    light.omni_range = radius
    light.omni_attenuation = 1.35
    light.shadow_enabled = shadows
    add_child(light)
    lights.append(light)
    return light

func _add_spot(node_name: String, at: Vector3, target: Vector3, color: Color, energy: float, radius: float, angle: float, shadows: bool) -> SpotLight3D:
    var light := SpotLight3D.new()
    light.name = node_name
    light.position = at
    light.light_color = color
    light.light_energy = energy
    light.spot_range = radius
    light.spot_angle = angle
    light.spot_attenuation = 1.2
    light.shadow_enabled = shadows
    add_child(light)
    var direction := (target - at).normalized()
    var up := Vector3.UP
    if absf(direction.dot(up)) > 0.98:
        up = Vector3.RIGHT
    light.look_at(target, up)
    lights.append(light)
    return light

func _build_dust() -> void:
    _add_dust("EntranceDust", Vector3(-4.0, 5.0, 2.0), 28, Color("#d8a77c"), 5.0)
    _add_dust("CorridorDust", Vector3(33.0, 3.2, 0.0), 26, Color("#9bd7de"), 7.0)
    _add_dust("ChamberDust", Vector3(72.0, 7.0, 0.0), 32, Color("#9de9d7"), 9.0)

func _add_dust(node_name: String, at: Vector3, amount: int, color: Color, radius: float) -> void:
    var particles := CPUParticles3D.new()
    particles.name = node_name
    particles.amount = amount
    particles.lifetime = 9.0
    particles.one_shot = false
    particles.explosiveness = 0.0
    particles.randomness = 0.85
    particles.local_coords = false
    particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
    particles.emission_sphere_radius = radius
    particles.direction = Vector3(0.18, 0.10, 0.05)
    particles.spread = 28.0
    particles.gravity = Vector3(0.0, -0.018, 0.0)
    particles.initial_velocity_min = 0.02
    particles.initial_velocity_max = 0.10
    particles.scale_amount_min = 0.018
    particles.scale_amount_max = 0.045
    particles.color = color
    particles.position = at
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 6
    mesh.rings = 3
    particles.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(color.r, color.g, color.b, 0.30)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = 0.45
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    particles.material_override = mat
    add_child(particles)
    dust_emitters.append(particles)
