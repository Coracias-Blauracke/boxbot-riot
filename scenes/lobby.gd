extends Node

## Where a run is composed, and the scene the game now starts on.
##
## Deliberately its OWN scene rather than a phase inside main.tscn. What goes
## here later - a solo/co-op toggle, character select, run rules, a difficulty -
## are all decisions taken BEFORE a run exists and re-taken between runs, and
## putting them inside the thing they configure means the run has to be able to
## exist half-built. Here the run is not instantiated until it is fully
## described.
##
## THE LOBBY OWNS THE RUN, not the other way round: main.tscn is instantiated as
## a child with its player_count and player_devices injected, exactly as main.gd
## itself builds a Character by injecting a model before add_child(). Which is
## also what makes restarting keep your players - the roster lives out here,
## above the thing being restarted.
##
## main.tscn stays independently launchable. Nothing here is required for it to
## run; it falls back to its own exports and to reload_current_scene() when no
## lobby is listening, so every capture command in CLAUDE.md still works when
## pointed straight at it.

const RUN_SCENE := preload("res://scenes/main.tscn")

## Which characters this build may be started with. Authored as one file for the
## same reason ShopData holds its pools rather than scanning a folder - and it
## is what makes a second authored character reachable at all, since main.tscn
## holds only one.
@export var characters: CharacterSet

## Only so a slot can describe its character in the same derived terms the shop
## uses. Nothing here computes what an item is worth; StatMetadata already knows
## how to render a modifier and whether it helps.
@export var stat_sheet: StatSheet

@export_group("Rack layout")
## M x N: tiles across, and rows on screen at once. Everything past N rows
## scrolls.
##
## Authored rather than derived from the roster size, because the two questions
## are different: how many characters exist is content, and how many should be
## readable at a glance is a layout decision that wants a person's eye. Tile
## size follows from these, so raising the column count shrinks the tiles rather
## than running the row off the screen.
@export_range(1, 12) var grid_columns: int = 4
@export_range(1, 8) var grid_rows: int = 2

@onready var _join_view: JoinView = $Ui/JoinView

var roster := PlayerRoster.new()

var _joiner: DeviceJoiner
## One per joined device, only to answer "has this player pressed START". The
## run builds its own; these are thrown away when it starts.
var _inputs: Array[PlayerInput] = []
var _run: Node = null

func _ready() -> void:
	_joiner = DeviceJoiner.new(roster)
	# Before anybody can join, so the first player's default pick has something
	# to be a pick OF.
	roster.catalogue = characters
	roster.changed.connect(_on_roster_changed)
	# A REDRAW and nothing else. Selecting must not rebuild the input list: the
	# selections are stepped from inside a loop over it - see PlayerRoster.
	roster.selection_changed.connect(_join_view.queue_redraw)

	_join_view.roster = roster
	_join_view.stat_sheet = stat_sheet
	_join_view.columns = grid_columns
	_join_view.visible_rows = grid_rows
	get_viewport().size_changed.connect(_on_roster_changed)
	_on_roster_changed()

	_apply_capture_args()

func _process(_delta: float) -> void:
	# Nothing is polled once a run exists: the run owns every device from that
	# point, and a lobby still reading them would start a second one.
	if _run != null:
		return

	_joiner.poll()

	# By INDEX, because a player's device is what the roster answers to and the
	# two lists are built in the same order. Iterating the inputs alone would
	# leave nothing to say WHOSE selection moved.
	#
	# ACCEPT and CANCEL are deliberately NOT read here - DeviceJoiner owns them,
	# because it is the only thing that can guarantee the press which joins
	# somebody does not also confirm their default chassis on the same frame.
	for index in mini(_inputs.size(), roster.count()):
		var input := _inputs[index]
		input.poll(_delta)
		if input.triggered(PlayerInput.Action.READY):
			start_run()
			return

		_move_cursor(index, input)
		_advance_scroll(index, input, _delta)

## Anybody may press it, but not until EVERY joined player has locked a chassis
## in. That reverses the earlier "any joined player may start it", and the
## reason it was worth reversing is that there is now something to be halfway
## through: starting on somebody's cursor rather than on their decision means a
## player spends the whole run as whoever they happened to be hovering.
##
## Who presses it is still a couch problem, exactly as with the pause menu.
func start_run() -> void:
	if _run != null or not roster.everyone_confirmed():
		return
	_build_run()

## Same roster, fresh run. Better than reloading the scene, which is what this
## replaces: the players who were mid-session stay exactly who they were, and
## nobody has to press anything to get back to where they died.
func _on_restart_requested() -> void:
	# Deferred: this arrives from inside the run's own _process, and freeing a
	# node in the middle of its frame is how a tree gets corrupted.
	_rebuild_run.call_deferred()

func _rebuild_run() -> void:
	_clear_run()
	_build_run()

func _clear_run() -> void:
	if _run == null:
		return
	remove_child(_run)
	_run.queue_free()
	_run = null

func _build_run() -> void:
	var run := RUN_SCENE.instantiate()
	# Injected BEFORE add_child, so _ready() sees the composition rather than
	# the authored default and spawns the right players the first time.
	run.set(&"player_count", roster.count())
	run.set(&"player_devices", roster.to_player_devices())
	# Index-aligned with the devices above, so a restart brings back both who was
	# playing and what they were playing. A run that reseeded the chassis would
	# be the same dead end as one that made everybody re-join.
	run.set(&"player_characters", roster.to_player_characters())
	run.restart_requested.connect(_on_restart_requested)

	_run = run
	add_child(run)
	_join_view.visible = false
	_inputs.clear()

## The same stick and the same repeat the shop cursor uses, so a player who
## learned to browse offers already knows how to browse a rack.
##
## Where a nudge LANDS is GridCursor's answer, not the roster's: the roster is a
## flat list and does not know how wide the rack is drawn, and the wrapping the
## player expects is per ROW and per COLUMN rather than across the whole list.
## Right from the end of a row returns to the start of that same row.
func _move_cursor(index: int, input: PlayerInput) -> void:
	var total := 0 if characters == null else characters.count()
	if total <= 0:
		return

	var device: int = roster.devices[index]
	var from := roster.pick_of(index)
	var to := from

	if input.triggered(PlayerInput.Action.LEFT):
		to = GridCursor.step_horizontal(from, total, _join_view.columns, -1)
	elif input.triggered(PlayerInput.Action.RIGHT):
		to = GridCursor.step_horizontal(from, total, _join_view.columns, 1)
	elif input.triggered(PlayerInput.Action.UP):
		to = GridCursor.step_vertical(from, total, _join_view.columns, -1)
	elif input.triggered(PlayerInput.Action.DOWN):
		to = GridCursor.step_vertical(from, total, _join_view.columns, 1)

	if roster.select_index(device, to):
		_follow_cursor(to)

## The rack scrolls as ONE viewport, following whoever moved last, and only when
## that cursor would otherwise be off screen. Four private viewports would be
## four grids, which throws away the only reason the rack is shared: seeing what
## everybody else is looking at. The cost is that a player at the far end can
## pull the view away from somebody standing still - a shared screen has to move
## for somebody, and moving for whoever just acted is the only rule a player can
## predict.
func _follow_cursor(index: int) -> void:
	_join_view.grid_top = GridCursor.scroll_to_show(
		index, _join_view.columns, _join_view.grid_top, _join_view.visible_rows
	)

## How many description lines a second the stick scrolls at full push. Slow
## enough to read while moving, which is the only speed that matters here.
const SCROLL_LINES_PER_SECOND := 7.0

## Where each player has scrolled their own panel, in fractional LINES so the
## stick reads as a rate rather than a staircase. The view takes the whole part.
var _scroll: Array[float] = []

## What each player's cursor was on last frame, so scrolling can reset when they
## move to a different chassis - carrying somebody's scroll position onto a
## shorter description would open it halfway down for no reason they can see.
var _scrolled_pick: Array[int] = []

func _advance_scroll(index: int, input: PlayerInput, delta: float) -> void:
	if index >= _scroll.size():
		return

	if _scrolled_pick[index] != roster.pick_of(index):
		_scrolled_pick[index] = roster.pick_of(index)
		_scroll[index] = 0.0

	var axis := input.scroll_axis()
	if not is_zero_approx(axis):
		# Clamped against what the panel can actually show, or a held stick
		# banks scroll the player then has to unwind before anything moves.
		_scroll[index] = clampf(
			_scroll[index] + axis * delta * SCROLL_LINES_PER_SECOND,
			0.0, float(_join_view.max_scroll_for(index))
		)

	var lines := int(_scroll[index])
	if _join_view.scroll_lines[index] == lines:
		return
	_join_view.scroll_lines[index] = lines
	_join_view.queue_redraw()

func _on_roster_changed() -> void:
	_inputs.clear()
	_scroll.clear()
	_scrolled_pick.clear()
	_join_view.scroll_lines.clear()
	for device in roster.devices:
		# also_keyboard stays FALSE here. A device belongs to one player in the
		# lobby by construction, and the keyboard-plus-pad-0 arrangement that
		# flag exists for is precisely what could not express three pads and a
		# keyboard. A solo toggle can hand it back later without changing this.
		_inputs.append(PlayerInput.new(device, false))
		_scroll.append(0.0)
		_scrolled_pick.append(roster.pick_of(_scroll.size() - 1))
		_join_view.scroll_lines.append(0)

	# Size is NOT set here. The view is anchored to the full rect, and assigning
	# a size to an anchored Control is overridden after _ready() anyway - Godot
	# warns about it, which is how this was caught.
	_join_view.pads_connected = Input.get_connected_joypads().size()
	_join_view.queue_redraw()

# --- capture ---------------------------------------------------------------

## A scripted run has nobody to press SPACE, so every capture command in the
## repo would sit here for ever. --capture fills the roster and starts at once;
## --capture-lobby fills it and STAYS, which is the only way this screen gets
## photographed at all.
func _apply_capture_args() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture"):
		return

	var wanted := 1
	for arg in args:
		if arg.begins_with("--capture-players="):
			wanted = clampi(int(arg.substr("--capture-players=".length())), 1, PlayerRoster.MAX_PLAYERS)
		elif arg.begins_with("--capture-grid="):
			# Framing for the rack, A/B-able the way --capture-zoom is for the
			# camera: one variable changed, same seed, same shots.
			var shape := arg.substr("--capture-grid=".length()).split("x", false)
			if shape.size() == 2:
				_join_view.columns = maxi(1, int(shape[0]))
				_join_view.visible_rows = maxi(1, int(shape[1]))
		elif arg.begins_with("--capture-roster="):
			_apply_capture_roster(int(arg.substr("--capture-roster=".length())))

	# Keyboard first, then pads in order - what one keyboard player and a couch
	# of pads actually produces.
	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	for index in range(1, wanted):
		roster.join(index - 1)

	for arg in args:
		if arg.begins_with("--capture-select="):
			_apply_capture_selection(arg.substr("--capture-select=".length()))
		elif arg.begins_with("--capture-scroll="):
			_apply_capture_scroll(arg.substr("--capture-scroll=".length()))

	if args.has("--capture-lobby"):
		# Browsing by default, so the state a player actually spends time in is
		# the one that gets photographed. --capture-confirmed asks for the other
		# half, which is the only way the locked cursors and the START line are
		# ever seen by a run with nobody at the controls.
		if args.has("--capture-confirmed"):
			_confirm_every_player()
		_start_lobby_capture(args)
		return

	# Every capture that reaches a RUN goes through here, and the run no longer
	# starts until everybody has locked a chassis in. A scripted player has
	# nobody to press A any more than it had anybody to press SPACE.
	_confirm_every_player()
	start_run()

func _confirm_every_player() -> void:
	for device in roster.devices:
		roster.confirm(device)

## A roster of N chassis built on the spot, so the rack can be photographed at
## fifty and at a hundred without authoring a hundred characters first.
##
## The layout has to be answered BEFORE the content exists - that is the whole
## reason for the flag - and a stress roster committed to content/ would be a
## hundred files that validate, offer themselves in a lobby and mean nothing.
## Each one differs in max health so the seat panels differ too, which is what
## makes a screenshot of fifty tiles worth reading.
func _apply_capture_roster(count: int) -> void:
	var built := CharacterSet.new()
	var made: Array[CharacterData] = []

	for entry in maxi(1, count):
		var character := CharacterData.new()
		character.display_key = "CHAR_STRESS_%02d" % (entry + 1)
		character.collider_radius = 12.0

		var hp := StatModifier.new()
		hp.stat = StatTypes.Stat.MAX_HP
		hp.modifier_type = StatTypes.Modifier.BASE
		hp.value = 100.0 + float(entry)
		character.base_stats = [hp]
		made.append(character)

	built.characters = made
	built.baseline = made[0]
	characters = built
	roster.catalogue = built

## --capture-select=0,3,5 puts player N on catalogue entry N, which no scripted
## player can do for themselves. Without it a capture can only ever photograph
## the default picks, and "everybody is on something different" would be
## indistinguishable from "nobody can change chassis at all".
##
## STEPPED rather than assigned, one nudge at a time, so it goes through exactly
## the path the stick goes through - the same reason --capture-pause calls
## request_toggle() instead of open(). A capture that reaches a state by a route
## no player has verifies nothing about the route players take.
func _apply_capture_selection(text: String) -> void:
	var wanted := text.split(",", false)
	var size := 0 if characters == null else characters.count()
	if size <= 0:
		push_error("--capture-select needs a CharacterSet on the lobby")
		return

	for index in mini(wanted.size(), roster.count()):
		var target := clampi(int(wanted[index]), 0, size - 1)
		var device: int = roster.devices[index]
		# Bounded by the catalogue: stepping wraps, so the target is reachable
		# within one lap and a typo cannot spin here for ever.
		for _step in size:
			if roster.pick_of(index) == target:
				break
			roster.select_next(device)

		# Through the same follow the stick goes through, or a capture parks a
		# cursor on a row the rack is not showing and photographs a screen no
		# player could ever produce.
		_follow_cursor(roster.pick_of(index))

## --capture-scroll=0,3 scrolls player N's panel down N lines. The right stick
## is the same hole every selected, hovered or focused state falls into: nobody
## is holding it during a capture, so without this the panel can only ever be
## photographed at the top and a broken clamp would never show up.
##
## Set on the VIEW's line counter rather than on the accumulator, so a capture
## cannot ask for a scroll the panel would refuse a player.
func _apply_capture_scroll(text: String) -> void:
	var wanted := text.split(",", false)
	for index in mini(wanted.size(), roster.count()):
		var lines := clampi(int(wanted[index]), 0, _join_view.max_scroll_for(index))
		_scroll[index] = float(lines)
		_join_view.scroll_lines[index] = lines
	_join_view.queue_redraw()

func _start_lobby_capture(args: PackedStringArray) -> void:
	var output_dir := ""
	for arg in args:
		if arg.begins_with("--capture-dir="):
			output_dir = arg.substr("--capture-dir=".length())
	if output_dir.is_empty():
		push_error("--capture-lobby needs --capture-dir=<path>")
		return

	var capture := DebugCapture.new()
	capture.output_dir = output_dir
	capture.interval = 0.5
	capture.shot_count = 2
	for arg in args:
		if arg.begins_with("--capture-shots="):
			capture.shot_count = int(arg.substr("--capture-shots=".length()))
		elif arg.begins_with("--capture-interval="):
			capture.interval = float(arg.substr("--capture-interval=".length()))
		elif arg.begins_with("--capture-delay="):
			capture.start_delay = float(arg.substr("--capture-delay=".length()))

	capture.state_provider = _describe_state
	capture.finished.connect(func() -> void: get_tree().quit())
	add_child(capture)
	capture.start()

func _describe_state() -> String:
	# The picks are printed as NAMES rather than indices: a shot of the screen
	# and a line reading "0 1 2" cannot together say whether the third slot drew
	# the third character or the first one twice.
	var picked: Array[String] = []
	for index in roster.count():
		var character := roster.character_at(index)
		picked.append("none" if character == null else character.display_key)

	var locked: Array[String] = []
	for index in roster.count():
		locked.append("yes" if roster.is_confirmed(index) else "no")

	return "lobby players=%d devices=%s characters=%s confirmed=%s pads=%d run=%s" % [
		roster.count(), str(roster.devices), str(picked), str(locked),
		Input.get_connected_joypads().size(), "yes" if _run != null else "no",
	]
