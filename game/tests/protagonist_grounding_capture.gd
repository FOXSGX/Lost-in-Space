extends SceneTree

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#b9cacc")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#e1eef1")
    env.ambient_light_energy = 0.4
    environment.environment = env
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -30, 0)
    sun.light_energy = 0.65
    sun.shadow_enabled = true
    world.add_child(sun)
    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(10, 8)
    floor.mesh = plane
    floor.position.y = 0.005
    var shader := Shader.new()
    shader.code = "shader_type spatial; void fragment(){vec2 cell=floor(UV*vec2(20.0,16.0)); float alt=mod(cell.x+cell.y,2.0); ALBEDO=mix(vec3(0.47,0.59,0.60),vec3(0.66,0.75,0.73),alt); ROUGHNESS=1.0;}"
    var material := ShaderMaterial.new()
    material.shader = shader
    floor.material_override = material
    world.add_child(floor)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 4.2
    camera.position = Vector3(0, 3.4, -7)
    world.add_child(camera)
    camera.look_at(Vector3(0, 0.95, 0))
    camera.current = true
    var visuals: Array[ProtagonistVisual] = []
    for index in 3:
        var visual := preload("res://scenes/protagonist_visual.tscn").instantiate() as ProtagonistVisual
        visual.position.x = float(1 - index) * 2.0
        world.add_child(visual)
        visuals.append(visual)
    for frame in 60:
        for index in 3:
            var visual := visuals[index]
            visual._time = PI / (2.0 * visual.WALK_RATE) - 1.0 / 60.0
            visual.update_state(1.0 / 60.0, Vector2(0, -5.8) if index == 1 else Vector2.ZERO, index == 2, false, false, 5)
        await process_frame
    var layer := CanvasLayer.new()
    root.add_child(layer)
    for index in 3:
        var label := Label.new()
        label.text = ["站立", "迈步", "倒地"][index]
        label.position = Vector2(190 + index * 342, 590)
        label.size = Vector2(215, 40)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 24)
        label.add_theme_color_override("font_color", Color("#274b59"))
        layer.add_child(label)
    await process_frame
    await RenderingServer.frame_post_draw
    var directory := ProjectSettings.globalize_path("res://../builds/ship-cabin-preview")
    DirAccess.make_dir_recursive_absolute(directory)
    root.get_texture().get_image().save_png(directory.path_join("character-grounding.png"))
    print("PROTAGONIST_GROUNDING_CAPTURE_OK")
    quit()
