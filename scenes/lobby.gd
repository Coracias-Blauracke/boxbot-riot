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
	for index in mini(_inputs.size(), roster.count()):
		var input := _inputs[index]
		input.poll(_delta)
		if input.triggered(PlayerInput.Action.READY):
			start_run()
			return

		var device: int = roster.devices[index]
		# The same stick and the same repeat the shop cursor uses. A player who
		# learned to browse offers already knows how to browse a roster.
		if input.triggered(PlayerInput.Action.LEFT):
			roster.select_previous(device)
		elif input.triggered(PlayerInput.Action.RIGHT):
			roster.select_next(device)

## Any joined player may start it. Deliberately not "everybody must be ready":
## that is the shop's problem, where each player is spending their own money.
## Here there is one decision and the people are in the same room.
func start_run() -> void:
	if roster.is_empty() or _run != null:
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

func _on_roster_changed() -> void:
	_inputs.clear()
	for device in roster.devices:
		# also_keyboard stays FALSE here. A device belongs to one player in the
		# lobby by construction, and the keyboard-plus-pad-0 arrangement that
		# flag exists for is precisely what could not express three pads and a
		# keyboard. A solo toggle can hand it back later without changing this.
		_inputs.append(PlayerInput.new(device, false))

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

	# Keyboard first, then pads in order - what one keyboard player and a couch
	# of pads actually produces.
	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	for index in range(1, wanted):
		roster.join(index - 1)

	for arg in args:
		if arg.begins_with("--capture-select="):
			_apply_capture_selection(arg.substr("--capture-select=".length()))

	if args.has("--capture-lobby"):
		_start_lobby_capture(args)
		return

	start_run()

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

	return "lobby players=%d devices=%s characters=%s pads=%d run=%s" % [
		roster.count(), str(roster.devices), str(picked),
		Input.get_connected_joypads().size(), "yes" if _run != null else "no",
	]
