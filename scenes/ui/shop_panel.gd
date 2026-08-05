class_name ShopPanel
extends Control

## ONE player's shop, in that player's share of the screen.
##
## Drives its own cursor from its own PlayerInput rather than from Godot's focus
## system, which holds ONE focus per viewport and therefore cannot serve four
## players at once. Everything here is per-panel state; nothing is global.
##
## Drawn rather than assembled from Containers, for the same reason the actors
## are drawn: there is no art yet, and a layout built from anchors and themes
## would have to be thrown away when there is.

## Readiness has to go through RunModel, not straight to ShopManager: the run is
## what checks whether everyone is ready and starts the next wave. Setting it on
## the manager alone flipped a flag nobody was watching.
signal ready_requested(index: int, value: bool)

enum Tab { SHOP, STATS }

## Which row group the cursor is in. Two zones rather than one flat list,
## because the offers read as a column and the things you own read as a strip,
## and a cursor that walks from one into the other in a straight line is how you
## sell an item while trying to buy one.
enum Zone { OFFERS, OWNED }

## One tile in the owned strip.
##
## The CHARACTER is one of these, not a special case beside them. It occupies
## the last tile and describes itself through the same block as everything else,
## because from the player's side "what am I carrying" and "what did I start
## with" are the same question. EntityData and ItemData carry the same shape
## under different names - base_stats/innate_effects against
## static_stats/dynamic_effects - so this flattens both into one thing the
## drawing code can read.
##
## `item` is null for the character, which is the only real difference: you
## cannot sell yourself. That falls out of the data rather than needing a branch
## in the renderer.
class OwnedEntry extends RefCounted:
	var display_key: String = ""
	var modifiers: Array[StatModifier] = []
	var effects: Array[DynamicEffect] = []
	var quantity: int = 1
	var tier_label: String = ""
	var item: ItemData = null

	func can_sell() -> bool:
		return item != null

const PAD := 22.0

## Widest the content column gets. A full-screen panel for one player would
## otherwise stretch four rows across 1920px, which reads as a spreadsheet
## rather than a shop.
const MAX_CONTENT_WIDTH := 760.0
const ROW_HEIGHT := 40.0
const COMPACT_ROW_HEIGHT := 32.0
const OWNED_TILE := 46.0

var player_index: int = 0
var accent: Color = Color.WHITE

var model: EntityModel
var shop: ShopManager
var input: PlayerInput
var stat_sheet: StatSheet

## Shown as the last tile in the owned strip, exactly like an item.
var character: CharacterData

var tab: Tab = Tab.SHOP
var zone: Zone = Zone.OFFERS
var cursor: int = 0
var stat_cursor: int = 0

## Who this player is still waiting on, filled by ShopScreen each frame.
var waiting_text: String = ""

var _compact: bool = false
var _owned: Array[OwnedEntry] = []
var _stats: Array[StatMetadata] = []

func bind(
	p_index: int, p_model: EntityModel, p_shop: ShopManager,
	p_input: PlayerInput, p_sheet: StatSheet, p_character: CharacterData = null
) -> void:
	character = p_character
	player_index = p_index
	model = p_model
	shop = p_shop
	input = p_input
	stat_sheet = p_sheet
	accent = PlayerPalette.color_for(p_index)

	if stat_sheet != null:
		_stats = stat_sheet.visible_sorted()
	if shop != null and not shop.offers_changed.is_connected(_on_offers_changed):
		shop.offers_changed.connect(_on_offers_changed)

## Back to the first offer. Called on every entry into the shop: a cursor left
## on "reroll" from last time is not where anybody meant to resume, and one left
## in the owned strip is worse - the first thing DOWN does there is nothing and
## the first thing ACCEPT does is sell something.
func reset_cursor() -> void:
	zone = Zone.OFFERS
	cursor = 0
	tab = Tab.SHOP
	queue_redraw()

func place(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	_compact = ShopLayout.is_compact(rect)
	queue_redraw()

func _on_offers_changed() -> void:
	_refresh_owned()
	_clamp_cursor()
	queue_redraw()

## Rebuilt from the model rather than tracked incrementally, so selling an item
## or loading a save can never leave the strip out of step with what is owned.
func _refresh_owned() -> void:
	_owned.clear()
	if model == null:
		return

	var quantities := model.items.get_all()
	for key in quantities:
		var item := key as ItemData
		var entry := OwnedEntry.new()
		entry.display_key = item.display_key
		entry.modifiers = item.static_stats
		entry.effects = item.dynamic_effects
		entry.quantity = quantities[key]
		entry.tier_label = "T%d" % item.tier
		entry.item = item
		_owned.append(entry)

	# Last, so it sits where the character tile sits in the genre. Not first and
	# not elsewhere: the strip is read left to right as "what I have picked up",
	# and what you started as is the oldest thing in it.
	if character != null:
		var self_entry := OwnedEntry.new()
		self_entry.display_key = character.display_key
		self_entry.modifiers = character.base_stats
		self_entry.effects = character.innate_effects
		self_entry.tier_label = "YOU"
		_owned.append(self_entry)

# --- input -----------------------------------------------------------------

func _process(delta: float) -> void:
	if input == null or shop == null or model == null or not visible:
		return

	input.poll(delta)

	if input.triggered(PlayerInput.Action.TAB):
		tab = Tab.STATS if tab == Tab.SHOP else Tab.SHOP
		queue_redraw()
		return

	if input.triggered(PlayerInput.Action.READY):
		# Toggling rather than latching, so a player who pressed it by mistake
		# is not stuck watching everyone else shop.
		ready_requested.emit(player_index, not shop.is_ready)
		queue_redraw()
		return

	if tab == Tab.STATS:
		_handle_stats()
	else:
		_handle_shop()

func _handle_stats() -> void:
	if _stats.is_empty():
		return
	if input.triggered(PlayerInput.Action.UP):
		stat_cursor = wrapi(stat_cursor - 1, 0, _stats.size())
		queue_redraw()
	elif input.triggered(PlayerInput.Action.DOWN):
		stat_cursor = wrapi(stat_cursor + 1, 0, _stats.size())
		queue_redraw()

func _handle_shop() -> void:
	var offer_rows := shop.offers.size() + 1  # offers, then reroll

	if input.triggered(PlayerInput.Action.DOWN):
		if zone == Zone.OFFERS:
			if cursor + 1 < offer_rows:
				cursor += 1
			elif not _owned.is_empty():
				zone = Zone.OWNED
				cursor = 0
		queue_redraw()
	elif input.triggered(PlayerInput.Action.UP):
		if zone == Zone.OWNED:
			zone = Zone.OFFERS
			cursor = offer_rows - 1
		elif cursor > 0:
			cursor -= 1
		queue_redraw()
	elif zone == Zone.OWNED and input.triggered(PlayerInput.Action.LEFT):
		cursor = wrapi(cursor - 1, 0, maxi(1, _owned.size()))
		queue_redraw()
	elif zone == Zone.OWNED and input.triggered(PlayerInput.Action.RIGHT):
		cursor = wrapi(cursor + 1, 0, maxi(1, _owned.size()))
		queue_redraw()
	elif input.triggered(PlayerInput.Action.REROLL):
		shop.reroll(model, model.rng)
	elif input.triggered(PlayerInput.Action.ACCEPT):
		_accept()

func _accept() -> void:
	if zone == Zone.OWNED:
		# can_sell() is false for the character tile. Nothing else has to know
		# that the character is in this list at all.
		if cursor < _owned.size() and _owned[cursor].can_sell():
			shop.sell(model, _owned[cursor].item)
			_on_offers_changed()
		return

	if cursor < shop.offers.size():
		shop.buy(model, cursor)
	else:
		shop.reroll(model, model.rng)

func _clamp_cursor() -> void:
	if zone == Zone.OWNED:
		if _owned.is_empty():
			zone = Zone.OFFERS
			cursor = 0
		else:
			cursor = clampi(cursor, 0, _owned.size() - 1)
	else:
		cursor = clampi(cursor, 0, shop.offers.size())
	stat_cursor = clampi(stat_cursor, 0, maxi(0, _stats.size() - 1))

# --- drawing ---------------------------------------------------------------

## Left edge and width of the content column, centred in whatever share of the
## screen this panel was given.
func _column_x() -> float:
	return (size.x - _column_width()) * 0.5

func _column_width() -> float:
	return minf(size.x - PAD * 2.0, MAX_CONTENT_WIDTH)

func _draw() -> void:
	if model == null or shop == null:
		return

	var font := get_theme_default_font()
	# Fully opaque. At 0.93 the HUD and the arena bled through and the shop read
	# as a translucent overlay rather than as the screen it is during this phase.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09))
	draw_rect(Rect2(Vector2.ZERO, size), accent.darkened(0.4), false, 2.0)

	var y := _draw_header(font)
	if tab == Tab.STATS:
		_draw_stats(font, y)
	else:
		_draw_shop(font, y)
	_draw_controls(font)

## Nothing on screen said which button does what, so "I do not know how to sell
## this" was a fault of the UI rather than of the player. Labelled per device,
## because telling a pad player to press Space is worse than saying nothing.
func _draw_controls(font: Font) -> void:
	if input == null:
		return
	var hint := "%s buy/sell   %s reroll   %s shop/stats   %s ready" % [
		input.label_for(PlayerInput.Action.ACCEPT),
		input.label_for(PlayerInput.Action.REROLL),
		input.label_for(PlayerInput.Action.TAB),
		input.label_for(PlayerInput.Action.READY),
	]
	draw_string(
		font, Vector2(_column_x(), size.y - 16.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, _column_width(), 13, Color(0.5, 0.55, 0.64)
	)

func _draw_header(font: Font) -> float:
	var left := _column_x()
	var width := _column_width()

	draw_string(
		font, Vector2(left, PAD + 18.0), "P%d" % (player_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, accent
	)

	var tabs := "[ SHOP ]  STATS" if tab == Tab.SHOP else "  SHOP  [ STATS ]"
	draw_string(
		font, Vector2(left + 46.0, PAD + 18.0), tabs,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.72, 0.77, 0.86)
	)

	# Health belongs here now: the HUD hides during the shop, and max HP is
	# buyable, so hiding it would mean shopping blind for the one stat the shop
	# can take from you.
	var money := "%d HP   %d  |  reroll %d" % [
		roundi(model.current_hp), model.get_currency(), shop.reroll_cost()
	]
	draw_string(
		font, Vector2(left + width - 300.0, PAD + 18.0), money,
		HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 17, Color(0.95, 0.86, 0.62)
	)

	# Readiness is shown on EVERY panel rather than once on a shared banner,
	# because at four players there is no shared space left and "who are we
	# waiting for" is exactly the question a full screen of panels creates.
	var state := (
		waiting_text if shop.is_ready
		else "READY: %s" % input.label_for(PlayerInput.Action.READY)
	)
	draw_string(
		font, Vector2(left + width - 300.0, PAD + 40.0), state,
		HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 15,
		Color(0.55, 0.92, 0.6) if shop.is_ready else Color(0.6, 0.64, 0.72)
	)

	return PAD + 58.0

func _draw_shop(font: Font, top: float) -> void:
	var row_height := COMPACT_ROW_HEIGHT if _compact else ROW_HEIGHT
	var y := top

	for index in shop.offers.size():
		var offer := shop.offers[index]
		var selected := zone == Zone.OFFERS and cursor == index
		_draw_row(
			font, y, row_height, selected, offer.sold,
			tr(offer.item.display_key),
			"T%d" % offer.item.tier,
			"-" if offer.sold else str(offer.price)
		)
		y += row_height

	var reroll_selected := zone == Zone.OFFERS and cursor == shop.offers.size()
	_draw_row(font, y, row_height, reroll_selected, false, "REROLL", "", str(shop.reroll_cost()))
	y += row_height + 12.0

	y = _draw_detail(font, y)
	_draw_owned(font, y)

## What the highlighted thing actually DOES, for an offer and for something
## already owned alike.
##
## Derived from the item rather than authored per item. A hand-written
## description and the numbers it describes drift apart the moment somebody
## retunes one of them, and at a few hundred items they drift silently - the
## text still reads fine, it is just no longer true.
func _draw_detail(font: Font, top: float) -> float:
	var entry := _highlighted()
	if entry == null:
		return top

	var left := _column_x()
	var y := top + 4.0
	var line := 20.0 if _compact else 22.0
	var font_size := 13 if _compact else 15

	draw_string(
		font, Vector2(left, y), tr(entry.display_key),
		HORIZONTAL_ALIGNMENT_LEFT, _column_width(), font_size + 1, Color(0.93, 0.95, 0.99)
	)
	y += line

	for modifier in entry.modifiers:
		if modifier == null:
			continue
		y = _draw_modifier_line(font, left, y, line, font_size, modifier)

	# The dynamic half. describe() is implemented by every effect in the
	# library, and a throwaway instance at one stack is what a single copy does -
	# which is what the shop is selling.
	for effect in entry.effects:
		if effect == null:
			continue
		draw_string(
			font, Vector2(left + 10.0, y), "* " + effect.describe(EffectInstance.new(effect, entry.item, 1)),
			HORIZONTAL_ALIGNMENT_LEFT, _column_width() - 10.0, font_size, Color(0.72, 0.82, 0.95)
		)
		y += line

	if zone == Zone.OWNED and entry.can_sell():
		draw_string(
			font, Vector2(left + 10.0, y),
			"%s: sell for %d" % [
				input.label_for(PlayerInput.Action.ACCEPT), shop.data.sell_price_for(entry.item)
			],
			HORIZONTAL_ALIGNMENT_LEFT, _column_width() - 10.0, font_size, Color(0.95, 0.86, 0.62)
		)
		y += line

	return y + 10.0

## Green when it helps, red when it hurts - and which is which comes from
## StatMetadata.higher_is_better, not from the sign, because less spread and
## less recoil are improvements.
func _draw_modifier_line(
	font: Font, left: float, y: float, line: float, font_size: int, modifier: StatModifier
) -> float:
	var meta: StatMetadata = stat_sheet.metadata_for(modifier.stat) if stat_sheet != null else null
	var label := tr(meta.display_key) if meta != null else "STAT_%d" % modifier.stat
	var value := (
		meta.format_modifier(modifier.modifier_type, modifier.value)
		if meta != null
		else str(modifier.value)
	)
	var good := meta.is_improvement(modifier.value) if meta != null else modifier.value >= 0.0

	draw_string(
		font, Vector2(left + 10.0, y), label,
		HORIZONTAL_ALIGNMENT_LEFT, _column_width() - 120.0, font_size, Color(0.74, 0.78, 0.85)
	)
	draw_string(
		font, Vector2(left + _column_width() - 110.0, y), value,
		HORIZONTAL_ALIGNMENT_RIGHT, 110.0, font_size,
		Color(0.5, 0.9, 0.55) if good else Color(0.95, 0.5, 0.45)
	)
	return y + line

func _highlighted() -> OwnedEntry:
	if zone == Zone.OWNED:
		return _owned[cursor] if cursor < _owned.size() else null
	if cursor >= shop.offers.size():
		return null

	var item := shop.offers[cursor].item
	if item == null:
		return null

	var entry := OwnedEntry.new()
	entry.display_key = item.display_key
	entry.modifiers = item.static_stats
	entry.effects = item.dynamic_effects
	entry.tier_label = "T%d" % item.tier
	entry.item = item
	return entry

func _draw_row(
	font: Font, y: float, height: float, selected: bool, dimmed: bool,
	label: String, badge: String, value: String
) -> void:
	var row := Rect2(Vector2(_column_x(), y), Vector2(_column_width(), height - 4.0))
	if selected:
		draw_rect(row, accent.darkened(0.55))
		draw_rect(row, accent, false, 1.5)
	else:
		draw_rect(row, Color(0.09, 0.10, 0.14, 0.8))

	var text_color := Color(0.45, 0.48, 0.54) if dimmed else Color(0.9, 0.92, 0.96)
	var baseline := y + height * 0.5 + 4.0
	var font_size := 15 if _compact else 17

	draw_string(font, Vector2(_column_x() + 12.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	if not badge.is_empty():
		draw_string(
			font, Vector2(_column_x() + _column_width() - 130.0, baseline), badge,
			HORIZONTAL_ALIGNMENT_RIGHT, 60.0, font_size - 2, Color(0.6, 0.66, 0.78)
		)
	draw_string(
		font, Vector2(_column_x() + _column_width() - 70.0, baseline), value,
		HORIZONTAL_ALIGNMENT_RIGHT, 58.0, font_size,
		Color(0.45, 0.48, 0.54) if dimmed else Color(0.95, 0.86, 0.62)
	)

## Placeholder tiles rather than icons, because there is no art. The tile still
## carries the tier and the refund, so "walk over it and read what it does" works
## in text until icons exist.
func _draw_owned(font: Font, top: float) -> void:
	if _owned.is_empty():
		draw_string(
			font, Vector2(_column_x(), top + 18.0), "nothing owned",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.48, 0.55)
		)
		return

	var x := _column_x()
	for index in _owned.size():
		if x + OWNED_TILE > _column_x() + _column_width():
			break
		var selected := zone == Zone.OWNED and cursor == index
		var tile := Rect2(Vector2(x, top), Vector2(OWNED_TILE - 6.0, OWNED_TILE - 6.0))

		draw_rect(tile, Color(0.12, 0.14, 0.19))
		draw_rect(tile, accent if selected else Color(0.3, 0.33, 0.4), false, 2.0 if selected else 1.0)
		draw_string(
			font, Vector2(x + 6.0, top + 26.0), _owned[index].tier_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			accent if not _owned[index].can_sell() else Color(0.8, 0.84, 0.9)
		)
		# Quantity, because items stack and a strip that hides the stack lies.
		var count := _owned[index].quantity
		if count > 1:
			draw_string(
				font, Vector2(x + 6.0, top + 40.0), "x%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.74)
			)
		x += OWNED_TILE


## The sheet enumerates StatSheet, never the enum, so a stat authored later
## appears here without this file being touched.
func _draw_stats(font: Font, top: float) -> void:
	var row_height := 24.0 if _compact else 28.0
	var visible_rows := int((size.y - top - 80.0) / row_height)
	var first := maxi(0, mini(stat_cursor - visible_rows / 2, _stats.size() - visible_rows))
	var y := top

	for offset in visible_rows:
		var index := first + offset
		if index >= _stats.size():
			break

		var meta := _stats[index]
		var selected := index == stat_cursor
		if selected:
			draw_rect(
				Rect2(Vector2(_column_x() - 4.0, y - 2.0), Vector2(_column_width() + 8.0, row_height)),
				accent.darkened(0.6)
			)

		draw_string(
			font, Vector2(_column_x(), y + row_height - 8.0), tr(meta.display_key),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.95, 0.96, 0.99) if selected else Color(0.74, 0.78, 0.85)
		)
		# The real computed value, so every modifier-based effect is already in
		# it - items, statuses and "for every 1000 bullets" alike, because they
		# all contribute by registering modifiers rather than by intercepting
		# the read.
		draw_string(
			font, Vector2(_column_x() + _column_width() - 120.0, y + row_height - 8.0),
			meta.format_value(model.stats.get_stat(meta.stat)),
			HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 15, Color(0.95, 0.86, 0.62)
		)
		y += row_height

	if stat_cursor < _stats.size():
		draw_string(
			font, Vector2(_column_x(), size.y - PAD - 12.0), tr(_stats[stat_cursor].description_key),
			HORIZONTAL_ALIGNMENT_LEFT, _column_width(), 14, Color(0.7, 0.75, 0.84)
		)
