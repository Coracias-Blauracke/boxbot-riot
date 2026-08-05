extends Node2D

## Vertical slice: arena, one player, chasing enemies, contact damage, death.
##
## Also the only place that knows how a model is paired with a node: the spawner
## builds the model and injects it. Nodes never create their own.

const CHARACTER_SCENE := preload("res://scenes/actors/character.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")

@export var world_data: WorldData
@export var character_data: CharacterData
@export var wave_table: WaveTable
@export var starting_weapons: Array[WeaponData] = []

## Local co-op, up to four. Player 0 takes keyboard and the first gamepad;
## the rest take a gamepad each.
@export_range(1, 4) var player_count: int = 1

## What happens to a player who runs out of health. A permadeath challenge is
## this dropdown and nothing else - see RunTypes.DeathRule.
@export var death_rule: RunTypes.DeathRule = RunTypes.DeathRule.REVIVE_NEXT_WAVE

var run: RunModel
var players: Array[Character] = []

## Player 0. Kept for the debug readout and the scripted capture runs.
var player: Character

## Players driven in a circle by the capture runs. One entry per player rather
## than a single flag, because the interesting co-op states need different
## players doing different things at once.
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

func _ready() -> void:
	# Capture runs override the scene's player count, so a co-op state can be
	# photographed without editing main.tscn for every run and remembering to
	# put it back.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-players="):
			player_count = clampi(int(arg.substr("--capture-players=".length())), 1, 4)

	run = RunModel.new(20260804, world_data, wave_table)
	run.death_rule = death_rule
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

	run.start_wave()
	print("wave %d started, boss=%s, duration=%.0fs" % [
		run.wave_number, run.spawn_boss_this_wave, run.director.duration
	])

	_maybe_start_capture()

func _physics_process(delta: float) -> void:
	if run == null:
		return
	for enemy_data in run.advance_wave(delta):
		_spawn_enemy(enemy_data)

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

func _spawn_player(index: int) -> Character:
	var model := EntityModel.new(character_data)
	run.add_player(model)

	var node := CHARACTER_SCENE.instantiate() as Character
	# bind() before add_child(): _ready() sizes the colliders from the data.
	node.bind(model, character_data, run.world)
	node.player_index = index

	# Player 0 keeps keyboard plus the first pad; everyone else gets one pad.
	if index > 0:
		node.motion = MotionSource.Device.new(index)

	# Spread them out so they do not start stacked on one another.
	node.position = (
		Vector2.ZERO
		if player_count == 1
		else Vector2.RIGHT.rotated(TAU * float(index) / float(player_count)) * 60.0
	)
	_actors.add_child(node)

	for weapon_data in starting_weapons:
		if weapon_data != null:
			node.equip(weapon_data)

	return node

func _spawn_enemy(enemy_data: EnemyData) -> Enemy:
	if enemy_data == null or player == null or not is_instance_valid(player):
		return null

	var model := EntityModel.new(enemy_data)
	model.rng = run.rng

	var node := ENEMY_SCENE.instantiate() as Enemy
	node.bind(model, enemy_data, run.world)
	# No target assigned: the enemy picks the nearest living player itself, and
	# keeps re-picking as they move apart.
	node.position = _enemy_spawn_position()
	_actors.add_child(node)
	return node

## Just beyond the edge of what is on screen, not at the arena wall.
##
## The arena is much larger than the view now, so spawning at the wall would
## have enemies walking in from off-map for ten seconds before they threatened
## anybody. They should arrive from just out of sight instead.
func _enemy_spawn_position() -> Vector2:
	var view := _camera.visible_world_size()
	var centre := _camera.global_position
	# Past the corner of the view, so nothing pops into existence on screen.
	var ring := view.length() * 0.5 * 1.12

	for attempt in 8:
		var angle := run.rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
		var candidate := centre + Vector2.RIGHT.rotated(angle) * ring

		if run.world.is_inside(candidate):
			return candidate

		# Outside the arena: pull it back to the wall and take it only if that
		# still leaves it off screen. Near a corner most angles fail this.
		var clamped := run.world.clamp_to_bounds(candidate)
		var offset := clamped - centre
		if absf(offset.x) > view.x * 0.5 or absf(offset.y) > view.y * 0.5:
			return clamped

	# Boxed in on every side - fall back to the arena rim.
	return run.world.random_point_on_edge(run.rng)

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
		per_player += " p%d=(%.0f,%.0f)%s$%d" % [
			index,
			entry.global_position.x,
			entry.global_position.y,
			"hp%.0f" % entry.model.current_hp if entry.model.is_alive else "DOWN",
			entry.model.get_currency(),
		]

	return "w%d %s t-%.0fs alive=%d/%d enemies=%d shots=%d zoom=%.2f%s" % [
		run.wave_number,
		_phase_name(),
		run.wave_time_remaining(),
		run.living_player_count(),
		players.size(),
		_count_enemies(),
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
