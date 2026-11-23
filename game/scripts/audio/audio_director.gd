class_name AudioDirector
extends Node

## Small, self-contained audio director. All sounds are generated for this
## project (see pipeline/synth_audio.py); nothing is loaded from outside res://.

const LOOPING: Array[String] = ["core_hum", "tunnel_wind", "alarm", "door_grind", "servo"]

var streams: Dictionary = {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx3d_players: Array[AudioStreamPlayer3D] = []
var core_hum: AudioStreamPlayer
var ambience: AudioStreamPlayer
var alarm: AudioStreamPlayer
var door_grind: AudioStreamPlayer
var servo: AudioStreamPlayer
var tension: float = 0.0
var _sfx_index: int = 0
var _sfx3d_index: int = 0
var _grind_on: bool = false
var _servo_on: bool = false
var _alarm_on: bool = false
var _ready_done: bool = false


func _ready() -> void:
	if not _ready_done:
		setup()


func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	name = "AudioDirector"
	for key in ["core_hum", "tunnel_wind", "alarm", "door_grind", "servo", "metal_clank", "lock_success",
			"lock_fail", "pin_pull", "separation", "door_latch", "door_open", "surge", "endstop", "memory",
			"data_reveal", "data_take", "step_1", "step_2", "step_3", "step_4", "lever_click", "shock"]:
		_load_stream(str(key))
	core_hum = _make_player("CoreHum", "core_hum", -12.0)
	ambience = _make_player("TunnelWind", "tunnel_wind", -21.0)
	alarm = _make_player("Alarm", "alarm", -40.0)
	door_grind = _make_player("DoorGrind", "door_grind", -13.0)
	servo = _make_player("Servo", "servo", -15.0)
	for i in range(10):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Sfx2D_%d" % i
		p.volume_db = -6.0
		add_child(p)
		sfx_players.append(p)
	for i in range(8):
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.name = "Sfx3D_%d" % i
		p3.unit_size = 4.0
		p3.max_distance = 32.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.volume_db = -4.0
		add_child(p3)
		sfx3d_players.append(p3)
	_start_loops()


func _load_stream(key: String) -> void:
	var path: String = "res://assets/audio/%s.wav" % key
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	if key in LOOPING and stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	streams[key] = stream


func _make_player(node_name: String, key: String, volume_db: float) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = node_name
	p.volume_db = volume_db
	if streams.has(key):
		p.stream = streams[key] as AudioStream
	add_child(p)
	return p


func _start_loops() -> void:
	if core_hum.stream != null:
		core_hum.play(0.0)
	if ambience.stream != null:
		ambience.play(0.0)
	if door_grind.stream != null:
		door_grind.volume_db = -60.0
		door_grind.play(randf() * 2.0)
	if servo.stream != null:
		servo.volume_db = -60.0
		servo.play(randf() * 2.0)
	if alarm.stream != null:
		alarm.volume_db = -60.0
		alarm.play(0.0)


func set_tension(value: float) -> void:
	tension = clampf(value, 0.0, 1.0)
	if core_hum != null:
		core_hum.volume_db = lerpf(-20.0, -8.0, tension)
		core_hum.pitch_scale = lerpf(0.82, 1.16, tension)
	if alarm != null:
		var want_alarm: bool = tension > 0.55
		if want_alarm and not _alarm_on:
			_alarm_on = true
			alarm.volume_db = -26.0
		elif not want_alarm and _alarm_on:
			_alarm_on = false
			alarm.volume_db = -60.0
		elif _alarm_on:
			alarm.volume_db = lerpf(-30.0, -18.0, (tension - 0.55) / 0.45)


func play_sfx(key: String, pos: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(key):
		return
	if pos != null and pos is Vector3:
		var p3: AudioStreamPlayer3D = sfx3d_players[_sfx3d_index % sfx3d_players.size()]
		_sfx3d_index += 1
		p3.stream = streams[key] as AudioStream
		p3.global_position = pos as Vector3
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.play()
	else:
		var p: AudioStreamPlayer = sfx_players[_sfx_index % sfx_players.size()]
		_sfx_index += 1
		p.stream = streams[key] as AudioStream
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()


func tick_door_grind(_delta: float) -> void:
	if door_grind != null and not _grind_on:
		_grind_on = true
		door_grind.volume_db = -13.0


func stop_door_grind() -> void:
	if door_grind != null and _grind_on:
		_grind_on = false
		door_grind.volume_db = -60.0


func tick_servo(_delta: float) -> void:
	if servo != null and not _servo_on:
		_servo_on = true
		servo.volume_db = -14.0


func stop_servo() -> void:
	if servo != null and _servo_on:
		_servo_on = false
		servo.volume_db = -60.0


func surge_pulse() -> void:
	play_sfx("shock", Vector3(0, 5, -2), 0.0, 0.85)
	if core_hum != null:
		core_hum.pitch_scale = 0.7
		var tween: Tween = create_tween()
		tween.tween_property(core_hum, "pitch_scale", lerpf(0.82, 1.16, tension), 1.6)


func stop_all_loops() -> void:
	if alarm != null:
		alarm.volume_db = -60.0
	if door_grind != null:
		door_grind.volume_db = -60.0
	if servo != null:
		servo.volume_db = -60.0
