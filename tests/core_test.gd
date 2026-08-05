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
