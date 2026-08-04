extends Node2D

## Vertical slice: arena, one player, chasing enemies, contact damage, death.
##
## Also the only place that knows how a model is paired with a node: the spawner
## builds the model and injects it. Nodes never create their own.

const CHARACTER_SCENE := preload("res://scenes/actors/character.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")

@export var world_data: WorldData
@export var character_data: CharacterData
@export var enemy_data: EnemyData
@export var enemy_count: int = 8

var run: RunModel
var player: Character

@onready var _arena: Arena = $Arena
@onready var _actors: Node2D = $Actors

func _ready() -> void:
	run = RunModel.new(20260804, world_data)
	_arena.bind(run.world)

	player = _spawn_player()
	for i in enemy_count:
		_spawn_enemy()

	run.start_wave()
	print("wave %d started, boss=%s" % [run.wave_number, run.spawn_boss_this_wave])

	_maybe_start_capture()

func _spawn_player() -> Character:
	var model := EntityModel.new(character_data)
	run.add_player(model)

	var node := CHARACTER_SCENE.instantiate() as Character
	# bind() before add_child(): _ready() sizes the colliders from the data.
	node.bind(model, character_data, run.world)
	node.position = Vector2.ZERO
	_actors.add_child(node)
	return node

func _spawn_enemy() -> Enemy:
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
	# --capture-still keeps the player put, which is the only way to observe
	# contact damage: enemies are slower and never catch a running player.
	var direction := Vector2.ZERO if args.has("--capture-still") else Vector2(1.0, -0.35).normalized()
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
	capture.state_provider = _describe_state
	capture.finished.connect(func() -> void: get_tree().quit())
	add_child(capture)
	capture.start()

func _describe_state() -> String:
	if player == null or not is_instance_valid(player):
		return "player is dead, enemies=%d" % _count_enemies()
	return "player=(%.0f,%.0f) hp=%.0f/%.0f enemies=%d nearest=%.0f" % [
		player.global_position.x,
		player.global_position.y,
		player.model.current_hp,
		player.model.get_max_hp(),
		_count_enemies(),
		_nearest_enemy_distance(),
	]
