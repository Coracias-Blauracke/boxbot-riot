extends SceneTree

## Tests for the core/ layer, run WITHOUT THE EDITOR AND WITHOUT THE GAME:
##   godot --headless --path . --script res://tests/core_test.gd
##
## This works because core/ depends on neither the SceneTree nor any autoload.
## That is the dividend of keeping logic on RefCounted instead of on nodes.

## Records how many times a hook fired, so tests can assert that events reach
## the right entity.
class SpyEffect extends DynamicEffect:
	var watched: Hooks.Hook = Hooks.Hook.ON_KILL
	var calls: int = 0

	## Weak on purpose. Holding the payload strongly closes the cycle
	## effect -> event -> entity -> dispatcher -> effect, which RefCounted
	## cannot collect. Measured: 33 leaked objects from this alone.
	var last_target: WeakRef = null
	var last_applier: WeakRef = null

	func get_hooks() -> Array:
		return [watched]

	func execute(_host: Variant, _inst: EffectInstance, event: EventPayload) -> void:
		calls += 1
		if event is StatusEvent:
			last_target = weakref((event as StatusEvent).target)
			last_applier = weakref((event as StatusEvent).applier)

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	print("=== CORE LAYER TESTS ===\n")

	_test_stats_formula()
	_test_mult_pool()
	_test_modifier_handles()
	_test_modifier_sources()
	_test_stat_floors()
	_test_max_hp_tracking()
	_test_counters()
	_test_currency()
	_test_notification_effect()
	_test_pipeline_effect()
	_test_counter_effect()
	_test_items_lifecycle()
	_test_item_tiers()
	_test_authored_tres()
	_test_status_modifier()
	_test_status_stacking()
	_test_status_refresh_modes()
	_test_status_damage_over_time()
	_test_status_events_reach_both_sides()
	_test_damage_pipeline_and_death()

	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --- stats -----------------------------------------------------------------

func _test_stats_formula() -> void:
	var stats := StatsManager.new()
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.BASE, 10.0)
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.FLAT, 5.0)
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.PERCENT, 0.5)
	# (10 + 5) * 1.5
	_check("formula (base+flat)*(1+pct)", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 22.5)

	# Single additive percent pool: +50% and +50% gives x2, not x2.25
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.PERCENT, 0.5)
	_check("percentages are additive", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 30.0)

func _test_mult_pool() -> void:
	var stats := StatsManager.new()
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.BASE, 100.0)
	_check("empty MULT pool is neutral", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 100.0)

	var first := stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.MULT, 1.5)
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.MULT, 1.5)
	# Multiplicative, unlike PERCENT: 1.5 * 1.5 = 2.25
	_check("MULT composes multiplicatively", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 225.0)

	stats.remove_modifier(first)
	_check("MULT removal is exact", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 150.0)

	# PERCENT and MULT coexist: (100) * (1 + 0.5) * 1.5
	stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.PERCENT, 0.5)
	_check("PERCENT and MULT combine", stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 225.0)

func _test_modifier_handles() -> void:
	var stats := StatsManager.new()
	var first := stats.add_modifier(StatTypes.Stat.ARMOR, StatTypes.Modifier.FLAT, 10.0)
	stats.add_modifier(StatTypes.Stat.ARMOR, StatTypes.Modifier.FLAT, 25.0)
	_check("two modifiers stack", stats.get_stat(StatTypes.Stat.ARMOR), 35.0)

	stats.remove_modifier(first)
	_check("handle removes exactly its own", stats.get_stat(StatTypes.Stat.ARMOR), 25.0)

	stats.remove_modifier(first)  # removing twice must be harmless
	_check("double removal is safe", stats.get_stat(StatTypes.Stat.ARMOR), 25.0)

func _test_modifier_sources() -> void:
	var stats := StatsManager.new()
	var slow_a := StringName("slow_a")
	var slow_b := StringName("slow_b")

	stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0)
	stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.PERCENT, -0.3, slow_a)
	stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.PERCENT, -0.2, slow_b)
	_check("two overlapping slows", stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 50.0)

	stats.remove_all_from_source(slow_a)
	_check("only one slow expires", stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 80.0)

	stats.remove_all_from_source(slow_b)
	_check("base restored after both expire", stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 100.0)

func _test_stat_floors() -> void:
	var stats := StatsManager.new()
	stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0)
	stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.PERCENT, -2.0)
	_check("speed never goes negative", stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 0.0)

# --- model -----------------------------------------------------------------

func _test_max_hp_tracking() -> void:
	var entity := EntityModel.new()
	entity.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0, StringName("base"))
	entity.current_hp = entity.get_max_hp()
	_check("starts at full HP", entity.current_hp, 100.0)

	entity.set_hp(60.0)
	_check("takes damage", entity.current_hp, 60.0)

	var item_source := StringName("hp_item")
	entity.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.FLAT, 50.0, item_source)
	_check("max HP increase tops up current", entity.current_hp, 110.0)
	_check("new max HP", entity.get_max_hp(), 150.0)

	entity.stats.remove_all_from_source(item_source)
	_check("max HP decrease clamps current", entity.current_hp, 100.0)

func _test_counters() -> void:
	var counters := CounterManager.new()
	counters.add(CounterTypes.Counter.BULLETS_FIRED, 999)
	_check_int("counter increments", counters.get_value(CounterTypes.Counter.BULLETS_FIRED), 999)
	_check_int("no threshold before 1000", counters.crossings(CounterTypes.Counter.BULLETS_FIRED, 1000, 999), 0)

	counters.add(CounterTypes.Counter.BULLETS_FIRED, 1)
	_check_int("threshold 1000 crossed", counters.crossings(CounterTypes.Counter.BULLETS_FIRED, 1000, 1), 1)

	counters.add(CounterTypes.Counter.BULLETS_FIRED, 2500)
	_check_int("one event crosses several thresholds", counters.crossings(CounterTypes.Counter.BULLETS_FIRED, 1000, 2500), 2)

	counters.add(CounterTypes.Counter.STEPS_TAKEN, 42)
	counters.reset_scope(CounterTypes.Scope.WAVE)
	_check_int("WAVE scope is cleared", counters.get_value(CounterTypes.Counter.STEPS_TAKEN), 0)
	_check_int("RUN scope is untouched", counters.get_value(CounterTypes.Counter.BULLETS_FIRED), 3500)

func _test_currency() -> void:
	var entity := EntityModel.new()
	entity.add_currency(100)
	entity.add_currency(-30)
	_check_int("currency balance goes down when spent", entity.get_currency(), 70)
	# The lifetime tally must ignore spending, otherwise "every 500 currency earned"
	# would be gameable by hoarding.
	_check_int("lifetime earned ignores spending", entity.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), 100)
	_check_bool("can_afford", entity.can_afford(70) and not entity.can_afford(71), true)

# --- effects ---------------------------------------------------------------

func _test_notification_effect() -> void:
	var entity := EntityModel.new()
	var effect := EffectCurrencyOnWaveEnd.new()
	effect.currency_per_stack = 50
	entity.effects.register(EffectInstance.new(effect, StringName("test"), 2))

	entity.notify(Hooks.Hook.ON_WAVE_ENDED, WaveEvent.new())
	_check_int("notification: currency scales with stacks", entity.get_currency(), 100)

	entity.notify(Hooks.Hook.ON_CRIT, EventPayload.new())
	_check_int("unrelated hook does not fire the effect", entity.get_currency(), 100)

func _test_pipeline_effect() -> void:
	var entity := EntityModel.new()
	entity.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 200.0)

	var armor := EffectArmorFromMaxHp.new()
	armor.max_hp_ratio = 0.1
	entity.effects.register(EffectInstance.new(armor, StringName("test")))

	var damage := DamageEvent.new()
	damage.amount = 50.0
	entity.pipeline(Hooks.Hook.TAKE_DAMAGE, damage)

	_check("pipeline absorbs damage", damage.absorbed, 20.0)
	_check("final damage", damage.final_amount(), 30.0)

	var small := DamageEvent.new()
	small.amount = 5.0
	entity.pipeline(Hooks.Hook.TAKE_DAMAGE, small)
	_check("absorption never exceeds damage", small.final_amount(), 0.0)

func _test_counter_effect() -> void:
	var entity := EntityModel.new()
	var effect := EffectStatPerCounter.new()
	effect.counter = CounterTypes.Counter.BULLETS_FIRED
	effect.step = 1000
	effect.stat = StatTypes.Stat.RANGED_DAMAGE
	effect.modifier_type = StatTypes.Modifier.PERCENT
	effect.value_per_step = 0.01

	entity.effects.register(EffectInstance.new(effect, StringName("test")))
	entity.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 100.0)

	entity.counters.add(CounterTypes.Counter.BULLETS_FIRED, 2500)
	entity.notify(Hooks.Hook.ON_WEAPON_FIRED, EventPayload.new())
	_check("counter effect applies thresholds", entity.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 102.0)

	entity.notify(Hooks.Hook.ON_WEAPON_FIRED, EventPayload.new())
	_check("counter effect is idempotent", entity.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 102.0)

	var other := EntityModel.new()
	other.effects.register(EffectInstance.new(effect, StringName("test")))
	other.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 100.0)
	other.notify(Hooks.Hook.ON_WEAPON_FIRED, EventPayload.new())
	_check("state does not leak between holders", other.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 100.0)

# --- items -----------------------------------------------------------------

func _make_item(tier: int, speed_flat: float, currency: int) -> ItemData:
	var item := ItemData.new()
	item.display_key = "TEST_ITEM"
	item.tier = tier

	var modifier := StatModifier.new()
	modifier.stat = StatTypes.Stat.MOVEMENT_SPEED
	modifier.modifier_type = StatTypes.Modifier.FLAT
	modifier.value = speed_flat
	item.static_stats = [modifier]

	if currency > 0:
		var effect := EffectCurrencyOnWaveEnd.new()
		effect.currency_per_stack = currency
		item.dynamic_effects = [effect]

	return item

func _test_items_lifecycle() -> void:
	var entity := EntityModel.new()
	var item := _make_item(1, 100.0, 10)

	entity.add_item(item, 3)
	_check("3 copies apply their modifiers", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 300.0)
	_check_int("inventory quantity", entity.items.get_quantity(item), 3)

	entity.notify(Hooks.Hook.ON_WAVE_ENDED, WaveEvent.new())
	_check_int("effect scales with owned count", entity.get_currency(), 30)

	entity.remove_item(item, 1)
	_check("selling one copy", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 200.0)

	entity.counters.set_value(CounterTypes.Counter.CURRENCY, 0)
	entity.notify(Hooks.Hook.ON_WAVE_ENDED, WaveEvent.new())
	_check_int("effect recomputes after a sale", entity.get_currency(), 20)

	entity.remove_item(item, 5)  # more than owned
	_check("selling the rest clears modifiers", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 0.0)
	_check_int("empty inventory", entity.items.get_quantity(item), 0)

	entity.counters.set_value(CounterTypes.Counter.CURRENCY, 0)
	entity.notify(Hooks.Hook.ON_WAVE_ENDED, WaveEvent.new())
	_check_int("effect removed along with the item", entity.get_currency(), 0)

func _test_item_tiers() -> void:
	var entity := EntityModel.new()
	entity.add_item(_make_item(4, 1.0, 0), 2)
	entity.add_item(_make_item(4, 1.0, 0), 1)
	entity.add_item(_make_item(1, 1.0, 0), 5)
	_check_int("counting by tier", entity.items.count_by_tier(4), 3)

## Goes through a REAL file on disk rather than an object built in code -
## exercises the whole path: .tres -> ItemData -> StatsManager + EffectDispatcher.
func _test_authored_tres() -> void:
	var item: ItemData = load("res://content/items/turbo_springs.tres")
	if item == null:
		_failed += 1
		printerr("  FAIL  could not load turbo_springs.tres")
		return

	var entity := EntityModel.new()
	entity.add_item(item, 2)

	# 2x (flat +100), 2x (percent +50%)  ->  (0 + 200) * (1 + 1.0)
	_check("tres: stats loaded from file", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 400.0)

	entity.notify(Hooks.Hook.ON_WAVE_ENDED, WaveEvent.new())
	_check_int("tres: dynamic effect from file", entity.get_currency(), 50)

	entity.remove_item(item, 2)
	_check("tres: full teardown", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 0.0)

# --- statuses --------------------------------------------------------------

func _make_slow(id: StringName, value: float, duration: float) -> StatusStatModifier:
	var slow := StatusStatModifier.new()
	slow.status_id = id
	slow.stat = StatTypes.Stat.MOVEMENT_SPEED
	slow.modifier_type = StatTypes.Modifier.PERCENT
	slow.value_per_stack = value
	slow.base_duration = duration
	return slow

func _test_status_modifier() -> void:
	var entity := EntityModel.new()
	entity.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0)

	entity.apply_status(_make_slow(&"slow_web", -0.3, 2.0))
	entity.apply_status(_make_slow(&"slow_frost", -0.2, 5.0))
	_check("two independent slows apply", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 50.0)
	_check_bool("status is queryable", entity.statuses.has(&"slow_web"), true)

	# The shorter one expires first - and must remove ONLY its own contribution.
	entity.tick_statuses(2.5)
	_check("expiry is surgical", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 80.0)
	_check_bool("expired status is gone", entity.statuses.has(&"slow_web"), false)
	_check_bool("the other status survives", entity.statuses.has(&"slow_frost"), true)

	entity.tick_statuses(5.0)
	_check("base restored after all expire", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 100.0)

func _test_status_stacking() -> void:
	var entity := EntityModel.new()
	entity.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0)

	var slow := _make_slow(&"slow", -0.1, 5.0)
	slow.max_stacks = 3

	entity.apply_status(slow)
	entity.apply_status(slow)
	_check_int("stacks accumulate", entity.statuses.get_stacks(&"slow"), 2)
	_check("modifier scales with stacks", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 80.0)

	entity.apply_status(slow, null, 5)
	_check_int("stacks are capped", entity.statuses.get_stacks(&"slow"), 3)
	_check("capped stacks cap the modifier", entity.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 70.0)

func _test_status_refresh_modes() -> void:
	var entity := EntityModel.new()

	var refresh := _make_slow(&"r", -0.1, 4.0)
	refresh.refresh_mode = StatusEffect.RefreshMode.REFRESH
	entity.apply_status(refresh)
	entity.tick_statuses(3.0)
	entity.apply_status(refresh)
	_check("REFRESH resets the timer", entity.statuses.get_active(&"r").remaining, 4.0)

	var extend := _make_slow(&"e", -0.1, 4.0)
	extend.refresh_mode = StatusEffect.RefreshMode.EXTEND
	entity.apply_status(extend)
	entity.tick_statuses(3.0)
	entity.apply_status(extend)
	_check("EXTEND adds to remaining", entity.statuses.get_active(&"e").remaining, 5.0)

func _test_status_damage_over_time() -> void:
	var target := EntityModel.new()
	target.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0)
	target.set_hp(100.0)

	var applier := EntityModel.new()
	applier.stats.add_modifier(StatTypes.Stat.POISON_DAMAGE, StatTypes.Modifier.BASE, 3.0)

	var poison := StatusDamageOverTime.new()
	poison.status_id = &"poison"
	poison.damage_per_stack = 2.0
	poison.scaling_stat = StatTypes.Stat.POISON_DAMAGE
	poison.base_duration = 3.0
	poison.tick_interval = 1.0

	target.apply_status(poison, applier)

	# damage_per_stack 2 + applier POISON_DAMAGE 3 = 5 per tick, 3 ticks
	target.tick_statuses(3.0)
	_check("DoT ticks scale off the applier", target.current_hp, 85.0)
	_check_bool("DoT expires with its duration", target.statuses.has(&"poison"), false)

	# The snapshot must survive the applier's death, not crash on it
	var orphan := EntityModel.new()
	orphan.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0)
	orphan.set_hp(100.0)
	orphan.apply_status(poison, null)
	orphan.tick_statuses(1.0)
	_check("DoT works without a living applier", orphan.current_hp, 98.0)

func _test_status_events_reach_both_sides() -> void:
	var target := EntityModel.new()
	var applier := EntityModel.new()

	var on_target := SpyEffect.new()
	on_target.watched = Hooks.Hook.ON_STATUS_RECEIVED
	target.effects.register(EffectInstance.new(on_target, StringName("spy")))

	var on_applier := SpyEffect.new()
	on_applier.watched = Hooks.Hook.ON_STATUS_APPLIED
	applier.effects.register(EffectInstance.new(on_applier, StringName("spy")))

	target.apply_status(_make_slow(&"slow", -0.1, 1.0), applier)

	_check_int("target is notified it received a status", on_target.calls, 1)
	_check_int("applier is notified it applied a status", on_applier.calls, 1)
	_check_bool(
		"the event carries both sides",
		on_applier.last_target.get_ref() == target and on_applier.last_applier.get_ref() == applier,
		true
	)

func _test_damage_pipeline_and_death() -> void:
	var target := EntityModel.new()
	target.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 30.0)
	target.set_hp(30.0)

	var killer := EntityModel.new()
	var on_kill := SpyEffect.new()
	on_kill.watched = Hooks.Hook.ON_KILL
	killer.effects.register(EffectInstance.new(on_kill, StringName("spy")))

	var blow := DamageEvent.new()
	blow.amount = 50.0
	blow.source = killer
	var dealt := target.apply_damage(blow)

	_check("damage is applied", dealt, 50.0)
	_check_bool("target died", target.is_alive, false)
	_check_int("killer is notified of the kill", on_kill.calls, 1)
	_check_int("kill counter", killer.counters.get_value(CounterTypes.Counter.ENEMIES_KILLED), 1)

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
