class_name PlayerInput
extends RefCounted

## Which physical device drives ONE player, and everything that device can say.
##
## DEVICE ASSIGNMENT IS A BINDING, NOT A FUNCTION OF THE PLAYER INDEX. "Three
## pads and one keyboard" has to be expressible, and it is not if player 0 is
## always keyboard-plus-pad-0 and player N is always pad N: the keyboard player
## and the first pad player end up fighting over the same slot. So a player owns
## a device id, and who owns what is decided when they join.
##
## Movement AND menu navigation both read from here. Binding them separately is
## how you get a player who can walk but cannot buy anything.
##
## Scene layer on purpose - it touches Input, which core/ may never do.

## Device ids. Godot numbers pads from 0; the keyboard needs a marker that
## cannot collide with one.
##
## Taken from PlayerRoster rather than declared again here, because the lobby
## and the run have to agree on the number and scenes/ may depend on core/ while
## core/ may never depend back. Two -1s in two layers is the kind of duplication
## that survives until somebody changes one of them.
const KEYBOARD := PlayerRoster.KEYBOARD_DEVICE

## Deadzone for treating a stick push as a discrete menu step.
const STICK_THRESHOLD := 0.6

## How long a held direction waits before repeating, and how fast after that.
## Without this a single flick jumps four slots.
const REPEAT_DELAY := 0.42
const REPEAT_INTERVAL := 0.14

enum Action {
	LEFT,
	RIGHT,
	UP,
	DOWN,
	## Buy the highlighted offer, or confirm.
	ACCEPT,
	## Sell the highlighted owned item, or back out.
	CANCEL,
	REROLL,
	## Declare ready and close this player's shop.
	READY,
	## Switch between the shop and the stat sheet.
	TAB,
	## Open or close the pause menu.
	##
	## Deliberately the SAME physical button as READY - START on a pad, ESC on
	## the keyboard - because the phase already says which one is meant. The
	## shop has no clock and closes only when everybody declares ready, so it is
	## a stopped state with nothing to pause, and PauseScreen ignores this
	## action while it is open. Giving pause a button of its own would have
	## spent the one button every player already knows.
	PAUSE,
}

var device_id: int = KEYBOARD

## Lets one player answer to a pad AND the keyboard. Only ever set this on a
## single player, or two of them share the keyboard and both move at once.
var also_keyboard: bool = false

var _held: Dictionary = {}       # Action -> bool
var _repeat_at: Dictionary = {}  # Action -> float, seconds remaining
var _fired: Dictionary = {}      # Action -> bool, true on the frame it triggers

## The process frame this device was last polled on.
##
## TWO screens hold the same PlayerInput now: the pause menu reads every device
## in every phase, and a shop panel reads its own. Without this guard the second
## poll of a frame DESTROYS the edges the first one produced - `triggered()` is
## true only on the frame a button goes down, so the second caller sees "it was
## already held" and reports nothing at all. First poller of the frame wins and
## everybody reads the same answer.
##
## The alternative was a rule that exactly one screen may poll at a time, which
## is the kind of invariant that holds right up until a third screen exists.
var _polled_frame: int = -1

func _init(p_device_id: int = KEYBOARD, p_also_keyboard: bool = false) -> void:
	device_id = p_device_id
	also_keyboard = p_also_keyboard

func uses_keyboard() -> bool:
	return device_id == KEYBOARD or also_keyboard

func is_pad() -> bool:
	return device_id >= 0

## The label for an action ON THIS DEVICE. A hint that names a key the player is
## not holding is worse than none - it tells the pad player to press Space.
func label_for(action: Action) -> String:
	if is_pad():
		match action:
			Action.ACCEPT: return "A"
			Action.CANCEL: return "B"
			Action.REROLL: return "X"
			Action.READY: return "START"
			Action.TAB: return "RB"
			Action.PAUSE: return "START"
			_: return ""
	match action:
		Action.ACCEPT: return "SPACE"
		Action.CANCEL: return "ESC"
		Action.REROLL: return "R"
		Action.READY: return "ENTER"
		Action.TAB: return "TAB"
		Action.PAUSE: return "ESC"
		_: return ""

# --- movement --------------------------------------------------------------

## Analogue, for walking. Deliberately separate from the menu directions below:
## a stick at 0.3 should move a character slowly and should NOT step a menu.
func movement() -> Vector2:
	var direction := Vector2.ZERO

	if is_pad():
		var raw := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		# Read the pad directly rather than through the InputMap: actions are
		# global in Godot, so four pads sharing one action set would move every
		# player at once.
		if raw.length() > 0.2:
			direction = raw

	if direction == Vector2.ZERO and uses_keyboard():
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	return direction

## Analogue, for scrolling a panel that is taller than its box. The RIGHT stick,
## so it never fights the cursor on the left one: the lobby wants to move a
## selection and read a description at the same time, and one stick cannot do
## both without the panel jumping every time somebody changes character.
##
## Deliberately NOT an Action. The four directions are discrete steps with a
## repeat, which is what a menu wants and exactly what scrolling does not:
## reading wants a rate, not a staircase.
func scroll_axis() -> float:
	if is_pad():
		var raw := Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		if absf(raw) > 0.2:
			return raw

	if uses_keyboard():
		if Input.is_key_pressed(KEY_PAGEDOWN):
			return 1.0
		if Input.is_key_pressed(KEY_PAGEUP):
			return -1.0

	return 0.0

# --- menus -----------------------------------------------------------------

## Call once per frame, before reading anything. Turns held buttons into
## discrete steps with a repeat, which is what a menu wants and what raw
## polling cannot give.
func poll(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _polled_frame:
		return
	_polled_frame = frame

	for action in Action.values():
		var down := _raw_pressed(action)
		var was_down: bool = _held.get(action, false)
		_held[action] = down

		if not down:
			_repeat_at[action] = 0.0
			_fired[action] = false
			continue

		if not was_down:
			_repeat_at[action] = REPEAT_DELAY
			_fired[action] = true
			continue

		# Only the four directions auto-repeat. A held ACCEPT must never buy
		# four things.
		if action > Action.DOWN:
			_fired[action] = false
			continue

		var left: float = _repeat_at.get(action, REPEAT_DELAY) - delta
		if left <= 0.0:
			left = REPEAT_INTERVAL
			_fired[action] = true
		else:
			_fired[action] = false
		_repeat_at[action] = left

## True on the frame the action triggers, repeats included.
func triggered(action: Action) -> bool:
	return _fired.get(action, false)

func held(action: Action) -> bool:
	return _held.get(action, false)

func _raw_pressed(action: Action) -> bool:
	return _pad_pressed(action) or (uses_keyboard() and _key_pressed(action))

func _pad_pressed(action: Action) -> bool:
	if not is_pad():
		return false

	match action:
		Action.LEFT:
			return (
				Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_LEFT)
				or Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X) < -STICK_THRESHOLD
			)
		Action.RIGHT:
			return (
				Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_RIGHT)
				or Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X) > STICK_THRESHOLD
			)
		Action.UP:
			return (
				Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_UP)
				or Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y) < -STICK_THRESHOLD
			)
		Action.DOWN:
			return (
				Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_DOWN)
				or Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y) > STICK_THRESHOLD
			)
		Action.ACCEPT:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
		Action.CANCEL:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)
		Action.REROLL:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_X)
		Action.READY:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)
		Action.TAB:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER)
		Action.PAUSE:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)

	return false

## Physical keycodes rather than InputMap actions, for the same reason the pad
## is read directly: an InputMap action is global, so it cannot belong to one
## player. Movement is the exception - only ever one keyboard player, so the
## authored move_* actions are fine there.
func _key_pressed(action: Action) -> bool:
	match action:
		Action.LEFT:
			return Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
		Action.RIGHT:
			return Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
		Action.UP:
			return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		Action.DOWN:
			return Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		Action.ACCEPT:
			return Input.is_key_pressed(KEY_SPACE)
		Action.CANCEL:
			return Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_BACKSPACE)
		Action.REROLL:
			return Input.is_key_pressed(KEY_R)
		Action.READY:
			return Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
		Action.TAB:
			return Input.is_key_pressed(KEY_TAB)
		Action.PAUSE:
			return Input.is_key_pressed(KEY_ESCAPE)

	return false
