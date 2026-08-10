class_name JoinView
extends Control

## The lobby screen: who is playing, and what they are playing.
##
## TWO regions, and the split is the whole design. Along the top sit the four
## player slots - one per seat, showing the chassis that seat is looking at in
## as much detail as fits. Below them is ONE shared grid of every character,
## carrying one cursor per joined player in that player's own colour.
##
## Shared rather than four private lists, because the interesting thing on a
## couch is seeing what everybody else is hovering. It is also the opposite of
## the shop, deliberately: there each player is spending their own money and
## gets their own panel, here everyone is choosing from the same rack.
##
## Godot's focus system cannot be used, for the same reason the shop cannot use
## it: focus is ONE per viewport and there are four cursors. Every cursor is a
## number in PlayerRoster and this class only draws them.
##
## Drawn rather than assembled from Containers, like every other screen here,
## because there is no art yet and a themed layout would be thrown away.

const SLOT_WIDTH := 420.0
## Tall enough that every authored chassis fits without scrolling, and no
## taller: the scroll is for the PROSE, which renders as a translation key until
## a translation is loaded. At 330 this window clipped the stat lines of two
## characters and drew a scrollbar for them, which is how the window, the clamp
## and the bar were verified before there was anything long to put in them.
const SLOT_HEIGHT := 380.0
const SLOT_GAP := 20.0

const TILE_WIDTH := 200.0
const TILE_HEIGHT := 148.0
const TILE_GAP := 18.0

## How many tiles a row holds. The LOBBY asks this to turn "down" into a delta
## of that many catalogue entries, which is why the grid's shape lives here and
## not in PlayerRoster - the model is a flat list and stays one.
const GRID_COLUMNS := 4

const PORTRAIT := 96.0

## One description row. Shared by the drawing and by max_scroll_for(), so the
## window a player scrolls and the window they read are the same window.
const LINE_HEIGHT := 17.0

var roster: PlayerRoster

## Supplies the name and the format for a stat line. Null simply drops the
## lines, which is what a lobby launched with nothing authored should do rather
## than refuse to draw.
var stat_sheet: StatSheet

## Which pads are plugged in, so an empty slot can say what to press. Refreshed
## by the lobby rather than polled here.
var pads_connected: int = 0

## First visible line of each player's description, index-aligned with the
## roster. Driven by the lobby off the right stick.
##
## LINES rather than pixels: a fractional offset means the top and bottom lines
## are drawn cut in half, and there is no per-slot clipping in a single Control
## that draws everything. A whole number of whole lines needs no clipping at
## all - a line is either inside the window or it is not drawn.
var scroll_lines: Array[int] = []

## One row of a description. A class rather than a Dictionary because `:=`
## cannot infer a type through Dictionary access, and the resulting warning is
## an error here.
class Line:
	var text: String = ""
	## Right-aligned second column. Empty for prose and ability lines.
	var value: String = ""
	var color: Color = Color(0.78, 0.82, 0.88)
	var value_color: Color = Color(0.78, 0.82, 0.88)
	var size: int = 13
	var indent: float = 0.0

	func _init(
		p_text: String, p_value: String = "", p_color: Color = Color(0.78, 0.82, 0.88),
		p_value_color: Color = Color(0.78, 0.82, 0.88), p_size: int = 13, p_indent: float = 0.0
	) -> void:
		text = p_text
		value = p_value
		color = p_color
		value_color = p_value_color
		size = p_size
		indent = p_indent

## How far down player `index` may scroll before the last line is on screen.
## Asked by the lobby, which owns the rate but must not own the layout that
## decides how much text there is.
func max_scroll_for(index: int) -> int:
	if roster == null:
		return 0
	var character := roster.character_at(index)
	if character == null:
		return 0
	return maxi(0, _description_lines(character).size() - _visible_lines())

func _visible_lines() -> int:
	return int((SLOT_HEIGHT - 12.0 - 156.0) / LINE_HEIGHT)

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or roster == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07))

	draw_string(
		font, Vector2(0.0, 58.0), "WHO IS PLAYING",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 38, Color(0.93, 0.94, 0.97)
	)

	_draw_slots(font, 86.0)
	_draw_grid(font, 86.0 + SLOT_HEIGHT + 46.0)
	_draw_footer(font, size.y - 64.0)

# --- the seats --------------------------------------------------------------

func _draw_slots(font: Font, top: float) -> void:
	var total := PlayerRoster.MAX_PLAYERS
	var row_width := float(total) * SLOT_WIDTH + float(total - 1) * SLOT_GAP
	var left := (size.x - row_width) * 0.5

	for index in total:
		_draw_slot(font, Rect2(
			Vector2(left + float(index) * (SLOT_WIDTH + SLOT_GAP), top),
			Vector2(SLOT_WIDTH, SLOT_HEIGHT)
		), index)

func _draw_slot(font: Font, rect: Rect2, index: int) -> void:
	var taken := index < roster.count()
	# The same table the blob on the floor and the HUD corner use, so the colour
	# somebody joins as is the colour they play as - and the colour their cursor
	# is down in the grid.
	var accent: Color = PlayerPalette.color_for(index) if taken else Color(0.24, 0.26, 0.32)

	draw_rect(rect, Color(0.07, 0.08, 0.11))
	draw_rect(rect, accent, false, 2.0 if taken else 1.0)

	if not taken:
		_draw_empty_slot(font, rect)
		return

	var device: int = roster.devices[index]
	var confirmed := roster.is_confirmed(index)

	draw_string(
		font, Vector2(rect.position.x + 16.0, rect.position.y + 30.0),
		"P%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, 80.0, 22, accent
	)
	draw_string(
		font, Vector2(rect.position.x + 60.0, rect.position.y + 30.0),
		_device_name(device), HORIZONTAL_ALIGNMENT_LEFT, 200.0, 14, Color(0.62, 0.66, 0.74)
	)

	var character := roster.character_at(index)
	if character == null:
		# No catalogue: the run will use whatever it authored, and saying so
		# beats an empty panel that reads as a missing character.
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 150.0), "DEFAULT CHASSIS",
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color(0.45, 0.49, 0.57)
		)
		return

	_draw_portrait(
		Rect2(Vector2(rect.position.x + 16.0, rect.position.y + 46.0), Vector2(PORTRAIT, PORTRAIT)),
		character, accent
	)

	var text_left := rect.position.x + 16.0 + PORTRAIT + 16.0
	draw_string(
		font, Vector2(text_left, rect.position.y + 78.0), tr(character.display_key),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - PORTRAIT - 48.0, 22, Color(0.93, 0.94, 0.97)
	)
	draw_string(
		font, Vector2(text_left, rect.position.y + 104.0),
		"CONFIRMED" if confirmed else "%s to confirm" % _confirm_label(device),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - PORTRAIT - 48.0, 14,
		Color(0.5, 0.9, 0.55) if confirmed else Color(0.6, 0.64, 0.72)
	)
	draw_string(
		font, Vector2(text_left, rect.position.y + 126.0),
		"%s to %s" % [_cancel_label(device), "change" if confirmed else "leave"],
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - PORTRAIT - 48.0, 13, Color(0.45, 0.49, 0.57)
	)

	_draw_description(font, rect, index, character)

func _draw_empty_slot(font: Font, rect: Rect2) -> void:
	# An empty slot names what is actually available to press. With no pad
	# plugged in, "A to join" is an instruction nobody can follow.
	var prompt := "SPACE or A" if pads_connected > 0 else "SPACE"
	if roster.has(PlayerRoster.KEYBOARD_DEVICE):
		# Only one player on the keyboard, so once it is taken the only way to
		# fill another slot is a pad. Saying what to DO beats reporting that
		# nothing is available.
		prompt = "A" if pads_connected > 0 else "CONNECT A PAD"

	draw_string(
		font, Vector2(rect.position.x, rect.position.y + SLOT_HEIGHT * 0.5), prompt,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 24, Color(0.55, 0.6, 0.68)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + SLOT_HEIGHT * 0.5 + 30.0), "to join",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color(0.4, 0.44, 0.52)
	)

## The description window, scrolled by whole lines.
##
## A scrollbar is drawn only when there is something to scroll to, because a
## track with a full-height thumb is a control that lies about being a control.
func _draw_description(font: Font, rect: Rect2, index: int, character: CharacterData) -> void:
	var lines := _description_lines(character)
	var top := rect.position.y + 156.0
	var bottom := rect.position.y + SLOT_HEIGHT - 12.0
	var step := LINE_HEIGHT
	var visible := _visible_lines()
	var offset := clampi(scroll_lines[index] if index < scroll_lines.size() else 0, 0, maxi(0, lines.size() - visible))

	var y := top + 12.0
	for row in range(offset, mini(offset + visible, lines.size())):
		var line := lines[row]
		draw_string(
			font, Vector2(rect.position.x + 16.0 + line.indent, y), line.text,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 130.0 - line.indent, line.size, line.color
		)
		if not line.value.is_empty():
			draw_string(
				font, Vector2(rect.position.x + rect.size.x - 104.0, y), line.value,
				HORIZONTAL_ALIGNMENT_RIGHT, 88.0, line.size, line.value_color
			)
		y += step

	if lines.size() <= visible:
		return

	# The track, and a thumb sized by how much of the text is on screen.
	var track := Rect2(
		Vector2(rect.position.x + rect.size.x - 10.0, top), Vector2(4.0, bottom - top)
	)
	draw_rect(track, Color(0.16, 0.18, 0.22))
	var share := float(visible) / float(lines.size())
	var thumb_height := maxf(18.0, track.size.y * share)
	var travel := (track.size.y - thumb_height) * float(offset) / float(lines.size() - visible)
	draw_rect(
		Rect2(track.position + Vector2(0.0, travel), Vector2(4.0, thumb_height)),
		Color(0.55, 0.6, 0.7)
	)

## Everything a chassis says about itself, in one list so scrolling is one
## number. Prose FIRST because it says what the character is for; the numbers
## under it are still derived, and the paragraph never replaces them.
func _description_lines(character: CharacterData) -> Array[Line]:
	var lines: Array[Line] = []
	var font := get_theme_default_font()
	var width := SLOT_WIDTH - 130.0

	if not character.description_key.is_empty():
		for text in _wrap(font, tr(character.description_key), width, 14):
			lines.append(Line.new(text, "", Color(0.82, 0.86, 0.93), Color.WHITE, 14))
		lines.append(Line.new(""))

	var modifiers := character.base_stats.duplicate()
	# The slot counts come LAST and always, never "only when unusual": a rule
	# that hides the ordinary value leaves the player unable to tell a chassis
	# with no opinion from one that happens to agree with the default.
	modifiers.append_array(character.slot_modifiers())

	for modifier in modifiers:
		if modifier != null:
			lines.append(_stat_line(modifier))

	# The ABILITIES, in the effect's own words - the same describe() the shop's
	# detail block calls. Without them the two most interesting chassis in the
	# roster read as ordinary stat bundles.
	for effect in character.innate_effects:
		if effect == null:
			continue
		for text in _wrap(
			font, "* " + effect.describe(EffectInstance.new(effect, character, 1)), width, 13
		):
			lines.append(Line.new(text, "", Color(0.72, 0.82, 0.95), Color.WHITE, 13))

	var weapons: Array[String] = []
	for weapon in character.starting_weapons:
		if weapon != null:
			weapons.append(tr(weapon.display_key))
	if not weapons.is_empty():
		lines.append(Line.new(""))
		lines.append(Line.new("STARTS WITH", "", Color(0.5, 0.54, 0.62), Color.WHITE, 12))
		for name in weapons:
			lines.append(Line.new(name, "", Color(0.66, 0.72, 0.82), Color.WHITE, 13, 10.0))

	return lines

## A BASE modifier is what the chassis IS and reads as a bare value; a FLAT or
## PERCENT one is a DELTA from the baseline and reads with its sign and its
## colour. Same distinction the authoring convention in docs/character_list.md
## draws, and it is why 165 HP does not render as "+165".
##
## Good and bad come from StatMetadata.higher_is_better, never from the sign -
## a character with less spread is a better one.
func _stat_line(modifier: StatModifier) -> Line:
	var meta: StatMetadata = stat_sheet.metadata_for(modifier.stat) if stat_sheet != null else null
	if meta == null:
		return Line.new("STAT_%d" % modifier.stat, str(modifier.value))

	var is_base := modifier.modifier_type == StatTypes.Modifier.BASE
	var value := (
		meta.format_value(modifier.value)
		if is_base
		else meta.format_modifier(modifier.modifier_type, modifier.value)
	)
	var value_color := Color(0.78, 0.82, 0.88)
	if not is_base:
		value_color = (
			Color(0.5, 0.9, 0.55)
			if meta.is_improvement(modifier.value)
			else Color(0.95, 0.5, 0.45)
		)

	return Line.new(tr(meta.display_key), value, Color(0.7, 0.74, 0.81), value_color)

## Greedy word wrap. Needed because the description is the first text in this
## repo long enough to need it, and because the scroll counts LINES - which
## means something has to decide where a line ends before anything is drawn.
func _wrap(font: Font, text: String, width: float, font_size: int) -> PackedStringArray:
	var wrapped := PackedStringArray()
	if font == null or text.is_empty():
		return wrapped

	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			current = candidate
			continue
		if not current.is_empty():
			wrapped.append(current)
		current = word

	if not current.is_empty():
		wrapped.append(current)
	return wrapped

# --- the rack ---------------------------------------------------------------

func _draw_grid(font: Font, top: float) -> void:
	if roster.catalogue == null or roster.catalogue.is_empty():
		return

	var total := roster.catalogue.count()
	var columns := mini(GRID_COLUMNS, total)
	var row_width := float(columns) * TILE_WIDTH + float(columns - 1) * TILE_GAP
	var left := (size.x - row_width) * 0.5

	for entry in total:
		var column := entry % GRID_COLUMNS
		var row := entry / GRID_COLUMNS
		_draw_tile(font, Rect2(
			Vector2(left + float(column) * (TILE_WIDTH + TILE_GAP), top + float(row) * (TILE_HEIGHT + TILE_GAP)),
			Vector2(TILE_WIDTH, TILE_HEIGHT)
		), entry)

func _draw_tile(font: Font, rect: Rect2, entry: int) -> void:
	var character := roster.catalogue.at(entry)
	if character == null:
		return

	draw_rect(rect, Color(0.08, 0.09, 0.12))
	draw_rect(rect, Color(0.18, 0.20, 0.25), false, 1.0)

	_draw_portrait(
		Rect2(rect.position + Vector2((TILE_WIDTH - PORTRAIT) * 0.5, 14.0), Vector2(PORTRAIT, PORTRAIT)),
		character, Color(0.3, 0.33, 0.4)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + TILE_HEIGHT - 16.0),
		tr(character.display_key), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14,
		Color(0.82, 0.86, 0.93)
	)

	_draw_cursors(font, rect, entry)

## Every cursor sitting on this tile, INSET one inside the other.
##
## Four players may hover the same chassis - duplicate picks are allowed on
## purpose - so the borders have to stack rather than overwrite, or three
## players are told they are somewhere they are not.
func _draw_cursors(font: Font, rect: Rect2, entry: int) -> void:
	var stacked := 0
	for index in roster.count():
		if roster.pick_of(index) != entry:
			continue

		var accent: Color = PlayerPalette.color_for(index)
		var inset := float(stacked) * 4.0
		var confirmed := roster.is_confirmed(index)
		draw_rect(
			Rect2(rect.position - Vector2(inset + 3.0, inset + 3.0),
				rect.size + Vector2(inset + 3.0, inset + 3.0) * 2.0),
			accent, false, 3.0 if confirmed else 1.5
		)
		# A locked cursor gets a filled tab with the player's number in it. A
		# border alone cannot say the difference between "looking at this" and
		# "playing this", and that difference is what START waits on.
		if confirmed:
			# Tabs walk SIDEWAYS while the borders nest outwards. Stacking them
			# on the same corner means the last one drawn hides the rest, and
			# two players on one chassis is exactly the case the tab exists for.
			var tab := Rect2(
				Vector2(rect.position.x + float(stacked) * 34.0, rect.position.y - inset - 21.0),
				Vector2(30.0, 18.0)
			)
			draw_rect(tab, accent)
			draw_string(
				font, Vector2(tab.position.x, tab.position.y + 14.0), "P%d" % (index + 1),
				HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 13, Color(0.05, 0.06, 0.08)
			)
		stacked += 1

## The chassis itself. There is no art, so it draws a placeholder - the same
## answer the arena gives, where every actor is a circle. The layout is the
## decision being made here and a Texture2D drops into it unchanged.
func _draw_portrait(rect: Rect2, character: CharacterData, accent: Color) -> void:
	if character.icon != null:
		draw_texture_rect(character.icon, rect, false)
		return

	draw_rect(rect, Color(0.11, 0.13, 0.17))
	draw_rect(rect, accent.darkened(0.3), false, 1.0)
	# A box robot, drawn as a box.
	var body := Rect2(rect.position + rect.size * 0.28, rect.size * 0.44)
	draw_rect(body, accent.darkened(0.15))

# --- the footer -------------------------------------------------------------

func _draw_footer(font: Font, y: float) -> void:
	var text := "waiting for a player"
	var color := Color(0.5, 0.54, 0.62)

	if roster.everyone_confirmed():
		text = "START or ENTER to begin with %d" % roster.count()
		color = Color(0.86, 0.9, 0.96)
	elif not roster.is_empty():
		# Names WHO the run is waiting on. "Not everybody is ready" leaves four
		# people looking at each other.
		var waiting: Array[String] = []
		for index in roster.count():
			if not roster.is_confirmed(index):
				waiting.append("P%d" % (index + 1))
		text = "waiting for %s to confirm" % ", ".join(waiting)

	draw_string(
		font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, color
	)

	if roster.is_empty() or roster.catalogue == null or roster.catalogue.count() <= 1:
		return

	draw_string(
		font, Vector2(0.0, y + 28.0),
		"move over the rack to choose - right stick or PAGE UP/DOWN scrolls your panel",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(0.5, 0.54, 0.62)
	)

func _device_name(device_id: int) -> String:
	return "KEYBOARD" if device_id == PlayerRoster.KEYBOARD_DEVICE else "PAD %d" % device_id

func _confirm_label(device_id: int) -> String:
	return "SPACE" if device_id == PlayerRoster.KEYBOARD_DEVICE else "A"

func _cancel_label(device_id: int) -> String:
	return "ESC" if device_id == PlayerRoster.KEYBOARD_DEVICE else "B"
