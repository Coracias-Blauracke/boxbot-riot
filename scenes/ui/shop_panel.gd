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

enum Tab { SHOP, STATS }

## Which row group the cursor is in. Two zones rather than one flat list,
## because the offers read as a column and the things you own read as a strip,
## and a cursor that walks from one into the other in a straight line is how you
## sell an item while trying to buy one.
enum Zone { OFFERS, OWNED }

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

var tab: Tab = Tab.SHOP
var zone: Zone = Zone.OFFERS
var cursor: int = 0
var stat_cursor: int = 0

## Who this player is still waiting on, filled by ShopScreen each frame.
var waiting_text: String = ""

var _compact: bool = false
var _owned: Array[ItemData] = []
var _stats: Array[StatMetadata] = []

func bind(
	p_index: int, p_model: EntityModel, p_shop: ShopManager,
	p_input: PlayerInput, p_sheet: StatSheet
) -> void:
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
	for item in model.items.get_all():
		_owned.append(item as ItemData)

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
		shop.set_ready(not shop.is_ready)
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
		if cursor < _owned.size():
			shop.sell(model, _owned[cursor])
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

func _draw_header(font: Font) -> float:
	var left := _column_x()
	var width := _column_width()

	draw_string(
		font, Vector2(left, PAD + 18.0), "P%d" % (player_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, accent
	)

	var tabs := "[ SKLEP ]  STATY" if tab == Tab.SHOP else "  SKLEP  [ STATY ]"
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
	var state := waiting_text if shop.is_ready else "GOTÓW: Enter / Start"
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
	_draw_row(font, y, row_height, reroll_selected, false, "PRZELOSUJ", "", str(shop.reroll_cost()))
	y += row_height + 12.0

	_draw_owned(font, y)

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
			font, Vector2(_column_x(), top + 18.0), "brak przedmiotów",
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
			font, Vector2(x + 6.0, top + 26.0), "T%d" % _owned[index].tier,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.84, 0.9)
		)
		# Quantity, because items stack and a strip that hides the stack lies.
		var count := model.items.get_quantity(_owned[index])
		if count > 1:
			draw_string(
				font, Vector2(x + 6.0, top + 40.0), "x%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.74)
			)
		x += OWNED_TILE

	if zone == Zone.OWNED and cursor < _owned.size():
		var item := _owned[cursor]
		draw_string(
			font, Vector2(_column_x(), top + OWNED_TILE + 20.0),
			"%s  —  sprzedaj za %d" % [tr(item.display_key), shop.data.sell_price_for(item)],
			HORIZONTAL_ALIGNMENT_LEFT, _column_width(), 14, Color(0.86, 0.88, 0.93)
		)

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
