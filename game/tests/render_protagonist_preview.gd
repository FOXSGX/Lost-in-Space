extends SceneTree

func _initialize() -> void:
    call_deferred("_render")

func _render() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1200, 620)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#e3e7e8")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.65
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, 30, 0)
    sun.light_energy = 1.5
    world.add_child(sun)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 4.5
    camera.position = Vector3(0, 2.7, -8)
    camera.current = true
    world.add_child(camera)
    camera.look_at(Vector3(0, 0.95, 0))
    for index in 3:
        var visual := preload("res://scenes/protagonist_visual.tscn").instantiate() as ProtagonistVisual
        visual.position.x = float(1 - index) * 1.65
        visual.rotation.y = [0.0, -PI / 2.0, PI][index]
        world.add_child(visual)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var picture := viewport.get_texture().get_image()
    var save_result := picture.save_png("res://../art-source/editable/protagonist/godot-preview.png")
    print("预览图保存结果：", save_result)
    camera.position = Vector3(0, 8.0, 7.0)
    camera.look_at(Vector3(0, 0.95, 0))
    await process_frame
    await RenderingServer.frame_post_draw
    var top_result := viewport.get_texture().get_image().save_png("res://../art-source/editable/protagonist/godot-topdown-preview.png")
    print("正交俯视预览保存结果：", top_result)
    quit(0 if save_result == OK and top_result == OK else 1)
