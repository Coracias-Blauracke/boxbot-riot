class_name PlayerRoster
extends RefCounted

## WHO IS PLAYING, and on what.
##
## The rules of joining, with no Input, no nodes and no drawing - which is what
## makes them testable headless, and what leaves DeviceJoiner with nothing to do
## but watch buttons and JoinView with nothing to do but draw.
##
## A DEVICE JOINS ONCE. "Only one player on the keyboard" is not a rule in here;
## it falls out of that one, because the keyboard IS one device. The old
## arrangement needed a special case precisely because it let player 0 hold the
## keyboard AND the first pad at the same time.
##
## Join ORDER is player order. First to press is P1 and takes the top-left
## corner in combat, in the shop and in this list, so the person who sees
## themselves as P1 in the lobby is P1 everywhere afterwards.

signal changed

## Four is the hard ceiling everywhere else too - HUD corners, shop panel
## layouts, PlayerPalette. Raising it means answering what a fifth corner is.
const MAX_PLAYERS := 4

## The keyboard, as a device id. Godot numbers pads from 0, so a negative marker
## cannot collide with one.
##
## Declared HERE and used by PlayerInput rather than the other way round:
## scenes/ may depend on core/ and never the reverse, so this is the only place
## the two layers can agree on the number.
const KEYBOARD_DEVICE := -1

## Device ids in join order. This is exactly the shape main.gd's player_devices
## export takes, which is why the lobby can hand a run its composition without
## either of them learning anything new.
var devices: Array[int] = []

func count() -> int:
	return devices.size()

func is_empty() -> bool:
	return devices.is_empty()

func is_full() -> bool:
	return devices.size() >= MAX_PLAYERS

func has(device_id: int) -> bool:
	return devices.has(device_id)

## Player index of a device, or -1. The view needs it to colour a slot, and it
## is the same index the HUD, the shop and PlayerPalette use.
func index_of(device_id: int) -> int:
	return devices.find(device_id)

func can_join(device_id: int) -> bool:
	return not is_full() and not has(device_id)

func join(device_id: int) -> bool:
	if not can_join(device_id):
		return false
	devices.append(device_id)
	changed.emit()
	return true

## Leaving CLOSES THE GAP rather than leaving a hole. Three players where P2
## dropped out are P1, P2, P3 - not P1, P3, P4 - because every layout downstream
## is driven by the player COUNT and a hole would leave an empty corner and a
## panel nobody drives.
func leave(device_id: int) -> bool:
	var index := devices.find(device_id)
	if index < 0:
		return false
	devices.remove_at(index)
	changed.emit()
	return true

func clear() -> void:
	if devices.is_empty():
		return
	devices.clear()
	changed.emit()

## A copy, so a run cannot edit the roster it was handed.
func to_player_devices() -> Array[int]:
	return devices.duplicate()
