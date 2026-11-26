class_name SurgeDirector
extends Node

## Resonance recoil ("共振反冲") director.
##
## It never fires a cutscene: it watches the real core state, warns for a few
## seconds with mechanical signs (lamps, cable tension, catwalk sway, klaxon),
## computes the severity from what the team actually did, then applies physical
## consequences. Every player action taken during the warning is a real
## mitigation and is recorded as an accident-phase action.

signal warning_started(seconds: float, severity_hint: float)
signal surge_started(severity: float)
signal surge_finished()

const WARNING_TIME := 3.6
const MIN_INTERVAL := 40.0
const FORCE_AFTER := 26.0
const SECOND_FORCE_PROGRESS := 0.30

var level: LevelBuilder
var core: CoreRig
var session: CoopSession
var audio: AudioDirector
var hud: GameHud
var player: PlayerController

var active: bool = true
var state: String = "idle"
var warning_left: float = 0.0
var severity: float = 0.0
var surge_count: int = 0
var cooldown: float = 12.0
var charge: float = 0.0
var balance_clock: float = 0.0
var last_count: int = 0
var _warning_responses: Dictionary = {}
var _armed_second: bool = false
var _time: float = 0.0


func setup(p_level: LevelBuilder, p_session: CoopSession, p_audio: AudioDirector, p_hud: GameHud, p_player: PlayerController) -> void:
	name = "SurgeDirector"
	level = p_level
	session = p_session
	audio = p_audio
	hud = p_hud
	player = p_player
	core = p_level.core


func set_remote(value: bool) -> void:
	active = not value


func _process(delta: float) -> void:
	_time += delta
	if level == null or core == null:
		return
	if not active:
		if warning_left > 0.0:
			warning_left = maxf(0.0, warning_left - delta)
		return
	match state:
		"idle":
			cooldown = maxf(0.0, cooldown - delta)
			# The hall has to be entered before the core can threaten anyone;
			# otherwise the very first seconds of the tunnel would already arm
			# a recoil nobody can see or answer.
			var stage: int = level.story_stage()
			if stage < 1:
				return
			_update_balance_clock(delta)
			var danger: float = _danger()
			if cooldown <= 0.0 and stage >= 2 and danger > 0.55:
				charge += delta
			else:
				charge = maxf(0.0, charge - delta * 0.6)
			if cooldown <= 0.0 and stage >= 2 and charge > 1.1:
				_begin_warning()
			elif cooldown <= 0.0 and stage >= 2 and balance_clock > FORCE_AFTER:
				_begin_warning()
			elif cooldown <= 0.0 and not _armed_second and level.isolation != null and level.isolation.progress > SECOND_FORCE_PROGRESS:
				_armed_second = true
				_begin_warning()
		"warning":
			warning_left -= delta
			_collect_responses()
			_pulse_warning()
			if warning_left <= 0.0:
				_fire()
		"surge":
			warning_left -= delta
			if warning_left <= 0.0:
				state = "idle"
				cooldown = MIN_INTERVAL
				level.set_alarm(false)
				surge_finished.emit()


func _update_balance_clock(delta: float) -> void:
	if level.story_stage() >= 2 and not core.is_locked():
		balance_clock += delta
		if level.isolation != null and level.isolation.progress > 0.0:
			balance_clock += delta * 0.0


func _danger() -> float:
	var cart_speed: float = absf(level.left_cart.velocity) + absf(level.right_cart.velocity)
	return absf(core.net) * 1.1 + absf(core.omega) * 0.55 + cart_speed * 0.8


func _begin_warning() -> void:
	state = "warning"
	charge = 0.0
	warning_left = WARNING_TIME
	severity = _estimate_severity()
	_warning_responses.clear()
	level.set_alarm(true)
	if audio != null:
		audio.play_sfx("alarm", level.HALL_CENTER + Vector3(0, 6, 0), 0.0)
		audio.surge_pulse()
	if hud != null:
		hud.show_alert("共振反冲预警  ·  3 秒", WARNING_TIME)
		hud.subtitle("核心在回弹！抓住栏杆、给制动蓄压、把支腿锁死——现在！", "七号", 3.4)
	warning_started.emit(WARNING_TIME, severity)


func _estimate_severity() -> float:
	var base: float = 0.52 + clampf(absf(core.omega) / 0.6, 0.0, 1.0) * 0.42
	var cart_speed: float = (absf(level.left_cart.velocity) + absf(level.right_cart.velocity)) * 0.5
	base += clampf(cart_speed / 0.30, 0.0, 1.0) * 0.22
	base -= clampf(level.stabilizers_latched() / 2.0, 0.0, 1.0) * 0.10
	return clampf(base, 0.25, 1.6)


func _collect_responses() -> void:
	if session == null:
		return
	# Grabbing a rail during the warning is a real protective action.
	for pid in session.current_grab_pids():
		if _warning_responses.has(pid):
			continue
		_warning_responses[pid] = true
		session.credit(pid, "surge_response", 1.0, "预兆中抓住栈桥横杆")
	# Brake pressure built during the warning, by whoever is on a pump.
	if level.brake != null:
		var pressure: float = level.brake.pressure
		if pressure > 0.05 and not level.brake.latched:
			for machine_id in ["brake", "brake_assist"]:
				var owner: int = session.claim_owner(machine_id)
				if owner == 0:
					continue
				if _warning_responses.has(owner):
					continue
				_warning_responses[owner] = true
				session.credit(owner, "surge_response", 1.0, "预兆中操作应急制动")
	# Holding a stabiliser pump counts too.
	for stab in level.stabilizers:
		var owner: int = session.claim_owner(stab.machine_id)
		if owner == 0 or _warning_responses.has(owner):
			continue
		if absf(stab.pressure - float(_warning_responses.get("p_%d" % owner, 0.0))) > 0.05 or stab.pressure > 0.15:
			_warning_responses[owner] = true
			session.credit(owner, "surge_response", 1.0, "预兆中泵压稳定支腿")


func _pulse_warning() -> void:
	if level == null:
		return
	# Ramps and cables shake harder as the warning runs out.
	level.set_warning_intensity(1.0 - warning_left / maxf(0.01, WARNING_TIME))


func _fire() -> void:
	severity = _final_severity()
	state = "surge"
	warning_left = 1.1
	surge_count += 1
	# Physical consequences on every linked machine.
	if core != null:
		core.play_surge(severity)
	if level.catwalk != null:
		level.catwalk.on_surge(severity)
	if level.brake != null:
		level.brake.on_surge(severity)
	for stab in level.stabilizers:
		stab.on_surge(severity)
	# Anyone still holding a rail through the shock gets the "held on" credit.
	if session != null:
		for pid in session.current_grab_pids():
			session.credit(pid, "brace_hold", 1.0, "冲击中抓住栏杆")
	if audio != null:
		audio.play_sfx("shock", level.HALL_CENTER + Vector3(0, 3, 0), 2.0)
		audio.surge_pulse()
	if hud != null:
		hud.show_alert("共振反冲  ·  %.0f%% 强度" % (severity * 100.0), 3.0)
		hud.shake(0.55 * severity)
		var line: String = "反冲冲击！"
		if level.brake != null and level.brake.latched:
			line += "制动吸收了大部分能量。"
		elif level.catwalk != null and level.catwalk.pins_seated == 0:
			line += "安全销全部脱开，栈桥限位失效！"
		elif level.catwalk != null and level.catwalk.pins_seated == 1:
			line += "一根安全销被震脱，需要有人重新固定。"
		else:
			line += "栈桥在晃，检查安全销和制动。"
		hud.subtitle(line, "七号", 3.2)
	surge_started.emit(severity)


func _final_severity() -> float:
	var value: float = severity
	if level.brake != null:
		value -= level.brake.brake_effect() * 0.30
	value += clampf((absf(level.left_cart.velocity) + absf(level.right_cart.velocity)) / 0.4, 0.0, 1.0) * 0.16
	if level.catwalk != null:
		value += (2 - level.catwalk.pins_seated) * 0.10
		value -= level.catwalk.preload_state * 0.12
	return clampf(value, 0.22, 1.6)


## Client-side replay of the host's warning / surge events (visuals only).
func apply_remote_warning(seconds: float, hint: float) -> void:
	warning_left = seconds
	severity = hint
	state = "warning"
	if level != null:
		level.set_alarm(true)
	if hud != null:
		hud.show_alert("共振反冲预警  ·  %.0f 秒" % ceil(seconds), seconds)
		hud.subtitle("核心在回弹！抓住栏杆、给制动蓄压、把支腿锁死——现在！", "七号", 3.4)
	if audio != null:
		audio.play_sfx("alarm", level.HALL_CENTER + Vector3(0, 6, 0), 0.0)


func apply_remote_surge(sev: float) -> void:
	severity = sev
	surge_count += 1
	state = "surge"
	warning_left = 1.1
	if core != null:
		core.play_surge(sev)
	if level != null:
		if level.catwalk != null:
			level.catwalk.on_surge(sev)
		if level.brake != null:
			level.brake.on_surge(sev)
	if audio != null:
		audio.play_sfx("shock", level.HALL_CENTER + Vector3(0, 3, 0), 2.0)
	if hud != null:
		hud.show_alert("共振反冲  ·  %.0f%% 强度" % (sev * 100.0), 3.0)
		hud.shake(0.55 * sev)


func reset_state() -> void:
	state = "idle"
	warning_left = 0.0
	charge = 0.0
	cooldown = 12.0
	balance_clock = 0.0
	_armed_second = false
	_warning_responses.clear()
	if level != null:
		level.set_alarm(false)


func snapshot() -> Dictionary:
	return {
		"state": state,
		"warning": warning_left,
		"severity": severity,
		"count": surge_count,
	}


func apply_snapshot(data: Dictionary) -> void:
	var new_state: String = str(data.get("state", state))
	var new_count: int = int(data.get("count", surge_count))
	if new_state == "warning" and state != "warning" and warning_left <= 0.1:
		apply_remote_warning(float(data.get("warning", WARNING_TIME)), float(data.get("severity", 0.5)))
	if new_count > surge_count and new_state == "surge":
		apply_remote_surge(float(data.get("severity", 0.5)))
	warning_left = float(data.get("warning", 0.0))
	if new_state == "idle" and warning_left <= 0.0:
		state = "idle"
