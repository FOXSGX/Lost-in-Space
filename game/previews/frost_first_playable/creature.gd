extends StaticBody3D

signal popped(creature: Node3D)
var charge: float = 0.0
var cooldown: float = 0.0
var launches: int = 0
var visual: MeshInstance3D
var skin: StandardMaterial3D
var sound: AudioStreamPlayer3D
var pop_sound: AudioStreamPlayer3D
var previous_launches: int = 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 3.2
	cylinder.height = 0.7
	shape.shape = cylinder
	shape.position.y = 0.35
	add_child(shape)
	visual = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 3.25
	mesh.height = 6.5
	visual.mesh = mesh
	visual.position.y = 0.35
	skin = StandardMaterial3D.new()
	skin.albedo_color = Color("c17e9e")
	skin.roughness = 0.5
	visual.material_override = skin
	add_child(visual)
	sound = AudioStreamPlayer3D.new()
	sound.stream = preload("res://assets/audio/oxygen-jet.wav")
	sound.volume_db = -16
	sound.max_distance = 40
	add_child(sound)
	pop_sound = AudioStreamPlayer3D.new()
	pop_sound.stream = preload("res://previews/frost_first_playable/audio/jump.wav")
	pop_sound.volume_db = -18
	pop_sound.max_distance = 55
	add_child(pop_sound)

func heat(delta: float) -> void:
	if cooldown <= 0:
		charge = minf(1, charge + delta / 3.8)
		if charge >= 1:
			launches += 1
			popped.emit(self)
			charge = 0
			cooldown = 2.5

func tick(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)

func _process(_delta: float) -> void:
	if launches > previous_launches:
		pop_sound.play()
	previous_launches = launches
	visual.scale = Vector3(1 + charge * 0.12, 0.12 + charge * 0.16, 1 + charge * 0.12)
	visual.rotation.z = sin(Time.get_ticks_msec() * 0.025) * charge * 0.025
	skin.albedo_color = Color("c17e9e").lerp(Color("f5cc91"), charge)
	sound.pitch_scale = 0.55 + charge
	if charge > 0.1 and not sound.playing:
		sound.play()
	elif charge <= 0.1 and sound.playing:
		sound.stop()
