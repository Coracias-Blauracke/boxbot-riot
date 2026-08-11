extends SceneTree

## Tests for the world, run and randomness layer:
##   godot --headless --path . --script res://tests/run_test.gd

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	print("=== WORLD / RUN TESTS ===\n")

	_test_rng_reproducible()
	_test_rng_streams_independent()
	_test_rng_substreams()
	_test_rng_persistence()
	_test_map_scaling_is_linear()
	_test_map_geometry_rectangle()
	_test_map_geometry_circle()
	_test_spawn_points_are_in_bounds()
	_test_overrides_agreement_is_not_conflict()
	_test_overrides_conflict_is_resolved_deterministically()
	_test_overrides_release()
	_test_wave_loop()
	_test_boss_chance_is_independent_per_player()
	_test_a_boss_wave_actually_puts_a_boss_on_the_floor()
	_test_run_length_comes_from_the_table()
	_test_wave_table_curves()
	_test_director_respects_availability()
	_test_director_spreads_spawns_across_the_wave()
	_test_director_ends_on_the_timer()
	_test_intermission_starts_the_next_wave()
	_test_one_death_does_not_end_a_co_op_run()
	_test_revive_rule_stands_players_up_at_the_shop()
	_test_permanent_rule_leaves_them_down()
	_test_shared_fate_ends_on_the_first_death()
	_test_victory_on_the_last_wave()
	_test_defeat_is_not_overwritten_by_victory()
	_test_a_corpse_does_not_bank_waves_survived()
	_test_run_frees_together_with_its_players()
	_test_a_group_arrives_as_one_group()
	_test_ring_places_the_group_off_screen_and_together()
	_test_ambush_keeps_its_distance_from_every_member()
	_test_ambush_without_players_still_spawns()
	_test_in_view_lands_on_screen_but_never_on_a_player()
	_test_in_view_falls_back_when_no_clear_spot_exists()
	_test_patterns_stay_inside_the_arena()
	_test_player_count_scales_budget_and_events()
	_test_wave_modifier_applies_only_to_its_waves()
	_test_horde_cost_cap_excludes_the_heavy_enemy()
	_test_a_cap_that_excludes_everything_is_ignored()
	_test_every_player_gets_their_own_shop()
	_test_shops_fill_when_the_shop_opens()
	_test_ready_up_closes_the_shop()
	_test_a_downed_player_does_not_hold_the_shop_open()
	_test_shop_layout_divides_the_screen()
	_test_readiness_only_counts_when_it_goes_through_the_run()
	_test_the_shop_waits_by_default()
	_test_a_pickup_pays_the_players_in_turn()
	_test_the_rotation_skips_whoever_is_down()
	_test_a_pickup_goes_through_the_currency_door()

	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --- randomness ------------------------------------------------------------

func _test_rng_reproducible() -> void:
	var a := RunRandom.new(8421)
	var b := RunRandom.new(8421)
	var first: Array = []
	var second: Array = []
	for i in 10:
		first.append(a.randi_in(RunRandom.Stream.COMBAT, 0, 1000))
		second.append(b.randi_in(RunRandom.Stream.COMBAT, 0, 1000))
	_check_bool("same seed replays identically", first == second, true)

	var other := RunRandom.new(99)
	var third: Array = []
	for i in 10:
		third.append(other.randi_in(RunRandom.Stream.COMBAT, 0, 1000))
	_check_bool("a different seed diverges", first != third, true)

func _test_rng_streams_independent() -> void:
	# The point of separate streams: firing extra bullets must not change what
	# the shop offers.
	var quiet := RunRandom.new(1234)
	var busy := RunRandom.new(1234)
	for i in 50:
		busy.randi_in(RunRandom.Stream.COMBAT, 0, 100)

	var from_quiet: Array = []
	var from_busy: Array = []
	for i in 5:
		from_quiet.append(quiet.randi_in(RunRandom.Stream.SHOP, 0, 1000))
		from_busy.append(busy.randi_in(RunRandom.Stream.SHOP, 0, 1000))

	_check_bool("combat rolls do not disturb the shop", from_quiet == from_busy, true)

func _test_rng_substreams() -> void:
	# Four players' shops must not interfere with each other either.
	var rng := RunRandom.new(555)
	var player_one: Array = []
	for i in 5:
		player_one.append(rng.randi_in(RunRandom.Stream.SHOP, 0, 1000, 1))

	var fresh := RunRandom.new(555)
	for i in 20:
		fresh.randi_in(RunRandom.Stream.SHOP, 0, 1000, 0)
	var player_one_again: Array = []
	for i in 5:
		player_one_again.append(fresh.randi_in(RunRandom.Stream.SHOP, 0, 1000, 1))

	_check_bool("one player's rerolls do not shift another's", player_one == player_one_again, true)

func _test_rng_persistence() -> void:
	var rng := RunRandom.new(777)
	for i in 7:
		rng.randi_in(RunRandom.Stream.SHOP, 0, 1000)
	var expected := rng.randi_in(RunRandom.Stream.SHOP, 0, 1000)

	# Rewind to the saved position and confirm we get the same next value -
	# this is what stops save-scumming the shop.
	var saved := RunRandom.new(777)
	for i in 7:
		saved.randi_in(RunRandom.Stream.SHOP, 0, 1000)
	var snapshot := saved.to_dict()

	var restored := RunRandom.new()
	restored.from_dict(snapshot)
	_check_int("restored stream continues where it left off", restored.randi_in(RunRandom.Stream.SHOP, 0, 1000), expected)

# --- map -------------------------------------------------------------------

func _test_map_scaling_is_linear() -> void:
	var world := WorldModel.new()
	world.base_extents = Vector2(100.0, 50.0)
	_check("neutral scale is 1.0", world.get_scale(), 1.0)
	_check("base extents", world.get_extents().x, 100.0)

	world.stats.add_modifier(StatTypes.Stat.MAP_SIZE, StatTypes.Modifier.PERCENT, 0.3, &"char_a")
	# Linear: each edge grows 30%, so the area grows 69%.
	_check("+30% scales each edge linearly", world.get_extents().x, 130.0)
	_check("the other edge scales too", world.get_extents().y, 65.0)

	# Two players carrying the same effect simply sum - no conflict.
	world.stats.add_modifier(StatTypes.Stat.MAP_SIZE, StatTypes.Modifier.PERCENT, 0.3, &"char_b")
	_check("two players' map growth sums", world.get_extents().x, 160.0)

	world.stats.remove_all_from_source(&"char_a")
	_check("removing one player's growth is exact", world.get_extents().x, 130.0)

func _test_map_geometry_rectangle() -> void:
	var world := WorldModel.new()
	world.base_extents = Vector2(100.0, 50.0)

	_check_bool("centre is inside", world.is_inside(Vector2.ZERO), true)
	_check_bool("corner is inside", world.is_inside(Vector2(99.0, 49.0)), true)
	_check_bool("outside is outside", world.is_inside(Vector2(101.0, 0.0)), false)
	_check("clamping pulls a point back", world.clamp_to_bounds(Vector2(500.0, 0.0)).x, 100.0)

	# Growing the arena makes a previously out-of-bounds point legal.
	world.stats.add_modifier(StatTypes.Stat.MAP_SIZE, StatTypes.Modifier.PERCENT, 0.5, &"grow")
	_check_bool("growth extends the bounds", world.is_inside(Vector2(140.0, 0.0)), true)

func _test_map_geometry_circle() -> void:
	var world := WorldModel.new()
	world.base_extents = Vector2(100.0, 100.0)
	world.set_shape(WorldTypes.MapShape.CIRCLE)

	_check_bool("inside the disc", world.is_inside(Vector2(99.0, 0.0)), true)
	# The rectangle corner falls outside a circle of the same extents.
	_check_bool("the rectangle corner is now outside", world.is_inside(Vector2(99.0, 99.0)), false)
	_check("clamping lands on the rim", world.clamp_to_bounds(Vector2(500.0, 0.0)).length(), 100.0)

func _test_spawn_points_are_in_bounds() -> void:
	var rng := RunRandom.new(4242)
	for shape in [WorldTypes.MapShape.RECTANGLE, WorldTypes.MapShape.CIRCLE]:
		var world := WorldModel.new()
		world.base_extents = Vector2(120.0, 80.0)
		world.set_shape(shape)

		var all_inside := true
		var all_on_edge := true
		for i in 200:
			if not world.is_inside(world.random_point_inside(rng)):
				all_inside = false
			var edge := world.random_point_on_edge(rng)
			if not world.is_inside(world.clamp_to_bounds(edge)):
				all_on_edge = false

		_check_bool("interior spawns stay in bounds (shape %d)" % shape, all_inside, true)
		_check_bool("edge spawns are reachable (shape %d)" % shape, all_on_edge, true)

# --- world overrides -------------------------------------------------------

func _test_overrides_agreement_is_not_conflict() -> void:
	var overrides := WorldOverrides.new(RunRandom.new(1))
	overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.CIRCLE, &"p1", 0)
	overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.CIRCLE, &"p2", 1)

	_check_bool("agreement is not a conflict", overrides.is_contested(WorldTypes.OVERRIDE_MAP_SHAPE), false)
	_check_int("agreed value wins outright", overrides.get_value(WorldTypes.OVERRIDE_MAP_SHAPE), WorldTypes.MapShape.CIRCLE)

func _test_overrides_conflict_is_resolved_deterministically() -> void:
	var winners: Array = []
	for attempt in 2:
		var overrides := WorldOverrides.new(RunRandom.new(31337))
		# Claims deliberately arrive in a different order each time.
		if attempt == 0:
			overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.CIRCLE, &"p1", 0)
			overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.RECTANGLE, &"p2", 1)
		else:
			overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.RECTANGLE, &"p2", 1)
			overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.CIRCLE, &"p1", 0)

		_check_bool("conflict is detected", overrides.is_contested(WorldTypes.OVERRIDE_MAP_SHAPE), true)
		_check_int("both candidates are reported", overrides.get_candidates(WorldTypes.OVERRIDE_MAP_SHAPE).size(), 2)
		winners.append(overrides.get_value(WorldTypes.OVERRIDE_MAP_SHAPE))

	# Sorting the claims before the roll is what makes this hold - otherwise the
	# result would depend on who joined first and the seed would mean nothing.
	_check_bool("same seed resolves the same way regardless of claim order", winners[0] == winners[1], true)

func _test_overrides_release() -> void:
	var overrides := WorldOverrides.new(RunRandom.new(7))
	overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.CIRCLE, &"item_a", 0)
	overrides.claim(WorldTypes.OVERRIDE_MAP_SHAPE, WorldTypes.MapShape.RECTANGLE, &"item_b", 0)
	_check_bool("contested while both are held", overrides.is_contested(WorldTypes.OVERRIDE_MAP_SHAPE), true)

	# Selling one of the items must settle the arena on the survivor.
	overrides.release(WorldTypes.OVERRIDE_MAP_SHAPE, &"item_b")
	_check_bool("no longer contested", overrides.is_contested(WorldTypes.OVERRIDE_MAP_SHAPE), false)
	_check_int("the survivor wins", overrides.get_value(WorldTypes.OVERRIDE_MAP_SHAPE), WorldTypes.MapShape.CIRCLE)

	overrides.release(WorldTypes.OVERRIDE_MAP_SHAPE, &"item_a")
	_check_bool("nothing claimed leaves no winner", overrides.get_value(WorldTypes.OVERRIDE_MAP_SHAPE) == null, true)

# --- run loop --------------------------------------------------------------

func _test_wave_loop() -> void:
	var run := RunModel.new(2024)
	run.total_waves = 2

	var player := EntityModel.new()
	run.add_player(player)
	_check_bool("player shares the run generator", player.rng == run.rng, true)

	player.counters.add(CounterTypes.Counter.BULLETS_FIRED, 10)  # RUN scope
	player.counters.add(CounterTypes.Counter.STEPS_TAKEN, 10)    # WAVE scope

	run.start_wave()
	_check_int("wave counter advances", run.wave_number, 1)
	_check_int("WAVE counters reset between waves", player.counters.get_value(CounterTypes.Counter.STEPS_TAKEN), 0)
	_check_int("RUN counters survive", player.counters.get_value(CounterTypes.Counter.BULLETS_FIRED), 10)

	run.end_wave()
	_check_int("shop opens after a wave", run.phase, WorldTypes.Phase.SHOP)
	_check_int("survived wave is recorded", player.counters.get_value(CounterTypes.Counter.WAVES_SURVIVED), 1)

	run.close_shop()
	run.start_wave()
	run.end_wave()
	_check_int("the run ends on the last wave", run.phase, WorldTypes.Phase.FINISHED)

func _test_boss_chance_is_independent_per_player() -> void:
	# Two players each carrying a 50% boss chance should produce a boss far more
	# often than one player alone - they roll independently rather than clashing.
	var solo := 0
	var duo := 0

	for seed_value in range(1, 201):
		solo += 1 if _boss_spawned(seed_value, 1) else 0
		duo += 1 if _boss_spawned(seed_value, 2) else 0

	_check_bool("a lone player triggers bosses sometimes", solo > 60 and solo < 140, true)
	_check_bool("two players roll independently, not exclusively", duo > solo, true)

func _boss_spawned(seed_value: int, player_count: int) -> bool:
	var run := RunModel.new(seed_value)
	var effect := EffectBossChancePerWave.new()
	effect.chance_per_stack = 0.5

	for i in player_count:
		var player := EntityModel.new()
		player.effects.register(EffectInstance.new(effect, StringName("boss_item")))
		run.add_player(player)

	# Read the field rather than capturing from the signal: GDScript lambdas
	# capture by VALUE, so assigning to an outer local inside one is silently
	# lost. That mistake made this test report a flat "no boss ever".
	run.start_wave()
	return run.spawn_boss_this_wave

## The gap this closes: spawn_boss was rolled, stored on the run, carried by
## wave_started and PRINTED by main.gd, and no spawner ever read it. A boss wave
## was announced and then played out exactly like any other.
func _test_a_boss_wave_actually_puts_a_boss_on_the_floor() -> void:
	print("
-- boss waves --")
	var table := _make_table()
	var boss := _make_enemy(400.0)
	boss.display_key = "TEST_BOSS"
	table.boss_entries = [_make_entry(boss, 1, 0.0, 1)]

	var director := WaveDirector.new()
	director.table = table
	var rng := RunRandom.new(4242)

	# An ordinary wave is unchanged - nothing about this may leak into the
	# waves that did not roll one.
	director.begin(3, 1, false)
	var plain := director.advance(0.001, rng)
	for group in plain:
		_check_bool("an ordinary wave has no boss in it", group.enemy == boss, false)

	# A boss wave puts it down on the FIRST frame: a boss that wandered in
	# halfway through is a wave with a surprise in it.
	director.begin(3, 1, true)
	var opening := director.advance(0.001, rng)
	var bosses := 0
	for group in opening:
		if group.enemy == boss:
			bosses += 1
			_check_int("and exactly one of it", group.count, 1)
	_check_int("a boss wave opens with the boss", bosses, 1)

	# Once, not once per frame.
	var later := 0
	for step in 200:
		for group in director.advance(0.05, rng):
			if group.enemy == boss:
				later += 1
	_check_int("and never again for the rest of the wave", later, 0)

	# Gated by the same min_wave the ordinary entries use, so "the queen appears
	# from wave 10" is authored rather than coded.
	table.boss_entries = [_make_entry(boss, 9, 0.0, 1)]
	director.begin(3, 1, true)
	var too_early := director.advance(0.001, rng)
	for group in too_early:
		_check_bool("a boss not yet available does not appear", group.enemy == boss, false)

	# And a boss rolled with nothing to be is a plain wave rather than an error.
	table.boss_entries = []
	director.begin(3, 1, true)
	director.advance(0.001, rng)
	_check_bool("an empty boss list simply runs the wave", true, true)

	# The CADENCE, which is what makes a boss reachable at all. Before this the
	# only thing that ever set spawn_boss was an effect no authored content
	# used, so a boss could not appear in a real run however the director
	# behaved.
	var curve := _make_table()
	curve.boss_every = 5
	_check_bool("wave 4 is ordinary", curve.is_boss_wave(4), false)
	_check_bool("wave 5 is a boss wave", curve.is_boss_wave(5), true)
	_check_bool("and so is wave 10", curve.is_boss_wave(10), true)
	curve.boss_every = 0
	_check_bool("zero never is", curve.is_boss_wave(5), false)

	# Seeded onto the event BEFORE the pipeline, so an effect can only ever add
	# a boss to a wave that was not going to have one.
	curve.boss_every = 2
	var run := RunModel.new(1, null, curve)
	run.add_player(EntityModel.new())
	run.start_wave()
	_check_bool("wave 1 has no boss", run.spawn_boss_this_wave, false)
	run.start_wave()
	_check_bool("wave 2 does", run.spawn_boss_this_wave, true)

# --- wave director ---------------------------------------------------------

func _make_enemy(hp: float) -> EnemyData:
	var data := EnemyData.new()
	data.display_key = "TEST_ENEMY"
	var modifier := StatModifier.new()
	modifier.stat = StatTypes.Stat.MAX_HP
	modifier.modifier_type = StatTypes.Modifier.BASE
	modifier.value = hp
	data.base_stats = [modifier]
	return data

func _make_entry(enemy: EnemyData, min_wave: int, cost: float, group: int) -> WaveEntry:
	var entry := WaveEntry.new()
	entry.enemy = enemy
	entry.min_wave = min_wave
	entry.cost = cost
	entry.group_size = group
	entry.weight = 1.0
	return entry

func _make_table() -> WaveTable:
	var table := WaveTable.new()
	table.entries = [
		_make_entry(_make_enemy(10.0), 1, 1.0, 3),
		_make_entry(_make_enemy(90.0), 3, 4.0, 1),
	]
	table.base_duration = 20.0
	table.duration_per_wave = 2.0
	table.max_duration = 30.0
	table.base_budget = 24.0
	table.budget_per_wave = 8.0
	table.budget_growth = 1.0
	table.spawn_events = 12
	table.total_waves = 20
	table.default_pattern = SpawnRing.new()
	# Neutral by default so the existing curve assertions keep measuring the
	# curve rather than the co-op scaling.
	table.budget_per_extra_player = 0.0
	table.events_per_extra_player = 0.0
	return table

## Enemies, not groups. advance() returns groups now, so .size() counts
## arrivals - which is a different number and would quietly change what the
## pacing assertions mean.
func _enemies_in(groups: Array[SpawnGroup]) -> int:
	var total := 0
	for group in groups:
		total += group.count
	return total

## The run length is authored on the table, so a twenty-wave curve and a
## fifty-wave curve are different content rather than the same content played
## for longer. It used to be a constant inside RunModel.
func _test_run_length_comes_from_the_table() -> void:
	var table := _make_table()
	table.total_waves = 7

	var run := RunModel.new(1, null, table)
	_check_int("the table sets the run length", run.total_waves, 7)

	# Still assignable afterwards, so a challenge or a test can shorten a run
	# without authoring a second table for it.
	run.total_waves = 2
	_check_int("and stays overridable", run.total_waves, 2)

	var without_table := RunModel.new(1)
	_check_bool("no table leaves the default intact", without_table.total_waves > 0, true)

func _test_wave_table_curves() -> void:
	var table := _make_table()
	_check("wave 1 duration", table.duration_for(1), 20.0)
	_check("duration grows", table.duration_for(3), 24.0)
	_check("duration is capped", table.duration_for(50), 30.0)

	_check("wave 1 budget", table.budget_for(1), 24.0)
	_check("budget grows", table.budget_for(3), 40.0)
	_check_bool("later waves are harder", table.budget_for(10) > table.budget_for(9), true)

func _test_director_respects_availability() -> void:
	var table := _make_table()
	_check_int("only the early enemy on wave 1", table.available_entries(1).size(), 1)
	_check_int("the heavy one joins on wave 3", table.available_entries(3).size(), 2)

func _test_director_spreads_spawns_across_the_wave() -> void:
	var director := WaveDirector.new()
	director.table = _make_table()
	director.begin(1)

	var rng := RunRandom.new(4242)
	var first_half := 0
	var second_half := 0
	var total := 0

	var step := 0.1
	var elapsed := 0.0
	while elapsed < director.duration:
		var spawned := _enemies_in(director.advance(step, rng))
		total += spawned
		if elapsed < director.duration * 0.5:
			first_half += spawned
		else:
			second_half += spawned
		elapsed += step

	_check_bool("the wave actually spawns something (%d)" % total, total > 0, true)
	# The bug this guards: with a fixed event count a small budget is spent in
	# the opening seconds and the rest of the wave is empty.
	_check_bool("spawns continue past the halfway point (%d then %d)" % [first_half, second_half], second_half > 0, true)
	_check_bool("neither half is starved", first_half > 0 and second_half > 0, true)

func _test_director_ends_on_the_timer() -> void:
	var director := WaveDirector.new()
	director.table = _make_table()
	director.begin(1)

	var rng := RunRandom.new(7)
	director.advance(director.duration - 0.5, rng)
	_check_bool("still running just before time", director.is_finished(), false)

	director.advance(1.0, rng)
	_check_bool("finishes on the timer, not on a clear arena", director.is_finished(), true)
	_check("no time left", director.time_remaining(), 0.0)

## Without this the run stops dead after wave one: the shop opens and nothing
## closes it, because there is no shop UI yet.
func _test_intermission_starts_the_next_wave() -> void:
	var run := RunModel.new(11, null, _make_table())
	run.total_waves = 5
	run.auto_intermission = 2.0
	run.add_player(EntityModel.new())

	run.start_wave()
	_check_int("wave 1 running", run.wave_number, 1)

	run.advance_wave(run.director.duration + 0.1)
	_check_int("timer opens the shop", run.phase, WorldTypes.Phase.SHOP)

	run.advance_wave(1.0)
	_check_int("intermission is still running", run.phase, WorldTypes.Phase.SHOP)
	_check_int("no new wave yet", run.wave_number, 1)

	run.advance_wave(1.5)
	_check_int("wave 2 begins", run.wave_number, 2)
	_check_int("back in combat", run.phase, WorldTypes.Phase.COMBAT)

# --- death rules -----------------------------------------------------------

## A player with a body. EntityModel.new() sits at zero HP and can never die,
## because set_hp() clamps to zero, sees no change and returns before it can
## flip is_alive.
func _run_with_players(count: int, rule: RunTypes.DeathRule) -> RunModel:
	var run := RunModel.new(4242)
	run.death_rule = rule
	for i in count:
		var player := EntityModel.new()
		player.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0, &"test_body")
		run.add_player(player)
	return run

func _kill(victim: EntityModel) -> void:
	var event := DamageEvent.new()
	event.amount = 9999.0
	victim.apply_damage(event)

func _test_one_death_does_not_end_a_co_op_run() -> void:
	var run := _run_with_players(2, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	run.start_wave()

	_kill(run.players[0])
	_check_int("one player left standing", run.living_player_count(), 1)
	_check_bool("the downed one is tracked", run.is_player_downed(0), true)
	_check_bool("the survivor is not", run.is_player_downed(1), false)
	_check_bool("the run carries on", run.is_run_over(), false)
	_check_int("still in combat", run.phase, WorldTypes.Phase.COMBAT)

	_kill(run.players[1])
	_check_bool("the last death ends it", run.is_run_over(), true)
	_check_int("as a defeat", run.outcome, RunTypes.Outcome.DEFEAT)
	_check_int("and the phase closes", run.phase, WorldTypes.Phase.FINISHED)

func _test_revive_rule_stands_players_up_at_the_shop() -> void:
	var run := _run_with_players(2, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	run.revive_hp_fraction = 0.5
	run.start_wave()

	_kill(run.players[0])
	_check_bool("down during the wave", run.players[0].is_alive, false)

	run.end_wave()
	_check_int("the shop opened", run.phase, WorldTypes.Phase.SHOP)
	_check_bool("and they are back up", run.players[0].is_alive, true)
	_check("on the configured fraction of max HP", run.players[0].current_hp, 50.0)
	_check_bool("no longer counted as down", run.is_player_downed(0), false)

	# Standing up must not cost the survivor anything either.
	_check("the survivor is untouched", run.players[1].current_hp, 100.0)

func _test_permanent_rule_leaves_them_down() -> void:
	var run := _run_with_players(2, RunTypes.DeathRule.PERMANENT)
	run.start_wave()

	_kill(run.players[0])
	run.end_wave()
	_check_int("the shop still opens for the survivor", run.phase, WorldTypes.Phase.SHOP)
	_check_bool("but the dead stay dead", run.players[0].is_alive, false)
	_check_bool("and stay on the downed list", run.is_player_downed(0), true)
	_check_bool("the run is not over yet", run.is_run_over(), false)

	run.close_shop()
	run.start_wave()
	_kill(run.players[1])
	_check_int("it ends with the last survivor", run.outcome, RunTypes.Outcome.DEFEAT)

func _test_shared_fate_ends_on_the_first_death() -> void:
	var run := _run_with_players(4, RunTypes.DeathRule.SHARED_FATE)
	run.start_wave()

	_kill(run.players[2])
	_check_int("three are still alive", run.living_player_count(), 3)
	_check_bool("and it is over anyway", run.is_run_over(), true)
	_check_int("as a defeat", run.outcome, RunTypes.Outcome.DEFEAT)

func _test_victory_on_the_last_wave() -> void:
	var run := _run_with_players(1, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	run.total_waves = 2

	run.start_wave()
	run.end_wave()
	run.close_shop()
	run.start_wave()
	run.end_wave()

	_check_int("clearing the last wave wins", run.outcome, RunTypes.Outcome.VICTORY)
	_check_int("and finishes the run", run.phase, WorldTypes.Phase.FINISHED)

	# A finished run must be inert: nothing may start another wave on top of it.
	run.start_wave()
	_check_int("no wave starts after the end", run.wave_number, 2)

func _test_defeat_is_not_overwritten_by_victory() -> void:
	# The race this exists for: the last player dies on the very frame the
	# director runs out of time on the final wave. Without one choke point for
	# the outcome, end_wave() would then overwrite the defeat with a victory.
	var run := _run_with_players(1, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	run.total_waves = 1
	run.start_wave()

	_kill(run.players[0])
	_check_int("dying loses the run", run.outcome, RunTypes.Outcome.DEFEAT)

	run.end_wave()
	_check_int("the final wave ending does not rewrite it", run.outcome, RunTypes.Outcome.DEFEAT)

func _test_a_corpse_does_not_bank_waves_survived() -> void:
	var run := _run_with_players(2, RunTypes.DeathRule.PERMANENT)
	run.start_wave()
	_kill(run.players[0])
	run.end_wave()

	_check_int(
		"the survivor is credited",
		run.players[1].counters.get_value(CounterTypes.Counter.WAVES_SURVIVED), 1
	)
	# Otherwise "every 5 waves survived, gain X" pays a corpse for the rest of
	# the run, which under PERMANENT is most of it.
	_check_int(
		"the corpse is not",
		run.players[0].counters.get_value(CounterTypes.Counter.WAVES_SURVIVED), 0
	)

func _test_run_frees_together_with_its_players() -> void:
	# add_player() connects to the player's `died` signal, and the run holds the
	# player. If that connection were a strong reference back, the pair would be
	# a cycle - and RefCounted has no cycle collector, so neither would ever be
	# freed. Asserted rather than assumed, because this exact shape has leaked
	# in this codebase before.
	var run := _run_with_players(2, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	# Typed explicitly: weakref() returns Variant, and `:=` off a Variant is a
	# parse error here - which silently skips the whole suite rather than
	# failing one assertion.
	var run_ref: WeakRef = weakref(run)
	var player_ref: WeakRef = weakref(run.players[0])

	run.start_wave()
	_kill(run.players[0])

	run = null
	_check_bool("the run frees", run_ref.get_ref() == null, true)
	_check_bool("and takes its players with it", player_ref.get_ref() == null, true)

# --- spawn placement -------------------------------------------------------

## A roomy arena and a view in the middle of it, so nothing under test is
## measuring a wall clamp by accident.
func _make_context(players: PackedVector2Array = PackedVector2Array()) -> SpawnContext:
	var context := SpawnContext.new()
	context.world = WorldModel.new()
	context.world.base_extents = Vector2(4000.0, 4000.0)
	context.view_centre = Vector2.ZERO
	context.view_size = Vector2(1400.0, 800.0)
	context.player_positions = players
	return context

## REGRESSION. WaveEntry.group_size promised a cluster while the director
## flattened it into `group_size` copies in one array and the spawner rolled an
## independent position for each. An authored group of three arrived at three
## unrelated points on the ring, and default_waves.tres has been authoring
## group_size = 3 the whole time.
func _test_a_group_arrives_as_one_group() -> void:
	var director := WaveDirector.new()
	director.table = _make_table()
	director.begin(1)

	var rng := RunRandom.new(99)
	var groups: Array[SpawnGroup] = []
	var elapsed := 0.0
	while elapsed < director.duration and groups.is_empty():
		groups = director.advance(0.1, rng)
		elapsed += 0.1

	_check_bool("the wave produced a group", groups.is_empty(), false)
	if groups.is_empty():
		return

	_check_int("a group of three is ONE decision", groups[0].count, 3)
	_check_bool("and it carries its pattern", groups[0].pattern != null, true)

func _test_ring_places_the_group_off_screen_and_together() -> void:
	var pattern := SpawnRing.new()
	pattern.view_margin = 1.12
	pattern.cluster_radius = 46.0

	var context := _make_context()
	var rng := RunRandom.new(31337)

	var all_off_screen := true
	var all_clustered := true

	for attempt in 60:
		var points := pattern.positions(context, 5, rng)
		if points.size() != 5:
			all_clustered = false
			break
		for point in points:
			# Off screen means outside the view rectangle on at least one axis.
			if absf(point.x) <= context.view_size.x * 0.5 and absf(point.y) <= context.view_size.y * 0.5:
				all_off_screen = false
			# Every member sits within the cluster radius of the anchor, which
			# is the first point by construction.
			if point.distance_to(points[0]) > pattern.cluster_radius + 0.001:
				all_clustered = false

	_check_bool("nothing pops into existence on screen", all_off_screen, true)
	_check_bool("the whole group shares one anchor", all_clustered, true)

func _test_ambush_keeps_its_distance_from_every_member() -> void:
	var pattern := SpawnNearPlayer.new()
	pattern.min_distance = 190.0
	pattern.max_distance = 310.0
	pattern.cluster_radius = 40.0

	var player := Vector2(120.0, -60.0)
	var context := _make_context(PackedVector2Array([player]))
	var rng := RunRandom.new(4242)

	var closest := INF
	var furthest := 0.0
	for attempt in 200:
		for point in pattern.positions(context, 4, rng):
			closest = minf(closest, point.distance_to(player))
			furthest = maxf(furthest, point.distance_to(player))

	# The floor must hold for the whole cluster. Scattering radius 40 around an
	# anchor at 190 would otherwise put the nearest member at 150.
	_check_bool("no member lands inside the floor (%.0f)" % closest, closest >= 190.0 - 0.001, true)
	# And it is still an ambush rather than a ring spawn: the far end stays
	# within the band plus the cluster it is allowed to scatter over.
	_check_bool("and none strays past the band (%.0f)" % furthest, furthest <= 310.0 + 40.0 + 0.001, true)

func _test_ambush_without_players_still_spawns() -> void:
	# Every player down, or a preview with none bound. Returning nothing here
	# would stall the wave silently rather than erroring.
	var pattern := SpawnNearPlayer.new()
	var context := _make_context()
	var points := pattern.positions(context, 3, RunRandom.new(5))

	_check_int("an ambush with nobody to ambush still places its group", points.size(), 3)

func _test_in_view_lands_on_screen_but_never_on_a_player() -> void:
	var pattern := SpawnInView.new()
	pattern.clear_radius = 230.0
	pattern.view_inset = 40.0
	pattern.cluster_radius = 40.0

	# Two players, because the clearance has to hold against BOTH. A floor
	# measured only against the nearest one still drops a group on the other.
	var players := PackedVector2Array([Vector2(-200.0, 80.0), Vector2(320.0, -120.0)])
	var context := _make_context(players)
	var rng := RunRandom.new(1234)

	var closest := INF
	var on_screen := 0
	var total := 0

	for attempt in 200:
		for point in pattern.positions(context, 3, rng):
			total += 1
			for player in players:
				closest = minf(closest, point.distance_to(player))
			# Inside the view rectangle - that is the whole difference from the
			# ring, which only ever places outside it.
			if absf(point.x) <= context.view_size.x * 0.5 and absf(point.y) <= context.view_size.y * 0.5:
				on_screen += 1

	_check_bool("nothing lands on a player (closest %.0f)" % closest, closest >= 230.0 - 0.001, true)
	# Not all of them: pushing clear of a player can shove a member past the
	# frame edge, which is preferable to dropping it in somebody's lap.
	_check_bool("the group lands in view (%d of %d)" % [on_screen, total], on_screen > total / 2, true)

func _test_in_view_falls_back_when_no_clear_spot_exists() -> void:
	# A view so small that every point in it is inside the clearance. Returning
	# nothing here would stall the wave with no error to explain why.
	var pattern := SpawnInView.new()
	pattern.clear_radius = 5000.0

	var context := _make_context(PackedVector2Array([Vector2.ZERO]))
	context.view_size = Vector2(200.0, 120.0)

	var points := pattern.positions(context, 4, RunRandom.new(77))
	_check_int("an impossible clearance still places the group", points.size(), 4)

func _test_patterns_stay_inside_the_arena() -> void:
	# A tight arena, so every pattern is forced against the walls.
	var context := SpawnContext.new()
	context.world = WorldModel.new()
	context.world.base_extents = Vector2(300.0, 200.0)
	context.view_centre = Vector2.ZERO
	context.view_size = Vector2(400.0, 240.0)
	context.player_positions = PackedVector2Array([Vector2(250.0, 150.0)])

	var patterns: Array[SpawnPattern] = [
		SpawnRing.new(), SpawnNearPlayer.new(), SpawnEdge.new(), SpawnInView.new()
	]
	var rng := RunRandom.new(808)

	for pattern in patterns:
		var all_inside := true
		for attempt in 100:
			for point in pattern.positions(context, 4, rng):
				if not context.world.is_inside(context.world.clamp_to_bounds(point)):
					all_inside = false
		_check_bool(
			"%s never places outside the arena" % pattern.get_script().get_global_name(),
			all_inside, true
		)

# --- co-op scaling and wave modifiers --------------------------------------

func _test_player_count_scales_budget_and_events() -> void:
	var table := _make_table()
	table.budget_per_extra_player = 1.0
	table.events_per_extra_player = 1.0

	_check("one player is the baseline", table.budget_for(1, 1), 24.0)
	_check("two players face twice the wave", table.budget_for(1, 2), 48.0)
	# Linear, not compounding: four players get four times, not eight. The
	# budget curve already compounds on its own across waves.
	_check("four players face four times, not eight", table.budget_for(1, 4), 96.0)

	_check_int("events scale too", table.events_for(1, 2), 24)
	# This is the point of scaling events alongside budget: the gap between
	# arrivals halves instead of each arrival doubling in size.
	_check_int("four players get four times the arrivals", table.events_for(1, 4), 48)

	# Setting the scale to zero has to switch co-op scaling off completely, so a
	# challenge or a hand-tuned table can opt out.
	var neutral := WaveTable.new()
	neutral.budget_per_extra_player = 0.0
	neutral.events_per_extra_player = 0.0
	_check("a zero scale disables budget scaling", neutral.budget_for(1, 4), neutral.budget_for(1, 1))
	_check_int("and event scaling too", neutral.events_for(1, 4), neutral.events_for(1, 1))

func _make_horde(wave: int, cap: float) -> WaveModifier:
	var horde := WaveModifier.new()
	horde.display_key = "WAVE_MOD_HORDE"
	horde.waves = PackedInt32Array([wave])
	horde.budget_multiplier = 2.0
	horde.events_multiplier = 2.0
	horde.max_entry_cost = cap
	return horde

func _test_wave_modifier_applies_only_to_its_waves() -> void:
	var table := _make_table()
	table.modifiers = [_make_horde(11, 0.0)]

	var plain := table.budget_for(10)
	var horde := table.budget_for(11)
	var after := table.budget_for(12)

	_check_bool("wave 11 carries 100%% more (%.0f vs %.0f)" % [horde, plain], horde > plain * 1.9, true)
	_check_bool("and wave 12 is back to normal", after < horde, true)
	_check_int("the modifier is reported for its wave", table.modifiers_for(11).size(), 1)
	_check_int("and not for others", table.modifiers_for(10).size(), 0)

	# every_n_waves is the other way of matching, for a recurring twist.
	var recurring := WaveModifier.new()
	recurring.display_key = "WAVE_MOD_EVERY_FIVE"
	recurring.every_n_waves = 5
	table.modifiers = [recurring]
	_check_int("every fifth wave matches", table.modifiers_for(15).size(), 1)
	_check_int("the others do not", table.modifiers_for(16).size(), 0)

func _test_horde_cost_cap_excludes_the_heavy_enemy() -> void:
	var table := _make_table()
	table.modifiers = [_make_horde(11, 1.0)]

	# Wave 11 has both enemies available: the cheap one at cost 1 and the heavy
	# one at cost 4. Doubling the budget without the cap just buys twice as many
	# heavies, which is a completely different wave from a horde.
	_check_int("both are normally eligible", table.available_entries(11).size(), 2)
	_check_int(
		"the cap leaves only the cheap swarm",
		table.available_entries(11, table.max_entry_cost_for(11)).size(), 1
	)
	_check("the cap is reported", table.max_entry_cost_for(11), 1.0)
	_check("and is absent on other waves", table.max_entry_cost_for(12), 0.0)

func _test_a_cap_that_excludes_everything_is_ignored() -> void:
	# The worst failure mode available here: nothing errors, no enemy is
	# eligible, and the wave simply does not happen for twenty seconds.
	var table := _make_table()
	table.modifiers = [_make_horde(11, 0.25)]

	_check_int(
		"an impossible cap falls back to the full set",
		table.available_entries(11, table.max_entry_cost_for(11)).size(), 2
	)

# --- shops in the run ------------------------------------------------------

func _make_run_shop_data() -> ShopData:
	var item := ItemData.new()
	item.display_key = "RUN_TEST_ITEM"
	item.tier = 1
	item.base_price = 5

	var data := ShopData.new()
	data.pool = [item]
	data.offer_count = 3
	return data

func _run_with_shop(count: int, rule := RunTypes.DeathRule.REVIVE_NEXT_WAVE) -> RunModel:
	var run := _run_with_players(count, rule)
	# Ready-up is the way out, not the timer. auto_intermission only exists
	# because there is no UI to press yet.
	run.auto_intermission = 0.0
	run.shop_data = _make_run_shop_data()
	return run

func _test_every_player_gets_their_own_shop() -> void:
	var run := _run_with_shop(3)

	_check_int("one shop per player", run.shops.size(), 3)
	_check_int("indexed to match its RNG sub-stream", run.shop_for(2).player_index, 2)
	_check_bool("and they are separate objects", run.shop_for(0) != run.shop_for(1), true)
	_check_bool("out of range is null rather than a crash", run.shop_for(9) == null, true)

func _test_shops_fill_when_the_shop_opens() -> void:
	var run := _run_with_shop(2)
	run.start_wave()
	_check_int("nothing on offer during combat", run.shop_for(0).offers.size(), 0)

	run.end_wave()
	_check_int("the shop phase fills them", run.shop_for(0).offers.size(), 3)
	_check_int("for every player, not just the first", run.shop_for(1).offers.size(), 3)

	run.close_shop()
	_check_int("and closing empties them", run.shop_for(0).offers.size(), 0)

func _test_ready_up_closes_the_shop() -> void:
	var run := _run_with_shop(2)
	run.start_wave()
	run.end_wave()
	_check_int("in the shop", run.phase, WorldTypes.Phase.SHOP)

	run.set_player_ready(0, true)
	_check_bool("one player is not everyone", run.all_players_ready(), false)
	_check_int("so the shop stays open", run.phase, WorldTypes.Phase.SHOP)

	run.set_player_ready(1, true)
	_check_int("the last one starts the wave", run.phase, WorldTypes.Phase.COMBAT)
	_check_int("and it is the next one", run.wave_number, 2)

func _test_a_downed_player_does_not_hold_the_shop_open() -> void:
	# Under PERMANENT a dead player can never press ready again, so counting
	# them would hold the run hostage for the rest of it.
	var run := _run_with_shop(2, RunTypes.DeathRule.PERMANENT)
	run.start_wave()
	_kill(run.players[0])
	run.end_wave()

	_check_int("the survivor gets a shop", run.shop_for(1).offers.size(), 3)
	# Offers a corpse cannot buy would be a whole panel of dead UI.
	_check_int("the corpse does not", run.shop_for(0).offers.size(), 0)

	run.set_player_ready(1, true)
	_check_int("and the survivor alone can start the wave", run.phase, WorldTypes.Phase.COMBAT)

## REGRESSION. The shop panel called ShopManager.set_ready() directly, which
## flips a flag nobody is watching: RunModel is what checks whether everyone is
## ready and starts the next wave. Pressing ready in the UI therefore did
## nothing at all, and no model test caught it because every one of them called
## the run's function - the very thing the UI was skipping.
func _test_readiness_only_counts_when_it_goes_through_the_run() -> void:
	var run := _run_with_shop(1)
	run.start_wave()
	run.end_wave()
	_check_int("in the shop", run.phase, WorldTypes.Phase.SHOP)

	# What the UI used to do.
	run.shop_for(0).set_ready(true)
	_check_bool("the flag is set", run.shop_for(0).is_ready, true)
	_check_int("but the run has not moved", run.phase, WorldTypes.Phase.SHOP)
	_check_int("and no wave started", run.wave_number, 1)

	# What it does now.
	run.set_player_ready(0, true)
	_check_int("routing it through the run starts the wave", run.phase, WorldTypes.Phase.COMBAT)
	_check_int("and it is the next one", run.wave_number, 2)

## The shop must NOT close itself now that there is a UI to press. Four seconds
## is not long enough to read one item, let alone buy one.
func _test_the_shop_waits_by_default() -> void:
	var run := _run_with_players(1, RunTypes.DeathRule.REVIVE_NEXT_WAVE)
	run.shop_data = _make_run_shop_data()
	_check("a fresh run does not close its own shop", run.auto_intermission, 0.0)

	run.start_wave()
	run.end_wave()
	for tick in 100:
		run.advance_wave(1.0)
	_check_int("a hundred seconds later it is still open", run.phase, WorldTypes.Phase.SHOP)

## ShopLayout lives in scenes/ but touches no Node, so unlike the rest of that
## layer it can be checked here rather than only photographed. Worth it: the
## three-player case is the one nobody can hold in their head.
func _test_shop_layout_divides_the_screen() -> void:
	var screen := Vector2(1920.0, 1080.0)

	_check("one player takes the whole width", ShopLayout.rect_for(0, 1, screen).size.x, 1920.0)

	var left := ShopLayout.rect_for(0, 2, screen)
	var right := ShopLayout.rect_for(1, 2, screen)
	_check("two players split vertically", left.size.x, 960.0)
	_check("and the second starts at the middle", right.position.x, 960.0)
	_check("each keeps full height", right.size.y, 1080.0)

	# The corner map has to match the HUD's, or the game teaches two conflicting
	# spatial rules: P1 top-left, P2 top-right, P3 bottom-left, P4 bottom-right.
	var corners := [Vector2(0, 0), Vector2(960, 0), Vector2(0, 540), Vector2(960, 540)]
	var matched := true
	for index in 4:
		if ShopLayout.rect_for(index, 4, screen).position != corners[index]:
			matched = false
	_check_bool("four players take the HUD's corners", matched, true)

	# Three uses the same quadrants rather than a bespoke split, so no player
	# gets a differently shaped panel.
	_check("three players still get quadrants", ShopLayout.rect_for(2, 3, screen).size.y, 540.0)
	_check_bool(
		"and the spare quadrant is reported for the wave line",
		ShopLayout.free_rect(3, screen) == Rect2(Vector2(960, 540), Vector2(960, 540)), true
	)
	_check_bool("with none spare at four", ShopLayout.free_rect(4, screen) == Rect2(), true)

	_check_bool("a quarter screen is not compact", ShopLayout.is_compact(ShopLayout.rect_for(0, 4, screen)), false)

# --- assertions ------------------------------------------------------------

# --- pickups ---------------------------------------------------------------
#
# WHOSE SCRAP IT IS is a run rule, so it is asserted here rather than in the
# scene layer. What the pickup NODE does - lying there, being magnetised, being
# swept up at the end of a wave - is measured by a capture run instead.

func _test_a_pickup_pays_the_players_in_turn() -> void:
	print("
-- pickups --")
	var run := RunModel.new(7)
	var first := EntityModel.new()
	var second := EntityModel.new()
	var third := EntityModel.new()
	for player in [first, second, third]:
		run.add_player(player as EntityModel)

	for i in 4:
		run.credit_pickup(10)

	# ROUND ROBIN, not "whoever walked over it". Four drops across three players
	# is 2 / 1 / 1, and the fifth would start the cycle again.
	_check_int("player one took the first and the fourth", first.get_currency(), 20)
	_check_int("player two took one", second.get_currency(), 10)
	_check_int("player three took one", third.get_currency(), 10)

func _test_the_rotation_skips_whoever_is_down() -> void:
	var run := RunModel.new(7)
	var alive := EntityModel.new()
	var downed := EntityModel.new()
	var other := EntityModel.new()
	for player in [alive, downed, other]:
		# Given health explicitly: a model built with no data starts at 0 current
		# HP, and set_hp() early-returns when the value does not change - so it
		# would take the blow and stay standing.
		var body := player as EntityModel
		body.stats.add_modifier(
			StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 50.0, &"test_body"
		)
		body.set_hp(50.0)
		run.add_player(body)

	var lethal := DamageEvent.new()
	lethal.amount = 9999.0
	downed.apply_damage(lethal)
	_check_bool("one of them is down", downed.is_alive, false)

	for i in 4:
		run.credit_pickup(5)

	# A corpse is skipped rather than paid: under PERMANENT it can never spend
	# again, and under REVIVE_NEXT_WAVE paying it would tax the survivors for the
	# rest of the wave.
	_check_int("the down one got nothing", downed.get_currency(), 0)
	_check_int("and the four went two each", alive.get_currency(), 10)
	_check_int("to the two still standing", other.get_currency(), 10)

func _test_a_pickup_goes_through_the_currency_door() -> void:
	var run := RunModel.new(7)
	var greedy := EntityModel.new()
	run.add_player(greedy)

	# CURRENCY_GAIN applies, because credit_pickup pays through add_currency -
	# the one door. Note what that means and is meant to mean: the bonus belongs
	# to whoever's TURN it is, not to whoever bent down.
	greedy.stats.add_modifier(
		StatTypes.Stat.CURRENCY_GAIN, StatTypes.Modifier.BASE, 0.5, &"prospector"
	)
	run.credit_pickup(10)
	_check_int("the stat reached the scrap", greedy.get_currency(), 15)

	# And the lifetime tally moves with it, so "for every 500 earned" counts what
	# was picked up rather than only what a kill would have paid.
	_check_int(
		"earnings are tallied too",
		greedy.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), 15
	)

	_check_bool("nothing is credited for nothing", run.credit_pickup(0) == null, true)

func _check(label: String, actual: float, expected: float) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s -> got %s, expected %s" % [label, actual, expected])

func _check_int(label: String, actual: int, expected: int) -> void:
	if actual == expected:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s -> got %d, expected %d" % [label, actual, expected])

func _check_bool(label: String, actual: bool, expected: bool) -> void:
	if actual == expected:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s -> got %s, expected %s" % [label, actual, expected])
