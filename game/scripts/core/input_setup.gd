class_name InputSetup
extends RefCounted

## Runtime input map. Keeping it in code guarantees that headless tests and the
## exported build agree on every physical key and action name.

const KEY_BINDINGS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
	"cancel": [KEY_ESCAPE],
	"reset_level": [KEY_R],
	"restart_level": [KEY_F5],
	"toggle_debug": [KEY_F3],
	"help": [KEY_F1],
	# --- Act 4 (Resonance 04) actions, registered in the same shared map -----
	"pickup": [KEY_F],
	"drop": [KEY_X],
	"rotate_crystal": [KEY_Q],
	"pause": [KEY_ESCAPE],
	# --- Act 01 (Silent Station) unified actions ------------------------------
	# X doubles as "drop" (Act 4) and "emergency stop" (Act 01); each act reads
	# the action name it actually polls, so the physical key stays consistent.
	"emergency": [KEY_X],
	# --- Act 02/03 (Cart Journey) unified actions -----------------------------
	# E already covers "repair/interact". B brakes the cart, G installs/confirms
	# an assembly, W/S/Shift drive the winch console, Space throws the drum
	# brake, Q releases a hold (also the global "cancel" action).
	"cart_brake": [KEY_B],
	"deposit": [KEY_G],
	"winch_haul": [KEY_W],
	"winch_payout": [KEY_S],
	"winch_creep": [KEY_SHIFT],
	"winch_brake": [KEY_SPACE],
	"winch_release": [KEY_Q],
	"cart_recover": [KEY_R],
	"show_help": [KEY_F1],
	"mute_preview": [KEY_M],
	"airwall_scan": [KEY_F4],
}

const PAD_BUTTONS: Dictionary = {
	"jump": [JOY_BUTTON_A],
	"interact": [JOY_BUTTON_X],
	"cancel": [JOY_BUTTON_START],
	"sprint": [JOY_BUTTON_LEFT_SHOULDER],
}

const PAD_AXES: Dictionary = {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
}


static func ensure_actions() -> void:
	for action in KEY_BINDINGS.keys():
		var name: String = str(action)
		if not InputMap.has_action(name):
			InputMap.add_action(name, 0.25)
		for key in KEY_BINDINGS[name]:
			var already: bool = false
			for ev in InputMap.action_get_events(name):
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode == int(key):
					already = true
					break
			if already:
				continue
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = int(key)
			InputMap.action_add_event(name, key_event)
	for action in PAD_BUTTONS.keys():
		var name2: String = str(action)
		if not InputMap.has_action(name2):
			InputMap.add_action(name2, 0.25)
		for button_index in PAD_BUTTONS[name2]:
			var button: InputEventJoypadButton = InputEventJoypadButton.new()
			button.button_index = int(button_index)
			InputMap.action_add_event(name2, button)
	for action in PAD_AXES.keys():
		var name3: String = str(action)
		if not InputMap.has_action(name3):
			InputMap.add_action(name3, 0.25)
		var spec: Array = PAD_AXES[name3] as Array
		var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion.axis = int(spec[0])
		motion.axis_value = float(spec[1])
		InputMap.action_add_event(name3, motion)
