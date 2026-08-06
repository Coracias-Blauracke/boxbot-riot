class_name JoinView
extends Control

## The four slots, drawn. Knows the roster and nothing else - not how a device
## joins, not what happens when the run starts.
##
## Slots are laid out left to right rather than in the HUD's corner map. The
## corner map exists so a player finds themselves in the same place during
## combat and in the shop, and that only means anything once they ARE somebody;
## here they are choosing to be, and a row reads as "who is in" at a glance.
##
## Drawn rather than assembled from Containers, like every other screen here,
## because there is no art yet and a themed layout would be thrown away.

const SLOT_WIDTH := 300.0
const SLOT_HEIGHT := 220.0
const SLOT_GAP := 24.0

var roster: PlayerRoster

## Which pads are plugged in, so an empty slot can say what to press. Refreshed
## by the lobby rather than polled here.
var pads_connected: int = 0

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or roster == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07))
	_draw_title(font)

	var total := PlayerRoster.MAX_PLAYERS
	var row_width := float(total) * SLOT_WIDTH + float(total - 1) * SLOT_GAP
	var left := (size.x - row_width) * 0.5
	var top := size.y * 0.5 - SLOT_HEIGHT * 0.5

	for index in total:
		_draw_slot(font, Rect2(
			Vector2(left + float(index) * (SLOT_WIDTH + SLOT_GAP), top),
			Vector2(SLOT_WIDTH, SLOT_HEIGHT)
		), index)

	_draw_footer(font, top + SLOT_HEIGHT + 60.0)

func _draw_title(font: Font) -> void:
	draw_string(
		font, Vector2(0.0, size.y * 0.5 - SLOT_HEIGHT * 0.5 - 70.0), "WHO IS PLAYING",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(0.93, 0.94, 0.97)
	)

func _draw_slot(font: Font, rect: Rect2, index: int) -> void:
	var taken := index < roster.count()
	# The same table the blob on the floor and the HUD corner use, so the colour
	# somebody joins as is the colour they play as.
	var accent: Color = PlayerPalette.color_for(index) if taken else Color(0.24, 0.26, 0.32)

	draw_rect(rect, Color(0.07, 0.08, 0.11))
	draw_rect(rect, accent, false, 2.0)

	if taken:
		var device: int = roster.devices[index]
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 62.0), "P%d" % (index + 1),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 40, accent
		)
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 108.0), _device_name(device),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color(0.82, 0.86, 0.93)
		)
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 160.0),
			"%s to leave" % ("ESC" if device == PlayerRoster.KEYBOARD_DEVICE else "B"),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color(0.5, 0.54, 0.62)
		)
		return

	# An empty slot names what is actually available to press. With no pad
	# plugged in, "A to join" is an instruction nobody can follow.
	var prompt := "SPACE or A" if pads_connected > 0 else "SPACE"
	if roster.has(PlayerRoster.KEYBOARD_DEVICE):
		# Only one player on the keyboard, so once it is taken the only way to
		# fill another slot is a pad. Saying what to DO beats reporting that
		# nothing is available.
		prompt = "A" if pads_connected > 0 else "CONNECT A PAD"

	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 100.0), prompt,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 24, Color(0.55, 0.6, 0.68)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 132.0), "to join",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color(0.4, 0.44, 0.52)
	)

func _draw_footer(font: Font, y: float) -> void:
	var text := "waiting for a player"
	var color := Color(0.5, 0.54, 0.62)
	if not roster.is_empty():
		text = "START or ENTER to begin with %d" % roster.count()
		color = Color(0.86, 0.9, 0.96)

	draw_string(
		font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, color
	)

func _device_name(device_id: int) -> String:
	return "KEYBOARD" if device_id == PlayerRoster.KEYBOARD_DEVICE else "PAD %d" % device_id
