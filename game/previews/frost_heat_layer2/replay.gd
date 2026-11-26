extends "res://previews/frost_layer1/replay.gd"

var mode: String = "heat"

func held_key(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = pressed
	Input.parse_input_event(event)

func reach(points: Array) -> bool:
	for point: Vector3 in points:
		if not await walk(point):
			await shot("failure-stuck")
			finish()
			return false
	return true

func look_at_point(point: Vector3) -> void:
	var delta: Vector3 = point-player._camera.global_position
	await mouse_look(atan2(-delta.x,-delta.z),-atan2(delta.y,Vector2(delta.x,delta.z).length()))

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
	output = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/"+mode).simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	preview = load("res://previews/frost_heat_layer2/preview.tscn").instantiate() as Main3D
	root.add_child(preview)
	await frames(30)
	player = preview.walker
	check(player.health==5 and preview._health_hud.cells.size()==5,"5 HP and shared five-cell HUD")
	check(preview._items.has_jet(1) and preview._items._cells.size()==2 and preview._items._equipment_cells.size()==2,"existing oxygen jet and independent two/two bars")
	check(preview.melt==0 and not preview.heating and preview.ice_parts.size()==4,"starts with intact blocking ice and heater off")
	await shot("01-cold-start")
	var route_start: float = preview.distance_walked
	var time_start: float = preview.elapsed
	if mode in ["clean","partial"]:
		# Comparable first-use route, without deliberate fault/recovery probes.
		if not await reach([Vector3(17,0,35)]):
			return
		await look_at_point(preview.HEAT_CONTROL)
		held_key(true)
		await frames(246 if mode=="partial" else 490)
		held_key(false)
		await frames(5)
		if mode=="partial":
			check(preview.melt>0.45 and preview.melt<0.7 and not preview.heating,"can stop supply before complete thaw")
			await look_at_point(Vector3(12,2.5,29))
			await shot("partial-opening")
		else:
			check(preview.melt==1 and not preview.heating,"uninterrupted single-person heat operation opens ice")
		var entry_x: float = 10.0 if mode=="partial" else 12.0
		if not await reach([Vector3(19.5,0,35),Vector3(19.5,0,31.2),Vector3(entry_x,0,31.2),Vector3(entry_x,0,8),Vector3(16,0,0),Vector3(0,0,0)]):
			return
		check(preview.entered,"uninterrupted short entry reaches the same ruin endpoint")
		if mode=="partial":
			check(preview.melt<0.7 and (preview.ice_parts[0].body as StaticBody3D).collision_layer==2,"partial opening is physically traversable while ice still exists")
	elif mode=="heat":
		if not await reach([Vector3(9.5,0,35),Vector3(9.5,0,31.2),Vector3(12,0,31.2)]):
			return
		await mouse_look(0,0)
		Input.action_press("move_up")
		await frames(80)
		Input.action_release("move_up")
		check(player.position.z>29.5 and not preview.entered,"cold ice physically blocks forward movement")
		await shot("02-cold-blocked")
		Input.action_press("jump")
		Input.action_press("move_up")
		await frames(120)
		Input.action_release("jump")
		Input.action_release("move_up")
		await frames(120)
		check(player.position.z>29.5 and preview.melt==0,"existing jet cannot bypass cold sheet")
		check(player.health==5,"mechanism test does not invent heat damage")
		if not await reach([Vector3(9.5,0,31.5),Vector3(9.5,0,35),Vector3(0,0,48)]):
			return
		route_start = preview.distance_walked
		time_start = preview.elapsed
		if not await reach([Vector3(17,0,35)]):
			return
		await look_at_point(preview.HEAT_CONTROL)
		await shot("03-control-pictogram")
		held_key(true)
		await frames(70)
		check(preview.heating and preview.melt>0.1 and preview.melt<0.4,"real held E supplies heat and thaws ice")
		await look_at_point(Vector3(12,2.6,29))
		await frames(30)
		check(preview.heating and preview.heat_beam.visible,"can turn to watch thaw while holding the control")
		var plug: StaticBody3D = preview.ice_parts[3].body as StaticBody3D
		var visible_size: Vector3 = ((plug.get_child(0) as MeshInstance3D).mesh as BoxMesh).size
		var physics_size: Vector3 = ((plug.get_child(1) as CollisionShape3D).shape as BoxShape3D).size
		check(visible_size.y<2.3 and visible_size.is_equal_approx(physics_size),"visible ice and physical collider shrink together")
		await shot("04-heat-partial")
		held_key(false)
		await frames(8)
		var held_melt: float = preview.melt
		await frames(90)
		check(not preview.heating and is_equal_approx(preview.melt,held_melt),"releasing E stops heat and preserves thaw")
		await look_at_point(preview.HEAT_CONTROL)
		held_key(true)
		await frames(25)
		if not await reach([Vector3(23,0,35)]):
			return
		await frames(10)
		var away_melt: float = preview.melt
		await frames(90)
		check(not preview.heating and is_equal_approx(preview.melt,away_melt),"walking away interrupts supply without reversing thaw")
		held_key(false)
		if not await reach([Vector3(17,0,35)]):
			return
		await look_at_point(preview.HEAT_CONTROL)
		held_key(true)
		await frames(10)
		check(preview.heating and preview.melt>away_melt,"returning to control resumes without reset or supplies")
		await look_at_point(Vector3(12,2.8,29))
		await frames(490)
		held_key(false)
		await frames(5)
		check(preview.melt==1.0 and not preview.heating,"one player fully thaws the passage")
		var clear: bool = true
		for part: Dictionary in preview.ice_parts:
			clear = clear and (part.body as StaticBody3D).collision_layer==0 and not (part.body.get_child(0) as MeshInstance3D).visible
		check(clear,"melted ice has no residual invisible blocking collider")
		await shot("05-ice-open")
		if not await reach([Vector3(19.5,0,35),Vector3(19.5,0,31.2),Vector3(12,0,31.2),Vector3(12,0,8),Vector3(16,0,0),Vector3(0,0,0)]):
			return
		check(preview.entered,"physically walked through the thawed service entry into ruin")
	else:
		var path: Array = preview.WEST_PATH if mode=="west" else ( [Vector3(23,0,36),Vector3(23,0,-7),Vector3(16,0,-7),Vector3(16,0,0),Vector3(0,0,0)] if mode=="direct" else preview.EAST_PATH )
		if not await reach(path):
			return
		check(preview.entered and preview.melt==0 and not preview.heating,"outside safe route reaches ruin without heat operation")
		check((preview.ice_parts[3].body as StaticBody3D).collision_layer==2,"safe route leaves thin ice physically intact")
	var route_length: float = preview.distance_walked-route_start
	var route_seconds: float = preview.elapsed-time_start
	await shot("06-inside")
	var return_start: float = preview.distance_walked
	if not await reach([Vector3(1,0,25)]):
		return
	await mouse_look(-2.35,0.14)
	await key(KEY_E)
	await frames(40)
	check(preview.shortcut_open,"original inner-side return door still works independently")
	if not await reach([Vector3(0,0,48)]):
		return
	check(preview.returned and player.health==5,"returned normally with five HP preserved")
	if mode=="heat":
		await frames(180)
		check(preview.melt==1 and not preview.heating,"thawed entry does not refreeze behind player")
		check(route_length<115.0,"heat route including interruption recovery stays shorter than old outside approaches")
	await mouse_look(0,-0.13)
	await shot("07-returned")
	checks.append({"mode":mode,"outbound_meters":route_length,"outbound_seconds":route_seconds,"return_meters":preview.distance_walked-return_start,"melt":preview.melt})
	finish()
