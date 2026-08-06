class_name PauseScreen
extends CanvasLayer

## Stops the run and offers the three things a play-test session needs: carry
## on, start over, or leave.
##
## ONE menu driven by EVERY device, which is deliberately the opposite of the
## shop. A shop panel gets its own cursor because each player is deciding
## something different; here there is a single decision that applies to
## everybody, so tying it to whichever device opened it would only mean a pad
## going flat can strand the whole run. Who reaches for the stick is a couch
## problem, not a software one.
##
## THE MENU IS ALSO THE RUN-OVER SCREEN. When the run ends it opens itself with
## RESUME dropped, because "the run is over and there is no way to start another
## one" was the same dead end as having no pause at all - and a second screen
## that says the same three things would be two things to keep in step.
##
## Restarting and quitting are EMITTED, not done here. This layer knows what was
## chosen; main.gd owns the tree and is the only place that reloads it.

signal restart_requested
signal quit_requested

enum Entry { RESUME, RESTART, QUIT }

const LABELS: Dictionary = {
	Entry.RESUME: "RESUME",
	Entry.RESTART: "RESTART RUN",
	Entry.QUIT: "QUIT",
}

## Drawn rather than built from Containers, for the same reason the shop panel
## is: there is no art yet, and a layout assembled from themes and anchors would
## be thrown away when there is.
class Menu extends Control:
	const WIDTH := 460.0
	const ROW := 58.0

	var title: String = ""
	var entries: PackedStringArray = PackedStringArray()
	var cursor: int = 0
	var hint: String = ""

	## Where the rows start, relative to the middle of the screen. The run-over
	## state pushes them down so they clear the HUD's outcome banner, which is
	## already centred and says what happened.
	var block_top: float = -70.0

	## Off once the run is over, because the HUD's outcome banner already draws
	## one. Two shades stacked read as 0.92 alpha and blacked the arena out
	## entirely - the corpse the player just made vanished behind them.
	var draw_shade: bool = true

	func _draw() -> void:
		var font := get_theme_default_font()
		if font == null or entries.is_empty():
			return

		if draw_shade:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.72))

		var left := size.x * 0.5 - WIDTH * 0.5
		var y := size.y * 0.5 + block_top

		if not title.is_empty():
			draw_string(
				font, Vector2(left, y - 34.0), title, HORIZONTAL_ALIGNMENT_CENTER,
				WIDTH, 52, Color(0.93, 0.94, 0.97)
			)

		for index in entries.size():
			var selected := index == cursor
			var row := Rect2(left, y, WIDTH, ROW - 10.0)
			draw_rect(row, Color(0.15, 0.17, 0.23) if selected else Color(0.07, 0.08, 0.11, 0.9))
			draw_rect(
				row, Color(0.88, 0.90, 0.96) if selected else Color(0.24, 0.26, 0.33),
				false, 2.0
			)
			draw_string(
				font, Vector2(left, y + 33.0), entries[index], HORIZONTAL_ALIGNMENT_CENTER,
				WIDTH, 26, Color(0.96, 0.97, 1.0) if selected else Color(0.62, 0.66, 0.75)
			)
			y += ROW

		# Across the whole screen rather than the row width: draw_string CLIPS at
		# the width it is given, and the hint is longer than a row. It lost its
		# last word silently and only a screenshot showed it.
		draw_string(
			font, Vector2(0.0, y + 26.0), hint, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 18, Color(0.5, 0.54, 0.62)
		)

var run: RunModel

var _inputs: Array[PlayerInput] = []
var _menu: Menu
var _entries: Array[Entry] = []
var _cursor: int = 0
var _open: bool = false

## Set once the run has ended. Latched rather than read off the phase every
## frame because it never goes back.
var _run_over: bool = false

func bind(p_run: RunModel, inputs: Array[PlayerInput]) -> void:
	run = p_run
	_inputs = inputs
	run.run_ended.connect(_on_run_ended)

	_menu = Menu.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	add_child(_menu)

func is_open() -> bool:
	return _open

## Exactly what pressing the button does, gate included.
##
## The capture flag calls THIS rather than open(), because a capture that goes
## straight to open() photographs a screen the button may not be able to reach -
## it would happily show a pause menu over the shop, which is the one place
## pausing is refused. A verification path that skips the gate verifies nothing.
func request_toggle() -> void:
	if not _open:
		if _can_open():
			open()
		return
	# Nothing to go back to once the run is over, so the button stops toggling.
	if not _run_over:
		close()

func open() -> void:
	if _open:
		return
	_open = true
	_rebuild()
	_menu.visible = true
	get_tree().paused = true

func close() -> void:
	if not _open:
		return
	_open = false
	_menu.visible = false
	get_tree().paused = false

# --- input -----------------------------------------------------------------

## This node runs with PROCESS_MODE_ALWAYS (set on the scene), so it keeps
## reading input while everything else is frozen. It is the only node that may.
func _process(delta: float) -> void:
	if run == null:
		return

	# Every device, every phase. Polling continuously is what makes releasing
	# START in the shop and pressing it again in combat two separate events: a
	# menu that only started polling once the shop closed would see the button
	# already down and open itself the instant somebody readied up.
	for input in _inputs:
		input.poll(delta)

	# Handled before anything else and returns immediately, because on the
	# keyboard this is the same key as CANCEL: without the early out, the press
	# that opens the menu also backs straight out of it in the same frame.
	if _any_triggered(PlayerInput.Action.PAUSE):
		request_toggle()
		return

	if _open:
		_handle_menu()

## No pause during the shop: it has no clock, it closes only when every player
## says so, and START already means ready-up there.
func _can_open() -> bool:
	return run.phase != WorldTypes.Phase.SHOP

func _handle_menu() -> void:
	if _entries.is_empty():
		return

	if _any_triggered(PlayerInput.Action.DOWN):
		_cursor = wrapi(_cursor + 1, 0, _entries.size())
		_menu.cursor = _cursor
		_menu.queue_redraw()
	elif _any_triggered(PlayerInput.Action.UP):
		_cursor = wrapi(_cursor - 1, 0, _entries.size())
		_menu.cursor = _cursor
		_menu.queue_redraw()
	elif _any_triggered(PlayerInput.Action.ACCEPT):
		_choose(_entries[_cursor])
	elif not _run_over and _any_triggered(PlayerInput.Action.CANCEL):
		# Backing out is the same as resuming. Not offered once the run is over,
		# because there is nothing behind this screen to go back to.
		close()

func _choose(entry: Entry) -> void:
	match entry:
		Entry.RESUME:
			close()
		Entry.RESTART:
			restart_requested.emit()
		Entry.QUIT:
			quit_requested.emit()

func _any_triggered(action: PlayerInput.Action) -> bool:
	for input in _inputs:
		if input.triggered(action):
			return true
	return false

# --- state -----------------------------------------------------------------

func _on_run_ended(_outcome: RunTypes.Outcome) -> void:
	_run_over = true
	open()

func _rebuild() -> void:
	_entries.clear()
	if not _run_over:
		_entries.append(Entry.RESUME)
	_entries.append(Entry.RESTART)
	_entries.append(Entry.QUIT)
	_cursor = 0

	var labels := PackedStringArray()
	for entry in _entries:
		labels.append(str(LABELS[entry]))

	_menu.entries = labels
	_menu.cursor = _cursor
	_menu.title = "" if _run_over else "PAUSED"
	# The HUD's outcome banner owns the middle of the screen once the run is
	# over, so the rows move below it rather than on top of it.
	_menu.block_top = 96.0 if _run_over else -70.0
	_menu.draw_shade = not _run_over
	_menu.hint = "ANY PAD OR THE KEYBOARD  -  A / SPACE TO CONFIRM"
	_menu.queue_redraw()
