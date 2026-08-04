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

var run: RunModel
var player: Character

var _circle_mode: bool = false
var _elapsed: float = 0.0

@onready var _arena: Arena = $Arena
@onready var _actors: Node2D = $Actors

func _ready() -> void:
	run = RunModel.new(20260804, world_data, wave_table)
	run.wave_ended.connect(_on_wave_ended)
	_arena.bind(run.world)

	player = _spawn_player()

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

func _spawn_player() -> Character:
	var model := EntityModel.new(character_data)
	run.add_player(model)

	var node := CHARACTER_SCENE.instantiate() as Character
	# bind() before add_child(): _ready() sizes the colliders from the data.
	node.bind(model, character_data, run.world)
	node.position = Vector2.ZERO
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
	node.target = player
	node.position = run.world.random_point_on_edge(run.rng)
	_actors.add_child(node)
	return node

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
	_circle_mode = args.has("--capture-circle")
	var direction := Vector2.ZERO if args.has("--capture-still") else Vector2(1.0, -0.35).normalized()
	if _circle_mode:
		direction = Vector2.RIGHT
	player.motion = MotionSource.Scripted.new(direction)

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
	if not _circle_mode or player == null or not is_instance_valid(player):
		return
	_elapsed += delta
	var scripted := player.motion as MotionSource.Scripted
	if scripted != null:
		scripted.direction = Vector2.RIGHT.rotated(_elapsed * 1.6)

func _count_projectiles() -> int:
	var total := 0
	for child in _actors.get_children():
		if child is Projectile:
			total += 1
	return total

func _describe_state() -> String:
	if player == null or not is_instance_valid(player):
		return "player is dead, enemies=%d" % _count_enemies()
	var swings := ""
	for weapon in player.get_weapons():
		swings += weapon.debug_swing_state()

	return "w%d t-%.0fs hp=%.0f/%.0f cur=%d enemies=%d nearest=%.0f shots=%d swing=[%s]" % [
		run.wave_number,
		run.wave_time_remaining(),
		player.model.current_hp,
		player.model.get_max_hp(),
		player.model.get_currency(),
		_count_enemies(),
		_nearest_enemy_distance(),
		_count_projectiles(),
		swings,
	]
