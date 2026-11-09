extends Node
class_name GuluSfx

## 极简音效层：3 个短音，全部由 tools/audio/make_sfx.py 本地合成（无第三方素材）。
## 每种音有最短间隔，避免连续触发时变成噪音。

const STREAMS := {
	"kick": "res://assets/audio/ball_kick.wav",
	"block": "res://assets/audio/dragon_block.wav",
	"loaded": "res://assets/audio/fuel_loaded.wav",
}

const MIN_INTERVAL := {
	"kick": 0.12,
	"block": 0.35,
	"loaded": 0.25,
}

const VOLUME_DB := {
	"kick": -6.0,
	"block": -8.0,
	"loaded": -6.0,
}

var _players: Dictionary = {}
var _last_ms: Dictionary = {}


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


func play(key: String) -> void:
	var player := _players.get(key) as AudioStreamPlayer
	if player == null:
		return
	var now := Time.get_ticks_msec()
	var interval := int(float(MIN_INTERVAL.get(key, 0.3)) * 1000.0)
	if now - int(_last_ms.get(key, -100000)) < interval:
		return
	_last_ms[key] = now
	player.play()
