class_name PlayerPanel
extends Control

## One player's readout, anchored in one corner of the screen.
##
## MIRRORS itself in the right-hand corners, so its contents always hug the edge
## they belong to. Without that, player 2's bar would start near the middle of
## the screen and read as if it described player 1.
##
## Drawn rather than assembled from Container nodes for the same reason the
## actors are: there is no art yet, and a layout built from anchors would have
## to be thrown away once there is.

const WIDTH := 266.0
const HEIGHT := 54.0

const NAME_WIDTH := 32.0
const BAR_WIDTH := 154.0
const BAR_HEIGHT := 13.0
const BAR_TOP := 5.0
const HP_WIDTH := 106.0

const ROW1_BASELINE := 16.0
const ROW2_BASELINE := 45.0
const COIN_RADIUS := 7.0

const NAME_SIZE := 19
const VALUE_SIZE := 17

var player_index: int = 0
var model: EntityModel
var accent: Color = Color.WHITE
var mirrored: bool = false

## Set when the shop charges a stat instead of currency. PriceEvent names the
## stat, StatMetadata supplies the icon and the number format, and this readout
## takes both as given - it never needs to know which of the two is in play.
## Null falls back to the drawn placeholder coin.
var currency_icon: Texture2D = null
var currency_format: StatMetadata.Format = StatMetadata.Format.INTEGER

## Only redraw when a displayed value actually moves. A poll every frame is
## cheap; re-rasterising four panels' worth of glyphs every frame is not.
var _last: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if model == null:
		return
	var now: Array = [model.current_hp, model.get_max_hp(), model.get_currency(), model.is_alive]
	if now == _last:
		return
	_last = now
	queue_redraw()

## Maps a left-anchored span into the mirrored layout of the right-hand corners.
func _x(x: float, w: float) -> float:
	return (size.x - x - w) if mirrored else x

func _align() -> int:
	return HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT

func _draw() -> void:
	if model == null:
		return

	var font := get_theme_default_font()
	var alive := model.is_alive
	var maximum := maxf(1.0, model.get_max_hp())
	var ratio := clampf(model.current_hp / maximum, 0.0, 1.0)

	var name_color := accent if alive else accent.darkened(0.45)
	draw_string(
		font, Vector2(_x(0.0, NAME_WIDTH), ROW1_BASELINE), "P%d" % (player_index + 1),
		_align(), NAME_WIDTH, NAME_SIZE, name_color
	)

	_draw_health_bar(ratio, alive)

	var hp_text := (
		"%d / %d" % [ceili(model.current_hp), roundi(maximum)] if alive else "DOWN"
	)
	draw_string(
		font, Vector2(_x(WIDTH - HP_WIDTH, HP_WIDTH), ROW1_BASELINE), hp_text,
		HORIZONTAL_ALIGNMENT_RIGHT if not mirrored else HORIZONTAL_ALIGNMENT_LEFT,
		HP_WIDTH, VALUE_SIZE,
		Color(0.88, 0.9, 0.94) if alive else Color(0.95, 0.42, 0.38)
	)

	_draw_currency(font)

func _draw_health_bar(ratio: float, alive: bool) -> void:
	var left := _x(NAME_WIDTH + 6.0, BAR_WIDTH)
	var track := Rect2(Vector2(left, BAR_TOP), Vector2(BAR_WIDTH, BAR_HEIGHT))
	draw_rect(track, Color(0.06, 0.07, 0.10, 0.85))

	if alive and ratio > 0.0:
		# The fill grows from the same edge the panel is anchored to, so a
		# mirrored bar drains towards the screen edge rather than away from it.
		var filled := BAR_WIDTH * ratio
		var fill_x := (left + BAR_WIDTH - filled) if mirrored else left
		draw_rect(
			Rect2(Vector2(fill_x, BAR_TOP), Vector2(filled, BAR_HEIGHT)),
			Color(0.32, 0.85, 0.42) if ratio > 0.3 else Color(0.92, 0.38, 0.32)
		)

	draw_rect(track, Color(0.55, 0.6, 0.7, 0.7) if alive else Color(0.4, 0.2, 0.2, 0.7), false, 1.5)

func _draw_currency(font: Font) -> void:
	var value := model.get_currency()
	var icon_span := COIN_RADIUS * 2.0

	if currency_icon != null:
		draw_texture_rect(
			currency_icon,
			Rect2(
				Vector2(_x(0.0, icon_span), ROW2_BASELINE - icon_span),
				Vector2(icon_span, icon_span)
			),
			false
		)
	else:
		var centre := Vector2(_x(0.0, icon_span) + COIN_RADIUS, ROW2_BASELINE - COIN_RADIUS)
		draw_circle(centre, COIN_RADIUS, Color(0.95, 0.78, 0.28))
		draw_arc(centre, COIN_RADIUS, 0.0, TAU, 16, Color(0.6, 0.45, 0.12), 1.5)

	var text_left := icon_span + 7.0
	var text_width := WIDTH - text_left
	draw_string(
		font, Vector2(_x(text_left, text_width), ROW2_BASELINE),
		_format_currency(float(value)),
		_align(), text_width, VALUE_SIZE, Color(0.95, 0.86, 0.62)
	)

## Routed through StatMetadata's formatter so a stat-paying shop shows "35%" or
## "40.0" exactly as the stat list does, with no second formatting rule here.
func _format_currency(value: float) -> String:
	match currency_format:
		StatMetadata.Format.PERCENT:
			return "%d%%" % roundi(value * 100.0)
		StatMetadata.Format.FLAT:
			return "%.1f" % value
		_:
			return str(roundi(value))
