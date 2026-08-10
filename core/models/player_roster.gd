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
##
## WHAT they are playing lives here too, beside who they are playing on. A
## character is decided before a run and re-decided between runs, which is the
## same argument that put the roster in the lobby rather than in the run - and
## it is what makes a restart keep both the people and their chassis. The rules
## of choosing are here rather than in the lobby for the same reason the rules
## of joining are: they are testable headless only while nothing in this file
## touches Input or a Node.

## Who is in. Emitted by joining and leaving ONLY.
signal changed

## Somebody moved onto a different character. Deliberately NOT `changed`, and
## the separation is load-bearing rather than tidy: the lobby rebuilds its
## PlayerInput list on `changed`, and it steps selections from inside a loop
## over that very list. One signal for both would mutate the array being
## iterated, sixty times a second, on the frame a player nudges the stick.
signal selection_changed

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

## What may be chosen between. Null or empty means no choice exists, every
## selection call is a no-op and to_player_characters() hands back nothing - at
## which point the run falls back to its own authored character, which is what
## keeps main.tscn launchable with no lobby in front of it.
var catalogue: CharacterSet = null:
	set(value):
		catalogue = value
		# A catalogue swapped under a filled roster would otherwise leave picks
		# pointing past the end of the new one, and character_at() would answer
		# null for a player who is plainly standing in a slot.
		_clamp_picks()

## Index into the catalogue, one per joined slot, in the SAME order as
## `devices`. Private, and kept in step by this class alone: two public arrays
## that must agree is a bug waiting for the first caller who edits one of them.
##
## This IS the cursor on the select screen. A player's cursor position and their
## choice are the same number - there is no second "what I am hovering" to keep
## in step with it, and no state that can disagree with what is drawn.
var _picks: Array[int] = []

## Who has locked their choice in. Same order, same lockstep.
##
## A confirmed player's cursor is FROZEN until they back out, which is the whole
## reason confirming is worth a flag: without it somebody confirms one chassis,
## carries on browsing, and their slot shows a character they will not play.
var _confirmed: Array[bool] = []

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
	# Picked BEFORE the device is appended, so the seat number the default reads
	# is the one this player is about to take rather than the next one.
	var pick := _default_pick()
	devices.append(device_id)
	_picks.append(pick)
	_confirmed.append(false)
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
	# The SAME index, or every player after the one who left inherits somebody
	# else's character while keeping their own pad.
	_picks.remove_at(index)
	_confirmed.remove_at(index)
	changed.emit()
	return true

func clear() -> void:
	if devices.is_empty():
		return
	devices.clear()
	_picks.clear()
	_confirmed.clear()
	changed.emit()

## A copy, so a run cannot edit the roster it was handed.
func to_player_devices() -> Array[int]:
	return devices.duplicate()

# --- characters ------------------------------------------------------------

## Which catalogue entry a player is on, or -1 for a slot nobody holds.
func pick_of(index: int) -> int:
	if index < 0 or index >= _picks.size():
		return -1
	return _picks[index]

func character_at(index: int) -> CharacterData:
	if catalogue == null:
		return null
	return catalogue.at(pick_of(index))

func character_for_device(device_id: int) -> CharacterData:
	return character_at(devices.find(device_id))

## Index-aligned with to_player_devices(), which is what lets the lobby hand a
## run both arrays and the run pair them up by position without either side
## learning what a lobby is. Empty when there is no catalogue, so a run with
## nothing injected keeps its authored character.
func to_player_characters() -> Array[CharacterData]:
	var chosen: Array[CharacterData] = []
	for index in _picks.size():
		chosen.append(character_at(index))
	return chosen

func select_next(device_id: int) -> bool:
	return select_by(device_id, 1)

func select_previous(device_id: int) -> bool:
	return select_by(device_id, -1)

## Moves a player's cursor by `delta` catalogue entries, wrapping both ways.
##
## A DELTA rather than a direction, because the select screen is a GRID and
## moving down is "forward by one row". How wide a row is belongs to the view -
## the roster is a flat list and stays one, so a layout change never reaches
## core/ and the rule can still be tested headless.
##
## Wrapping is deliberate: a list with ends to fall off makes the last character
## harder to reach than the first for no reason a player could name.
func select_by(device_id: int, delta: int) -> bool:
	var size := _catalogue_size()
	var index := devices.find(device_id)
	if index < 0 or size <= 1 or is_confirmed(index):
		return false

	_picks[index] = posmod(_picks[index] + delta, size)
	selection_changed.emit()
	return true

# --- locking it in ----------------------------------------------------------

func is_confirmed(index: int) -> bool:
	return index >= 0 and index < _confirmed.size() and _confirmed[index]

func is_device_confirmed(device_id: int) -> bool:
	return is_confirmed(devices.find(device_id))

func confirm(device_id: int) -> bool:
	var index := devices.find(device_id)
	# Nothing to confirm with an empty catalogue: the run would be started on a
	# choice nobody made.
	if index < 0 or _confirmed[index] or _catalogue_size() <= 0:
		return false

	_confirmed[index] = true
	selection_changed.emit()
	return true

## ONE button, two meanings, and the state says which - exactly as the shop's
## tile menu layers CLOSE over the screen it was opened from. Backing out of a
## locked choice returns to browsing; backing out of browsing leaves the lobby.
##
## The layering lives HERE rather than in DeviceJoiner so it can be tested
## without a device: the joiner watches buttons and knows nothing about what a
## press means.
func back_out(device_id: int) -> bool:
	var index := devices.find(device_id)
	if index < 0:
		return false

	if _confirmed[index]:
		_confirmed[index] = false
		selection_changed.emit()
		return true

	return leave(device_id)

## Whether the run may start. Everybody who joined, and at least one of them -
## an empty lobby trivially satisfies "all of them agree" and must not start a
## run with no players in it.
func everyone_confirmed() -> bool:
	if devices.is_empty():
		return false
	return not _confirmed.has(false)

## Start at the seat number, walk forward to the first character nobody else is
## on. With eight characters and four players that is four different chassis
## and nobody had to press anything to get there.
##
## A DEFAULT, not a rule. Duplicate picks are allowed - forbidding them means
## answering what four players do with two authored characters, and "we both
## want the tank" is not a problem worth code on a shared couch.
func _default_pick() -> int:
	var size := _catalogue_size()
	if size <= 0:
		return 0

	var start := devices.size() % size
	for step in size:
		var candidate := (start + step) % size
		if not _picks.has(candidate):
			return candidate
	return start

func _catalogue_size() -> int:
	return 0 if catalogue == null else catalogue.count()

func _clamp_picks() -> void:
	var size := _catalogue_size()
	for index in _picks.size():
		_picks[index] = 0 if size <= 0 else clampi(_picks[index], 0, size - 1)
