class_name RunModel
extends RefCounted

## One playthrough: the arena, the players, the wave loop and all randomness.
##
## Deliberately emits its own signals rather than touching the EventBus autoload.
## That keeps core/ runnable headless - the scene layer bridges these to the bus.

signal phase_changed(phase: WorldTypes.Phase)
signal wave_started(wave_number: int, spawn_boss: bool)
signal wave_ended(wave_number: int)
signal player_downed(player_index: int)
signal player_revived(player_index: int)
signal run_ended(outcome: RunTypes.Outcome)

var rng: RunRandom
var world: WorldModel
var overrides: WorldOverrides
var director: WaveDirector

var players: Array[EntityModel] = []

## ONE SHOP PER PLAYER, index-aligned with `players`. Not one shop shared four
## ways: each has its own offers, its own reroll count, its own readiness and
## its own RNG sub-stream. Everything below the shop was already built this way
## - currency is a per-entity counter and prices come out of a pipeline
## evaluated per buyer - so a single shared shop would have been the odd one out.
var shops: Array[ShopManager] = []

## Authored rules, shared by every player's shop. The DATA is common; nothing
## about the state is.
var shop_data: ShopData = null
var wave_number: int = 0
var total_waves: int = 20
var phase: WorldTypes.Phase = WorldTypes.Phase.PREPARING

## How death is handled. Changing this is the ENTIRE difference between the
## normal mode and a permadeath challenge - the wave loop below is shared.
var death_rule: RunTypes.DeathRule = RunTypes.DeathRule.REVIVE_NEXT_WAVE

## Share of max HP a revived player stands up on. Full would make going down
## free, and being downed is supposed to cost the team something.
var revive_hp_fraction: float = 0.5

var outcome: RunTypes.Outcome = RunTypes.Outcome.UNDECIDED

## Indices of players currently down. Under REVIVE_NEXT_WAVE this empties when
## the shop opens; under the other rules it only ever grows.
var _downed: Array[int] = []

## Outcome of the CALCULATE_WAVE pipeline for the wave now in progress; the
## spawner reads this rather than having to catch the signal.
var spawn_boss_this_wave: bool = false

## TEMPORARY. With no shop UI, nothing closes the shop and the run stops dead
## after wave one. A timed intermission keeps waves coming so the game can be
## played and tested. Set to 0 once the shop exists - it will then be closed by
## every player declaring themselves ready instead.
var auto_intermission: float = 4.0
var _intermission_left: float = 0.0

func _init(run_seed: int = 0, world_data: WorldData = null, wave_table: WaveTable = null) -> void:
	rng = RunRandom.new(run_seed)
	world = WorldModel.new(world_data)
	overrides = WorldOverrides.new(rng)
	overrides.resolved.connect(_on_override_resolved)

	director = WaveDirector.new()
	director.table = wave_table

	# Authored on the table, not hardcoded here. Still assignable afterwards so
	# tests and challenge modes can shorten a run without a second .tres.
	if wave_table != null:
		total_waves = wave_table.total_waves

## Players share one RunRandom so the whole run stays reproducible from one seed.
func add_player(player: EntityModel) -> int:
	var index := players.size()
	players.append(player)
	player.rng = rng
	# Note this does NOT close a reference cycle, despite RunModel holding the
	# player: a Godot signal connection stores the target by ObjectID, not as a
	# strong reference. That distinction matters here because RefCounted has no
	# cycle collector, so run_test.gd asserts it with a weakref rather than
	# taking it on trust.
	player.died.connect(_on_player_died)

	# Created here rather than when the shop opens, so the pairing with `players`
	# can never drift and player_index always matches the RNG sub-stream.
	var shop := ShopManager.new()
	shop.player_index = index
	shops.append(shop)

	return index

func shop_for(index: int) -> ShopManager:
	return shops[index] if index >= 0 and index < shops.size() else null

# --- death and the end of the run ------------------------------------------

func living_player_count() -> int:
	var alive := 0
	for player in players:
		if player.is_alive:
			alive += 1
	return alive

func is_player_downed(index: int) -> bool:
	return _downed.has(index)

func is_run_over() -> bool:
	return outcome != RunTypes.Outcome.UNDECIDED

## Scans rather than taking the dead player as an argument, because the signal
## carries no sender and two players can go down in the same frame - a shared
## explosion, or the last tick of a poison both are carrying.
func _on_player_died() -> void:
	for index in players.size():
		if players[index].is_alive or _downed.has(index):
			continue
		_downed.append(index)
		player_downed.emit(index)

	if is_run_over():
		return

	var lost := (
		not _downed.is_empty()
		if death_rule == RunTypes.DeathRule.SHARED_FATE
		else living_player_count() == 0
	)
	if lost:
		_finish(RunTypes.Outcome.DEFEAT)

## Under REVIVE_NEXT_WAVE the downed stand up when the shop opens, NOT when the
## next wave starts. They are out for the rest of the wave either way, and a
## player who cannot spend the currency they died holding falls further behind
## every wave - which is the spiral this rule exists to avoid.
func _revive_downed() -> void:
	if death_rule != RunTypes.DeathRule.REVIVE_NEXT_WAVE:
		return
	for index in _downed:
		players[index].revive(revive_hp_fraction)
		player_revived.emit(index)
	_downed.clear()

## The single choke point for ending a run, so the first outcome sticks. The
## last player can die on the very frame the director runs out of time, and a
## defeat must not then be overwritten by the victory that wave would have been.
func _finish(p_outcome: RunTypes.Outcome) -> void:
	if is_run_over():
		return
	outcome = p_outcome
	phase = WorldTypes.Phase.FINISHED
	phase_changed.emit(phase)
	run_ended.emit(outcome)

# --- wave loop -------------------------------------------------------------

func start_wave() -> void:
	if is_run_over():
		return

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
	# The player count is what scales the wave: more players means a bigger
	# budget AND more frequent arrivals, not the same wave shared out.
	director.begin(wave_number, players.size())

	for player in players:
		player.notify(Hooks.Hook.ON_WAVE_STARTED, event)

	phase_changed.emit(phase)
	wave_started.emit(wave_number, event.spawn_boss)

func end_wave() -> void:
	# The last player can die on the frame the director runs out of time. The
	# run is already lost by then and must not be handed a shop.
	if is_run_over():
		return

	var event := WaveEvent.new()
	event.wave_number = wave_number
	event.context["run"] = self

	# Only the living are credited with surviving. A corpse collecting
	# WAVES_SURVIVED would feed "every 5 waves, gain X" effects for free, and
	# under PERMANENT would go on doing so for the rest of the run.
	for player in players:
		if player.is_alive:
			player.counters.add(CounterTypes.Counter.WAVES_SURVIVED)
		player.notify(Hooks.Hook.ON_WAVE_ENDED, event)

	wave_ended.emit(wave_number)

	if wave_number >= total_waves:
		_finish(RunTypes.Outcome.VICTORY)
	else:
		open_shop()

func open_shop() -> void:
	phase = WorldTypes.Phase.SHOP
	_intermission_left = auto_intermission
	# Before everything else, so an effect hanging on ON_SHOP_OPENED sees a
	# living player rather than having to ask whether this one is a corpse - and
	# so a revived player gets a shop below.
	_revive_downed()

	for index in players.size():
		var shop := shops[index]
		shop.data = shop_data
		# A player still down does not get a shop. Under PERMANENT they never
		# will again, and rolling offers for a corpse would put a whole panel of
		# things on screen that nobody can buy.
		if players[index].is_alive:
			shop.open(players[index], wave_number, rng)
		else:
			shop.close()

	for player in players:
		player.notify(Hooks.Hook.ON_SHOP_OPENED, EventPayload.new())
	phase_changed.emit(phase)

func close_shop() -> void:
	for shop in shops:
		shop.close()
	for player in players:
		player.notify(Hooks.Hook.ON_SHOP_CLOSED, EventPayload.new())
	phase = WorldTypes.Phase.PREPARING
	phase_changed.emit(phase)

## Every LIVING player has to declare themselves ready.
##
## The living part matters: under PERMANENT a dead player can never press
## anything again, so counting them would hold the run hostage for the rest of
## it. Returns false when nobody is alive at all, because that is a lost run
## rather than a wave everyone is ready for.
func all_players_ready() -> bool:
	var any_living := false
	for index in players.size():
		if not players[index].is_alive:
			continue
		any_living = true
		if not shops[index].is_ready:
			return false
	return any_living

## The intended way out of the shop phase once there is a UI to press it.
## `auto_intermission` remains as the fallback until then.
func set_player_ready(index: int, value: bool) -> void:
	if index < 0 or index >= shops.size():
		return

	shops[index].set_ready(value)
	if phase == WorldTypes.Phase.SHOP and all_players_ready():
		close_shop()
		start_wave()

## Advances the wave and returns whatever should spawn this frame. Ends the wave
## on its own once the timer runs out.
##
## Note it does NOT tick statuses: in the running game each actor ticks its own,
## and doing it here as well would advance every player's statuses twice.
func advance_wave(delta: float) -> Array[SpawnGroup]:
	if phase == WorldTypes.Phase.SHOP and auto_intermission > 0.0:
		_intermission_left -= delta
		if _intermission_left <= 0.0:
			close_shop()
			start_wave()
		return []

	if phase != WorldTypes.Phase.COMBAT:
		return []

	var spawns := director.advance(delta, rng)
	if director.is_finished():
		end_wave()
	return spawns

func wave_time_remaining() -> float:
	return director.time_remaining()

## Seconds left of the shop phase. TEMPORARY in the same sense as
## auto_intermission: once the shop closes on every player declaring themselves
## ready, this becomes meaningless and the HUD should show readiness instead.
func intermission_remaining() -> float:
	return maxf(0.0, _intermission_left)

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
