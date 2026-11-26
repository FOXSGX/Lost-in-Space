extends "res://tests/input_driver.gd"

func run() -> void:
    await boot()
    (scene.get("hud") as CanvasLayer).hide()
    scene.set("pulse_enabled",false)
    for material: ShaderMaterial in scene.get("mineral_materials"):
        material.set_shader_parameter("emission_gain",0.20)
    for view: String in ["A_entry","B_cart_side","C_mineral"]:
        scene.call("set_reference_view",view)
        await frames(60);await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(output.path_join(view+".png"))
    check((scene.get("meshes") as Array).size()>50,"质量对照使用完整静态场景")
    await finish()
