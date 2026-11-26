extends Node
class_name GuluSfx

## 极简音效层：4 个短音 + 1 条 BGM，全部由 tools/audio/*.py 本地合成（无第三方素材）。
## 每种音有最短间隔，避免连续触发时变成噪音。

const STREAMS := {
	"metal": "res://assets/audio/goal_frame.wav",
	"kick": "res://assets/audio/ball_kick.wav",
	"block": "res://assets/audio/dragon_block.wav",
	"loaded": "res://assets/audio/fuel_loaded.wav",
	"step": "res://assets/audio/footstep.wav",
}

const MIN_INTERVAL := {
	"kick": 0.12,
	"block": 0.35,
	"loaded": 0.25,
	"metal": 0.10,
	"step": 0.16,
}

const VOLUME_DB := {
	"kick": -6.0,
	"block": -8.0,
	"loaded": -6.0,
	"metal": -10.0,
	"step": -17.0,
}

var _players: Dictionary = {}
## 背景音乐：40 s 无缝循环，由 tools/audio/make_bgm.py 程序化生成（无第三方素材）。
const MUSIC_PATH := "res://assets/audio/bgm_loop.wav"
const MUSIC_VOLUME_DB := -15.0
var _music: AudioStreamPlayer
## 环境底噪（风/管线低频）：一条 6 秒无缝循环，按地图调音量与音高。
const AMB_PATH := "res://assets/audio/amb_wind.wav"
var _amb: AudioStreamPlayer

var _last_ms: Dictionary = {}
var _duck_until := 0
## 静音：只挡播放，不销毁播放器；设置会被 gulu_app 写进 user://gulu_record.cfg。
var muted := false


func _ready() -> void:
	for key in STREAMS:
		var path: String = STREAMS[key]
		if not ResourceLoader.exists(path):
			push_warning("音效缺失：%s" % path)
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = float(VOLUME_DB.get(key, -9.0))
		add_child(player)
		_players[key] = player
		_last_ms[key] = -100000



## 环境底噪：地图切换时调用；pitch 与音量决定是“风”还是“管线低频”。
func play_ambience(pitch: float, volume_db: float) -> void:
	if muted:
		return
	if _amb == null:
		if not ResourceLoader.exists(AMB_PATH):
			return
		var stream := load(AMB_PATH) as AudioStreamWAV
		if stream == null:
			return
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.get_length() * stream.mix_rate
		_amb = AudioStreamPlayer.new()
		_amb.stream = stream
		add_child(_amb)
	_amb.pitch_scale = clampf(pitch, 0.5, 2.0)
	_amb.volume_db = volume_db
	if not _amb.playing:
		_amb.play()


func stop_ambience() -> void:
	if _amb != null and _amb.playing:
		_amb.stop()
func setup_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		push_warning("BGM 缺失：%s" % MUSIC_PATH)
		return
	var stream := load(MUSIC_PATH) as AudioStreamWAV
	if stream == null:
		push_warning("BGM 不是 AudioStreamWAV：%s" % MUSIC_PATH)
		return
	# 运行时打开循环：整段无缝，循环点就是文件首尾（生成脚本保证首尾连续）。
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	_music = AudioStreamPlayer.new()
	_music.name = "Bgm"
	_music.stream = stream
	_music.volume_db = MUSIC_VOLUME_DB
	add_child(_music)
	_music.play()


func has_music() -> bool:
	return _music != null and _music.stream != null


func music_playing() -> bool:
	return _music != null and _music.playing


func music_length() -> float:
	if _music == null or _music.stream == null:
		return 0.0
	return _music.stream.get_length()


func music_volume_db() -> float:
	return _music.volume_db if _music != null else -200.0


func set_muted(value: bool) -> void:
	if value and _amb != null and _amb.playing:
		_amb.stop()
	muted = value
	if _music != null:
		_music.volume_db = -80.0 if value else MUSIC_VOLUME_DB


func is_muted() -> bool:
	return muted


func play(key: String) -> void:
	play_pitched(key, 1.0)


## 带音高变化（连击 / 倒计时用）：1.0 = 原调，>1 更尖。
func play_pitched(key: String, pitch: float) -> void:
	if muted:
		return
	var player := _players.get(key) as AudioStreamPlayer
	if player == null:
		return
	var now := Time.get_ticks_msec()
	var interval := int(float(MIN_INTERVAL.get(key, 0.3)) * 1000.0)
	if now - int(_last_ms.get(key, -100000)) < interval:
		return
	# 优先听清“进球”：进球后的 0.38 s 内不再叠倒计时/风声。
	if key != "loaded" and now < _duck_until:
		return
	if key == "loaded":
		_duck_until = now + 380
	_last_ms[key] = now
	player.pitch_scale = clampf(pitch, 0.6, 1.35)
	player.play()
