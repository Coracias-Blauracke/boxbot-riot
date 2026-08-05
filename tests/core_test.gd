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

## Halves every price. Exists to prove CALCULATE_PRICE is actually consulted
## rather than the shop quietly using its own arithmetic.
class DiscountEffect extends DynamicEffect:
	func get_hooks() -> Array:
		return [Hooks.Hook.CALCULATE_PRICE]

	func execute(_host: Variant, _inst: EffectInstance, event: EventPayload) -> void:
		var price := event as PriceEvent
		if price != null:
			price.price = price.price / 2

## Switches the buyer onto paying with MAX_HP at one point per two currency.
##
## The EXCHANGE RATE lives here, in the effect, and not in ShopManager - which
## is the whole design. A character who pays in blood and one who pays in max HP
## want completely different numbers, and only the effect knows which it is.
class BloodPriceEffect extends DynamicEffect:
	func get_hooks() -> Array:
		return [Hooks.Hook.CALCULATE_PRICE]

	func execute(_host: Variant, _inst: EffectInstance, event: EventPayload) -> void:
		var price := event as PriceEvent
		if price == null:
			return
		price.uses_stat_payment = true
		price.pay_with_stat = StatTypes.Stat.MAX_HP
		price.price = maxi(1, price.price / 2)

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
	_test_a_corpse_takes_no_further_damage()
	_test_healing_cannot_raise_a_corpse()
	_test_revive_restores_a_fraction_of_max_hp()
	_test_shop_rolls_respect_tier_weights()
	_test_shops_are_independent_per_player()
	_test_price_goes_through_the_pipeline()
	_test_buying_costs_currency_and_grants_the_item()
	_test_selling_refunds_without_crediting_earnings()
	_test_reroll_costs_more_every_time()
	_test_stat_payment_spends_the_stat_not_the_currency()
	_test_shop_slot_count_comes_from_the_stat()
	_test_modifier_text_reads_as_a_change_not_a_value()
	_test_buying_an_authored_item_actually_changes_the_stat()
	_test_status_chance_scales_off_the_applier()
	_test_status_damage_is_snapshotted_not_read_live()
	_test_status_rate_makes_it_tick_faster()
	_test_status_max_stacks_scales_and_caps()
	_test_status_duration_scales()
	_test_status_tick_count_falls_out_of_duration()
	_test_status_damage_is_tallied_per_status()
	_test_a_status_on_a_player_behaves_the_same()
	_test_census_counts_by_status()
	_test_census_prunes_what_has_been_freed()
	_test_census_caches_within_a_generation()
	_test_census_finds_what_is_nearby()
	_test_stat_per_world_count_tracks_a_live_number()
	_test_burn_spreads_off_a_corpse()
	_test_authored_statuses_load_and_differ()
	_test_outgoing_damage_sees_the_target()
	_test_hits_can_apply_a_status_but_ticks_cannot()
	_test_damage_bonus_against_a_status()
	_test_healing_off_a_statused_target()
	_test_doubling_stacks_only_on_the_applier_side()
	_test_apply_tally_counts_fresh_targets_only()
	_test_every_authored_item_loads()

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
	# Which stat scales it is now named through `scaling`, so bleed and burn
	# differ by authoring rather than by a field on the class.
	poison.scaling = [_make_scaling(StatusScaling.Axis.DAMAGE, StatTypes.Stat.POISON_DAMAGE)]
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

# --- death, corpses and revival --------------------------------------------
#
# REGRESSIONS. All three only became reachable once a downed player stopped
# being freed on death: before that, everything that died left the tree in the
# same frame and nothing could ever address it again.

## A bare EntityModel sits at zero HP and can never die - set_hp() clamps to
## zero, sees no change and returns before it can flip is_alive. Every death
## test has to give it a body first.
func _living(maximum: float = 100.0) -> EntityModel:
	var entity := EntityModel.new()
	entity.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, maximum, &"test_body")
	return entity

func _hit(victim: EntityModel, amount: float, attacker: EntityModel = null) -> float:
	var event := DamageEvent.new()
	event.source = attacker
	event.amount = amount
	return victim.apply_damage(event)

func _test_a_corpse_takes_no_further_damage() -> void:
	var killer := _living()
	var victim := _living()

	_hit(victim, 500.0, killer)
	_check_bool("victim died", victim.is_alive, false)
	_check_int("one kill credited", killer.counters.get_value(CounterTypes.Counter.ENEMIES_KILLED), 1)

	# The kill credit below apply_damage() only ever checked `not is_alive`, so
	# every later hit on the same corpse awarded another kill. A poison ticking
	# on a downed player would have farmed it for the rest of the run.
	var on_kill := SpyEffect.new()
	on_kill.watched = Hooks.Hook.ON_KILL
	killer.effects.register(EffectInstance.new(on_kill, &"kill_watcher"))

	var banked := victim.counters.get_value(CounterTypes.Counter.DAMAGE_TAKEN)

	_check("hitting a corpse lands nothing", _hit(victim, 500.0, killer), 0.0)
	_check_int("no second kill credited", killer.counters.get_value(CounterTypes.Counter.ENEMIES_KILLED), 1)
	_check_int("ON_KILL does not fire again", on_kill.calls, 0)
	_check_int(
		"the corpse banks no further damage taken",
		victim.counters.get_value(CounterTypes.Counter.DAMAGE_TAKEN), banked
	)

func _test_healing_cannot_raise_a_corpse() -> void:
	var victim := _living()
	_hit(victim, 500.0)

	# set_hp() would happily push current_hp back above zero while is_alive
	# stayed false, leaving something neither dead nor playable. Lifesteal and
	# regeneration both route through heal(), so this was one tick away.
	_check("healing a corpse heals nothing", victim.heal(50.0), 0.0)
	_check("the corpse stays at zero", victim.current_hp, 0.0)
	_check_bool("and stays dead", victim.is_alive, false)

func _test_revive_restores_a_fraction_of_max_hp() -> void:
	var player := _living(200.0)
	_hit(player, 500.0)
	_check_bool("player is down", player.is_alive, false)

	# A one-element array, not an int: a lambda captures outer locals by VALUE,
	# so an int incremented inside one is silently lost. The array is a
	# reference, so mutating its contents survives.
	var revived: Array[int] = [0]
	player.revived.connect(func() -> void: revived[0] += 1)

	_check("revive returns the health it granted", player.revive(0.25), 50.0)
	_check_bool("player is up", player.is_alive, true)
	_check_int("the revived signal fired once", revived[0], 1)

	# Reviving something already standing must be a no-op, or a second call
	# would top a wounded player back up for free.
	_check("reviving the living grants nothing", player.revive(1.0), 0.0)
	_check("and leaves their health alone", player.current_hp, 50.0)
	_check_int("no second signal", revived[0], 1)

# --- shop ------------------------------------------------------------------

func _make_priced_item(key: String, tier: int, price: int) -> ItemData:
	var item := ItemData.new()
	item.display_key = key
	item.tier = tier
	item.base_price = price
	return item

## Tier 3 is deliberately unreachable and tier 4 only opens up later, so the
## weighting can be asserted rather than eyeballed.
func _make_shop_data() -> ShopData:
	var data := ShopData.new()
	data.pool = [
		_make_priced_item("T1_A", 1, 10),
		_make_priced_item("T1_B", 1, 10),
		_make_priced_item("T2_A", 2, 20),
		_make_priced_item("T4_A", 4, 60),
	]
	data.offer_count = 4
	data.price_per_wave = 0.0
	data.reroll_base_cost = 5
	data.reroll_cost_growth = 2.0
	data.sell_ratio = 0.5
	data.base_tier_weights = PackedFloat32Array([100.0, 20.0, 0.0, 0.0])
	data.tier_weight_per_wave = PackedFloat32Array([0.0, 0.0, 0.0, 10.0])
	return data

func _make_buyer(currency: int = 500) -> EntityModel:
	var buyer := _living(200.0)
	buyer.add_currency(currency)
	return buyer

func _make_shop(index: int = 0) -> ShopManager:
	var shop := ShopManager.new()
	shop.data = _make_shop_data()
	shop.player_index = index
	return shop

func _tiers_offered(shop: ShopManager) -> Array:
	var tiers: Array = []
	for offer in shop.offers:
		tiers.append(offer.item.tier)
	return tiers

func _test_shop_rolls_respect_tier_weights() -> void:
	var shop := _make_shop()
	var buyer := _make_buyer()
	var rng := RunRandom.new(2468)

	var early_tiers: Array = []
	for attempt in 40:
		shop.open(buyer, 1, rng)
		early_tiers.append_array(_tiers_offered(shop))

	_check_int("the shop fills every slot", shop.offers.size(), 4)
	_check_bool("tier 4 is absent while its weight is 0", early_tiers.has(4), false)
	_check_bool("tier 3 has no items so it never appears", early_tiers.has(3), false)
	_check_bool("tier 1 dominates early", early_tiers.count(1) > early_tiers.count(2), true)

	# Its weight climbs 10 per wave, so by wave 20 it should be the common one.
	var late_tiers: Array = []
	for attempt in 40:
		shop.open(buyer, 20, rng)
		late_tiers.append_array(_tiers_offered(shop))

	_check_bool("tier 4 shows up once its weight has grown", late_tiers.has(4), true)

	# REGRESSION. Avoiding duplicates used to fall through to a zero-weight tier
	# once every other item had been drawn: the pool holds four items and the
	# shop wants four slots, so the tier 4 item was the only distinct one left
	# and went in on wave 1. Zero weight means "not yet", not "last resort".
	shop.data.allow_duplicate_offers = false
	var forced: Array = []
	for attempt in 30:
		shop.open(buyer, 1, rng)
		forced.append_array(_tiers_offered(shop))
	_check_bool("a zero-weight tier never fills a leftover slot", forced.has(4), false)
	_check_bool("repeats are preferred to breaking the curve", forced.size() > 30, true)

func _test_shops_are_independent_per_player() -> void:
	# Two shops, ONE generator, different sub-streams. This is what stops player
	# 1's rerolls from shifting what player 2 is offered.
	var rng := RunRandom.new(13579)
	var first := _make_shop(0)
	var second := _make_shop(1)
	var buyer := _make_buyer()

	first.open(buyer, 3, rng)
	var untouched: Array = _tiers_offered(first)

	# Player 2 rerolls repeatedly in between.
	second.open(buyer, 3, rng)
	for attempt in 5:
		second.open(buyer, 3, rng)

	var fresh_rng := RunRandom.new(13579)
	var replay := _make_shop(0)
	replay.open(buyer, 3, fresh_rng)

	_check_bool(
		"another player's rolls do not disturb this one",
		_tiers_offered(replay) == untouched, true
	)

func _test_price_goes_through_the_pipeline() -> void:
	var shop := _make_shop()
	var buyer := _make_buyer()
	var item := shop.data.pool[0]

	shop.wave_number = 1
	_check_int("base price with no effects", shop.quote(buyer, item).price, 10)

	# Wave scaling is authored on ShopData, not baked into the item.
	shop.data.price_per_wave = 0.5
	shop.wave_number = 3
	_check_int("price scales with the wave", shop.quote(buyer, item).price, 20)

	buyer.effects.register(EffectInstance.new(DiscountEffect.new(), &"half_off"))
	_check_int("and CALCULATE_PRICE gets the last word", shop.quote(buyer, item).price, 10)

func _test_buying_costs_currency_and_grants_the_item() -> void:
	var shop := _make_shop()
	var buyer := _make_buyer(30)
	var rng := RunRandom.new(555)
	shop.open(buyer, 1, rng)

	var offer := shop.offers[0]
	var price := offer.price

	_check_bool("the purchase goes through", shop.buy(buyer, 0), true)
	_check_int("currency is spent", buyer.get_currency(), 30 - price)
	_check_int("the item is owned", buyer.items.get_quantity(offer.item), 1)
	_check_int("and counted", buyer.counters.get_value(CounterTypes.Counter.ITEMS_BOUGHT), 1)
	_check_bool("the slot is marked sold", offer.sold, true)
	_check_bool("buying the same slot twice fails", shop.buy(buyer, 0), false)

	# Broke, so nothing else is affordable.
	buyer.counters.set_value(CounterTypes.Counter.CURRENCY, 0)
	_check_bool("no purchase without the currency", shop.buy(buyer, 1), false)
	_check_int("and nothing was taken", buyer.get_currency(), 0)

func _test_selling_refunds_without_crediting_earnings() -> void:
	var shop := _make_shop()
	var buyer := _make_buyer(100)
	var item := shop.data.pool[0]

	buyer.add_item(item)
	var earned_before := buyer.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED)

	_check_bool("the sale goes through", shop.sell(buyer, item), true)
	_check_int("the item is gone", buyer.items.get_quantity(item), 0)
	_check_int("half the authored price comes back", buyer.get_currency(), 105)

	# The exploit this guards: add_currency() also credits CURRENCY_EARNED, so a
	# buy-then-sell loop would farm every "for each 500 earned" effect for the
	# price of the spread.
	_check_int(
		"a refund is not earnings",
		buyer.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), earned_before
	)
	_check_bool("selling what you do not own fails", shop.sell(buyer, item), false)

func _test_reroll_costs_more_every_time() -> void:
	var shop := _make_shop()
	var buyer := _make_buyer(100)
	var rng := RunRandom.new(31)
	shop.open(buyer, 1, rng)

	_check_int("the first reroll is the base cost", shop.reroll_cost(), 5)
	_check_bool("and it is affordable", shop.reroll(buyer, rng), true)
	_check_int("currency is spent", buyer.get_currency(), 95)
	_check_int("the next one costs more", shop.reroll_cost(), 10)
	_check_int("the counter moves", buyer.counters.get_value(CounterTypes.Counter.REROLLS_USED), 1)

	# Reopening the shop resets the escalation - it is a per-visit decision, not
	# a per-run tax.
	shop.open(buyer, 2, rng)
	_check_int("reopening resets the price", shop.reroll_cost(), 5)

	buyer.counters.set_value(CounterTypes.Counter.CURRENCY, 2)
	_check_bool("a reroll you cannot afford fails", shop.reroll(buyer, rng), false)
	_check_int("and costs nothing", buyer.get_currency(), 2)

func _test_stat_payment_spends_the_stat_not_the_currency() -> void:
	# The feature PriceEvent was designed around: one co-op player pays currency
	# while another pays a stat, with no special case in the shop.
	var shop := _make_shop()
	var buyer := _make_buyer(100)
	buyer.effects.register(EffectInstance.new(BloodPriceEffect.new(), &"blood_price"))

	var rng := RunRandom.new(909)
	shop.open(buyer, 1, rng)

	var offer := shop.offers[0]
	_check_bool("the offer is flagged as a stat payment", offer.uses_stat_payment, true)

	var hp_before := buyer.get_max_hp()
	_check_bool("the purchase goes through", shop.buy(buyer, 0), true)
	_check_int("currency is untouched", buyer.get_currency(), 100)
	_check("max HP paid for it", buyer.get_max_hp(), hp_before - float(offer.price))

	# Must never be affordable down to the stat's floor - that would let a
	# purchase kill the buyer, or divide by zero further along.
	buyer.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.FLAT, -190.0, &"drain")
	_check_bool("cannot pay a stat down to its floor", shop.buy(buyer, 1), false)

func _test_shop_slot_count_comes_from_the_stat() -> void:
	# The requirement: one character sees 1 slot, another sees 8. Solved the way
	# WEAPON_SLOTS already solves it - as a stat - so an ITEM can grant a slot
	# too, and ShopManager never learns such a thing exists.
	var shop := _make_shop()
	var rng := RunRandom.new(4711)

	var plain := _make_buyer()
	shop.open(plain, 1, rng)
	_check_int("no opinion falls back to the authored count", shop.offers.size(), 4)

	var narrow := _make_buyer()
	narrow.stats.add_modifier(StatTypes.Stat.SHOP_SLOTS, StatTypes.Modifier.BASE, 1.0, &"character")
	shop.open(narrow, 1, rng)
	_check_int("a one-slot character sees one", shop.offers.size(), 1)

	var wide := _make_buyer()
	wide.stats.add_modifier(StatTypes.Stat.SHOP_SLOTS, StatTypes.Modifier.BASE, 8.0, &"character")
	shop.open(wide, 1, rng)
	_check_int("an eight-slot character sees eight", shop.offers.size(), 8)

	# And an item grants one on top, with no special case anywhere.
	wide.stats.add_modifier(StatTypes.Stat.SHOP_SLOTS, StatTypes.Modifier.FLAT, 1.0, &"item")
	shop.open(wide, 1, rng)
	_check_int("an item adds a slot", shop.offers.size(), 9)

## What a shop offer says it does. Derived from the item rather than authored
## per item, so it cannot drift away from the numbers it describes.
func _test_modifier_text_reads_as_a_change_not_a_value() -> void:
	var flat := StatMetadata.new()
	flat.stat = StatTypes.Stat.MAX_HP
	flat.format = StatMetadata.Format.FLAT

	_check_bool("a whole value drops its decimal", flat.format_value(100.0) == "100", true)
	_check_bool("a fractional one keeps it", flat.format_value(1.5) == "1.5", true)
	_check_bool("a flat modifier carries its sign", flat.format_modifier(StatTypes.Modifier.FLAT, 10.0) == "+10", true)
	_check_bool("and a negative one", flat.format_modifier(StatTypes.Modifier.FLAT, -10.0) == "-10", true)

	# A PERCENT modifier is a proportion, not a quantity of the stat, so it reads
	# as a percentage whatever the stat's own format says.
	_check_bool(
		"a percent modifier is a percentage",
		flat.format_modifier(StatTypes.Modifier.PERCENT, 0.5) == "+50%", true
	)
	_check_bool(
		"a mult modifier reads as a factor",
		flat.format_modifier(StatTypes.Modifier.MULT, 1.5) == "x1.50", true
	)

	# ...but a FLAT modifier to a percent-FORMATTED stat is in that stat's unit.
	var chance := StatMetadata.new()
	chance.stat = StatTypes.Stat.CRIT_CHANCE
	chance.format = StatMetadata.Format.PERCENT
	_check_bool(
		"a flat modifier to a percent stat stays in its unit",
		chance.format_modifier(StatTypes.Modifier.FLAT, 0.08) == "+8%", true
	)

	# Good and bad is not the same as positive and negative: less spread is an
	# improvement, which is what higher_is_better is for.
	var spread := StatMetadata.new()
	spread.stat = StatTypes.Stat.SPREAD_ANGLE
	spread.higher_is_better = false
	_check_bool("less spread is an improvement", spread.is_improvement(-0.2), true)
	_check_bool("more spread is not", spread.is_improvement(0.2), false)
	_check_bool("more health is", flat.is_improvement(10.0), true)

## END TO END on the REAL content, not on a fabricated item.
##
## Every other shop test builds items with no stats on them, so all of them
## would still pass if buying moved nothing at all. This one goes through the
## authored .tres, the authored pool and ShopManager.buy(), and then asks the
## stat.
func _test_buying_an_authored_item_actually_changes_the_stat() -> void:
	var shop_data: ShopData = load("res://content/shop/default_shop.tres")
	var plating: ItemData = load("res://content/items/scrap_plating.tres")
	var sights: ItemData = load("res://content/items/machined_sights.tres")
	if shop_data == null or plating == null or sights == null:
		_failed += 1
		printerr("  FAIL  authored shop content did not load")
		return

	_check_bool("the authored pool is not empty", shop_data.pool.is_empty(), false)

	var shop := ShopManager.new()
	shop.data = shop_data
	shop.wave_number = 1

	var buyer := _living(100.0)
	buyer.add_currency(500)

	# Placed by hand rather than rolled, so the assertion is about the purchase
	# rather than about what the dice offered.
	var offer := ShopOffer.new()
	offer.item = plating
	offer.price = shop.quote(buyer, plating).price
	shop.offers = [offer]

	var hp_before := buyer.get_max_hp()
	_check_bool("scrap plating is bought", shop.buy(buyer, 0), true)
	_check("and max HP actually moves by the authored +10", buyer.get_max_hp(), hp_before + 10.0)

	# The other direction: an item whose whole point is a NEGATIVE modifier on a
	# stat where less is better.
	var spread_offer := ShopOffer.new()
	spread_offer.item = sights
	shop.offers = [spread_offer]

	buyer.stats.add_modifier(StatTypes.Stat.SPREAD_ANGLE, StatTypes.Modifier.BASE, 10.0, &"weapon")
	var spread_before := buyer.stats.get_stat(StatTypes.Stat.SPREAD_ANGLE)
	_check_bool("machined sights are bought", shop.buy(buyer, 0), true)
	_check_bool(
		"spread went DOWN (%.1f -> %.1f)" % [spread_before, buyer.stats.get_stat(StatTypes.Stat.SPREAD_ANGLE)],
		buyer.stats.get_stat(StatTypes.Stat.SPREAD_ANGLE) < spread_before, true
	)
	_check(
		"ranged damage moves by the authored +3",
		buyer.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 3.0
	)

	# Selling has to hand the stat back, or an item is a one-way purchase that
	# quietly keeps working after it is gone.
	shop.sell(buyer, plating)
	_check("selling gives the max HP back", buyer.get_max_hp(), hp_before)

# --- statuses: the resolved-parameter machinery -----------------------------
#
# Every axis is checked the same way: give the APPLIER a stat, apply the status,
# then assert the status sitting on the TARGET behaves differently. That shape
# is the whole design - a status' parameters belong to whoever inflicted it and
# are frozen at the moment it landed.

func _make_scaling(axis: StatusScaling.Axis, stat: StatTypes.Stat) -> StatusScaling:
	var entry := StatusScaling.new()
	entry.axis = axis
	entry.stat = stat
	return entry

func _make_bleed(scaling: Array[StatusScaling] = []) -> StatusDamageOverTime:
	var bleed := StatusDamageOverTime.new()
	bleed.status_id = &"bleed"
	bleed.base_duration = 5.0
	bleed.tick_interval = 1.0
	bleed.max_stacks = 10
	bleed.damage_per_stack = 1.0
	bleed.damage_type = StatTypes.DamageType.BLEED
	bleed.refresh_mode = StatusEffect.RefreshMode.REFRESH
	bleed.scaling = scaling
	return bleed

func _test_status_chance_scales_off_the_applier() -> void:
	# chance starts at 1.0, so a scaling stat is only visible in the FAILURE
	# direction: a negative modifier has to make the roll miss sometimes.
	var bleed := _make_bleed([_make_scaling(StatusScaling.Axis.CHANCE, StatTypes.Stat.BLEED_CHANCE)])

	var cursed := _living()
	cursed.stats.add_modifier(StatTypes.Stat.BLEED_CHANCE, StatTypes.Modifier.FLAT, -0.5, &"curse")

	var landed := 0
	for attempt in 400:
		var victim := _living()
		victim.rng = RunRandom.new(attempt + 1)
		if victim.apply_status(bleed, cursed) != null:
			landed += 1
	_check_bool("a chance stat moves the roll (%d/400)" % landed, landed > 120 and landed < 280, true)

	# Without the penalty it always lands, so the number above is the stat and
	# not the generator being noisy.
	var clean := _living()
	var always := 0
	for attempt in 50:
		var victim := _living()
		victim.rng = RunRandom.new(attempt + 1)
		if victim.apply_status(bleed, clean) != null:
			always += 1
	_check_int("with no penalty it always lands", always, 50)

func _test_status_damage_is_snapshotted_not_read_live() -> void:
	var bleed := _make_bleed([_make_scaling(StatusScaling.Axis.DAMAGE, StatTypes.Stat.BLEED_DAMAGE)])

	var attacker := _living()
	var handle := attacker.stats.add_modifier(
		StatTypes.Stat.BLEED_DAMAGE, StatTypes.Modifier.FLAT, 4.0, &"buff"
	)

	var victim := _living(200.0)
	victim.apply_status(bleed, attacker)

	# THE POINT: the buff is gone before the first tick. A live read would
	# retroactively weaken bleed already ticking; a snapshot does not.
	attacker.stats.remove_modifier(handle)

	var before := victim.current_hp
	victim.tick_statuses(1.0)
	_check("the snapshot survives the buff expiring", before - victim.current_hp, 5.0)

	# A status applied AFTER the buff is gone is correspondingly weaker, which is
	# what proves the snapshot is per application rather than taken once ever.
	var second := _living(200.0)
	second.apply_status(bleed, attacker)
	var second_before := second.current_hp
	second.tick_statuses(1.0)
	_check("a later application reads the weaker stats", second_before - second.current_hp, 1.0)

func _test_status_rate_makes_it_tick_faster() -> void:
	var bleed := _make_bleed([_make_scaling(StatusScaling.Axis.RATE, StatTypes.Stat.BLEED_RATE)])

	var plain_attacker := _living()
	var fast_attacker := _living()
	# +100% rate halves the interval, so one second buys two ticks, not one.
	fast_attacker.stats.add_modifier(
		StatTypes.Stat.BLEED_RATE, StatTypes.Modifier.FLAT, 1.0, &"pacemaker"
	)

	var plain := _living(200.0)
	plain.apply_status(bleed, plain_attacker)
	var plain_before := plain.current_hp
	plain.tick_statuses(1.0)

	var hurried := _living(200.0)
	hurried.apply_status(bleed, fast_attacker)
	var hurried_before := hurried.current_hp
	hurried.tick_statuses(1.0)

	_check("one tick at the authored rate", plain_before - plain.current_hp, 1.0)
	_check("two ticks at double rate", hurried_before - hurried.current_hp, 2.0)

func _test_status_max_stacks_scales_and_caps() -> void:
	var bleed := _make_bleed(
		[_make_scaling(StatusScaling.Axis.MAX_STACKS, StatTypes.Stat.BLEED_MAX_STACKS)]
	)
	bleed.max_stacks = 2

	var attacker := _living()
	var victim := _living(500.0)
	for attempt in 6:
		victim.apply_status(bleed, attacker)
	_check_int("stacks stop at the authored cap", victim.statuses.get_stacks(&"bleed"), 2)

	# The raised cap has to apply on the very application that grants it, which
	# is why the cap is resolved BEFORE the stacks are clamped to it.
	attacker.stats.add_modifier(
		StatTypes.Stat.BLEED_MAX_STACKS, StatTypes.Modifier.FLAT, 1.0, &"item"
	)
	var wider := _living(500.0)
	for attempt in 6:
		wider.apply_status(bleed, attacker)
	_check_int("and at the raised cap with the item", wider.statuses.get_stacks(&"bleed"), 3)

func _test_status_duration_scales() -> void:
	var bleed := _make_bleed(
		[_make_scaling(StatusScaling.Axis.DURATION, StatTypes.Stat.BLEED_RATE)]
	)

	var attacker := _living()
	attacker.stats.add_modifier(StatTypes.Stat.BLEED_RATE, StatTypes.Modifier.FLAT, 3.0, &"item")

	var victim := _living(500.0)
	var status := victim.apply_status(bleed, attacker)
	_check("duration takes the bonus", status.remaining, 8.0)

func _test_status_tick_count_falls_out_of_duration() -> void:
	# The requested rule - "five ticks, and a new stack resets the count" - needs
	# no counter of its own. It is duration divided by interval, plus REFRESH.
	var bleed := _make_bleed()

	var attacker := _living()
	var victim := _living(500.0)
	victim.apply_status(bleed, attacker)

	var before := victim.current_hp
	for tick in 10:
		victim.tick_statuses(1.0)
	_check("exactly five ticks land, then it is gone", before - victim.current_hp, 5.0)
	_check_bool("and it has expired", victim.statuses.has(&"bleed"), false)

	# Reapplying partway through resets the clock, so the total exceeds five.
	var renewed := _living(500.0)
	renewed.apply_status(bleed, attacker)
	var renewed_before := renewed.current_hp
	for tick in 4:
		renewed.tick_statuses(1.0)
	renewed.apply_status(bleed, attacker)
	for tick in 10:
		renewed.tick_statuses(1.0)
	_check_bool(
		"a refresh extends the tick count (%.0f)" % (renewed_before - renewed.current_hp),
		renewed_before - renewed.current_hp > 5.0, true
	)

func _test_status_damage_is_tallied_per_status() -> void:
	# "Every 1000 fire damage dealt" must not be fed by a sword, so the tally is
	# per status rather than into DAMAGE_DEALT alone.
	var burn := _make_bleed()
	burn.status_id = &"burn"
	burn.damage_counter = CounterTypes.Counter.BURN_DAMAGE_DEALT
	burn.damage_per_stack = 3.0

	var attacker := _living()
	var victim := _living(200.0)
	victim.apply_status(burn, attacker)
	victim.tick_statuses(1.0)

	_check_int(
		"the burn tally moves",
		attacker.counters.get_value(CounterTypes.Counter.BURN_DAMAGE_DEALT), 3
	)
	_check_int(
		"and the generic damage tally moves too",
		attacker.counters.get_value(CounterTypes.Counter.DAMAGE_DEALT), 3
	)

func _test_a_status_on_a_player_behaves_the_same() -> void:
	# Statuses must work on a player and on a destructible crate exactly as on an
	# enemy. There is one EntityModel, so this is really a check that nothing has
	# quietly grown a special case for who can be afflicted.
	var bleed := _make_bleed()
	var enemy_side := _living(100.0)
	var player_side := _living(100.0)

	enemy_side.apply_status(bleed, player_side)
	player_side.apply_status(bleed, enemy_side)

	enemy_side.tick_statuses(1.0)
	player_side.tick_statuses(1.0)

	_check("the enemy bleeds", 100.0 - enemy_side.current_hp, 1.0)
	_check("and so does the player", 100.0 - player_side.current_hp, 1.0)

# --- census -----------------------------------------------------------------

func _test_census_counts_by_status() -> void:
	var burn := _make_bleed()
	burn.status_id = &"burn"

	var census := WorldCensus.new()
	var attacker := _living()
	var registered: Array[EntityModel] = []

	for index in 5:
		var entity := _living(100.0)
		census.register(entity)
		registered.append(entity)
		if index < 3:
			entity.apply_status(burn, attacker)

	_check_int("five registered and alive", census.count_alive(), 5)
	_check_int("three of them burning", census.count_with_status(&"burn"), 3)
	_check_int("none carry two statuses", census.count_with_at_least(2), 0)

	registered[0].apply_status(_make_bleed(), attacker)
	census.invalidate()
	_check_int("one now carries two", census.count_with_at_least(2), 1)

func _test_census_prunes_what_has_been_freed() -> void:
	# The reason this is derived rather than counted by signals: a freed entity
	# has to simply vanish. There is no unregister() to forget to call.
	var census := WorldCensus.new()
	var kept := _living(100.0)
	census.register(kept)

	var doomed := _living(100.0)
	census.register(doomed)
	_check_int("both counted", census.count_alive(), 2)

	doomed = null
	census.invalidate()
	_check_int("the freed one prunes itself", census.count_alive(), 1)

	# A corpse is still registered but is not alive, which is a different thing
	# from having been freed.
	_hit(kept, 500.0)
	census.invalidate()
	_check_int("a corpse is not counted alive", census.count_alive(), 0)

func _test_census_caches_within_a_generation() -> void:
	var census := WorldCensus.new()
	var entity := _living(100.0)
	census.register(entity)
	_check_int("counted once", census.count_alive(), 1)

	# Killed WITHOUT invalidating. The cached answer is deliberately stale for
	# the rest of the frame - that is what makes twenty queries cost one walk.
	_hit(entity, 500.0)
	_check_int("the cache holds for the frame", census.count_alive(), 1)

	census.invalidate()
	_check_int("and refreshes on the next", census.count_alive(), 0)

func _at(position: Vector2, maximum: float = 100.0) -> EntityModel:
	var entity := _living(maximum)
	entity.world_position = position
	return entity

func _test_census_finds_what_is_nearby() -> void:
	var census := WorldCensus.new()
	var centre := _at(Vector2.ZERO)
	var near := _at(Vector2(50.0, 0.0))
	var far := _at(Vector2(400.0, 0.0))
	for entity in [centre, near, far]:
		census.register(entity)

	var found := census.entities_within(Vector2.ZERO, 100.0, centre)
	_check_int("only the near one, and not the excluded centre", found.size(), 1)
	_check_bool("and it is the right one", found[0] == near, true)

	# A corpse is not a spread target: it is filtered by _living().
	_hit(near, 500.0)
	census.invalidate()
	_check_int("a corpse is not nearby", census.entities_within(Vector2.ZERO, 100.0, centre).size(), 0)

func _test_stat_per_world_count_tracks_a_live_number() -> void:
	# The distinguishing property against EffectStatPerCounter: this number goes
	# DOWN as well as up, so the effect has to be idempotent rather than additive.
	var burn := _make_bleed()
	burn.status_id = &"burn"

	var effect := EffectStatPerWorldCount.new()
	effect.status_id = &"burn"
	effect.stat = StatTypes.Stat.ATTACK_SPEED
	effect.modifier_type = StatTypes.Modifier.PERCENT
	effect.value_per_target = 0.01

	var census := WorldCensus.new()
	var player := _living()
	# A PERCENT modifier scales the base+flat pool, so without a base there is
	# nothing to scale and the stat sits on its floor. Easy to forget, and the
	# reason this assertion is written against 1.0 rather than 0.
	player.stats.add_modifier(StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.BASE, 1.0, &"body")
	player.effects.register(EffectInstance.new(effect, &"pyrojoy"))

	var burning: Array[EntityModel] = []
	for index in 3:
		var enemy := _living(100.0)
		census.register(enemy)
		enemy.apply_status(burn, player)
		burning.append(enemy)

	var tick := TickEvent.new()
	tick.census = census
	player.notify(Hooks.Hook.ON_TICK, tick)
	_check("three burning is +3%", player.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 1.03)

	# One dies. The bonus has to FALL, which an additive effect could not do.
	_hit(burning[0], 500.0)
	census.invalidate()
	player.notify(Hooks.Hook.ON_TICK, tick)
	_check("and drops back to +2% when one dies", player.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 1.02)

	# Ticking again with nothing changed must not stack it up.
	player.notify(Hooks.Hook.ON_TICK, tick)
	player.notify(Hooks.Hook.ON_TICK, tick)
	_check("repeated ticks do not accumulate", player.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 1.02)

func _test_burn_spreads_off_a_corpse() -> void:
	var burn := StatusSpreadOnDeath.new()
	burn.status_id = &"burn"
	burn.base_duration = 2.5
	burn.tick_interval = 0.5
	burn.max_stacks = 1
	burn.damage_per_stack = 1.0
	burn.spread_radius = 100.0
	burn.max_targets = 3

	var census := WorldCensus.new()
	var player := _living()
	census.register(player)

	var victim := _at(Vector2.ZERO, 3.0)
	var neighbour := _at(Vector2(60.0, 0.0))
	var distant := _at(Vector2(500.0, 0.0))
	for entity in [victim, neighbour, distant]:
		census.register(entity)

	victim.apply_status(burn, player)
	_check_bool("the victim is burning", victim.statuses.has(&"burn"), true)
	_check_bool("the neighbour is not yet", neighbour.statuses.has(&"burn"), false)

	# Burned to death by its own status, which is the case that matters: the
	# spread has to fire from ON_DEATH, and the status is what killed it.
	for tick in 6:
		victim.tick_statuses(0.5)

	_check_bool("the victim died", victim.is_alive, false)
	_check_bool("and the fire jumped to the neighbour", neighbour.statuses.has(&"burn"), true)
	_check_bool("but not across the map", distant.statuses.has(&"burn"), false)

	# Credit stays with the original applier through the jump, so a chain still
	# feeds that player's tallies rather than the corpse's.
	neighbour.tick_statuses(0.5)
	_check_bool(
		"the spreading fire still credits the player",
		player.counters.get_value(CounterTypes.Counter.DAMAGE_DEALT) > 0, true
	)

func _test_authored_statuses_load_and_differ() -> void:
	# The four are ONE mechanic with different numbers. This asserts the numbers
	# actually differ, because a copy-paste that left them identical would look
	# perfectly fine in the files.
	var bleed: StatusEffect = load("res://content/statuses/bleed.tres")
	var poison: StatusEffect = load("res://content/statuses/poison.tres")
	var burn: StatusEffect = load("res://content/statuses/burn.tres")
	var slow: StatusEffect = load("res://content/statuses/slow.tres")

	if bleed == null or poison == null or burn == null or slow == null:
		_failed += 1
		printerr("  FAIL  authored statuses did not load")
		return

	_check_int("bleed caps at ten stacks", bleed.max_stacks, 10)
	_check_bool("poison stacks effectively without limit", poison.max_stacks > 50, true)
	_check_int("burn allows exactly one", burn.max_stacks, 1)
	_check_bool("burn is the one that spreads", burn is StatusSpreadOnDeath, true)
	_check("slow never ticks", slow.tick_interval, 0.0)

	# Five ticks for everything that ticks, which is the authored rule.
	_check("bleed lasts five ticks", bleed.base_duration / bleed.tick_interval, 5.0)
	_check("and so does burn", burn.base_duration / burn.tick_interval, 5.0)

# --- the effect archetypes the authored items needed ------------------------

func _test_outgoing_damage_sees_the_target() -> void:
	# The distinction that made this hook necessary: CALCULATE_DAMAGE fires once
	# per SHOT, before a target exists. This one fires per impact and can read
	# who is being hit.
	var spy := SpyEffect.new()
	spy.watched = Hooks.Hook.ON_OUTGOING_DAMAGE

	var attacker := _living()
	attacker.effects.register(EffectInstance.new(spy, &"watcher"))
	var victim := _living(100.0)

	_hit(victim, 10.0, attacker)
	_check_int("the attacker's pipeline ran", spy.calls, 1)

	# And it is a PIPELINE, so it can still change the number.
	_check_int("it is registered as a pipeline", Hooks.kind_of(Hooks.Hook.ON_OUTGOING_DAMAGE), Hooks.Kind.PIPELINE)

func _test_hits_can_apply_a_status_but_ticks_cannot() -> void:
	var bleed := _make_bleed()

	var on_hit := EffectApplyStatusOnHit.new()
	on_hit.status = bleed
	on_hit.damage_types = [StatTypes.DamageType.MELEE]

	var attacker := _living()
	attacker.effects.register(EffectInstance.new(on_hit, &"sharp_blade"))

	var victim := _living(200.0)
	_hit(victim, 5.0, attacker)
	_check_bool("a melee hit causes bleeding", victim.statuses.has(&"bleed"), true)

	# THE TRAP: bleed deals BLEED damage, which would trigger the same effect and
	# refresh its own timer every tick - a status that never ends.
	var before := victim.statuses.get_active(&"bleed").remaining
	victim.tick_statuses(0.5)
	var after := victim.statuses.get_active(&"bleed").remaining
	_check_bool("a bleed tick does not reapply bleed (%.1f -> %.1f)" % [before, after], after < before, true)

	# And a damage type it was not authored for does nothing.
	var untouched := _living(200.0)
	var ranged := DamageEvent.new()
	ranged.source = attacker
	ranged.amount = 5.0
	ranged.damage_type = StatTypes.DamageType.RANGED
	untouched.apply_damage(ranged)
	_check_bool("a ranged hit does not, on a melee-only item", untouched.statuses.has(&"bleed"), false)

func _test_damage_bonus_against_a_status() -> void:
	var burn := _make_bleed()
	burn.status_id = &"burn"

	var fuel := EffectDamageVersusStatus.new()
	fuel.status_id = &"burn"
	fuel.bonus = 0.5

	var attacker := _living()
	attacker.effects.register(EffectInstance.new(fuel, &"fuel"))

	var plain := _living(200.0)
	_check("no bonus against a clean target", _hit(plain, 10.0, attacker), 10.0)

	var burning := _living(200.0)
	burning.apply_status(burn, attacker)
	_check("and +50% against a burning one", _hit(burning, 10.0, attacker), 15.0)

	# The count variant, which is the same class with the other field set.
	var diverse := EffectDamageVersusStatus.new()
	diverse.status_id = &""
	diverse.minimum_status_count = 2
	diverse.bonus = 0.5

	var counter_attacker := _living()
	counter_attacker.effects.register(EffectInstance.new(diverse, &"diverse"))

	var one_status := _living(200.0)
	one_status.apply_status(burn, counter_attacker)
	_check("one status is not enough", _hit(one_status, 10.0, counter_attacker), 10.0)

	one_status.apply_status(_make_bleed(), counter_attacker)
	_check("two statuses earn the bonus", _hit(one_status, 10.0, counter_attacker), 15.0)

func _test_healing_off_a_statused_target() -> void:
	var poison := _make_bleed()
	poison.status_id = &"poison"

	var sandwich := EffectHealWhenHittingStatus.new()
	sandwich.status_id = &"poison"
	sandwich.chance = 1.0
	sandwich.heal_amount = 3.0

	var attacker := _living(100.0)
	attacker.effects.register(EffectInstance.new(sandwich, &"green_sandwich"))
	_hit(attacker, 50.0)
	_check("the attacker is wounded", attacker.current_hp, 50.0)

	var clean := _living(200.0)
	_hit(clean, 5.0, attacker)
	_check("hitting a clean target heals nothing", attacker.current_hp, 50.0)

	var poisoned := _living(200.0)
	poisoned.apply_status(poison, attacker)
	_hit(poisoned, 5.0, attacker)
	_check("hitting a poisoned one heals", attacker.current_hp, 53.0)

func _test_doubling_stacks_only_on_the_applier_side() -> void:
	var bleed := _make_bleed()

	var doubler := EffectDoubleStatusStacks.new()
	doubler.chance = 1.0
	doubler.multiplier = 2

	var attacker := _living()
	attacker.effects.register(EffectInstance.new(doubler, &"universal_doubler"))

	var victim := _living(500.0)
	victim.apply_status(bleed, attacker, 2)
	_check_int("stacks are doubled on application", victim.statuses.get_stacks(&"bleed"), 4)

	# StatusManager runs the pipeline on the applier AND on the target with the
	# same payload. Without the applier check the holder would also double what
	# is inflicted ON them, which is the opposite of the item.
	var holder := _living(500.0)
	holder.effects.register(EffectInstance.new(doubler, &"universal_doubler"))
	var enemy := _living()
	holder.apply_status(bleed, enemy, 2)
	_check_int("but not what is inflicted on the holder", holder.statuses.get_stacks(&"bleed"), 2)

func _test_apply_tally_counts_fresh_targets_only() -> void:
	var poison := _make_bleed()
	poison.status_id = &"poison"
	poison.apply_counter = CounterTypes.Counter.ENEMIES_POISONED

	var attacker := _living()
	var first := _living(200.0)
	var second := _living(200.0)

	first.apply_status(poison, attacker)
	second.apply_status(poison, attacker)
	_check_int("two targets poisoned", attacker.counters.get_value(CounterTypes.Counter.ENEMIES_POISONED), 2)

	# Refreshing something already poisoned is not a new victim - otherwise
	# "every 100 enemies poisoned" would be farmed on one target.
	first.apply_status(poison, attacker)
	first.apply_status(poison, attacker)
	_check_int("refreshing does not count again", attacker.counters.get_value(CounterTypes.Counter.ENEMIES_POISONED), 2)

func _test_every_authored_item_loads() -> void:
	# A .tres pointing at a deleted effect loads as null and fails silently
	# mid-wave. The validator catches it too; this catches it in the suite.
	var pool: ShopData = load("res://content/shop/default_shop.tres")
	if pool == null:
		_failed += 1
		printerr("  FAIL  the authored shop pool did not load")
		return

	var broken := 0
	var with_effects := 0
	for item in pool.pool:
		if item == null or item.display_key.is_empty():
			broken += 1
			continue
		for effect in item.dynamic_effects:
			if effect == null:
				broken += 1
			else:
				with_effects += 1

	_check_bool("the pool has grown past the first eight (%d)" % pool.pool.size(), pool.pool.size() >= 19, true)
	_check_int("nothing in it is broken", broken, 0)
	_check_bool("and several carry real behaviour (%d)" % with_effects, with_effects >= 7, true)

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
