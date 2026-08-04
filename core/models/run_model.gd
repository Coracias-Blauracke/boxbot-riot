class_name RunModel
extends RefCounted

## One playthrough: the arena, the players, the wave loop and all randomness.
##
## Deliberately emits its own signals rather than touching the EventBus autoload.
## That keeps core/ runnable headless - the scene layer bridges these to the bus.

signal phase_changed(phase: WorldTypes.Phase)
signal wave_started(wave_number: int, spawn_boss: bool)
signal wave_ended(wave_number: int)

var rng: RunRandom
var world: WorldModel
var overrides: WorldOverrides
var director: WaveDirector

var players: Array[EntityModel] = []
var wave_number: int = 0
var total_waves: int = 20
var phase: WorldTypes.Phase = WorldTypes.Phase.PREPARING

## Outcome of the CALCULATE_WAVE pipeline for the wave now in progress; the
## spawner reads this rather than having to catch the signal.
var spawn_boss_this_wave: bool = false

func _init(run_seed: int = 0, world_data: WorldData = null, wave_table: WaveTable = null) -> void:
	rng = RunRandom.new(run_seed)
	world = WorldModel.new(world_data)
	overrides = WorldOverrides.new(rng)
	overrides.resolved.connect(_on_override_resolved)

	director = WaveDirector.new()
	director.table = wave_table

## Players share one RunRandom so the whole run stays reproducible from one seed.
func add_player(player: EntityModel) -> int:
	var index := players.size()
	players.append(player)
	player.rng = rng
	return index

# --- wave loop -------------------------------------------------------------

func start_wave() -> void:
	wave_number += 1
	phase = WorldTypes.Phase.COMBAT

	var event := WaveEvent.new()
	event.wave_number = wave_number
	event.context["run"] = self

	# WAVE-scoped counters reset here; RUN-scoped ones carry on.
	for player in players:
		player.counters.reset_scope(CounterTypes.Scope.WAVE)

	# Pipeline first, so effects can influence how the wave is built. Two
	# players each carrying "10% chance of a boss" roll independently - this is
	# a probability, not a discrete override, so it never goes through
	# WorldOverrides.
	for player in players:
		player.pipeline(Hooks.Hook.CALCULATE_WAVE, event)

	spawn_boss_this_wave = event.spawn_boss
	director.begin(wave_number)

	for player in players:
		player.notify(Hooks.Hook.ON_WAVE_STARTED, event)

	phase_changed.emit(phase)
	wave_started.emit(wave_number, event.spawn_boss)

func end_wave() -> void:
	var event := WaveEvent.new()
	event.wave_number = wave_number
	event.context["run"] = self

	for player in players:
		player.counters.add(CounterTypes.Counter.WAVES_SURVIVED)
		player.notify(Hooks.Hook.ON_WAVE_ENDED, event)

	wave_ended.emit(wave_number)

	if wave_number >= total_waves:
		phase = WorldTypes.Phase.FINISHED
		phase_changed.emit(phase)
	else:
		open_shop()

func open_shop() -> void:
	phase = WorldTypes.Phase.SHOP
	for player in players:
		player.notify(Hooks.Hook.ON_SHOP_OPENED, EventPayload.new())
	phase_changed.emit(phase)

func close_shop() -> void:
	for player in players:
		player.notify(Hooks.Hook.ON_SHOP_CLOSED, EventPayload.new())
	phase = WorldTypes.Phase.PREPARING
	phase_changed.emit(phase)

## Advances the wave and returns whatever should spawn this frame. Ends the wave
## on its own once the timer runs out.
##
## Note it does NOT tick statuses: in the running game each actor ticks its own,
## and doing it here as well would advance every player's statuses twice.
func advance_wave(delta: float) -> Array[EnemyData]:
	if phase != WorldTypes.Phase.COMBAT:
		return []

	var spawns := director.advance(delta, rng)
	if director.is_finished():
		end_wave()
	return spawns

func wave_time_remaining() -> float:
	return director.time_remaining()

## For headless tests, where there are no actor nodes to tick themselves.
func tick_statuses(delta: float) -> void:
	for player in players:
		player.tick_statuses(delta)

# --- world overrides -------------------------------------------------------

## Called by WORLD-scoped effects that demand a discrete arena property.
func claim_world_shape(new_shape: WorldTypes.MapShape, source: Variant, player_index: int) -> void:
	overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, new_shape, source, player_index)

func _on_override_resolved(key: StringName, winner: Variant, _was_contested: bool) -> void:
	if key != WorldTypes.OVERRIDE_MAP_SHAPE:
		return
	world.set_shape(winner if winner != null else WorldTypes.MapShape.RECTANGLE)
