extends SceneTree

## Audio sanity: every generated clip loaded, loops configured, playback works.

var failures: int = 0
var checks: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("AUDIO ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(30)
	var audio: AudioDirector = app.get("audio") as AudioDirector
	check(audio != null, "audio director present")
	check(audio.streams.size() >= 20, "generated clips loaded", {"count": audio.streams.size(), "keys": audio.streams.keys()})
	check(audio.core_hum != null and audio.core_hum.playing, "core hum loop playing")
	check(audio.ambience != null and audio.ambience.playing, "tunnel ambience loop playing")
	var hum: AudioStreamWAV = audio.streams.get("core_hum") as AudioStreamWAV
	check(hum != null and hum.loop_mode != AudioStreamWAV.LOOP_DISABLED, "core hum loop mode configured", {"loop": hum.loop_mode if hum != null else -1})
	for key in ["metal_clank", "lock_success", "lock_fail", "separation", "pin_pull", "data_take", "surge", "step_1"]:
		var s: AudioStream = audio.streams.get(key) as AudioStream
		check(s != null and s.get_length() > 0.05, "clip " + key, {"length": s.get_length() if s != null else 0.0})
	audio.play_sfx("metal_clank", Vector3.ZERO, -3.0)
	await frames(10)
	var playing: int = 0
	for p in audio.sfx3d_players:
		if p.playing:
			playing += 1
	for p in audio.sfx_players:
		if p.playing:
			playing += 1
	check(playing > 0, "one-shot playback works", {"playing": playing})
	var story: StoryDirector = app.get("story") as StoryDirector
	story.set_process(false)
	audio.set_tension(0.9)
	await frames(10)
	check(audio.core_hum.volume_db > -15.0, "core hum responds to tension", {"db": audio.core_hum.volume_db})
	var report: Dictionary = {"ok": failures == 0, "failures": failures, "checks": checks, "streams": audio.streams.size()}
	var f: FileAccess = FileAccess.open(out_dir + "/audio_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("AUDIO_REPORT ", JSON.stringify({"ok": failures == 0, "failures": failures, "streams": audio.streams.size()}))
	quit(0 if failures == 0 else 1)
