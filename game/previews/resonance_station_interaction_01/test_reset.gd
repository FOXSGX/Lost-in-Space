extends SceneTree

func _initialize() -> void:run.call_deferred()
func frames(count: int) -> void:
    for _i: int in range(count):await physics_frame

func run() -> void:
    var scene: Node3D=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(scene);current_scene=scene
    await frames(25)
    var old_id: int=scene.get_instance_id()
    # Test reset mechanics independently. The full interaction test records the
    # actual playable chain; this helper only seeds the pre-reset state.
    var device: Node3D=scene.get("device") as Node3D
    device.set("phase","active");device.set("activation_count",1)
    Input.action_press("reset_preview");await frames(2);Input.action_release("reset_preview");await frames(30)
    var fresh: Node3D=current_scene as Node3D
    var fresh_device: Node3D=fresh.get("device") as Node3D
    var ok: bool=fresh.get_instance_id()!=old_id and str(fresh_device.get("phase"))=="free" and int(fresh_device.get("activation_count"))==0
    var actor: CharacterBody3D=fresh.get("player") as CharacterBody3D
    var core: RigidBody3D=fresh_device.get("core") as RigidBody3D
    # Controlled dropped-item recovery setup. Only the item is placed; the
    # character stays at the real spawn on the cave floor.
    core.global_position=actor.position+Vector3(.65,.12,0)
    core.linear_velocity=Vector3.ZERO
    await frames(25)
    Input.action_press("pickup");await frames(2);Input.action_release("pickup");await frames(12)
    var recovered: bool=str(fresh_device.get("phase"))=="held" and int(actor.get("carrying"))==3
    var file: FileAccess=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":ok and recovered,"reset_passed":ok,"floor_recovery_passed":recovered,"fresh_state":fresh_device.call("stage_snapshot"),"new_scene":fresh.get_instance_id()!=old_id},"  "));file.close()
    print("INTERACTION_RESET ",ok," FLOOR_RECOVERY ",recovered)
    fresh.queue_free();await frames(3);quit(0 if ok and recovered else 1)
