extends RefCounted
class_name SfxKit

## 《迷失太空》轻量级 3D/2D 音效播放套件（自动复用加载缓存、播完自动清理）

const DIR := "res://assets/audio/rebuild/"
static var _cache: Dictionary = {}

static func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key] as AudioStream
	var path: String = DIR + key + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path) as AudioStream
	_cache[key] = st
	return st

## 在世界坐标播放一次 3D 空间音效（播完自动释放）
static func play_3d(parent: Node, key: String, pos: Vector3, volume_db: float = -4.0, pitch: float = 1.0, max_dist: float = 36.0) -> void:
	if parent == null or DisplayServer.get_name() == "headless":
		return
	var st: AudioStream = _stream(key)
	if st == null:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.position = pos
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## 播放一次非空间 2D UI/第一人称音效
static func play_2d(parent: Node, key: String, volume_db: float = -5.0, pitch: float = 1.0) -> void:
	if parent == null or DisplayServer.get_name() == "headless":
		return
	var st: AudioStream = _stream(key)
	if st == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## 挂接在物体上的循环 3D 音源（用于复古磁力音响 BGM 等）
static func attach_loop_3d(parent: Node3D, key: String, volume_db: float = -6.0, max_dist: float = 28.0) -> AudioStreamPlayer3D:
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var st: AudioStream = _stream(key)
	if st == null:
		return null
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = volume_db
	p.max_distance = max_dist
	if st is AudioStreamWAV:
		var wav: AudioStreamWAV = (st as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		p.stream = wav
	parent.add_child(p)
	p.play()
	return p

## 挂接循环环境音（极地风雪等）
static func attach_loop_2d(parent: Node, key: String, volume_db: float = -18.0) -> AudioStreamPlayer:
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var st: AudioStream = _stream(key)
	if st == null:
		return null
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = volume_db
	if st is AudioStreamWAV:
		var wav: AudioStreamWAV = (st as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		p.stream = wav
	parent.add_child(p)
	p.play()
	return p
