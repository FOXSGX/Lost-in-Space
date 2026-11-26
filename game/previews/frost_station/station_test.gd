extends SceneTree

var a: Node3D
var p: Node3D
var failures: int = 0
var checks: int = 0
var shots: String = ""

func _initialize() -> void:call_deferred("run")
func frames(n: int) -> void:
	for i: int in n:await physics_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures += 1
func walk(point: Vector3, maximum: int = 1800) -> bool:
	for i: int in maximum:
		var offset: Vector3 = point-p.position
		if Vector2(offset.x,offset.z).length()<0.65:
			a.accept_controls(1,{})
			await frames(6)
			return true
		var yaw: float = atan2(-offset.x,-offset.z)
		p._camera_yaw_target = yaw
		a.accept_controls(1,{"move":Vector2(0,-1),"yaw":yaw})
		await physics_frame
	print("BLOCKED target=",point," actual=",p.position)
	a.accept_controls(1,{})
	return false
func use() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = "interact"
	Input.parse_input_event(event)
	await frames(2)
func aim(point: Vector3) -> void:
	var offset: Vector3 = point-(p.position+Vector3.UP*1.5)
	var yaw: float = atan2(-offset.x,-offset.z)
	var pitch: float = atan2(-offset.y,Vector2(offset.x,offset.z).length())
	p._camera_yaw_target = yaw
	p._camera_pitch_target = pitch
	a.accept_controls(1,{"yaw":yaw,"pitch":pitch})
func shot(name_value: String) -> void:
	if shots.is_empty() or DisplayServer.get_name()=="headless":return
	await frames(8)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(shots+"/"+name_value+".png")
func drive(point: Vector3, maximum: int = 1800) -> bool:
	for i: int in maximum:
		var offset: Vector3 = point-a.world.cart.position
		if Vector2(offset.x,offset.z).length()<2:
			a.accept_controls(1,{})
			await frames(90)
			return true
		var desired: float = atan2(-offset.x,-offset.z)
		var angle: float = wrapf(desired-a.world.cart.rotation.y,-PI,PI)
		a.accept_controls(1,{"move":Vector2(clampf(-angle*1.7,-1,1),-0.45 if absf(angle)>0.6 else -1.0)})
		await physics_frame
	print("CART_BLOCKED target=",point," actual=",a.world.cart.position)
	return false
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--shots" in args:shots = args[args.find("--shots")+1]
	a = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	p = a.players[1]
	await frames(20)
	check(a.world.rooms.size()==7,"six buildings plus ship built")
	check(a.world.museum_bones.size()==14,"museum static unfinished skeleton")
	var wheel_event: InputEventMouseButton = InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	Input.parse_input_event(wheel_event)
	await frames(2)
	check(a._items.ensure_bag(1).selected==1,"real wheel input switches selected hand slot")
	a._items.ensure_bag(1).selected = 0
	check(await walk(Vector3(0,0,-4)),"walk out of ship toward station")
	# Use a clear outside approach around the small initial meltable snowbank.
	check(await walk(Vector3(10,0,-4)),"open station route available beside snow")
	check(await walk(Vector3(10,0,-85)),"walk from apron through compact courtyard")
	check(await walk(Vector3(0,0,-91)),"reach main entrance")
	aim(Vector3(0,1.5,-108));await shot("01-main-entrance")
	check(await walk(Vector3(0,0,-95)),"enter central main hall")
	check(await walk(Vector3(-23,0,-95)),"find visible side stairs")
	check(await walk(Vector3(-23,4.2,-116)),"ordinary input climbs stairs to upper ring")
	check(p.position.y>3.9,"upper floor actual height")
	check(await walk(Vector3(-5,4.2,-116)),"walk ring to office door")
	check(await walk(Vector3(-5,4.2,-120)),"enter chief office")
	check(a.nearby_station(1).get("kind","")=="safe","upstairs cabinet reachable")
	await use()
	check(not a.progress.energy,"cabinet cannot open without key")
	aim(Vector3(-5,5.5,-123));await shot("02-chief-office")
	check(await walk(Vector3(-5,4.2,-116)),"return from office to ring")
	check(await walk(Vector3(19,4.2,-118)),"reach observation side")
	aim(Vector3(0,20,-185));await shot("03-bone-window")
	check(await walk(Vector3(-23,4.2,-116)),"return toward side stairs")
	check(await walk(Vector3(-23,0,-95)),"walk down side stairs")
	check(await walk(Vector3(12,0,-99)),"open continuous lab reachable")
	aim(Vector3(15,1.5,-106));await shot("04-laboratory")
	# Focused fixtures for tools and each optional room, then real local traversal.
	p.position = Vector3(15,0.4,-104.2)
	await frames(8)
	await use()
	check(a._items.count_kind(1,"suction")==1,"normal E picks up suction tool")
	aim(Vector3(13,0.5,-102))
	var before: Vector3 = Vector3.ZERO
	var target: Node3D
	for entry: Dictionary in a._items.drops:
		if entry.kind=="crate":
			target = a._items._prop_bodies[entry.uid]
			break
	if target != null:
		p.position = target.position+Vector3(0,0,5)
		p.position.y = 0.5
		aim(target.position)
		before = target.position
		var packet: Dictionary = p.controls.duplicate()
		packet.heat = true
		a.accept_controls(1,packet)
		await frames(35)
		check(not a.grabbed.is_empty() and target.position.distance_to(before)>0.3,"held input physically pulls crate")
		a.handle_action(1,"push")
		await frames(4)
		check(a.grabbed.is_empty(),"push releases target")
		a.accept_controls(1,{})
	a._items.bags[1].slots = [{"kind":"chips"},{}]
	a._items.bags[1].selected = 0
	a.handle_action(1,"item_use")
	check(a.progress.get("snacks_eaten",0)==1 and a._items.occupied(1)==0,"food consumed once")
	a.handle_action(1,"item_use")
	check(a.progress.snacks_eaten==1,"empty slot does not repeat food reward")
	p.position = Vector3(5,1,8)
	a._items.add_item(1,"keepsake",-1,{},true)
	await frames(6)
	await use()
	check(a.progress.get("collection_count",0)==1,"keepsake deposited in ship collection")
	check(a.world.collection_models[0].visible,"collected keepsake appears on ship shelf")
	await use()
	check(a.progress.collection_count==1,"collection cannot duplicate")
	p.position = Vector3(50,0.4,-106)
	await frames(8)
	await use()
	check(a.progress.get("district_power",false),"normal E restores optional district power")
	check(a.world.power_lights[0].light_energy>0,"outside district lamps actually lit")
	aim(Vector3(58,2,-120));await shot("05-power")
	# Melt a real warehouse doorway, using held heater controls.
	a._items.bags[1].slots = [{"kind":"heater","charge":180.0},{}]
	a._items.bags[1].selected = 0
	var ice: Node3D = a.world.ice[a.world.warehouse_ice[0]]
	p.position = Vector3(ice.position.x,0.4,-18)
	await frames(8)
	aim(ice.position)
	var heat: Dictionary = p.controls.duplicate();heat.heat = true
	a.accept_controls(1,heat)
	await frames(390)
	a.accept_controls(1,{})
	check(ice.amount==1 and ice.collision_layer==0,"held heat opens warehouse ice collision")
	check(await walk(Vector3(ice.original.x,0,-27)),"walk through melted warehouse room entry")
	aim(Vector3(-53,2,-31));await shot("06-warehouse")
	p.position = Vector3(-49,0.4,-50)
	await frames(8)
	check(await walk(Vector3(-49,0,-60)),"museum open entrance")
	aim(Vector3(-49,4,-80));await shot("07-museum")
	p.position = Vector3(49,0.4,-42)
	await frames(8)
	check(await walk(Vector3(49,0,-58)),"living public room reachable")
	check(await walk(Vector3(49,0,-70)),"living room partitions reachable")
	aim(Vector3(38,1.5,-78));await shot("08-dorm")
	# Vehicle case is isolated in its garage fixture but driven through real geometry.
	a._items.bags[1].slots = [{"kind":"cell"},{}]
	p.position = a.world.cart.to_global(Vector3(0,0,3.8))
	await frames(8)
	await use()
	check(a.world.cart.cargo.size()==1 and a._items.occupied(1)==0,"rear E loads cargo without duplication")
	await use()
	check(a.world.cart.cargo.is_empty() and a._items.count_kind(1,"cell")==1,"rear E unloads cargo")
	p.position = a.world.cart.position+Vector3(-3,0,0)
	await frames(8)
	await use()
	check(a.world.cart.riders.has(1),"normal E boards driver seat")
	var cart_start: Vector3 = a.world.cart.position
	a.accept_controls(1,{"move":Vector2(0,1)})
	await frames(170)
	a.accept_controls(1,{})
	await frames(90)
	check(a.world.cart.position.distance_to(cart_start)>10,"reverse drives cart through broad garage door")
	await use()
	check(not a.world.cart.riders.has(1),"normal E exits to safe ground")
	# Isolate the road fixture, then use real steering through the open compound into cave.
	a.world.cart.position = Vector3(36,1,-93)
	a.world.cart.rotation = Vector3.ZERO
	a.world.cart.speed = 0
	p.position = Vector3(33,0.5,-93)
	await frames(8)
	await use()
	check(await drive(Vector3(36,0,-140)),"cart drives east-side compound road")
	check(await drive(Vector3(2,0,-150)),"cart turns on open approach to fossil mouth")
	check(await drive(Vector3(0,0,-210)),"cart actually enters first fossil hall")
	check(a.world.cart.position.z<-190,"vehicle remains driveable inside ruins")
	aim(Vector3(0,5,-245));await shot("09-cart-inside-ruins")
	await use()
	# The complete mainline is checked by reaching the real key fixture, then office and core.
	p.position = Vector3(-2.4,12.2,-600)
	await frames(8)
	await use()
	check(a.progress.key,"real key fixture acquired")
	p.position = Vector3(-5,4.3,-120)
	await frames(8)
	await use()
	check(a.progress.energy,"key opens upstairs safe")
	check(a.world.safe_door.rotation.y<-1 and not a.world.energy_visual.visible,"cabinet visibly opens and secured core disappears")
	p.position = Vector3(0,1,14)
	await frames(8)
	await use();await use()
	check(a.progress.flight,"energy install and flight loop complete")
	check(a.snapshot().surface_schema==4 and a.snapshot().cart.has("cargo"),"new world snapshot schema contains vehicle and cargo")
	# Team interactions and adversarial boarding checks use the same host action path.
	a.spawn_actor(2,false)
	p.position = Vector3(0,0.4,-65)
	a.players[2].position = Vector3(0,0.4,-70)
	a._items.bags[1].slots = [{"kind":"suction"},{}]
	a._items.bags[1].selected = 0
	await frames(8)
	aim(a.players[2].position+Vector3.UP)
	await frames(2)
	var health: int = a.players[2].health
	var teammate_start: Vector3 = a.players[2].position
	a.handle_action(1,"push")
	await frames(20)
	check(a.players[2].position.distance_to(teammate_start)>0.5 and a.players[2].health==health,"suction pushes teammate without direct damage")
	a.world.cart.position = Vector3(26,1,-20)
	a.world.cart.rotation = Vector3.ZERO
	p.position = Vector3(22,0.5,-20)
	await frames(8)
	check(not a.world.cart.board(1),"garage wall blocks remote boarding")
	a.world.cart.position = a.world.cart.home
	p.position = a.world.cart.position+Vector3(-3,0,0)
	a.players[2].position = a.world.cart.position+Vector3(3,0,0)
	await frames(8)
	a.handle_action(1,"interact")
	a.handle_action(2,"interact")
	check(a.world.cart.riders.size()==2,"driver and teammate can occupy separate seats")
	a.accept_controls(1,{"move":Vector2(0,1)})
	await frames(60)
	check(a.players[2].position.distance_to(a.world.cart.to_global(a.world.cart.SEATS[1]))<0.3,"passenger follows moving transport")
	a.accept_controls(1,{})
	a.world.cart.cargo = [{"kind":"cell","charge":63.0}]
	a.hurt(1,5);a.hurt(2,5)
	await frames(140)
	check(a.progress.wipes==1 and a.world.cart.riders.is_empty() and a.world.cart.cargo.size()==1,"team wipe releases seats and preserves vehicle cargo")
	print("STATION_RESULT checks=",checks," failures=",failures)
	quit(failures)
