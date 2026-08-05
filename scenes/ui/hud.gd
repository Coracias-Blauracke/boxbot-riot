class_name Hud
extends CanvasLayer

## The whole on-screen readout: one panel per player, plus the wave line they
## share.
##
## LAYOUT IS DRIVEN BY PLAYER COUNT, not by a fixed design. One player claims
## the top-left corner and nothing else moves; every further player claims
## another corner. Deliberately not a bar along one edge: this is a top-down
## game where the edges of the screen are where enemies come from, and a strip
## of chrome there costs reaction time.
##
## Nothing is centred on a player, because with four of them there is no "the"
## player to centre on. Only what they genuinely share - the wave and its clock
## - sits in the middle.
##
## Polls the models each frame rather than subscribing to hp_changed and
## friends. Four players' worth of health and currency is a handful of reads,
## the panels redraw only when a value actually moves, and a poll cannot go
## stale the way a signal missed during a respawn can.

## Distance from each screen edge to its panel.
const MARGIN := 26.0

## Which corner each player index claims, as (anchor_x, anchor_y).
const CORNERS: Array[Vector2] = [
	Vector2(0.0, 0.0),  ## P1 - top left
	Vector2(1.0, 0.0),  ## P2 - top right
	Vector2(0.0, 1.0),  ## P3 - bottom left
	Vector2(1.0, 1.0),  ## P4 - bottom right
]

var run: RunModel

var _panels: Array[PlayerPanel] = []
var _wave_label: Label
var _timer_label: Label
var _overlay: Control
var _outcome_label: Label
var _outcome_detail: Label

func bind(p_run: RunModel, models: Array[EntityModel]) -> void:
	run = p_run
	run.run_ended.connect(_on_run_ended)
	run.phase_changed.connect(_on_phase_changed)

	_build_banner()
	_build_overlay()

	for index in models.size():
		_panels.append(_build_panel(index, models[index]))

func _build_panel(index: int, model: EntityModel) -> PlayerPanel:
	var panel := PlayerPanel.new()
	panel.player_index = index
	panel.model = model
	panel.accent = PlayerPalette.color_for(index)

	var corner: Vector2 = CORNERS[index % CORNERS.size()]
	# Right-hand panels mirror their contents so they hug the edge they are
	# anchored to instead of trailing off towards the centre of the arena.
	panel.mirrored = corner.x > 0.0

	panel.anchor_left = corner.x
	panel.anchor_right = corner.x
	panel.anchor_top = corner.y
	panel.anchor_bottom = corner.y
	panel.offset_left = MARGIN if corner.x == 0.0 else -MARGIN - PlayerPanel.WIDTH
	panel.offset_right = panel.offset_left + PlayerPanel.WIDTH
	panel.offset_top = MARGIN if corner.y == 0.0 else -MARGIN - PlayerPanel.HEIGHT
	panel.offset_bottom = panel.offset_top + PlayerPanel.HEIGHT

	add_child(panel)
	return panel

func _build_banner() -> void:
	_wave_label = _centred_label(14.0, 34, Color(0.93, 0.94, 0.97))
	_timer_label = _centred_label(56.0, 25, Color(0.68, 0.73, 0.82))

func _centred_label(top: float, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -220.0
	label.offset_right = 220.0
	label.offset_top = top
	label.offset_bottom = top + float(font_size) + 8.0
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	add_child(label)
	return label

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.02, 0.05, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	_outcome_label = _overlay_label(-52.0, 62)
	_outcome_detail = _overlay_label(26.0, 26)
	_outcome_detail.add_theme_color_override(&"font_color", Color(0.72, 0.77, 0.86))

func _overlay_label(offset_y: float, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -420.0
	label.offset_right = 420.0
	label.offset_top = offset_y
	label.offset_bottom = offset_y + float(font_size) + 10.0
	label.add_theme_font_size_override(&"font_size", font_size)
	_overlay.add_child(label)
	return label

# --- per-frame -------------------------------------------------------------

func _process(_delta: float) -> void:
	if run == null:
		return

	match run.phase:
		WorldTypes.Phase.COMBAT:
			_wave_label.text = "WAVE %d" % run.wave_number
			_timer_label.text = _clock(run.wave_time_remaining())
		WorldTypes.Phase.SHOP:
			_wave_label.text = "WAVE %d CLEARED" % run.wave_number
			# Reads the intermission because there is no shop yet. Once there is,
			# this line becomes "waiting for P2, P4" instead of a countdown.
			_timer_label.text = "next in %ds" % ceili(run.intermission_remaining())
		WorldTypes.Phase.FINISHED:
			_wave_label.text = ""
			_timer_label.text = ""
		_:
			_wave_label.text = "GET READY"
			_timer_label.text = ""

func _clock(seconds: float) -> String:
	var whole := maxi(0, ceili(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]

## The shop panels are the screen during their phase, and everything the HUD
## shows is repeated in their headers. Leaving it up meant two currency
## readouts, and at four players the corner panels landed on top of the shop.
func _on_phase_changed(phase: WorldTypes.Phase) -> void:
	visible = phase != WorldTypes.Phase.SHOP

func _on_run_ended(outcome: RunTypes.Outcome) -> void:
	visible = true
	var won := outcome == RunTypes.Outcome.VICTORY
	_outcome_label.text = "RUN COMPLETE" if won else "WIPED OUT"
	_outcome_label.add_theme_color_override(
		&"font_color", Color(0.55, 0.92, 0.6) if won else Color(0.95, 0.45, 0.4)
	)
	_outcome_detail.text = "cleared %d of %d waves" % [
		run.wave_number if won else run.wave_number - 1, run.total_waves
	]
	_overlay.visible = true
