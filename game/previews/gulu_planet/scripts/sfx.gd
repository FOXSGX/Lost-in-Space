extends Node
class_name GuluSfx

## 极简音效层：5 个短音，全部由 tools/audio/make_sfx.py 本地合成（无第三方素材）。
## 每种音有最短间隔，避免连续状态切换时变成噪音。

const STREAMS := {
	"notice": "res://assets/audio/dragon_notice.wav",
	"windup": "res://assets/audio/dragon_windup.wav",
	"release": "res://assets/audio/fuel_release.wav",
	"loaded": "res://assets/audio/fuel_loaded.wav",
	"chomp": "res://assets/audio/dragon_chomp.wav",
}

const MIN_INTERVAL := {
	"notice": 0.45,
	"windup": 0.9,
	"release": 0.5,
	"loaded": 0.25,
	"chomp": 0.6,
}

const VOLUME_DB := {
	"notice": -9.0,
	"windup": -11.0,
	"release": -7.0,
	"loaded": -6.0,
	"chomp": -9.0,
}

var _players: Dictionary = {}
var _last_ms: Dictionary = {}


func _ready() -> void:
	for key in STREAMS:
		var path: String = STREAMS[key]
		if not ResourceLoader.exists(path):
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


func play(key: String) -> void:
	var player := _players.get(key) as AudioStreamPlayer
	if player == null:
		return
	var now := Time.get_ticks_msec()
	var interval := int(float(MIN_INTERVAL.get(key, 0.4)) * 1000.0)
	if now - int(_last_ms.get(key, -100000)) < interval:
		return
	_last_ms[key] = now
	player.play()
