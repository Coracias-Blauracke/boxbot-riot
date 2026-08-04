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

# --- assertions ------------------------------------------------------------

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
