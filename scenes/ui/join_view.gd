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

const TILE_GAP := 14.0
const TILE_MAX_WIDTH := 200.0
## Height as a share of width. Fixed, so a tile keeps its shape whatever M and N
## the rack is authored at - a grid that changes proportions with its column
## count needs its portrait art authored twice.
const TILE_ASPECT := 0.74
const GRID_MARGIN := 60.0

## The rack, M x N. Authored on the lobby rather than fixed here, because how
## many characters fit on a screen is a layout decision and the roster is meant
## to grow to Brotato size and beyond.
##
## `columns` decides where "right" wraps and `visible_rows` decides when the
## rack starts scrolling. Neither reaches PlayerRoster, which stays a flat list
## - GridCursor turns the two into an index.
var columns: int = 4
var visible_rows: int = 2

## First row on screen. ONE number for the whole rack rather than one per
## player: the grid is shared, and four viewports would be four grids, which
## takes away the only reason it is shared at all - seeing what the others are
## looking at.
var grid_top: int = 0

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

	lines.append_array(_delta_lines(character))

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

## What a chassis TRADES, and nothing else.
##
## Only stats that differ from the roster's baseline appear, so a panel says
## "tougher, slower, one weapon fewer" instead of listing six numbers of which
## four are the same on every character. An unchanged stat drawn in grey is
## noise the player has to read past every single time.
##
## Deliberately NOT computed from effective stat values. A holder's PERCENT is
## applied to their WEAPONS - Riveter's -15% RANGED_DAMAGE sits on a base of
## zero and would compare equal to the baseline - so the comparison is between
## the authored POOLS, which is also where the sign the player cares about is.
##
## Good and bad come from StatMetadata.higher_is_better, never from the sign: a
## chassis with less spread is a better one, and lower SPREAD_ANGLE draws green.
func _delta_lines(character: CharacterData) -> Array[Line]:
	var lines: Array[Line] = []
	if stat_sheet == null or roster.catalogue == null:
		return lines

	var mine := _Pools.new(character)
	var baseline := _Pools.new(roster.catalogue.baseline_or_first())

	# In the STAT SHEET's order, for the same reason the shop's sheet enumerates
	# it: a stat authored later appears here without this screen being touched.
	for meta in stat_sheet.visible_sorted():
		_append_delta(
			lines, meta, StatTypes.Modifier.FLAT,
			mine.additive_of(meta.stat) - baseline.additive_of(meta.stat)
		)
		_append_delta(
			lines, meta, StatTypes.Modifier.PERCENT,
			mine.percent_of(meta.stat) - baseline.percent_of(meta.stat)
		)

	if lines.is_empty():
		# The baseline itself, and every future chassis that trades nothing.
		# An empty block reads as a screen that failed to load.
		lines.append(Line.new(
			"no trades - the standard frame", "", Color(0.5, 0.54, 0.62), Color.WHITE, 13
		))

	return lines

func _append_delta(
	lines: Array[Line], meta: StatMetadata, kind: StatTypes.Modifier, delta: float
) -> void:
	if is_zero_approx(delta):
		return

	lines.append(Line.new(
		tr(meta.display_key), meta.format_modifier(kind, delta), Color(0.7, 0.74, 0.81),
		Color(0.5, 0.9, 0.55) if meta.is_improvement(delta) else Color(0.95, 0.5, 0.45)
	))

## One chassis's authored modifiers, gathered per stat.
##
## BASE and FLAT are summed because both are in the stat's own unit and both
## move it by adding; PERCENT is kept apart because it scales instead. That is
## the same split WeaponModel makes when a holder's stats reach a weapon, and
## keeping it here means a -15% and a +15 never cancel into nothing.
##
## MULT is deliberately absent. Its neutral is 1.0, so a difference of two
## multipliers is not a quantity of the stat and cannot be rendered as one -
## nothing authored uses it on a character, and folding it in would be a lie the
## day something does.
class _Pools:
	var _additive: Dictionary = {}
	var _percent: Dictionary = {}

	func _init(character: CharacterData) -> void:
		if character == null:
			return

		var modifiers := character.base_stats.duplicate()
		modifiers.append_array(character.slot_modifiers())

		for modifier in modifiers:
			if modifier == null:
				continue
			if modifier.modifier_type == StatTypes.Modifier.PERCENT:
				_percent[modifier.stat] = percent_of(modifier.stat) + modifier.value
			elif modifier.modifier_type != StatTypes.Modifier.MULT:
				_additive[modifier.stat] = additive_of(modifier.stat) + modifier.value

	func additive_of(stat: StatTypes.Stat) -> float:
		var value: float = _additive.get(stat, 0.0)
		return value

	func percent_of(stat: StatTypes.Stat) -> float:
		var value: float = _percent.get(stat, 0.0)
		return value

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

## The tile size M and N imply, fitted to the space the rack actually has.
##
## Derived rather than authored, because M and N are the numbers somebody wants
## to change: at eight columns the tiles have to be smaller or the row runs off
## the screen, and asking an author to keep a width in step with a column count
## is asking them to get it wrong.
func tile_size(area: Vector2) -> Vector2:
	var wide := maxi(1, columns)
	var high := maxi(1, visible_rows)

	var by_width := (area.x - float(wide - 1) * TILE_GAP) / float(wide)
	var by_height := (area.y - float(high - 1) * TILE_GAP) / float(high) / TILE_ASPECT
	var width := minf(TILE_MAX_WIDTH, minf(by_width, by_height))
	return Vector2(width, width * TILE_ASPECT)

func _grid_area(top: float) -> Rect2:
	# Down to the footer, which is what leaves room for more rows on a taller
	# screen instead of leaving the bottom third empty as the fixed layout did.
	return Rect2(
		Vector2(GRID_MARGIN, top),
		Vector2(size.x - GRID_MARGIN * 2.0, maxf(80.0, size.y - 116.0 - top))
	)

func _draw_grid(font: Font, top: float) -> void:
	if roster.catalogue == null or roster.catalogue.is_empty():
		return

	var total := roster.catalogue.count()
	var area := _grid_area(top)
	var tile := tile_size(area.size)
	var wide := mini(maxi(1, columns), total)

	var row_width := float(wide) * tile.x + float(wide - 1) * TILE_GAP
	var left := (size.x - row_width) * 0.5
	var rows := GridCursor.row_count(total, columns)
	var first := clampi(grid_top, 0, maxi(0, rows - visible_rows))

	for row in range(first, mini(first + visible_rows, rows)):
		for column in maxi(1, columns):
			var entry := row * maxi(1, columns) + column
			if entry >= total:
				break
			_draw_tile(font, Rect2(
				Vector2(
					left + float(column) * (tile.x + TILE_GAP),
					area.position.y + float(row - first) * (tile.y + TILE_GAP)
				),
				tile
			), entry)

	_draw_grid_scrollbar(
		Vector2(left + row_width + 14.0, area.position.y), tile, rows, first
	)

## Drawn only when there is somewhere to scroll to. A track whose thumb fills it
## is a control that lies about being a control.
##
## Placed against the TILES rather than against the screen edge: the rack is
## centred and is usually narrower than the space it is given, so an edge-hugging
## bar reads as belonging to the window instead of to the thing it scrolls.
func _draw_grid_scrollbar(at: Vector2, tile: Vector2, rows: int, first: int) -> void:
	if rows <= visible_rows:
		return

	var height := float(visible_rows) * tile.y + float(visible_rows - 1) * TILE_GAP
	var track := Rect2(at, Vector2(5.0, height))
	draw_rect(track, Color(0.14, 0.16, 0.20))

	var share := float(visible_rows) / float(rows)
	var thumb := maxf(24.0, height * share)
	var travel := (height - thumb) * float(first) / float(rows - visible_rows)
	draw_rect(
		Rect2(track.position + Vector2(0.0, travel), Vector2(5.0, thumb)),
		Color(0.55, 0.6, 0.7)
	)

func _draw_tile(font: Font, rect: Rect2, entry: int) -> void:
	var character := roster.catalogue.at(entry)
	if character == null:
		return

	draw_rect(rect, Color(0.08, 0.09, 0.12))
	draw_rect(rect, Color(0.18, 0.20, 0.25), false, 1.0)

	var portrait := rect.size.x * 0.5
	_draw_portrait(
		Rect2(
			rect.position + Vector2((rect.size.x - portrait) * 0.5, rect.size.y * 0.09),
			Vector2(portrait, portrait)
		),
		character, Color(0.3, 0.33, 0.4)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + rect.size.y - 10.0),
		tr(character.display_key), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x,
		clampi(roundi(rect.size.x * 0.075), 9, 14), Color(0.82, 0.86, 0.93)
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
			#
			# Sized off the TILE, so a rack authored eight columns wide does not
			# wear four tabs wider than the thing they label.
			var tab_width := minf(30.0, rect.size.x * 0.24)
			var tab := Rect2(
				Vector2(
					rect.position.x + float(stacked) * (tab_width + 4.0),
					rect.position.y - inset - tab_width * 0.62
				),
				Vector2(tab_width, tab_width * 0.6)
			)
			draw_rect(tab, accent)
			draw_string(
				font, Vector2(tab.position.x, tab.position.y + tab_width * 0.47),
				"P%d" % (index + 1), HORIZONTAL_ALIGNMENT_CENTER, tab.size.x,
				clampi(roundi(tab_width * 0.44), 8, 13), Color(0.05, 0.06, 0.08)
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
