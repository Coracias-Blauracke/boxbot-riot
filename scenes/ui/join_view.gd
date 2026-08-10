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
##
## A slot also shows WHAT that player is about to play, described from the
## character's own modifiers rather than from authored prose - the same rule the
## shop's detail block follows, and for the same reason: a hand-written line
## drifts from the numbers it describes the moment somebody retunes one.

const SLOT_WIDTH := 300.0
const SLOT_HEIGHT := 360.0
const SLOT_GAP := 24.0

## How many stat lines a slot draws before it stops. Seven covers every authored
## character with its two slot counts; overflow is the shop's unsolved problem
## too, and solving it here first would mean designing it twice.
const MAX_STAT_LINES := 7

## Abilities are prose and wrap badly at this width, so two is the honest
## ceiling until the tooltip the shop is waiting for exists here too.
const MAX_ABILITY_LINES := 2

var roster: PlayerRoster

## Supplies the name and the format for a stat line. Null simply drops the
## lines, which is what a lobby launched with nothing authored should do rather
## than refuse to draw.
var stat_sheet: StatSheet

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
			font, Vector2(rect.position.x, rect.position.y + 44.0), "P%d" % (index + 1),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 32, accent
		)
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 68.0), _device_name(device),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color(0.62, 0.66, 0.74)
		)
		_draw_character(font, rect, index, accent)
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + SLOT_HEIGHT - 22.0),
			"%s to leave" % ("ESC" if device == PlayerRoster.KEYBOARD_DEVICE else "B"),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, Color(0.5, 0.54, 0.62)
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
		font, Vector2(rect.position.x, rect.position.y + 140.0), prompt,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 24, Color(0.55, 0.6, 0.68)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 172.0), "to join",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color(0.4, 0.44, 0.52)
	)

## The chassis, and what it costs to play. Every line here is DERIVED from the
## character's own modifiers, so authoring a character is a .tres and nothing
## else - no screen learns that a new one exists.
func _draw_character(font: Font, rect: Rect2, index: int, accent: Color) -> void:
	var character := roster.character_at(index)
	if character == null:
		# No catalogue: the run will use whatever it authored, and saying so
		# beats an empty half of a slot that reads as a missing character.
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 130.0), "DEFAULT CHASSIS",
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color(0.45, 0.49, 0.57)
		)
		return

	var total := 0 if roster.catalogue == null else roster.catalogue.count()
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 116.0), tr(character.display_key),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(0.93, 0.94, 0.97)
	)

	# Arrows only when there is somewhere to go. A control hint for a control
	# that does nothing is worse than no hint.
	if total > 1:
		draw_string(
			font, Vector2(rect.position.x + 12.0, rect.position.y + 116.0), "<",
			HORIZONTAL_ALIGNMENT_LEFT, 30.0, 22, accent
		)
		draw_string(
			font, Vector2(rect.position.x + rect.size.x - 42.0, rect.position.y + 116.0), ">",
			HORIZONTAL_ALIGNMENT_RIGHT, 30.0, 22, accent
		)
		draw_string(
			font, Vector2(rect.position.x, rect.position.y + 138.0),
			"%d / %d" % [roster.pick_of(index) + 1, total],
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, Color(0.5, 0.54, 0.62)
		)

	# The slot counts come LAST and always, never "only when unusual": a rule
	# that hides the ordinary value leaves the player unable to tell a chassis
	# that says nothing about slots from one that happens to agree with the
	# default. They are asked of the character rather than rebuilt here.
	var lines := character.base_stats.duplicate()
	lines.append_array(character.slot_modifiers())

	var y := rect.position.y + 160.0
	var drawn := 0
	for modifier in lines:
		if modifier == null or drawn >= MAX_STAT_LINES:
			break
		_draw_stat_line(font, rect, y, modifier)
		y += 17.0
		drawn += 1

	# The ABILITIES, in the effect's own words - the same describe() the shop's
	# detail block calls. Without them the two most interesting chassis in the
	# roster look like ordinary stat bundles: nothing on screen would say that
	# one hits burning targets harder and the other pays for the shop in blood.
	var abilities := 0
	for effect in character.innate_effects:
		if effect == null or abilities >= MAX_ABILITY_LINES:
			break
		draw_string(
			font, Vector2(rect.position.x + 14.0, y + 6.0),
			"* " + effect.describe(EffectInstance.new(effect, character, 1)),
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, Color(0.72, 0.82, 0.95)
		)
		y += 15.0
		abilities += 1

	var weapons: Array[String] = []
	for weapon in character.starting_weapons:
		if weapon != null:
			weapons.append(tr(weapon.display_key))
	if weapons.is_empty():
		return

	draw_string(
		font, Vector2(rect.position.x, rect.position.y + SLOT_HEIGHT - 46.0),
		", ".join(weapons),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, Color(0.66, 0.72, 0.82)
	)

## A BASE modifier is what the chassis IS and reads as a bare value; a FLAT or
## PERCENT one is a DELTA from the baseline and reads with its sign and its
## colour. Same distinction the authoring convention in docs/character_list.md
## draws, and it is why 165 HP does not render as "+165".
##
## Good and bad come from StatMetadata.higher_is_better, never from the sign -
## a character with less spread is a better one.
func _draw_stat_line(font: Font, rect: Rect2, y: float, modifier: StatModifier) -> void:
	var meta: StatMetadata = stat_sheet.metadata_for(modifier.stat) if stat_sheet != null else null
	if meta == null:
		return

	var is_base := modifier.modifier_type == StatTypes.Modifier.BASE
	var value := (
		meta.format_value(modifier.value)
		if is_base
		else meta.format_modifier(modifier.modifier_type, modifier.value)
	)
	var color := Color(0.78, 0.82, 0.88)
	if not is_base:
		color = (
			Color(0.5, 0.9, 0.55)
			if meta.is_improvement(modifier.value)
			else Color(0.95, 0.5, 0.45)
		)

	draw_string(
		font, Vector2(rect.position.x + 14.0, y), tr(meta.display_key),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 110.0, 13, Color(0.7, 0.74, 0.81)
	)
	draw_string(
		font, Vector2(rect.position.x + rect.size.x - 104.0, y), value,
		HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 13, color
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

	# Only once somebody is in, and only when there is a roster to move through.
	# An empty lobby has nothing to steer.
	if roster.is_empty() or roster.catalogue == null or roster.catalogue.count() <= 1:
		return

	draw_string(
		font, Vector2(0.0, y + 30.0), "LEFT and RIGHT change your chassis",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(0.5, 0.54, 0.62)
	)

func _device_name(device_id: int) -> String:
	return "KEYBOARD" if device_id == PlayerRoster.KEYBOARD_DEVICE else "PAD %d" % device_id
