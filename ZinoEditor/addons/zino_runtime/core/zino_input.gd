@tool
class_name ZinoInput
extends RefCounted
## Registers the default racing input actions at runtime, so projects work without manual input setup.
## Existing user-defined actions with the same names are left untouched.

const ACCELERATE := "zino_accelerate"
const BRAKE := "zino_brake"
const STEER_LEFT := "zino_steer_left"
const STEER_RIGHT := "zino_steer_right"
const HANDBRAKE := "zino_handbrake"
const RESET := "zino_reset_vehicle"
const CAMERA := "zino_camera_next"
const NITRO := "zino_nitro"
const SHIFT_UP := "zino_shift_up"
const SHIFT_DOWN := "zino_shift_down"
const PAUSE := "zino_pause"

const DEFAULTS := {
	ACCELERATE: [KEY_W, KEY_UP],
	BRAKE: [KEY_S, KEY_DOWN],
	STEER_LEFT: [KEY_A, KEY_LEFT],
	STEER_RIGHT: [KEY_D, KEY_RIGHT],
	HANDBRAKE: [KEY_SPACE],
	RESET: [KEY_R],
	CAMERA: [KEY_C],
	NITRO: [KEY_N, KEY_SHIFT],
	SHIFT_UP: [KEY_E],
	SHIFT_DOWN: [KEY_Q],
	PAUSE: [KEY_ESCAPE, KEY_P],
}

const PAD := {
	ACCELERATE: JOY_AXIS_TRIGGER_RIGHT,
	BRAKE: JOY_AXIS_TRIGGER_LEFT,
}

static func ensure_actions() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.15)
		for key in DEFAULTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if PAD.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD[action]
			jm.axis_value = 1.0
			InputMap.action_add_event(action, jm)
	for pair in [[STEER_LEFT, -1.0], [STEER_RIGHT, 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXIS_LEFT_X
		jm.axis_value = pair[1]
		if not InputMap.action_has_event(pair[0], jm):
			InputMap.action_add_event(pair[0], jm)
	var hb := InputEventJoypadButton.new()
	hb.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event(HANDBRAKE, hb):
		InputMap.action_add_event(HANDBRAKE, hb)
