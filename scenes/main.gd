extends Node2D

## Vertical slice: arena, one player, chasing enemies, contact damage, death.
##
## Also the only place that knows how a model is paired with a node: the spawner
## builds the model and injects it. Nodes never create their own.

const CHARACTER_SCENE := preload("res://scenes/actors/character.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")

## Asked of whoever owns this scene, so the lobby can rebuild the run with the
## SAME roster instead of reloading the tree and losing who was playing.
##
## Falls back to reload_current_scene() when nobody is listening, which keeps
## main.tscn independently launchable - every capture command in CLAUDE.md
## points straight at it, and none of them should need a lobby.
signal restart_requested

@export var world_data: WorldData

## The character everybody plays when the lobby has not said otherwise. Kept as
## a single export precisely so main.tscn stays launchable on its own - every
## capture command in CLAUDE.md points straight at it and none of them should
## need a select screen in front.
@export var character_data: CharacterData
@export var wave_table: WaveTable
@export var shop_data: ShopData
@export var stat_sheet: StatSheet

## Which weapon classes exist and what holding several is worth. Injected into
## every player model, because core/ may not load content itself.
@export var weapon_classes: WeaponClassSet

## Local co-op, up to four. Player 0 takes keyboard and the first gamepad;
## the rest take a gamepad each.
@export_range(1, 4) var player_count: int = 1

## Which device drives which player: -1 is the keyboard, 0 and up are gamepads,
## one entry per player in order.
##
## An ARRAY rather than a rule, because no rule survives contact with a real
## couch. Three pads and one keyboard is an ordinary case, and deriving the
## device from the player index cannot express it - the keyboard player and the
## first pad player collide on the same slot. Left empty, it falls back to the
## old behaviour so nothing has to be authored to launch.
##
## This is the placeholder for a join flow, which is still a known gap: the real
## version assigns a device when somebody presses a button to join.
@export var player_devices: Array[int] = []

## Which character each player is playing, index-aligned with player_devices and
## injected by the lobby's select screen.
##
## An ARRAY beside character_data rather than instead of it, exactly as
## player_devices sits beside its own fallback: a short or empty list means the
## run was not composed by a lobby, and every player it does not name keeps the
## authored character. A run is therefore never half-described - which is the
## whole reason the lobby owns the run and not the other way round.
@export var player_characters: Array[CharacterData] = []

## What happens to a player who runs out of health. A permadeath challenge is
## this dropdown and nothing else - see RunTypes.DeathRule.
@export var death_rule: RunTypes.DeathRule = RunTypes.DeathRule.REVIVE_NEXT_WAVE

## Share of max HP a revived player stands up on. Exposed alongside death_rule
## because the two are one decision: a rule that revives and a cost of being
## revived. Leaving this reachable only from core/ made half the knob authored
## and half of it welded shut.
@export_range(0.05, 1.0, 0.05) var revive_hp_fraction: float = 0.5

## 0 draws a fresh seed every run. A FIXED value makes a run reproducible, which
## is what every A/B capture in this repo depends on - the co-op scaling
## measurement and the camera framing comparison are both worthless without it.
## Keep it set while developing; ship with 0.
##
## RESTART OBEYS THIS AND DOES NOT WORK AROUND IT. Reloading the scene reads the
## export again, so a fixed seed replays the same run - which is what a fixed
## seed is for: dying on wave 4 and immediately trying that exact wave 4 again.
## A restart that quietly reseeded would take away the only tool for retrying
## one situation, and the way to get a different run is already the authored 0.
@export var run_seed: int = 20260804

var run: RunModel
var players: Array[Character] = []

## Player 0. Kept for the debug readout and the scripted capture runs.
var player: Character

## Players driven in a circle by the capture runs. One entry per player rather
## than a single flag, because the interesting co-op states need different
## players doing different things at once.
## Used when neither the WaveEntry nor the WaveTable names a pattern. Without
## it, a table authored before patterns existed would spawn nothing at all and
## never say why.
var _fallback_pattern: SpawnPattern = SpawnRing.new()

## Capture only. 0 leaves RunModel's own value alone.
var _forced_intermission: float = 0.0
var _capture_shop_owned: bool = false
var _capture_shop_menu: bool = false

## Capture only, in seconds from startup.
##
## A LIST because each entry TOGGLES: repeating the flag is what makes resuming
## observable at all. One entry freezes the run and every shot after it reads
## the same numbers, which proves nothing about getting going again.
var _capture_pause_at: Array[float] = []

## Capture only, seconds from startup. 0 is off.
var _capture_restart_at: float = 0.0

## How many times this process has restarted. STATIC because the whole point of
## a restart is that everything else is thrown away - an instance variable would
## come back as 0 and --capture-restart would reload for ever.
static var _restarts: int = 0

var _circling: Array[Character] = []
var _elapsed: float = 0.0

## Radians per second the circling players turn at. Speed divided by this is the
## radius they trace, and the radius decides whether they kite or get eaten:
## at 1.6 it is ~137 units, tight enough to stay inside the swarm, which is what
## makes --capture-circle a separation test. --capture-downed needs the opposite
## and turns slower, so the survivors outrun the horde long enough for the wave
## to end and the revive to happen on camera.
var _circle_rate: float = 1.6

@onready var _arena: Arena = $Arena
@onready var _actors: Node2D = $Actors
@onready var _camera: ArenaCamera = $Camera2D
@onready var _hud: Hud = $Hud
@onready var _shop_screen: ShopScreen = $ShopScreen
@onready var _pause_screen: PauseScreen = $PauseScreen

func _ready() -> void:
	# Capture runs override the scene's player count, so a co-op state can be
	# photographed without editing main.tscn for every run and remembering to
	# put it back.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-players="):
			player_count = clampi(int(arg.substr("--capture-players=".length())), 1, 4)
		# Framing is a feel decision that cannot be settled from a table, so it
		# has to be A/B-able: same seed, same scripted motion, same shot timings,
		# one variable changed. Both knobs are needed because group_margin caps
		# how far default_zoom can actually go - see ArenaCamera.
		elif arg.begins_with("--capture-zoom="):
			_camera.default_zoom = float(arg.substr("--capture-zoom=".length()))
		elif arg.begins_with("--capture-margin="):
			_camera.group_margin = float(arg.substr("--capture-margin=".length()))
		elif arg == "--capture-shop-menu":
			# Parks the cursor AND opens the tile menu on it.
			_capture_shop_owned = true
			_capture_shop_menu = true
		elif arg == "--capture-shop-owned":
			# A UI state that needs input cannot otherwise be photographed at
			# all, which is a real hole in how this repo verifies the scene
			# layer. This parks every shop cursor on the owned strip instead.
			_capture_shop_owned = true
		elif arg.begins_with("--capture-intermission="):
			# The shop phase is four seconds, which is not long enough to
			# reliably photograph. Holding it open is the only way to read the
			# panel at each player count.
			_forced_intermission = float(arg.substr("--capture-intermission=".length()))
		elif arg.begins_with("--capture-pause="):
			# Same hole as --capture-shop-owned: a screen that only opens when
			# somebody presses a button cannot be photographed by a run with
			# nobody at the controls.
			_capture_pause_at.append(float(arg.substr("--capture-pause=".length())))
		elif arg.begins_with("--capture-restart="):
			_capture_restart_at = float(arg.substr("--capture-restart=".length()))

	run = RunModel.new(run_seed, world_data, wave_table)
	run.death_rule = death_rule
	run.revive_hp_fraction = revive_hp_fraction
	run.shop_data = shop_data
	# A capture run has nobody to press ready, so it would sit in the shop
	# forever. Any capture gets a default; --capture-intermission overrides it.
	if _forced_intermission > 0.0:
		run.auto_intermission = _forced_intermission
	elif OS.get_cmdline_user_args().has("--capture"):
		run.auto_intermission = 3.0
	run.wave_ended.connect(_on_wave_ended)
	run.run_ended.connect(_on_run_ended)
	_arena.bind(run.world)
	_camera.bind(run.world)

	for index in player_count:
		players.append(_spawn_player(index))
	player = players[0]

	# After the players exist, so every panel has a model to read from the
	# first frame instead of drawing an empty corner for one.
	var models: Array[EntityModel] = []
	for entry in players:
		models.append(entry.model)
	_hud.bind(run, models)
	_shop_screen.bind(run, players, stat_sheet)
	if _capture_shop_owned:
		_shop_screen.park_cursor_on_owned(_capture_shop_menu)

	# Every device, because the pause menu is one menu for the whole couch - see
	# PauseScreen for why it is not owned by whoever opened it.
	var inputs: Array[PlayerInput] = []
	for entry in players:
		inputs.append(entry.input)
	_pause_screen.bind(run, inputs)
	_pause_screen.restart_requested.connect(_restart)
	_pause_screen.quit_requested.connect(_quit)

	run.start_wave()
	print("wave %d started, boss=%s, duration=%.0fs, restarts=%d" % [
		run.wave_number, run.spawn_boss_this_wave, run.director.duration, _restarts
	])

	_schedule_capture_events()
	_maybe_start_capture()

# --- restart ---------------------------------------------------------------

## A scene reload, which is only honest because nothing outlives the scene:
## there are no autoloads and every model hangs off the RunModel built in
## _ready. The day something does outlive it, this starts leaking state into
## the next run silently, which is why it is worth writing down.
func _restart() -> void:
	print("restart requested on wave %d, phase=%s" % [run.wave_number, _phase_name()])
	_restarts += 1
	# Unpaused FIRST. The flag lives on the TREE, not on the scene, so it
	# survives a reload and the fresh run would come up frozen with nothing on
	# screen to say why.
	get_tree().paused = false

	# The lobby rebuilds this node with the roster it still holds. Reloading the
	# whole tree would take the lobby with it and every player would have to
	# join again after every death, which is the opposite of what a restart is
	# for during a play-test.
	if not restart_requested.get_connections().is_empty():
		restart_requested.emit()
		return

	get_tree().reload_current_scene()

func _quit() -> void:
	get_tree().paused = false
	get_tree().quit()

## Capture only. Both of these exist because a screen reached by pressing a
## button is invisible to a run with nobody pressing anything.
func _schedule_capture_events() -> void:
	# request_toggle rather than open: the capture has to go through the same
	# gate the button does, or it can photograph a state no player could reach.
	for at in _capture_pause_at:
		if at > 0.0:
			get_tree().create_timer(at).timeout.connect(_pause_screen.request_toggle)
	# Once per process. Without the guard the reloaded scene reads the same
	# command line and restarts again, for ever.
	if _capture_restart_at > 0.0 and _restarts == 0:
		get_tree().create_timer(_capture_restart_at).timeout.connect(_restart)

func _physics_process(delta: float) -> void:
	if run == null:
		return
	for group in run.advance_wave(delta):
		_spawn_group(group)

## The wave ends on its timer, so whatever is still standing is cleared rather
## than left for the player to hunt down one straggler at a time.
func _on_wave_ended(_wave_number: int) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node).queue_free()
	print("wave %d ended, currency=%d" % [run.wave_number, player.model.get_currency() if is_instance_valid(player) else 0])

## The corpses stay on the floor - clearing them would undo the whole point of
## not freeing a downed player. Only the horde is cleared.
func _on_run_ended(outcome: RunTypes.Outcome) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node).queue_free()
	print("run ended: %s on wave %d" % [
		"VICTORY" if outcome == RunTypes.Outcome.VICTORY else "DEFEAT", run.wave_number
	])

## Which chassis player `index` is in. The lobby's answer when it gave one, the
## authored fallback otherwise - see player_characters.
func _character_for(index: int) -> CharacterData:
	if index < player_characters.size() and player_characters[index] != null:
		return player_characters[index]
	return character_data

func _spawn_player(index: int) -> Character:
	var character := _character_for(index)
	var model := EntityModel.new(character)
	# Before any weapon arrives, so the starting loadout is counted too - though
	# the recompute is idempotent either way.
	model.weapon_classes = weapon_classes
	run.add_player(model)

	var node := CHARACTER_SCENE.instantiate() as Character
	# bind() before add_child(): _ready() sizes the colliders from the data.
	node.bind(model, character, run.world)
	node.player_index = index

	node.input = _device_for(index)
	node.motion = MotionSource.FromInput.new(node.input)

	# Spread them out so they do not start stacked on one another.
	node.position = (
		Vector2.ZERO
		if player_count == 1
		else Vector2.RIGHT.rotated(TAU * float(index) / float(player_count)) * 60.0
	)
	_actors.add_child(node)

	# Granted through the normal inventory path, so they show in the owned strip,
	# describe themselves like any purchase and can be sold.
	for item in character.starting_items:
		if item != null:
			model.add_item(item)

	# Same for the loadout, and from the CHARACTER rather than from an export on
	# this scene. The rack in the hands follows the model, so nothing here has to
	# tell the view about them.
	for weapon_data in character.starting_weapons:
		if weapon_data != null:
			model.add_weapon(weapon_data)

	return node

## Places a whole group at once, asking its SpawnPattern where.
##
## The pattern lives in core/ and takes plain numbers, so this stays the only
## place that knows a camera exists. It is also why the group survives as a
## group: one call, one anchor, the cluster arrives together.
## Authored assignment when there is one, otherwise the old rule: player 0 takes
## the keyboard AND the first pad, everyone after takes the pad matching their
## index.
##
## That fallback is exactly what player_devices exists to escape - it cannot
## express three pads and one keyboard, because the keyboard player is also
## holding pad 0. It stays only so the game launches with nothing authored.
func _device_for(index: int) -> PlayerInput:
	if index < player_devices.size():
		var id: int = player_devices[index]
		# Only the keyboard player also answers to the keyboard; giving it to a
		# second player would have two of them move on the same key.
		return PlayerInput.new(id, id == PlayerInput.KEYBOARD)

	if index == 0:
		return PlayerInput.new(0, true)
	return PlayerInput.new(index, false)

func _spawn_group(group: SpawnGroup) -> void:
	if group == null or group.enemy == null:
		return

	var pattern: SpawnPattern = group.pattern if group.pattern != null else _fallback_pattern
	for point in pattern.positions(_spawn_context(), group.count, run.rng):
		_spawn_enemy(group.enemy, point)

## Rebuilt per spawn event rather than cached. A stale view rectangle would
## place a group against a frame the camera has already left, which at speed
## puts them on screen.
func _spawn_context() -> SpawnContext:
	var context := SpawnContext.new()
	context.view_centre = _camera.global_position
	context.view_size = _camera.visible_world_size()
	context.world = run.world

	# LIVING players only. An ambush aimed at a corpse would arrive nowhere
	# near the people still playing.
	var living := PackedVector2Array()
	for entry in players:
		if is_instance_valid(entry) and entry.model != null and entry.model.is_alive:
			living.append(entry.global_position)
	context.player_positions = living

	return context

func _spawn_enemy(enemy_data: EnemyData, at: Vector2) -> Enemy:
	if enemy_data == null:
		return null

	var model := EntityModel.new(enemy_data)
	model.rng = run.rng
	# Registered where it is created. There is no unregister and there cannot be
	# one forgotten: the census holds weakrefs and prunes itself.
	run.census.register(model)

	var node := ENEMY_SCENE.instantiate() as Enemy
	# No target assigned: the enemy picks the nearest living player itself, and
	# keeps re-picking as they move apart.
	node.bind(model, enemy_data, run.world)
	# Through the model, exactly as a character's loadout is, so the rack in the
	# mandibles follows the same path the rack in the hands does.
	for weapon_data in enemy_data.weapons:
		if weapon_data != null:
			model.add_weapon(weapon_data)
	node.position = at
	_actors.add_child(node)
	return node

## Largest gap between where an actor IS and where its model says it is.
##
## The number that says whether core/ can do geometry at all. Everything spatial
## in core/ - the census, a status spreading off a corpse, an explosion - reads
## EntityModel.world_position, and nothing in the running game wrote it: every
## entity sat at the origin, so "within 90 units" was true of the whole arena and
## burn spread to three arbitrary enemies at any distance. A screenshot cannot
## show that and neither can a count, because both look exactly right.
##
## 0 means the view is publishing. Anything else is the old bug returning.
func _max_position_drift() -> float:
	var worst := 0.0
	for child in _actors.get_children():
		var actor := child as Actor
		if actor == null or actor.model == null:
			continue
		worst = maxf(worst, actor.global_position.distance_to(actor.model.world_position))
	return worst

func _count_enemies() -> int:
	var total := 0
	for child in _actors.get_children():
		if child is Enemy:
			total += 1
	return total

func _nearest_enemy_distance() -> float:
	var nearest := INF
	for child in _actors.get_children():
		if child is Enemy:
			nearest = minf(nearest, player.global_position.distance_to((child as Node2D).global_position))
	return nearest

## Smallest gap between any two enemies - the number that tells you whether
## separation is working. Without it a swarm collapses towards zero.
func _min_enemy_gap() -> float:
	var enemies: Array[Node2D] = []
	for child in _actors.get_children():
		if child is Enemy:
			enemies.append(child as Node2D)

	var smallest := INF
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			smallest = minf(smallest, enemies[i].global_position.distance_to(enemies[j].global_position))
	return smallest if smallest < INF else 0.0

# --- debug capture ---------------------------------------------------------

func _maybe_start_capture() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture"):
		return

	var output_dir := ""
	for arg in args:
		if arg.begins_with("--capture-dir="):
			output_dir = arg.substr("--capture-dir=".length())
	if output_dir.is_empty():
		push_error("--capture needs --capture-dir=<path>")
		return

	# A restarted pass writes beside the first one rather than over it. The two
	# sets of PNGs ARE the evidence that a restart produced a fresh run, so one
	# overwriting the other would destroy the measurement it was taken for.
	if _restarts > 0:
		output_dir = output_dir.path_join("after_restart")
		DirAccess.make_dir_recursive_absolute(output_dir)

	# Deterministic input, so a recorded run is reproducible.
	#   --capture-still  keeps the player put; the only way to observe contact
	#                    damage, since enemies never catch a running player.
	#   --capture-circle runs in circles, which is what makes a swarm without
	#                    separation collapse into a single dot.
	var direction := Vector2.ZERO if args.has("--capture-still") else Vector2(1.0, -0.35).normalized()
	if args.has("--capture-circle"):
		direction = Vector2.RIGHT

	# --capture-scatter drives every player towards a different corner, which is
	# how the co-op framing gets checked: if the camera only held one of them,
	# the others would leave the frame.
	if args.has("--capture-scatter"):
		for index in players.size():
			var away := Vector2.RIGHT.rotated(TAU * float(index) / float(players.size()) + 0.6)
			players[index].motion = MotionSource.Scripted.new(away)
	elif args.has("--capture-downed"):
		# Player 0 stands still and is killed; everyone else circles nearby and
		# lives. The only way to photograph ONE player down while the run carries
		# on - which is the whole state the corner panels, the corpse rendering
		# and RunTypes.DeathRule exist for. --capture-still cannot produce it,
		# because it kills everybody at once and ends the run.
		players[0].motion = MotionSource.Scripted.new(Vector2.ZERO)
		_circle_rate = 0.55
		for index in range(1, players.size()):
			players[index].motion = MotionSource.Scripted.new(Vector2.RIGHT)
			_circling.append(players[index])
	else:
		player.motion = MotionSource.Scripted.new(direction)
		if args.has("--capture-circle"):
			_circling.append(player)

	var capture := DebugCapture.new()
	capture.output_dir = output_dir
	capture.interval = 0.6
	capture.shot_count = 5
	for arg in args:
		if arg.begins_with("--capture-shots="):
			capture.shot_count = int(arg.substr("--capture-shots=".length()))
		elif arg.begins_with("--capture-interval="):
			capture.interval = float(arg.substr("--capture-interval=".length()))
		elif arg.begins_with("--capture-delay="):
			capture.start_delay = float(arg.substr("--capture-delay=".length()))
	capture.state_provider = _describe_state
	# The pass BEFORE a scheduled restart must not close the window when it runs
	# out of shots, or it takes the restart down with it and the second half of
	# the comparison is never taken. Measured: the run quit at 11s and the
	# restart was scheduled for 12s.
	if _capture_restart_at <= 0.0 or _restarts > 0:
		capture.finished.connect(func() -> void: get_tree().quit())
	add_child(capture)
	capture.start()

func _process(delta: float) -> void:
	if _circling.is_empty():
		return
	_elapsed += delta
	# Spaced around the circle so two circling players do not overlap into one
	# blob and hide whichever bug the capture was taken to look for.
	for index in _circling.size():
		var scripted := _circling[index].motion as MotionSource.Scripted
		if scripted != null:
			scripted.direction = Vector2.RIGHT.rotated(
				_elapsed * _circle_rate + TAU * float(index) / float(_circling.size())
			)

func _count_projectiles() -> int:
	var total := 0
	for child in _actors.get_children():
		if child is Projectile:
			total += 1
	return total

func _describe_state() -> String:
	if player == null or not is_instance_valid(player):
		return "player node is gone, enemies=%d" % _count_enemies()

	# One entry per player: position, health and their own currency, so co-op
	# runs show whether anything is shared that should not be.
	var per_player := ""
	for index in players.size():
		var entry := players[index]
		if entry == null or not is_instance_valid(entry):
			per_player += " p%d=GONE" % index
			continue

		# DOWN rather than "hp0". The whole point of the change is that a player
		# model outlives its own death, so a capture has to be able to tell "at
		# zero health, still in the run" from "no longer here at all".
		# The rack as the MODEL sees it and as the mount actually built it, both.
		# They are the same number only if the view really is following the
		# model - which is the whole claim weapons in the shop rest on, and a
		# single count could not tell a working sync from a stale one.
		# The CHASSIS by name, because a capture of four players on four different
		# characters and one of four players on the same character four times are
		# the same picture: four boxes. Only the numbers can tell them apart.
		per_player += " p%d=%s(%.0f,%.0f)%s$%d wp%d/%d" % [
			index,
			"?" if entry.data == null else entry.data.display_key,
			entry.global_position.x,
			entry.global_position.y,
			"hp%.0f" % entry.model.current_hp if entry.model.is_alive else "DOWN",
			entry.model.get_currency(),
			entry.model.weapons.size(),
			entry.get_weapons().size(),
		]

	return "w%d %s t-%.0fs alive=%d/%d enemies=%d drift=%.0f bleed=%d burn=%d shots=%d zoom=%.2f%s" % [
		run.wave_number,
		_phase_name(),
		run.wave_time_remaining(),
		run.living_player_count(),
		players.size(),
		_count_enemies(),
		_max_position_drift(),
		# Straight off the census, so a status that is not landing is visible in
		# the numbers rather than only in a screenshot.
		run.census.count_with_status(&"bleed"),
		run.census.count_with_status(&"burn"),
		_count_projectiles(),
		_camera.zoom.x,
		per_player,
	]

func _phase_name() -> String:
	match run.phase:
		WorldTypes.Phase.COMBAT:
			return "combat"
		WorldTypes.Phase.SHOP:
			return "shop"
		WorldTypes.Phase.FINISHED:
			return "VICTORY" if run.outcome == RunTypes.Outcome.VICTORY else "DEFEAT"
		_:
			return "prep"
