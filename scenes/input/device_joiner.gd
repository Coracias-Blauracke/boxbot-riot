class_name DeviceJoiner
extends RefCounted

## Watches the devices that have NOT joined yet, and only that.
##
## The one mechanism the engine was missing for local co-op. PlayerInput can
## answer for a device it already owns; nothing could answer "did ANYBODY press
## something on a pad nobody is holding", which is the entire question a lobby
## asks.
##
## Deliberately separate from the roster and from the view. The rules of who may
## join live in PlayerRoster where they can be tested headless, the drawing
## lives in JoinView, and this reads buttons. A later lobby with a solo/co-op
## toggle, character select and a run-rules dropdown wraps this rather than
## reimplementing it - the toggle only decides whether this is polled at all.
##
## Scene layer on purpose: it touches Input, which core/ may never do.

## Confirm to join. SPACE on the keyboard, A on a pad - the same button that
## confirms everywhere else, so nobody has to be told twice.
## Back out to leave, which is CANCEL's job everywhere else.

signal joined(device_id: int)
signal left(device_id: int)

var roster: PlayerRoster

## Edge state per device, so holding the button joins once rather than joining,
## leaving and rejoining sixty times a second.
var _confirm_held: Dictionary = {}  # device_id -> bool
var _cancel_held: Dictionary = {}   # device_id -> bool

func _init(p_roster: PlayerRoster = null) -> void:
	roster = p_roster

## Call once per frame. Reads every connected pad plus the keyboard.
##
## Pads are read DIRECTLY rather than through the InputMap for the same reason
## PlayerInput reads them directly: an InputMap action is global, so four pads
## sharing one would report a single join for whoever pressed first.
func poll() -> void:
	if roster == null:
		return

	_poll_device(PlayerRoster.KEYBOARD_DEVICE)
	for pad in Input.get_connected_joypads():
		_poll_device(pad)

## A device that has not joined can join; one that has can leave. The same
## device is never asked both questions in a frame, which is what stops a
## confirm press from being read as a leave by the player it just created.
func _poll_device(device_id: int) -> void:
	var confirm := _confirm_pressed(device_id)
	var cancel := _cancel_pressed(device_id)

	var confirm_edge: bool = confirm and not bool(_confirm_held.get(device_id, false))
	var cancel_edge: bool = cancel and not bool(_cancel_held.get(device_id, false))
	_confirm_held[device_id] = confirm
	_cancel_held[device_id] = cancel

	if roster.has(device_id):
		if cancel_edge and roster.leave(device_id):
			left.emit(device_id)
		return

	if confirm_edge and roster.join(device_id):
		joined.emit(device_id)

func _confirm_pressed(device_id: int) -> bool:
	if device_id == PlayerRoster.KEYBOARD_DEVICE:
		return Input.is_key_pressed(KEY_SPACE)
	return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)

func _cancel_pressed(device_id: int) -> bool:
	if device_id == PlayerRoster.KEYBOARD_DEVICE:
		return Input.is_key_pressed(KEY_ESCAPE)
	return Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)

## What a slot tells the player to press. Named per device for the same reason
## the shop's hints are: telling a pad player to press SPACE is worse than
## saying nothing.
static func confirm_label(device_id: int) -> String:
	return "SPACE" if device_id == PlayerRoster.KEYBOARD_DEVICE else "A"
