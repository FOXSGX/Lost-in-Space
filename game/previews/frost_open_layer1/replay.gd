extends "res://previews/frost_layer1/replay.gd"

var route_name: String = "east"
var max_route_height: float = 0.0

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			route_name = argument.trim_prefix("--route=")
	output = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261024-frost-open-layer1/runtime/"+route_name).simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	preview = load("res://previews/frost_open_layer1/preview.tscn").instantiate() as Main3D
	root.add_child(preview)
	await frames(30)
	player = preview.walker
	check(player.health==5 and preview._health_hud.cells.size()==5,"five HP and shared green five-cell HUD")
	check(player._camera.projection==Camera3D.PROJECTION_PERSPECTIVE and not player._visual.visible,"real first-person camera")
	check(preview._items.has_jet(1) and preview._items._cells.size()==2 and preview._items._equipment_cells.size()==2,"existing jet and two hand/two equipment cells")
	await shot("01-open-start")
	var targets: Array[Vector3] = [Vector3(-5,32.3,-3),Vector3(-56,preview.open_height(-56,-6)+9.5,-6),Vector3(51,preview.open_height(55,-5)+10.5,-5)]
	for index: int in targets.size():
		var target: Vector3 = targets[index]
		var delta: Vector3 = target-player._camera.global_position
		await mouse_look(atan2(-delta.x,-delta.z),-atan2(delta.y,Vector2(delta.x,delta.z).length()))
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player._camera.global_position,target,2)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
		var family: String = ["Tower","Antenna","Loader"][index]
		check(hit.is_empty() or String((hit.collider as Node).name).begins_with(family) or (hit.position as Vector3).distance_to(target)<1.0,"spawn sees landmark %d through real geometry" % index)
		await shot("start-landmark-%d" % index)
	# Exercise actual controls, the blocked direct route, and jet resource recovery.
	if route_name == "east":
		await mouse_look(0)
		var base_y: float = player.position.y
		Input.action_press("jump")
		await frames(6)
		Input.action_release("jump")
		await frames(10)
		check(player.position.y>base_y+0.5 and not player.jet_active,"short jump remains normal")
		await frames(60)
		Input.action_press("jump")
		var active: int = 0
		for index: int in 110:
			await frames(1)
			active += 1 if player.jet_active else 0
		Input.action_release("jump")
		await frames(150)
		check(active>=28 and active<=32,"existing single-bottle jet lasts about 0.5s")
		check(preview._items.tank_oxygen(1)<100 and preview._items.jet_reserve(1)>0.99,"landing refills by consuming bottle oxygen")
		await walk(Vector3(0,0,32))
		Input.action_press("move_up")
		await frames(90)
		Input.action_release("move_up")
		await key(KEY_E)
		check(player.position.z>28.5 and not preview.shortcut_open,"direct path blocked and outer E cannot open")
		Input.action_press("move_up")
		Input.action_press("jump")
		await frames(120)
		Input.action_release("move_up")
		Input.action_release("jump")
		await frames(120)
		check(player.position.z>28.5 and not preview.shortcut_open,"jump/jet cannot bypass closed direct gate")
		await walk(Vector3(0,0,48))
	var path: Array = preview.WEST_PATH if route_name in ["west","loop"] else (preview.CROSS_PATH if route_name=="cross" else preview.EAST_PATH)
	var outbound_start: float = preview.elapsed
	var outbound_distance: float = preview.distance_walked
	for index: int in path.size():
		if not await walk(path[index]):
			await shot("failure-stuck")
			finish()
			return
		max_route_height = maxf(max_route_height,player.position.y)
		var floor_error: float = absf(player.position.y+0.05-preview.open_height(player.position.x,player.position.z))
		check(player.is_on_floor() and floor_error<0.35,"grounded on visible terrain at checkpoint %d" % index)
		if index in [1,2,3]:
			var delta: Vector3 = Vector3(-5,31.7,-3)-player._camera.global_position
			await mouse_look(atan2(-delta.x,-delta.z),-atan2(delta.y,Vector2(delta.x,delta.z).length()))
			await shot("route-view-%d" % index)
		if route_name=="west" and index==2:
			check(player.position.y>3.5,"west approach reaches the natural high ground by walking")
			var back: Vector3 = Vector3(0,1.0,48)-player._camera.global_position
			await mouse_look(atan2(-back.x,-back.z),-atan2(back.y,Vector2(back.x,back.z).length()))
			var back_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player._camera.global_position,Vector3(0,1,48),2)
			check(player.get_world_3d().direct_space_state.intersect_ray(back_ray).is_empty(),"high ground has a real sightline back to landing pad")
			await shot("look-back-to-pad")
	check(preview.entered,"entered the same roofed ruin by this approach")
	var out_length: float = preview.distance_walked-outbound_distance
	var out_seconds: float = preview.elapsed-outbound_start
	await mouse_look(0,-0.1)
	await shot("02-inside-ruin")
	if route_name=="loop":
		# An open region must also allow the player to return without the gate.
		var outside: Array = preview.EAST_PATH.duplicate()
		outside.reverse()
		for point: Vector3 in outside:
			if not await walk(point):
				finish()
				return
		await walk(Vector3(0,0,48))
		check(preview.returned and not preview.shortcut_open,"outside return works without making shortcut mandatory")
		checks.append({"route":route_name,"outbound_meters":out_length,"outbound_seconds":out_seconds})
		await shot("outside-return")
		finish()
		return
	var back_start: float = preview.elapsed
	var back_distance: float = preview.distance_walked
	if not await walk(Vector3(1,0,25)):
		finish()
		return
	await mouse_look(-2.35,0.14)
	await key(KEY_E)
	await frames(40)
	check(preview.shortcut_open and preview.gate.collision_layer==0,"inner E moves gate and collision open")
	await shot("03-inner-latch")
	await walk(Vector3(0,0,48))
	check(preview.returned,"returned to pad through shortcut without teleport")
	check(preview.distance_walked-back_distance<out_length*0.65,"same-endpoint return is shorter than approach")
	await mouse_look(0,-0.13)
	await shot("04-returned")
	checks.append({"route":route_name,"outbound_meters":out_length,"outbound_seconds":out_seconds,"return_meters":preview.distance_walked-back_distance,"return_seconds":preview.elapsed-back_start,"max_route_height":max_route_height})
	finish()
