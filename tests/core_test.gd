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
	_test_slow_power_scales_a_debuff_and_a_buff_alike()
	_test_the_authored_character_bleeds_on_every_hit()
	_test_weapon_slots_cap_what_is_carried()
	_test_buying_a_weapon_takes_a_slot_and_selling_frees_it()
	_test_a_full_rack_refuses_the_purchase_and_keeps_the_money()
	_test_the_offer_mix_comes_from_the_chance_not_the_pool_sizes()
	_test_every_purchasable_describes_itself_the_same_way()
	_test_weapon_and_item_purchases_are_tallied_apart()
	_test_the_authored_items_that_were_decorative_now_work()
	_test_weapon_classes_grant_bonuses_by_count()
	_test_a_weapon_counts_toward_every_tag_it_names()
	_test_selling_takes_the_class_bonus_back()
	_test_a_threshold_can_grant_a_behaviour_and_take_it_back()
	_test_armor_halves_at_fifteen_and_never_reaches_all()
	_test_dodge_is_capped_and_only_answers_hits()
	_test_armor_takes_a_share_of_what_is_left()
	_test_the_riot_shield_finally_does_something()
	_test_lifesteal_takes_a_share_of_what_landed()
	_test_regeneration_pays_out_once_a_second()
	_test_the_bloodstone_finally_does_something()
	_test_merging_two_copies_frees_a_slot()
	_test_a_full_rack_takes_a_purchase_only_when_it_merges()
	_test_a_device_joins_once_and_the_keyboard_is_a_device()
	_test_leaving_closes_the_gap_rather_than_leaving_a_hole()
	_test_currency_gain_scales_earnings_and_never_spending()
	_test_a_price_effect_discounts_by_kind_and_switches_the_payment()
	_test_the_blood_bank_pays_for_everything_in_blood()
	_test_the_model_applies_exactly_the_slot_modifiers_the_data_names()
	_test_a_default_pick_prefers_a_chassis_nobody_is_on()
	_test_leaving_takes_that_player_s_character_with_it()
	_test_selecting_wraps_and_two_players_may_share_a_chassis()
	_test_no_catalogue_means_the_run_keeps_its_own_character()
	_test_confirming_freezes_a_cursor_and_backing_out_thaws_it()
	_test_the_run_waits_for_every_joined_player_to_confirm()
	_test_a_grid_step_is_a_delta_the_view_chooses()
	_test_a_cursor_wraps_inside_its_row_and_its_column()
	_test_a_ragged_last_row_wraps_among_what_is_there()
	_test_the_rack_scrolls_only_when_the_cursor_would_leave_it()
	_test_an_orbiting_enemy_keeps_its_distance()
	_test_an_armed_enemy_gets_a_rack_to_put_it_in()
	_test_neutral_is_nobody_s_ally_and_nobody_s_enemy()
	_test_a_blast_reaches_the_other_side_and_spares_its_own()
	_test_blast_damage_tapers_towards_the_rim()
	_test_a_capped_blast_takes_the_nearest()
	_test_area_size_scales_the_radius()
	_test_a_blast_rolls_one_crit_for_everything_it_catches()
	_test_an_explosion_inherits_the_crit_of_the_shot_that_set_it_off()
	_test_a_blast_announces_itself_to_whoever_is_listening()
	_test_a_blast_with_nowhere_to_look_hurts_nobody()
	_test_a_blast_goes_through_the_targets_own_defences()
	_test_elemental_damage_finally_feeds_something()
	_test_a_bug_that_bursts_hurts_the_players_and_not_the_swarm()
	_test_an_exploding_kill_goes_off_where_the_victim_was()
	_test_a_second_copy_of_an_exploding_item_hits_harder()
	_test_a_chain_does_not_spend_its_targets_on_corpses()
	_test_the_authored_popper_bursts_on_death()
	_test_the_authored_mortar_explodes_where_it_lands()
	_test_a_behaviour_can_ask_for_less_than_full_speed()
	_test_a_charge_stops_before_it_commits()
	_test_a_dash_does_not_follow_you()
	_test_two_chargers_keep_separate_clocks()
	_test_flat_armor_costs_a_weak_hit_more_than_a_heavy_one()
	_test_the_authored_warden_is_a_wall_a_fast_weapon_cannot_chew()
	_test_a_dying_thing_can_ask_for_more_of_them()
	_test_a_timer_asks_once_per_interval_and_keeps_the_remainder()
	_test_two_holders_of_one_spawn_effect_keep_separate_clocks()
	_test_a_request_places_itself_around_whoever_asked()
	_test_the_authored_splitter_and_hive_ask_for_swarmlings()

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
	# A ticking status lives by its COUNT now, not by base_duration.
	poison.tick_count = 3

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
		tiers.append(offer.entry.tier)
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
	_check_int("the item is owned", buyer.items.get_quantity(offer.entry as ItemData), 1)
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
	offer.entry = plating
	offer.price = shop.quote(buyer, plating).price
	shop.offers = [offer]

	var hp_before := buyer.get_max_hp()
	_check_bool("scrap plating is bought", shop.buy(buyer, 0), true)
	_check("and max HP actually moves by the authored +10", buyer.get_max_hp(), hp_before + 10.0)

	# The other direction: an item whose whole point is a NEGATIVE modifier on a
	# stat where less is better.
	var spread_offer := ShopOffer.new()
	spread_offer.entry = sights
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
	bleed.tick_count = 5
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

	# But the TOTAL is unchanged: a faster status delivers its five ticks sooner,
	# it does not deliver more of them. Otherwise RATE would be a damage stat
	# wearing a pacing stat's name.
	for tick in 20:
		plain.tick_statuses(0.5)
		hurried.tick_statuses(0.5)
	_check("five ticks either way, just sooner", plain_before - plain.current_hp, 5.0)
	_check("and the fast one deals no more", hurried_before - hurried.current_hp, 5.0)

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
	# "Five ticks, and a new stack resets the count" is a COUNT, deliberately not
	# a duration. Measuring it in seconds would make a faster tick rate also
	# deliver more ticks, which turns pacing into damage.
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
	# No base of its own any more: EntityModel seeds every multiplicative stat
	# with its neutral, so adding another 1.0 here would read 2.0 and every
	# assertion below would be off by exactly double.
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
	_check_int("bleed gives five ticks", bleed.tick_count, 5)
	_check_int("and so does burn", burn.tick_count, 5)

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
	# Named on the CHANCE axis, because a stat only reaches a status the status
	# actually lists - which is the point of StatusScaling and easy to forget.
	var bleed := _make_bleed([_make_scaling(StatusScaling.Axis.CHANCE, StatTypes.Stat.BLEED_CHANCE)])

	var on_hit := EffectApplyStatusOnHit.new()
	on_hit.status = bleed
	on_hit.damage_types = [StatTypes.DamageType.MELEE]
	# Certain, so the mechanism is what is under test rather than the dice.
	on_hit.base_chance = 1.0

	var attacker := _living()
	attacker.effects.register(EffectInstance.new(on_hit, &"sharp_blade"))

	var victim := _living(200.0)
	_hit(victim, 5.0, attacker)
	_check_bool("a melee hit causes bleeding", victim.statuses.has(&"bleed"), true)

	# THE TRAP: bleed deals BLEED damage, which would trigger the same effect and
	# reset its own tick count every tick - a status that never ends. Measured on
	# ticks_left, which is what a ticking status actually spends.
	var before := victim.statuses.get_active(&"bleed").ticks_left
	# A full interval, or no tick fires and the assertion proves nothing.
	victim.tick_statuses(1.0)
	var after := victim.statuses.get_active(&"bleed").ticks_left
	_check_bool("a bleed tick does not reapply bleed (%d -> %d)" % [before, after], after < before, true)

	# And a damage type it was not authored for does nothing.
	var untouched := _living(200.0)
	var ranged := DamageEvent.new()
	ranged.source = attacker
	ranged.amount = 5.0
	ranged.damage_type = StatTypes.DamageType.RANGED
	untouched.apply_damage(ranged)
	_check_bool("a ranged hit does not, on a melee-only item", untouched.statuses.has(&"bleed"), false)

	# The default is 0.0, so an item grants NOTHING on its own and every point of
	# chance comes from stats. Defaulting to certain made "+10% chance to cause
	# bleeding" mean "always, minus ten", which is the opposite of the item.
	var stingy := EffectApplyStatusOnHit.new()
	stingy.status = bleed
	var miser := _living()
	miser.effects.register(EffectInstance.new(stingy, &"no_chance"))

	var lucky := _living(200.0)
	for attempt in 20:
		_hit(lucky, 1.0, miser)
	_check_bool("with no chance granted, nothing lands", lucky.statuses.has(&"bleed"), false)

	# ...and a stat alone is enough to make it happen.
	miser.stats.add_modifier(StatTypes.Stat.BLEED_CHANCE, StatTypes.Modifier.FLAT, 1.0, &"item")
	_hit(lucky, 1.0, miser)
	_check_bool("a chance stat alone makes it land", lucky.statuses.has(&"bleed"), true)

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

func _test_slow_power_scales_a_debuff_and_a_buff_alike() -> void:
	# POWER multiplies the authored magnitude rather than being added to it,
	# which is the whole reason one axis can serve a slow and a rage buff. Adding
	# would strengthen the buff and WEAKEN the debuff with the same number.
	var slow := StatusStatModifier.new()
	slow.status_id = &"slow"
	slow.base_duration = 3.0
	slow.max_stacks = 1
	slow.stat = StatTypes.Stat.MOVEMENT_SPEED
	slow.modifier_type = StatTypes.Modifier.PERCENT
	slow.value_per_stack = -0.3
	slow.scaling = [_make_scaling(StatusScaling.Axis.POWER, StatTypes.Stat.SLOW_POWER)]

	var plain := _living()
	var victim := _living()
	victim.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0, &"body")
	victim.apply_status(slow, plain)
	_check("authored slow is -30%", victim.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 70.0)

	var strong := _living()
	strong.stats.add_modifier(StatTypes.Stat.SLOW_POWER, StatTypes.Modifier.FLAT, 0.2, &"item")

	var harder := _living()
	harder.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 100.0, &"body")
	harder.apply_status(slow, strong)
	# -0.3 * 1.2 = -0.36, so a stronger slow makes them SLOWER, not faster.
	_check("+20% power deepens it to -36%", harder.stats.get_stat(StatTypes.Stat.MOVEMENT_SPEED), 64.0)

	# The same axis on a positive magnitude strengthens rather than reverses it.
	var rage := StatusStatModifier.new()
	rage.status_id = &"rage"
	rage.base_duration = 3.0
	rage.max_stacks = 1
	rage.stat = StatTypes.Stat.MELEE_DAMAGE
	rage.modifier_type = StatTypes.Modifier.PERCENT
	rage.value_per_stack = 0.25
	rage.scaling = [_make_scaling(StatusScaling.Axis.POWER, StatTypes.Stat.SLOW_POWER)]

	var buffed := _living()
	buffed.stats.add_modifier(StatTypes.Stat.MELEE_DAMAGE, StatTypes.Modifier.BASE, 100.0, &"body")
	buffed.apply_status(rage, strong)
	_check("and the same +20% strengthens a buff", buffed.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 130.0)

	# Duration scales too, so "slows last a second longer" is an ordinary item.
	var longer := StatusStatModifier.new()
	longer.status_id = &"slow"
	longer.base_duration = 3.0
	longer.max_stacks = 1
	longer.scaling = [_make_scaling(StatusScaling.Axis.DURATION, StatTypes.Stat.SLOW_DURATION)]

	var patient := _living()
	patient.stats.add_modifier(StatTypes.Stat.SLOW_DURATION, StatTypes.Modifier.FLAT, 2.0, &"item")
	var target := _living()
	var status := target.apply_status(longer, patient)
	_check("duration takes its own stat", status.remaining, 5.0)

## The authored loadout, asserted rather than inferred from a screenshot. A
## capture can show four bleeding enemies without proving the chance is 100% -
## a slow single-target weapon looks the same at 60%.
func _test_the_authored_character_bleeds_on_every_hit() -> void:
	var character: CharacterData = load("res://content/characters/test_character.tres")
	var bleed: StatusEffect = load("res://content/statuses/bleed.tres")
	if character == null or bleed == null:
		_failed += 1
		printerr("  FAIL  authored character or bleed did not load")
		return

	var player := EntityModel.new(character)
	for item in character.starting_items:
		player.add_item(item)

	# Two barbed edges at +0.15 and six serrated rounds at +0.10.
	_check("the loadout grants +90% bleed chance", player.stats.get_stat(StatTypes.Stat.BLEED_CHANCE), 0.9)

	# Each item rolls with its OWN base chance plus that shared pool, so the
	# weaker of the two is what has to clear 1.0 for the answer to be "always".
	var lowest_base := 1.0
	for item in character.starting_items:
		for effect in item.dynamic_effects:
			var on_hit := effect as EffectApplyStatusOnHit
			if on_hit != null:
				lowest_base = minf(lowest_base, on_hit.base_chance)
	_check_bool(
		"even the weakest source clears 100%% (%.2f + 0.90)" % lowest_base,
		lowest_base + 0.9 >= 1.0, true
	)

	# And end to end: twenty ranged hits, twenty targets, all bleeding.
	var missed := 0
	for attempt in 20:
		var victim := _living(200.0)
		victim.rng = RunRandom.new(attempt + 1)
		var shot := DamageEvent.new()
		shot.source = player
		shot.amount = 1.0
		shot.damage_type = StatTypes.DamageType.RANGED
		victim.apply_damage(shot)
		if not victim.statuses.has(&"bleed"):
			missed += 1
	_check_int("every ranged hit causes bleeding", missed, 0)

# --- assertions ------------------------------------------------------------

func _check(label: String, actual: float, expected: float) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s -> got %s, expected %s" % [label, actual, expected])

# --- weapon classes ---------------------------------------------------------

func _make_class(tag: StringName, steps: Array) -> WeaponClassData:
	var made := WeaponClassData.new()
	made.tag = tag
	made.display_key = "CLASS_%s" % String(tag).to_upper()

	# Each step is [required, stat, value] as a FLAT modifier.
	for step in steps:
		var modifier := StatModifier.new()
		modifier.stat = step[1]
		modifier.modifier_type = StatTypes.Modifier.FLAT
		modifier.value = step[2]

		var tier := WeaponClassTier.new()
		tier.required = step[0]
		tier.modifiers = [modifier]
		made.tiers.append(tier)

	return made

func _make_tagged_weapon(tags: Array[StringName]) -> WeaponData:
	var made := WeaponData.new()
	made.display_key = "W"
	made.tags = tags
	return made

func _class_set(entries: Array[WeaponClassData]) -> WeaponClassSet:
	var made := WeaponClassSet.new()
	made.classes = entries
	return made

func _test_weapon_classes_grant_bonuses_by_count() -> void:
	print("\n-- weapon classes --")
	var blade := _make_class(&"blade", [
		[2, StatTypes.Stat.MELEE_DAMAGE, 4.0],
		[4, StatTypes.Stat.MELEE_DAMAGE, 6.0],
	])

	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")
	holder.weapon_classes = _class_set([blade])

	var sword := _make_tagged_weapon([&"blade"] as Array[StringName])
	holder.add_weapon(sword)
	_check("one blade is below the threshold", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 0.0)

	holder.add_weapon(sword)
	_check("two blades cross the first tier", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)
	_check_int("two copies of one weapon count as two", holder.weapon_tag_count(&"blade"), 2)

	holder.add_weapon(sword)
	_check("three is still the first tier", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)

	# CUMULATIVE: crossing the second tier keeps the first. "Highest only" would
	# read 6.0 here and could not express a class where each step adds.
	holder.add_weapon(sword)
	_check("four stacks both tiers", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 10.0)
	_check_int("and the shop knows nothing is left to reach", blade.next_threshold(4), 0)
	_check_int("while at two it names the next one", blade.next_threshold(2), 4)

func _test_a_weapon_counts_toward_every_tag_it_names() -> void:
	print("\n-- two tags at once --")
	var blade := _make_class(&"blade", [[2, StatTypes.Stat.MELEE_DAMAGE, 4.0]])
	var gun := _make_class(&"gun", [[2, StatTypes.Stat.RANGED_DAMAGE, 3.0]])

	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")
	holder.weapon_classes = _class_set([blade, gun])

	# A bayonet is both, and should raise both counts rather than forcing a
	# choice the fiction does not have.
	var bayonet := _make_tagged_weapon([&"blade", &"gun"] as Array[StringName])
	holder.add_weapon(bayonet)
	holder.add_weapon(bayonet)

	_check_int("it counted as a blade", holder.weapon_tag_count(&"blade"), 2)
	_check_int("and as a gun", holder.weapon_tag_count(&"gun"), 2)
	_check("both bonuses land", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)
	_check("at the same time", holder.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 3.0)

## THE ONE THAT MATTERS. A count goes DOWN as well as up, and an incremental
## version that adds on acquisition and subtracts on loss breaks permanently the
## first time an event is missed - exactly the bug WorldCensus exists to avoid.
func _test_selling_takes_the_class_bonus_back() -> void:
	print("\n-- selling a set --")
	var blade := _make_class(&"blade", [
		[2, StatTypes.Stat.MELEE_DAMAGE, 4.0],
		[3, StatTypes.Stat.MELEE_DAMAGE, 6.0],
	])

	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")
	holder.weapon_classes = _class_set([blade])

	var sword := _make_tagged_weapon([&"blade"] as Array[StringName])
	for i in 3:
		holder.add_weapon(sword)
	_check("three blades stack both tiers", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 10.0)

	holder.remove_weapon(sword)
	_check("selling one drops the second tier", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)

	holder.remove_weapon(sword)
	_check("selling another drops the first", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 0.0)

	# IDEMPOTENT: recomputing without anything changing must not stack a second
	# copy on top of the first, which is what an add-only version would do.
	# One added, because two were removed from three and one is still carried.
	holder.add_weapon(sword)
	_check("back to two blades", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)
	holder.weapon_classes = _class_set([blade])
	_check("recomputing changes nothing", holder.stats.get_stat(StatTypes.Stat.MELEE_DAMAGE), 4.0)

## Thresholds are authored individually and need not be contiguous: a class may
## give NOTHING from one to five and something large at six. That is the shape
## a stat line cannot express, which is why tiers carry effects at all.
func _test_a_threshold_can_grant_a_behaviour_and_take_it_back() -> void:
	print("\n-- a behaviour at the top of a class --")
	var spy := SpyEffect.new()
	spy.watched = Hooks.Hook.ON_KILL

	var payoff := WeaponClassTier.new()
	payoff.required = 6
	payoff.effects = [spy]

	var loyal := WeaponClassData.new()
	loyal.tag = &"loyal"
	loyal.display_key = "CLASS_LOYAL"
	# ONE tier, at six. Nothing at all for the first five weapons.
	loyal.tiers = [payoff]

	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")
	holder.weapon_classes = _class_set([loyal])

	var weapon := _make_tagged_weapon([&"loyal"] as Array[StringName])
	for i in 5:
		holder.add_weapon(weapon)

	holder.notify(Hooks.Hook.ON_KILL, EventPayload.new())
	_check_int("five weapons grant nothing", spy.calls, 0)

	holder.add_weapon(weapon)
	holder.notify(Hooks.Hook.ON_KILL, EventPayload.new())
	_check_int("the sixth turns the behaviour on", spy.calls, 1)

	# And it must come back off. An effect that outlives the count that granted
	# it is the same silent-drift bug as a stat bonus that is never stripped.
	holder.remove_weapon(weapon)
	holder.notify(Hooks.Hook.ON_KILL, EventPayload.new())
	_check_int("dropping to five turns it off again", spy.calls, 1)

	holder.add_weapon(weapon)
	holder.notify(Hooks.Hook.ON_KILL, EventPayload.new())
	_check_int("and back on without stacking a second copy", spy.calls, 2)

# --- defence ----------------------------------------------------------------

func _armoured(armor: float, maximum: float = 1000.0) -> EntityModel:
	var entity := _living(maximum)
	entity.stats.add_modifier(StatTypes.Stat.ARMOR, StatTypes.Modifier.BASE, armor, &"test")
	return entity

## The anchor the whole curve is built from: fifteen armor halves the blow.
## Diminishing in REDUCTION and linear in SURVIVAL, which is the property that
## makes armor worth buying for ever without ever making anything untouchable.
func _test_armor_halves_at_fifteen_and_never_reaches_all() -> void:
	print("\n-- armor --")
	_check("no armor takes it all", _hit(_armoured(0.0), 100.0), 100.0)
	_check("five armor takes a quarter off", _hit(_armoured(5.0), 100.0), 75.0)
	_check("fifteen halves it", _hit(_armoured(15.0), 100.0), 50.0)
	_check("thirty leaves a third", _hit(_armoured(30.0), 100.0), 100.0 / 3.0)
	_check("forty-five leaves a quarter", _hit(_armoured(45.0), 100.0), 25.0)

	# The asymptote is the point. Something ALWAYS gets through, so effects that
	# hang on taking damage cannot be switched off by stacking armor.
	var mountain := _hit(_armoured(100000.0), 100.0)
	_check_bool("absurd armor still lets something through", mountain > 0.0, true)
	_check_bool("but almost nothing", mountain < 1.0, true)

	# Effective health rises LINEARLY: every point is worth 1/15 of max HP,
	# which is why there is no level at which armor stops paying.
	_check("fifteen armor doubles effective health", 100.0 / _hit(_armoured(15.0), 100.0) * 100.0, 200.0)
	_check("thirty triples it", 100.0 / _hit(_armoured(30.0), 100.0) * 100.0, 300.0)

func _test_dodge_is_capped_and_only_answers_hits() -> void:
	print("\n-- dodge --")
	var lucky := _living(1000.0)
	lucky.stats.add_modifier(StatTypes.Stat.DODGE, StatTypes.Modifier.BASE, 5.0, &"test")

	# Capped in get_stat, so the STAT SHEET shows the ceiling too - a player
	# stacking dodge past it can see that they have, instead of buying nothing.
	_check("dodge is capped where the table says", lucky.stats.get_stat(StatTypes.Stat.DODGE), 0.6)

	# Damage over time is not a blow and cannot be dodged. Without this every
	# status would quietly scale with the dodge stat.
	var certain := _living(1000.0)
	certain.stats.add_modifier(StatTypes.Stat.DODGE, StatTypes.Modifier.BASE, 1.0, &"test")
	certain.rng = RunRandom.new(4)

	var bleed := DamageEvent.new()
	bleed.amount = 20.0
	bleed.damage_type = StatTypes.DamageType.BLEED
	_check("a bleed tick cannot be dodged", certain.apply_damage(bleed), 20.0)

	# A hit at the cap is avoided 60% of the time, so over many swings some land
	# and some do not. Asserting the RANGE rather than a count keeps this from
	# breaking when the RNG stream shifts for an unrelated reason.
	var landed := 0
	for i in 200:
		var swing := DamageEvent.new()
		swing.amount = 1.0
		swing.damage_type = StatTypes.DamageType.MELEE
		if certain.apply_damage(swing) > 0.0:
			landed += 1
	_check_bool("some blows still land at the cap", landed > 0, true)
	_check_bool("and many do not", landed < 200, true)
	_check_bool("the dodges were tallied", certain.counters.get_value(CounterTypes.Counter.DODGES) > 0, true)

## ORDER, asserted rather than assumed. Flat absorption happens first and armor
## takes its share of what remains; the other way round would charge armor
## against damage an effect had already removed.
func _test_armor_takes_a_share_of_what_is_left() -> void:
	print("\n-- absorb then reduce --")
	var target := _armoured(15.0)

	var event := DamageEvent.new()
	event.amount = 100.0
	event.damage_type = StatTypes.DamageType.MELEE
	# As though an effect had soaked a flat 20 during TAKE_DAMAGE.
	event.absorbed = 20.0

	# 80 remain, armor halves them, so 40 land - not 30, which is what taking
	# half of the original 100 and then the flat 20 would give.
	_check("armor halves the remainder", target.apply_damage(event), 40.0)

## Against the AUTHORED file, because riot_shield has been documented as
## decorative since it was written - it granted ARMOR, ARMOR did nothing, and
## the item displayed perfectly while changing not one number in a fight.
func _test_the_riot_shield_finally_does_something() -> void:
	print("\n-- riot shield --")
	var shield := load("res://content/items/riot_shield.tres") as ItemData
	_check_bool("it loads", shield != null, true)

	var bare := _living(1000.0)
	var guarded := _living(1000.0)
	guarded.add_item(shield)

	var without := _hit(bare, 100.0)
	var with := _hit(guarded, 100.0)
	_check_bool("wearing it reduces the blow", with < without, true)

	# The exact figure follows from the curve and the item's authored ARMOR, so
	# retuning either shows up here rather than in a play-test six weeks later.
	var armor := guarded.stats.get_stat(StatTypes.Stat.ARMOR)
	_check("by exactly what the curve says", with, 100.0 * (1.0 - StatTypes.armor_reduction(armor)))

func _test_lifesteal_takes_a_share_of_what_landed() -> void:
	print("\n-- lifesteal --")
	var thief := _living(200.0)
	thief.stats.add_modifier(StatTypes.Stat.LIFESTEAL, StatTypes.Modifier.BASE, 0.5, &"item")
	thief.set_hp(100.0)

	_hit(_living(1000.0), 40.0, thief)
	_check("half of what landed comes back", thief.current_hp, 120.0)

	# From what LANDED, not what was intended: a heavily armoured target heals
	# its attacker less, which is the honest reading of stealing from damage
	# dealt and stops the victim's armor from inflating the thief's healing.
	thief.set_hp(100.0)
	_hit(_armoured(15.0, 1000.0), 40.0, thief)
	_check("armor on the target halves the steal too", thief.current_hp, 110.0)

	# HITS only. A bleed applied once would otherwise heal its applier for the
	# whole duration, and every status would quietly become a healing item.
	thief.set_hp(100.0)
	var tick := DamageEvent.new()
	tick.source = thief
	tick.amount = 40.0
	tick.damage_type = StatTypes.DamageType.BLEED
	_living(1000.0).apply_damage(tick)
	_check("a bleed tick steals nothing", thief.current_hp, 100.0)

func _test_regeneration_pays_out_once_a_second() -> void:
	print("\n-- regeneration --")
	var mender := _living(200.0)
	mender.stats.add_modifier(StatTypes.Stat.HP_REGEN, StatTypes.Modifier.BASE, 3.0, &"item")
	mender.set_hp(100.0)

	# Paid once a SECOND, not every frame. Sixty heals a second would fire
	# CALCULATE_HEAL and ON_HEAL sixty times for fractions of a point.
	for i in 30:
		mender.tick_regen(1.0 / 60.0)
	_check("half a second heals nothing yet", mender.current_hp, 100.0)

	for i in 30:
		mender.tick_regen(1.0 / 60.0)
	_check("a full second pays the whole stat", mender.current_hp, 103.0)

	# Losing the item must not pay out a second that was never earned.
	mender.stats.remove_all_from_source(&"item")
	for i in 30:
		mender.tick_regen(1.0 / 60.0)
	mender.stats.add_modifier(StatTypes.Stat.HP_REGEN, StatTypes.Modifier.BASE, 3.0, &"item")
	mender.tick_regen(0.5)
	_check("the debt was cleared while the stat was zero", mender.current_hp, 103.0)

	# A corpse does not regenerate. Standing up goes through revive() alone.
	var corpse := _living(50.0)
	corpse.stats.add_modifier(StatTypes.Stat.HP_REGEN, StatTypes.Modifier.BASE, 5.0, &"item")
	_hit(corpse, 100.0)
	_check_bool("it is down", corpse.is_alive, false)
	corpse.tick_regen(2.0)
	_check("and stays down", corpse.current_hp, 0.0)

## The last of the items documented as decorative. bloodstone granted LIFESTEAL,
## LIFESTEAL did nothing, and the item read perfectly while changing no number.
func _test_the_bloodstone_finally_does_something() -> void:
	print("\n-- bloodstone --")
	var stone := load("res://content/items/bloodstone.tres") as ItemData
	_check_bool("it loads", stone != null, true)

	var wearer := _living(200.0)
	wearer.add_item(stone)
	wearer.set_hp(50.0)

	var share := wearer.stats.get_stat(StatTypes.Stat.LIFESTEAL)
	_check_bool("it grants some lifesteal", share > 0.0, true)

	_hit(_living(1000.0), 100.0, wearer)
	_check("and the wearer heals by that share", wearer.current_hp, 50.0 + 100.0 * share)

# --- merging ----------------------------------------------------------------

## A family as a chain: I -> II -> III, top tier upgrades into nothing.
func _make_family(tags: Array[StringName], links: int = 3) -> Array[WeaponData]:
	var chain: Array[WeaponData] = []
	for i in links:
		var link := _make_tagged_weapon(tags)
		link.display_key = "W_%d" % (i + 1)
		link.tier = mini(4, i + 1)
		chain.append(link)
	for i in links - 1:
		chain[i].upgrades_into = chain[i + 1]
	return chain

func _test_merging_two_copies_frees_a_slot() -> void:
	print("\n-- merging --")
	var chain := _make_family([&"gun"] as Array[StringName])
	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")

	holder.add_weapon(chain[0])
	_check_bool("one copy cannot merge", holder.can_merge_weapon(chain[0]), false)

	holder.add_weapon(chain[0])
	_check_bool("two can", holder.can_merge_weapon(chain[0]), true)
	_check_bool("and it goes through", holder.merge_weapon(chain[0]), true)

	_check_int("two became one", holder.weapons.size(), 1)
	_check_int("no copies of tier I are left", holder.weapon_count(chain[0]), 0)
	_check_int("and it is tier II", holder.weapon_count(chain[1]), 1)

	# The top of the chain is a perfectly good weapon that simply stops here.
	holder.add_weapon(chain[2])
	holder.add_weapon(chain[2])
	_check_bool("the top tier cannot merge further", holder.can_merge_weapon(chain[2]), false)
	_check_bool("and refuses when asked", holder.merge_weapon(chain[2]), false)
	_check_int("so both copies stay", holder.weapon_count(chain[2]), 2)

	# DUPLICATES ARE CARRIED, which is the whole reason a class set is
	# reachable: four copies of one weapon is four toward its tag.
	var loaded := _living(100.0)
	loaded.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 6.0, &"body")
	for i in 4:
		loaded.add_weapon(chain[0])
	_check_int("four copies are four weapons", loaded.weapons.size(), 4)
	_check_int("and four toward the tag", loaded.weapon_tag_count(&"gun"), 4)

func _test_a_full_rack_takes_a_purchase_only_when_it_merges() -> void:
	print("\n-- a full rack --")
	var chain := _make_family([&"gun"] as Array[StringName])
	var other := _make_tagged_weapon([&"gun"] as Array[StringName])

	var holder := _living(100.0)
	holder.stats.add_modifier(StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, 2.0, &"body")
	holder.add_weapon(chain[0])
	holder.add_weapon(other)
	_check_bool("the rack is full", holder.has_free_weapon_slot(), false)

	# Something new has nowhere to go.
	_check_bool("a stranger is refused", holder.can_take_weapon(_make_tagged_weapon([] as Array[StringName])), false)

	# A duplicate of something upgradeable merges instead of overflowing.
	_check_bool("a duplicate is accepted", holder.can_take_weapon(chain[0]), true)
	_check_bool("and lands", holder.take_weapon(chain[0]), true)
	_check_int("the rack is still two weapons", holder.weapons.size(), 2)
	_check_int("no tier I left", holder.weapon_count(chain[0]), 0)
	_check_int("one tier II gained", holder.weapon_count(chain[1]), 1)

	# A duplicate of a TOP-tier weapon has nothing to merge into, so a full rack
	# refuses it like anything else. `other` has no upgrade at all.
	_check_bool("a duplicate with no next tier is refused", holder.can_take_weapon(other), false)
	_check_bool("and does not land", holder.take_weapon(other), false)
	_check_int("nothing was added", holder.weapons.size(), 2)

# --- the four items that used to be decorative ------------------------------

## REGRESSION, against the AUTHORED files rather than against fixtures.
##
## Four items moved a number in the stat sheet and changed nothing about a shot,
## because only MELEE_DAMAGE and RANGED_DAMAGE ever crossed from a holder to
## their weapon. Written against content/ on purpose: a fixture proving the
## mechanism works would have passed the whole time this bug was live.
func _test_the_authored_items_that_were_decorative_now_work() -> void:
	print("\n-- the decorative four --")
	var wielder := _living(100.0)
	var weapon := WeaponModel.new()
	weapon.rng = RunRandom.new(7)
	weapon.set_wielder(wielder)
	# A spread of its own to be reduced. An item granting -20% of a stat needs
	# something to take a fifth OF.
	weapon.stats.add_modifier(StatTypes.Stat.SPREAD_ANGLE, StatTypes.Modifier.BASE, 3.0, &"weapon")

	var before_crit := weapon.combined_stat(StatTypes.Stat.CRIT_CHANCE)
	var before_speed := weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED)
	var before_spread := weapon.combined_stat(StatTypes.Stat.SPREAD_ANGLE)

	var lucky_charm := load("res://content/items/lucky_charm.tres") as ItemData
	var sights := load("res://content/items/machined_sights.tres") as ItemData
	_check_bool("both items load", lucky_charm != null and sights != null, true)

	wielder.add_item(lucky_charm)
	_check_bool(
		"lucky_charm reaches the weapon's crit",
		weapon.combined_stat(StatTypes.Stat.CRIT_CHANCE) > before_crit, true
	)

	# pyrojoy is NOT tested through add_item: its attack speed comes from
	# EffectStatPerWorldCount, which only contributes on a tick with burning
	# enemies in the census. What the fix owes it is that a PERCENT modifier on
	# the holder reaches the weapon at all, so that is what is asserted.
	wielder.stats.add_modifier(
		StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.PERCENT, 0.1, &"burning"
	)
	_check(
		"a percentage on the holder multiplies the weapon's rate",
		weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED), before_speed * 1.1
	)

	wielder.add_item(sights)
	# Spread is a stat where LOWER is better, so the item lowers it. Asserting
	# "it moved" rather than "it grew" is the whole reason higher_is_better
	# exists elsewhere.
	#
	# It also only works because a holder's PERCENT is applied to the WEAPON's
	# value. The item is -20% SPREAD_ANGLE and the holder's own spread is zero,
	# so reading their total would give a fifth of nothing.
	_check("the weapon's own spread was 3.0", before_spread, 3.0)
	_check(
		"machined_sights takes a fifth off the weapon's spread",
		weapon.combined_stat(StatTypes.Stat.SPREAD_ANGLE), 2.4
	)

	# The other half of the same bug: a holder carrying nothing must leave a
	# weapon exactly as it was. ATTACK_SPEED floors at 0.05, so before every
	# entity was seeded with its neutral this would have read a twentieth.
	var empty_handed := _living(100.0)
	var untouched := WeaponModel.new()
	untouched.set_wielder(empty_handed)
	_check("an empty-handed holder slows nothing", untouched.combined_stat(StatTypes.Stat.ATTACK_SPEED), 1.0)
	_check("and a fresh entity reads its neutral", empty_handed.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 1.0)

# --- who is playing ---------------------------------------------------------

func _test_a_device_joins_once_and_the_keyboard_is_a_device() -> void:
	print("\n-- joining --")
	var roster := PlayerRoster.new()

	_check_int("nobody has joined yet", roster.count(), 0)
	_check_bool("the keyboard may join", roster.join(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_bool("the first pad may join", roster.join(0), true)
	_check_int("both are in", roster.count(), 2)

	# "Only one player on the keyboard" is NOT a rule of its own. It falls out of
	# a device joining once, because the keyboard is one device - which is the
	# whole reason the old keyboard-plus-pad-0 arrangement needed a special case.
	_check_bool("the keyboard cannot join twice", roster.join(PlayerRoster.KEYBOARD_DEVICE), false)
	_check_bool("nor can a pad already in", roster.join(0), false)
	_check_int("nothing was added", roster.count(), 2)

	# Join order is player order, everywhere downstream.
	_check_int("first to press is P1", roster.index_of(PlayerRoster.KEYBOARD_DEVICE), 0)
	_check_int("second is P2", roster.index_of(0), 1)
	_check_int("a device that never joined has no index", roster.index_of(3), -1)

	_check_bool("a third fits", roster.join(1), true)
	_check_bool("and a fourth", roster.join(2), true)
	_check_bool("the roster is full at four", roster.is_full(), true)
	_check_bool("a fifth is refused", roster.join(3), false)
	_check_int("four is the ceiling", roster.count(), PlayerRoster.MAX_PLAYERS)

func _test_leaving_closes_the_gap_rather_than_leaving_a_hole() -> void:
	print("\n-- leaving --")
	var roster := PlayerRoster.new()
	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	roster.join(0)
	roster.join(1)

	_check_bool("the middle player leaves", roster.leave(0), true)
	_check_int("two are left", roster.count(), 2)

	# Every layout downstream is driven by the player COUNT: a hole would leave
	# an empty HUD corner and a shop panel nobody drives.
	_check_int("the keyboard is still P1", roster.index_of(PlayerRoster.KEYBOARD_DEVICE), 0)
	_check_int("the third player moved up into P2", roster.index_of(1), 1)

	_check_bool("leaving twice does nothing", roster.leave(0), false)
	_check_bool("a freed slot can be rejoined", roster.join(0), true)
	_check_int("and lands at the end", roster.index_of(0), 2)

	# What the run is actually handed, and it must be a COPY: a run editing the
	# roster it was given would rewrite the lobby behind its back.
	var handed := roster.to_player_devices()
	handed.append(99)
	_check_int("the roster is unchanged by its reader", roster.count(), 3)

# --- what a purchase costs --------------------------------------------------

func _test_currency_gain_scales_earnings_and_never_spending() -> void:
	print("\n-- currency gain --")
	var earner := _living(100.0)
	earner.stats.add_modifier(
		StatTypes.Stat.CURRENCY_GAIN, StatTypes.Modifier.FLAT, 0.3, &"prospector"
	)

	earner.add_currency(10)
	_check_int("a payout is worth 30% more", earner.get_currency(), 13)
	# The tally moves with the balance: it is what "for every 500 earned" hangs
	# on, and crediting the pre-bonus figure would hide the stat from exactly
	# the effects that count earnings.
	_check_int(
		"and the lifetime tally is credited the same figure",
		earner.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), 13
	)

	# Spending arrives at the SAME call with a negative amount. A bonus that
	# also inflated prices would be a curse wearing a bonus's name.
	earner.add_currency(-13)
	_check_int("spending is not scaled", earner.get_currency(), 0)
	_check_int(
		"and never credits earnings",
		earner.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), 13
	)

	# Floored on the STAT rather than clamped in add_currency, so the stat sheet
	# shows the same number the arithmetic uses.
	var cursed := _living(100.0)
	cursed.stats.add_modifier(
		StatTypes.Stat.CURRENCY_GAIN, StatTypes.Modifier.FLAT, -3.0, &"curse"
	)
	_check("the stat floors at -100%", cursed.stats.get_stat(StatTypes.Stat.CURRENCY_GAIN), -1.0)
	cursed.add_currency(50)
	_check_int("so a payout is worth nothing rather than costing money", cursed.get_currency(), 0)

	# A refund goes to CURRENCY directly and must stay out of this entirely, or
	# buying and selling with a currency bonus prints money.
	var shop := _make_shop()
	var trader := _make_buyer(0)
	trader.stats.add_modifier(
		StatTypes.Stat.CURRENCY_GAIN, StatTypes.Modifier.FLAT, 0.3, &"prospector"
	)
	var item := _make_priced_item("REFUND", 1, 100)
	trader.add_item(item)
	_check_bool("the sale goes through", shop.sell(trader, item), true)
	_check_int("a refund is half the authored price and no more", trader.get_currency(), 50)

func _test_a_price_effect_discounts_by_kind_and_switches_the_payment() -> void:
	print("\n-- priced by an effect --")
	var shop := _make_shop()
	var item := _make_priced_item("PRICED", 1, 100)
	var weapon := _make_weapon("PRICED_W", 1, 100)

	var buyer := _make_buyer(500)
	var discount := EffectPriceModifier.new()
	discount.price_share = 0.8
	discount.applies_to = EffectPriceModifier.Applies.ITEMS
	buyer.effects.register(EffectInstance.new(discount, &"discount"))

	_check_int("an item is a fifth cheaper", shop.quote(buyer, item).price, 80)
	# The kind filter is why this is ONE class rather than two: "weapons cost
	# more" and "items cost less" are the same sentence with a different subject.
	_check_int("a weapon is untouched by an items-only discount", shop.quote(buyer, weapon).price, 100)

	# Stacks MULTIPLY. Additive stacking would reach free at five copies and
	# then start paying the buyer, which the shop's own clamp would hide.
	var doubled := _make_buyer(500)
	var stacked := EffectInstance.new(discount, &"discount")
	stacked.stacks = 2
	doubled.effects.register(stacked)
	_check_int("two copies compound rather than add", shop.quote(doubled, item).price, 64)

	var payer := _make_buyer(500)
	var blood := EffectPriceModifier.new()
	blood.uses_stat_payment = true
	blood.payment_stat = StatTypes.Stat.MAX_HP
	blood.payment_rate = 0.5
	var blood_instance := EffectInstance.new(blood, &"blood")
	blood_instance.stacks = 2
	payer.effects.register(blood_instance)

	var quoted := shop.quote(payer, item)
	_check_bool("the buyer is switched onto a stat", quoted.uses_stat_payment, true)
	_check_int("which stat is the effect's business too", quoted.pay_with_stat, StatTypes.Stat.MAX_HP)
	# The EXCHANGE RATE lives in the effect, and is applied ONCE whatever the
	# stack count - two copies of "pay in HP" is still one payment, and
	# compounding it would make the second copy a discount.
	_check_int("the rate converts once, not once per stack", quoted.price, 50)

	# A reroll goes through the same pipeline, which is the whole reason it was
	# moved onto it: "you pay for everything in blood" must not leave the one
	# price on the screen that is still money.
	# The CACHED quote the screen reads, not just the freshly computed one. It
	# is refreshed by every path that can change what a reroll costs - opening,
	# rerolling, buying, and SELLING, because selling can take away the very
	# effect that priced it. Missing one leaves a stale number on screen.
	var trader := _make_buyer(500)
	var discount_item := _make_priced_item("DISCOUNTER", 1, 10)
	var seller_effect := EffectPriceModifier.new()
	seller_effect.price_share = 0.5
	discount_item.dynamic_effects = [seller_effect]

	var rng_sell := RunRandom.new(77)
	shop.open(trader, 1, rng_sell)
	_check_int("the reroll starts at its authored cost", shop.reroll_price, 5)

	trader.add_item(discount_item)
	shop.sell(trader, discount_item)
	_check_int("selling the discounter puts the reroll back up", shop.reroll_price, 5)

	trader.add_item(discount_item)
	shop.open(trader, 1, rng_sell)
	_check_int("and holding one halves it", shop.reroll_price, 3)
	shop.sell(trader, discount_item)
	_check_int("selling it refreshes the cached quote", shop.reroll_price, 5)

	var reroll := shop.quote_reroll(payer)
	_check_bool("and so does the reroll", reroll.uses_stat_payment, true)
	_check_bool("which knows it is not a purchase", reroll.is_reroll, true)
	_check_bool("and has no entry to be a kind of", reroll.entry == null, true)

	# A KIND filter is a statement about what is being bought, so it must not
	# reach the reroll at all - otherwise "items cost 20% less" quietly reprices
	# a thing that is not an item.
	_check_int(
		"an items-only effect leaves the reroll alone",
		shop.quote_reroll(buyer).price, shop.reroll_cost()
	)

## The authored file, asserted rather than a hand-built copy of it. Two of these
## exist already (riot_shield, bloodstone) and both caught a real gap between
## what a .tres says and what the engine does with it.
func _test_the_blood_bank_pays_for_everything_in_blood() -> void:
	print("\n-- blood bank --")
	var character: CharacterData = load("res://content/characters/blood_bank.tres")
	if character == null:
		_failed += 1
		printerr("  FAIL  blood_bank did not load")
		return

	var buyer := EntityModel.new(character)
	buyer.add_currency(500)
	var shop := _make_shop()

	var item_quote := shop.quote(buyer, _make_priced_item("ITEM", 1, 40))
	_check_bool("an item is paid for in a stat", item_quote.uses_stat_payment, true)
	_check_int("at the authored rate of 0.3", item_quote.price, 12)

	# EVERYTHING, weapons included. Max HP is this character's currency, so a
	# kind it could not buy with blood would be a kind it could barely buy at
	# all - its money only pays for rerolls.
	var weapon_quote := shop.quote(buyer, _make_weapon("WEAPON", 1, 40))
	_check_bool("and so is a weapon", weapon_quote.uses_stat_payment, true)
	_check_int("at the same rate", weapon_quote.price, 12)

	# End to end, through the shop rather than through quote(): the pool here is
	# items only, so the first offer is one.
	var rng := RunRandom.new(4242)
	shop.open(buyer, 1, rng)
	var hp_before := buyer.get_max_hp()
	var currency_before := buyer.get_currency()
	var price := shop.offers[0].price

	_check_bool("the purchase goes through", shop.buy(buyer, 0), true)
	_check_int("currency is untouched", buyer.get_currency(), currency_before)
	_check("max HP paid for it", buyer.get_max_hp(), hp_before - float(price))

	# Rerolling too. "Everything" has to include the one price that used to be
	# decided by arithmetic instead of by the pipeline.
	_check_bool("the reroll is quoted in blood as well", shop.reroll_uses_stat_payment, true)
	var hp_before_reroll := buyer.get_max_hp()
	var reroll_price := shop.reroll_price
	_check_bool("the reroll goes through", shop.reroll(buyer, rng), true)
	_check_int("and it too left the money alone", buyer.get_currency(), currency_before)
	_check("paying for it in blood", buyer.get_max_hp(), hp_before_reroll - float(reroll_price))
	# A shrinking MAX_HP has to drag current_hp down with it, or the buyer walks
	# around above their own maximum. This is the first content that shrinks it.
	_check_bool("and current health is clamped to the new maximum", buyer.current_hp <= buyer.get_max_hp(), true)

func _test_the_model_applies_exactly_the_slot_modifiers_the_data_names() -> void:
	print("\n-- slots as modifiers --")
	var character := CharacterData.new()
	character.weapon_slots = 5
	character.shop_slots = 7

	var model := EntityModel.new(character)
	_check("the rack is what the chassis says", model.stats.get_stat(StatTypes.Stat.WEAPON_SLOTS), 5.0)
	_check("and so is the shop", model.stats.get_stat(StatTypes.Stat.SHOP_SLOTS), 7.0)

	# The regression this guards: the rule "a slot count IS a BASE modifier on
	# its stat" used to live inside EntityModel, so any screen wanting to
	# describe a chassis had to know it a second time. Asserting the two agree
	# is asserting there is still only one copy of it.
	var named := character.slot_modifiers()
	_check_int("the data names both of them", named.size(), 2)
	for modifier in named:
		_check_int(
			"a named modifier is a BASE one", modifier.modifier_type, StatTypes.Modifier.BASE
		)
		_check(
			"and the model applies exactly it",
			model.stats.get_stat(modifier.stat), modifier.value
		)

# --- what they are playing --------------------------------------------------

## Three named chassis, so an assertion can say WHICH one a player ended up on
## rather than only that the number moved.
func _make_catalogue(names: Array) -> CharacterSet:
	var set_data := CharacterSet.new()
	var built: Array[CharacterData] = []
	for key in names:
		var character := CharacterData.new()
		character.display_key = str(key)
		built.append(character)
	set_data.characters = built
	return set_data

func _test_a_default_pick_prefers_a_chassis_nobody_is_on() -> void:
	print("\n-- default picks --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["ALPHA", "BETA", "GAMMA"])

	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	roster.join(0)
	roster.join(1)

	# Four players and eight characters is the real case, and the point is that
	# the common one - everybody on something different - costs nobody a press.
	_check_int("P1 defaults to the first chassis", roster.pick_of(0), 0)
	_check_int("P2 does not double up on it", roster.pick_of(1), 1)
	_check_int("nor does P3", roster.pick_of(2), 2)

	# A DEFAULT, not a rule: past the end of the catalogue somebody has to share,
	# and the seat number decides who with rather than an arbitrary first entry.
	roster.join(2)
	_check_int("the fourth player shares, because there is nothing left", roster.pick_of(3), 0)

	var chosen := roster.to_player_characters()
	_check_int("one character per player, in player order", chosen.size(), 4)
	_check_bool("and P3 really holds the third", chosen[2].display_key == "GAMMA", true)

func _test_leaving_takes_that_player_s_character_with_it() -> void:
	print("\n-- leaving with a character --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["ALPHA", "BETA", "GAMMA"])
	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	roster.join(0)
	roster.join(1)

	# The regression this test exists for: devices and picks are two lists that
	# must agree, and a leave that closes the gap in one and not the other hands
	# the player who moved up somebody else's chassis while they keep their pad.
	roster.leave(0)

	_check_int("two are left", roster.count(), 2)
	_check_bool("the keyboard kept its own", roster.character_for_device(PlayerRoster.KEYBOARD_DEVICE).display_key == "ALPHA", true)
	_check_bool("and the pad that moved up kept ITS own", roster.character_for_device(1).display_key == "GAMMA", true)
	_check_int("the emptied slot holds no pick at all", roster.pick_of(2), -1)

	# Which is also what a rejoin has to see: the freed BETA, not a third ALPHA.
	roster.join(0)
	_check_bool("a rejoining player takes what nobody is on", roster.character_for_device(0).display_key == "BETA", true)

func _test_selecting_wraps_and_two_players_may_share_a_chassis() -> void:
	print("\n-- selecting --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["ALPHA", "BETA", "GAMMA"])
	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	roster.join(0)

	_check_bool("stepping forward answers yes", roster.select_next(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_int("P1 moved one along", roster.pick_of(0), 1)
	_check_int("and nobody else moved", roster.pick_of(1), 1)

	# Wrapping in both directions. A list with ends to fall off makes the last
	# character harder to reach than the first for no reason a player could name.
	roster.select_next(PlayerRoster.KEYBOARD_DEVICE)
	roster.select_next(PlayerRoster.KEYBOARD_DEVICE)
	_check_int("forward wraps to the start", roster.pick_of(0), 0)
	_check_bool("stepping back answers yes", roster.select_previous(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_int("and back wraps to the end", roster.pick_of(0), 2)

	# Duplicates are allowed on purpose - see the character list. Forbidding them
	# means answering what four players do with two authored characters.
	roster.select_previous(PlayerRoster.KEYBOARD_DEVICE)
	_check_int("two players may sit on one chassis", roster.pick_of(0), 1)
	_check_int("without displacing the other", roster.pick_of(1), 1)

	_check_bool("a device nobody joined on selects nothing", roster.select_next(7), false)

	# The signal the lobby redraws on. Deliberately NOT `changed`: the lobby
	# rebuilds its input list on that one, from inside a loop over that very
	# list, and stepping a selection would mutate the array being iterated.
	var beats: Array[int] = [0]
	roster.selection_changed.connect(func() -> void: beats[0] += 1)
	roster.changed.connect(func() -> void: beats[0] += 100)
	roster.select_next(0)
	_check_int("selecting reports selection_changed and nothing else", beats[0], 1)

func _test_no_catalogue_means_the_run_keeps_its_own_character() -> void:
	print("\n-- no catalogue --")
	var roster := PlayerRoster.new()
	roster.join(PlayerRoster.KEYBOARD_DEVICE)

	# main.tscn is still launchable on its own, and a capture run points straight
	# at it. Nothing injected has to mean "keep what you authored" rather than
	# "play as null".
	_check_int("a player joined with nothing to choose", roster.count(), 1)
	_check_bool("and holds no character", roster.character_at(0) == null, true)
	_check_int("so the run is handed one empty slot, not a null one", roster.to_player_characters().size(), 1)
	_check_bool("nothing is handed over", roster.to_player_characters()[0] == null, true)
	_check_bool("and there is nothing to step through", roster.select_next(PlayerRoster.KEYBOARD_DEVICE), false)

	# A catalogue arriving late must not leave picks pointing past its end.
	roster.catalogue = _make_catalogue(["ALPHA"])
	_check_bool("a late catalogue reaches the player already in", roster.character_at(0).display_key == "ALPHA", true)
	_check_bool("a single entry has nowhere to step to", roster.select_next(PlayerRoster.KEYBOARD_DEVICE), false)

func _test_confirming_freezes_a_cursor_and_backing_out_thaws_it() -> void:
	print("\n-- locking a chassis in --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["ALPHA", "BETA", "GAMMA"])
	roster.join(PlayerRoster.KEYBOARD_DEVICE)

	_check_bool("nobody starts confirmed", roster.is_confirmed(0), false)
	_check_bool("confirming answers yes", roster.confirm(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_bool("and confirming twice does not", roster.confirm(PlayerRoster.KEYBOARD_DEVICE), false)

	# The reason confirming is worth a flag at all: without the freeze somebody
	# locks one chassis, carries on browsing, and their slot shows a character
	# they will not be playing.
	_check_bool("a locked cursor refuses to move", roster.select_next(PlayerRoster.KEYBOARD_DEVICE), false)
	_check_int("and stays where it was", roster.pick_of(0), 0)

	# ONE button, two meanings, and the state says which - the same layering the
	# shop's tile menu uses for CLOSE.
	_check_bool("backing out of a lock answers yes", roster.back_out(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_bool("and returns to browsing rather than leaving", roster.has(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_bool("the cursor moves again", roster.select_next(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_int("to the next chassis", roster.pick_of(0), 1)

	# Backing out AGAIN is the one that leaves, which is what makes B a single
	# button a player never has to think about.
	_check_bool("backing out of browsing leaves", roster.back_out(PlayerRoster.KEYBOARD_DEVICE), true)
	_check_int("the lobby is empty", roster.count(), 0)
	_check_bool("and backing out of nothing does nothing", roster.back_out(PlayerRoster.KEYBOARD_DEVICE), false)

func _test_the_run_waits_for_every_joined_player_to_confirm() -> void:
	print("\n-- everybody, or nobody --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["ALPHA", "BETA"])

	# An empty lobby trivially satisfies "all of them agree", which would start a
	# run with no players in it.
	_check_bool("an empty lobby is not ready", roster.everyone_confirmed(), false)

	roster.join(PlayerRoster.KEYBOARD_DEVICE)
	roster.join(0)
	_check_bool("two joined and neither confirmed", roster.everyone_confirmed(), false)

	roster.confirm(PlayerRoster.KEYBOARD_DEVICE)
	_check_bool("one of two is not everybody", roster.everyone_confirmed(), false)

	roster.confirm(0)
	_check_bool("both confirmed", roster.everyone_confirmed(), true)

	# A third player arriving un-readies the lobby, which is the whole point of
	# asking every JOINED player rather than counting confirmations.
	roster.join(1)
	_check_bool("somebody joining takes it back", roster.everyone_confirmed(), false)

	# And leaving hands it back, rather than leaving a lobby nobody can start.
	roster.leave(1)
	_check_bool("and their leaving gives it back", roster.everyone_confirmed(), true)

	# The flags travel with the PLAYER, exactly as the picks do: P2 leaving must
	# not hand P3 somebody else's confirmation.
	roster.join(1)
	roster.confirm(1)
	roster.back_out(0)
	roster.leave(0)
	_check_int("two are left", roster.count(), 2)
	_check_bool("the keyboard is still locked", roster.is_confirmed(0), true)
	_check_bool("and the player who moved up kept their own lock", roster.is_confirmed(1), true)

func _test_a_grid_step_is_a_delta_the_view_chooses() -> void:
	print("\n-- landing on an entry --")
	var roster := PlayerRoster.new()
	roster.catalogue = _make_catalogue(["A", "B", "C", "D", "E", "F", "G", "H"])
	roster.join(PlayerRoster.KEYBOARD_DEVICE)

	# WHERE a nudge lands is GridCursor's answer, computed from the row the
	# cursor is in; the roster only stores it. A roster that worked it out would
	# have to know how wide the rack is drawn, which is a screen's business and
	# changes with an authored number.
	_check_bool("landing somewhere else answers yes", roster.select_index(PlayerRoster.KEYBOARD_DEVICE, 5), true)
	_check_int("and that is where the cursor is", roster.pick_of(0), 5)

	# A no-op is reported as one, so the lobby can skip the scroll-follow rather
	# than dragging a shared rack around for a press that changed nothing.
	_check_bool("landing where you already are is not a move", roster.select_index(PlayerRoster.KEYBOARD_DEVICE, 5), false)

	# Clamped rather than trusted: an index out of range would leave the panel
	# describing a character nobody can point at.
	roster.select_index(PlayerRoster.KEYBOARD_DEVICE, 99)
	_check_int("past the end lands on the last", roster.pick_of(0), 7)
	roster.select_index(PlayerRoster.KEYBOARD_DEVICE, -4)
	_check_int("before the start lands on the first", roster.pick_of(0), 0)

	# The flat stepper is still what a capture run drives, and a locked cursor
	# refuses both forms.
	_check_bool("stepping flat still works", roster.select_by(PlayerRoster.KEYBOARD_DEVICE, 3), true)
	_check_int("three entries on", roster.pick_of(0), 3)
	roster.confirm(PlayerRoster.KEYBOARD_DEVICE)
	_check_bool("a locked cursor refuses to be placed", roster.select_index(PlayerRoster.KEYBOARD_DEVICE, 1), false)
	_check_int("and has not moved", roster.pick_of(0), 3)

func _test_a_cursor_wraps_inside_its_row_and_its_column() -> void:
	print("\n-- wrapping in a rack --")
	# Twelve at four wide: three full rows.
	var total := 12
	var columns := 4

	# RIGHT from the end of a row returns to the start of THAT row, never to the
	# next one. A flat wrap reads as the cursor teleporting - you press right
	# expecting the row you are reading and land a row down, which is how
	# somebody loses their place in a rack of eighty.
	_check_int("right along a row", GridCursor.step_horizontal(1, total, columns, 1), 2)
	_check_int("right from the end wraps to the same row", GridCursor.step_horizontal(3, total, columns, 1), 0)
	_check_int("and in the middle row too", GridCursor.step_horizontal(7, total, columns, 1), 4)
	_check_int("left from the start wraps to the end of the row", GridCursor.step_horizontal(4, total, columns, -1), 7)

	# DOWN walks the column and wraps inside it, for the same reason.
	_check_int("down a column", GridCursor.step_vertical(1, total, columns, 1), 5)
	_check_int("down from the bottom wraps to the top", GridCursor.step_vertical(9, total, columns, 1), 1)
	_check_int("up from the top wraps to the bottom", GridCursor.step_vertical(2, total, columns, -1), 10)

	# One row, or one column, still has to answer.
	_check_int("a single row wraps on itself", GridCursor.step_horizontal(2, 3, 4, 1), 0)
	_check_int("a single column steps nowhere sideways", GridCursor.step_horizontal(1, 3, 1, 1), 1)
	_check_int("but still walks vertically", GridCursor.step_vertical(1, 3, 1, 1), 2)
	_check_int("an empty rack is index zero", GridCursor.step_horizontal(0, 0, 4, 1), 0)

func _test_a_ragged_last_row_wraps_among_what_is_there() -> void:
	print("\n-- a ragged last row --")
	# Ten at four wide: rows of 4, 4 and 2. The last row is where every
	# off-by-one in this kind of arithmetic lives.
	var total := 10
	var columns := 4

	_check_int("the last row holds two", GridCursor.row_length(8, total, columns), 2)
	_check_int("right in the short row wraps after the second", GridCursor.step_horizontal(9, total, columns, 1), 8)
	_check_int("and left from its start goes to the second", GridCursor.step_horizontal(8, total, columns, -1), 9)

	# A column the short row does not reach must wrap one row EARLIER, or the
	# cursor lands on an index that is not drawn and the panel describes a
	# character nobody can see.
	_check_int("column 0 reaches all three rows", GridCursor.column_length(0, total, columns), 3)
	_check_int("column 2 reaches only two", GridCursor.column_length(2, total, columns), 2)
	_check_int("down column 2 wraps at the second row", GridCursor.step_vertical(6, total, columns, 1), 2)
	_check_int("up column 2 lands on the last row that has it", GridCursor.step_vertical(2, total, columns, -1), 6)
	_check_int("while column 0 reaches the short row", GridCursor.step_vertical(4, total, columns, 1), 8)

	_check_int("three rows in all", GridCursor.row_count(total, columns), 3)
	_check_int("and one row for a rack smaller than a row", GridCursor.row_count(2, columns), 1)

func _test_the_rack_scrolls_only_when_the_cursor_would_leave_it() -> void:
	print("\n-- scrolling the rack --")
	var columns := 4
	# A cursor already on screen must not move the view. The rack is SHARED, so
	# a view that re-centred on every step would drag three other players'
	# screens around every time one of them nudged a stick.
	_check_int("a visible cursor leaves the view alone", GridCursor.scroll_to_show(5, columns, 0, 2), 0)
	_check_int("even at the bottom of the window", GridCursor.scroll_to_show(7, columns, 0, 2), 0)

	# And when it does move, it moves the LEAST it can.
	_check_int("dropping past the bottom scrolls one row", GridCursor.scroll_to_show(8, columns, 0, 2), 1)
	_check_int("rising above the top scrolls back", GridCursor.scroll_to_show(3, columns, 2, 2), 0)
	_check_int("a jump lands the row at the bottom", GridCursor.scroll_to_show(40, columns, 0, 3), 8)

	_check_int("the view cannot park past the end", GridCursor.clamp_scroll(9, 12, columns, 2), 1)
	_check_int("nor before the start", GridCursor.clamp_scroll(-3, 12, columns, 2), 0)
	_check_int("and a rack that fits never scrolls", GridCursor.clamp_scroll(2, 6, columns, 2), 0)

func _test_an_orbiting_enemy_keeps_its_distance() -> void:
	print("\n-- orbiting --")
	var orbit := OrbitBehavior.new()
	orbit.preferred_distance = 200.0
	orbit.tolerance = 40.0
	orbit.strafe_weight = 1.0

	var target := Vector2.ZERO

	# Too far: close in, straight at the target.
	var far := orbit.get_direction(null, Vector2(400.0, 0.0), target, 0.016, null)
	_check("far away it walks in", far.x, -1.0)
	_check("and does not veer", far.y, 0.0)

	# Too near: back off. The retreat carries some of the circle, so a group of
	# them does not collapse into a line reversing along one axis.
	var near := orbit.get_direction(null, Vector2(80.0, 0.0), target, 0.016, null)
	_check_bool("close in it backs away", near.x > 0.0, true)
	_check_bool("while still curving", absf(near.y) > 0.0, true)

	# THE BAND between them is what stops the enemy juddering in place at exactly
	# the preferred distance, flipping between "too near" and "too far" every
	# frame. Inside it there is no radial motion at all.
	var banded := orbit.get_direction(null, Vector2(200.0, 0.0), target, 0.016, null)
	_check("in the band it does not close", banded.x, 0.0)
	_check_bool("it circles instead", absf(banded.y) > 0.9, true)

	# Which way round is authored, so two of them do not smear into a cloud.
	orbit.clockwise = true
	var other_way := orbit.get_direction(null, Vector2(200.0, 0.0), target, 0.016, null)
	_check("clockwise circles the other way", other_way.y, -banded.y)

	# A turret rather than a skirmisher, with one authored number.
	orbit.strafe_weight = 0.0
	var still := orbit.get_direction(null, Vector2(200.0, 0.0), target, 0.016, null)
	_check("no strafe weight stands still in the band", still.length(), 0.0)

	# On top of the target there is no direction to be had, and no divide by zero.
	_check("standing on it asks for nothing", orbit.get_direction(null, target, target, 0.016, null).length(), 0.0)

func _test_an_armed_enemy_gets_a_rack_to_put_it_in() -> void:
	print("\n-- an armed bug --")
	var unarmed := EnemyData.new()
	unarmed.display_key = "ENEMY_TEST"
	var plain := EntityModel.new(unarmed)
	_check("an unarmed bug has no rack", plain.stats.get_stat(StatTypes.Stat.WEAPON_SLOTS), 0.0)

	# The trap this exists for: add_weapon asks WEAPON_SLOTS exactly as it does
	# for a player, so without a seeded capacity a bug would be refused its own
	# authored gun - silently, since add_weapon returns false and nothing looks.
	var armed := EnemyData.new()
	armed.display_key = "ENEMY_TEST_ARMED"
	armed.weapons = [_make_weapon("SPIT", 1, 0, 6.0)]

	var model := EntityModel.new(armed)
	_check("an armed bug gets exactly one slot", model.stats.get_stat(StatTypes.Stat.WEAPON_SLOTS), 1.0)
	_check_bool("and the weapon fits", model.add_weapon(armed.weapons[0]), true)
	_check_int("it is carrying it", model.weapons.size(), 1)

	# Exactly what it was authored with, and no more: a bug never buys, sells or
	# merges, so a spare slot would be capacity nobody can ever use.
	_check_bool("with no room for a second", model.add_weapon(armed.weapons[0]), false)

# --- weapons as purchasables -----------------------------------------------

func _make_weapon(key: String, tier: int, price: int, damage: float = 10.0) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.display_key = key
	weapon.tier = tier
	weapon.base_price = price

	var modifier := StatModifier.new()
	modifier.stat = StatTypes.Stat.RANGED_DAMAGE
	modifier.modifier_type = StatTypes.Modifier.BASE
	modifier.value = damage
	weapon.base_stats = [modifier]
	return weapon

## A buyer with a real rack size. WEAPON_SLOTS is a stat, so a test that forgets
## to set one gets zero slots and every purchase refuses - which is correct, and
## is why the shop asks before it charges.
func _make_wielder(slots: int, currency: int = 500) -> EntityModel:
	var wielder := _living(200.0)
	wielder.stats.add_modifier(
		StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, float(slots), &"test_body"
	)
	wielder.add_currency(currency)
	return wielder

func _test_weapon_slots_cap_what_is_carried() -> void:
	print("\n-- weapon slots --")
	var wielder := _make_wielder(2)
	var pistol := _make_weapon("W_PISTOL", 1, 25)
	var blade := _make_weapon("W_BLADE", 1, 30)

	_check_int("an empty rack has the authored size", wielder.weapon_slots(), 2)
	_check_bool("the first weapon goes on", wielder.add_weapon(pistol), true)
	_check_bool("a duplicate is allowed", wielder.add_weapon(pistol), true)
	_check_int("both copies are counted", wielder.weapon_count(pistol), 2)
	_check_bool("a full rack refuses the third", wielder.add_weapon(blade), false)
	_check_int("nothing was carried past the cap", wielder.weapons.size(), 2)

	# ONE copy, not the stack. Selling one of two identical pistols must leave
	# the other one in your hands.
	_check_bool("removing takes one copy", wielder.remove_weapon(pistol), true)
	_check_int("the other copy stays", wielder.weapon_count(pistol), 1)
	_check_bool("the freed slot can be refilled", wielder.add_weapon(blade), true)

	# A slot granted by an item is an ordinary modifier, which is the whole
	# reason capacity is a stat rather than a number on the mount.
	wielder.stats.add_modifier(
		StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.FLAT, 1.0, &"test_item"
	)
	_check_bool("an item granting a slot makes room", wielder.add_weapon(blade), true)

func _make_weapon_shop() -> ShopManager:
	var data := ShopData.new()
	data.pool = [_make_priced_item("T1_ITEM", 1, 10)]
	data.weapon_pool = [_make_weapon("T1_GUN", 1, 25)]
	data.offer_count = 4
	data.price_per_wave = 0.0
	data.sell_ratio = 0.5
	data.allow_duplicate_offers = true
	data.base_tier_weights = PackedFloat32Array([100.0, 0.0, 0.0, 0.0])
	data.tier_weight_per_wave = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

	var shop := ShopManager.new()
	shop.data = data
	return shop

func _test_buying_a_weapon_takes_a_slot_and_selling_frees_it() -> void:
	print("\n-- buying a weapon --")
	var shop := _make_weapon_shop()
	shop.data.weapon_offer_chance = 1.0
	var buyer := _make_wielder(2, 200)
	shop.open(buyer, 1, RunRandom.new(99))

	var weapon := shop.offers[0].entry as WeaponData
	_check_bool("every slot rolled a weapon", weapon != null, true)
	_check_bool("the purchase goes through", shop.buy(buyer, 0), true)
	_check_int("it is carried", buyer.weapon_count(weapon), 1)
	_check_int("it cost what it was quoted", buyer.get_currency(), 200 - 25)

	# The same path an item takes: the shop asks the ENTRY what to do, so the
	# weapon lands in the rack rather than in the item inventory. A weapon's
	# base_stats belong to the WeaponModel, not to the wielder's StatsManager.
	_check_int("it did not land in the items", buyer.items.get_all().size(), 0)
	_check(
		"and pushed nothing into the wielder's stats",
		buyer.stats.get_stat(StatTypes.Stat.RANGED_DAMAGE), 0.0
	)

	_check_bool("it can be sold", shop.sell(buyer, weapon), true)
	_check_int("the rack is empty again", buyer.weapons.size(), 0)
	_check_int("half the authored price comes back", buyer.get_currency(), 200 - 25 + 12)

	# A refund is not earnings, exactly as for an item - otherwise buy-and-sell
	# farms every "for each 500 earned" effect for the price of the spread.
	_check_int(
		"selling credited no earnings",
		buyer.counters.get_value(CounterTypes.Counter.CURRENCY_EARNED), 200
	)

func _test_a_full_rack_refuses_the_purchase_and_keeps_the_money() -> void:
	print("\n-- a full rack --")
	var shop := _make_weapon_shop()
	shop.data.weapon_offer_chance = 1.0
	var buyer := _make_wielder(1, 500)
	shop.open(buyer, 1, RunRandom.new(7))

	_check_bool("the first weapon fits", shop.buy(buyer, 0), true)
	var before_refusal := buyer.get_currency()

	# THE MONEY MUST NOT MOVE. can_be_acquired_by is checked before the quote,
	# so a refusal cannot leave the buyer paying for something they never got.
	_check_bool("the second is refused", shop.buy(buyer, 1), false)
	_check_int("no money changed hands", buyer.get_currency(), before_refusal)
	_check_int("the rack is still one weapon", buyer.weapons.size(), 1)
	_check_bool("the offer was not marked sold", shop.offers[1].sold, false)

## THE SCALABILITY GUARANTEE. The mix comes from an authored chance, never from
## how much content happens to exist - so authoring ninety more weapons must not
## quietly make items rarer and invalidate every balance judgement made before.
func _test_the_offer_mix_comes_from_the_chance_not_the_pool_sizes() -> void:
	print("\n-- the offer mix --")
	var shop := _make_weapon_shop()
	# Lopsided ON PURPOSE: five weapons against one item. A merged pool would
	# offer weapons five times out of six whatever anybody intended.
	shop.data.weapon_pool = [
		_make_weapon("G1", 1, 25), _make_weapon("G2", 1, 25), _make_weapon("G3", 1, 25),
		_make_weapon("G4", 1, 25), _make_weapon("G5", 1, 25),
	]
	var buyer := _make_wielder(6, 5000)
	var rng := RunRandom.new(4242)

	shop.data.weapon_offer_chance = 0.0
	var weapons_at_zero := 0
	for attempt in 20:
		shop.open(buyer, 1, rng)
		for offer in shop.offers:
			if offer.entry is WeaponData:
				weapons_at_zero += 1
	_check_int("chance 0 offers no weapons at all", weapons_at_zero, 0)

	shop.data.weapon_offer_chance = 1.0
	var items_at_one := 0
	for attempt in 20:
		shop.open(buyer, 1, rng)
		for offer in shop.offers:
			if not (offer.entry is WeaponData):
				items_at_one += 1
	_check_int("chance 1 offers no items at all", items_at_one, 0)

	shop.data.weapon_offer_chance = 0.5
	var mixed_weapons := 0
	var mixed_items := 0
	for attempt in 20:
		shop.open(buyer, 1, rng)
		for offer in shop.offers:
			if offer.entry is WeaponData:
				mixed_weapons += 1
			else:
				mixed_items += 1
	_check_bool("half and half offers both kinds", mixed_weapons > 0 and mixed_items > 0, true)
	_check_int("every slot is filled regardless", mixed_weapons + mixed_items, 80)

	# A slot must never come back EMPTY because the kind it rolled had nothing
	# left. Weapons switched off entirely, weapons still asked for.
	shop.data.weapon_pool = []
	shop.data.weapon_offer_chance = 1.0
	shop.open(buyer, 1, rng)
	_check_int("an empty weapon pool still fills the shop", shop.offers.size(), 4)

func _test_every_purchasable_describes_itself_the_same_way() -> void:
	print("\n-- one description path --")
	var item := _make_priced_item("I", 1, 10)
	var modifier := StatModifier.new()
	modifier.stat = StatTypes.Stat.MAX_HP
	modifier.modifier_type = StatTypes.Modifier.FLAT
	modifier.value = 5.0
	item.static_stats = [modifier]

	var weapon := _make_weapon("W", 2, 25, 14.0)
	var character := CharacterData.new()
	character.display_key = "C"
	character.base_stats = [modifier]

	# The detail block, the owned strip and the offer row all read these two,
	# which is what lets one renderer draw all three without a branch.
	_check_int("an item reports its static stats", item.modifiers().size(), 1)
	_check_int("a weapon reports its base stats", weapon.modifiers().size(), 1)
	_check_int("a character reports its base stats", character.modifiers().size(), 1)

	_check_bool("an item can be sold", item.can_be_sold(), true)
	_check_bool("a weapon can be sold", weapon.can_be_sold(), true)
	# You cannot sell yourself, and it falls out of the data rather than out of
	# a branch in the renderer.
	_check_bool("a character cannot be sold", character.can_be_sold(), false)

	var wielder := _make_wielder(1, 0)
	_check_bool("an item never refuses", item.can_be_acquired_by(wielder), true)
	_check_bool("a weapon fits while there is room", weapon.can_be_acquired_by(wielder), true)
	wielder.add_weapon(weapon)
	_check_bool("and refuses once there is not", weapon.can_be_acquired_by(wielder), false)

func _test_weapon_and_item_purchases_are_tallied_apart() -> void:
	print("\n-- two tallies --")
	var shop := _make_weapon_shop()
	var buyer := _make_wielder(4, 500)

	shop.data.weapon_offer_chance = 1.0
	shop.open(buyer, 1, RunRandom.new(11))
	shop.buy(buyer, 0)

	shop.data.weapon_offer_chance = 0.0
	shop.open(buyer, 1, RunRandom.new(11))
	shop.buy(buyer, 0)

	# "For every 5 items bought" must not be fed by a weapon. A counter is a
	# number effects do arithmetic on, and one tally covering both kinds cannot
	# be un-mixed afterwards.
	_check_int(
		"the weapon landed in its own tally",
		buyer.counters.get_value(CounterTypes.Counter.WEAPONS_BOUGHT), 1
	)
	_check_int(
		"the item landed in its own",
		buyer.counters.get_value(CounterTypes.Counter.ITEMS_BOUGHT), 1
	)

# --- area damage ------------------------------------------------------------
#
# Everything here rests on EntityModel.world_position, which is written by the
# view. These tests write it themselves, exactly as the census tests do, and are
# therefore blind to a view that never writes it at all - which is what happened.
# The guard for that is the `drift` figure in the capture state line, not this
# file, and the distinction is worth remembering before trusting a green suite.

func _sided(
	position: Vector2, side: WorldTypes.Faction, maximum: float = 100.0
) -> EntityModel:
	var entity := _at(position, maximum)
	entity.faction = side
	return entity

## Registers everything with one census and hands it back, so the caller keeps it
## alive - the entities only hold a weakref to it.
func _census_of(entities: Array) -> WorldCensus:
	var census := WorldCensus.new()
	for entity in entities:
		census.register(entity as EntityModel)
	return census

## Flat by default: most of these tests are about WHO is caught, and a taper
## would make every expected number a lerp.
func _make_blast(damage: float, size: float = 100.0) -> BlastData:
	var blast := BlastData.new()
	blast.base_damage = damage
	blast.radius = size
	blast.edge_damage_share = 1.0
	return blast

func _test_a_blast_reaches_the_other_side_and_spares_its_own() -> void:
	print("\n-- area damage --")
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var player := _sided(Vector2(40.0, 0.0), WorldTypes.Faction.PLAYERS)
	var swarm_mate := _sided(Vector2(40.0, 0.0), WorldTypes.Faction.ENEMIES)
	var crate := _sided(Vector2(40.0, 0.0), WorldTypes.Faction.NEUTRAL)
	var census := _census_of([bug, player, swarm_mate, crate])

	var event := bug.detonate(_make_blast(20.0), bug.world_position)

	_check("the other side took it", player.current_hp, 80.0)
	_check("its own side did not", swarm_mate.current_hp, 100.0)
	# NEUTRAL is not the enemy of anybody. A crate that every explosion in the
	# game hurts by default is how friendly fire arrives without being decided.
	_check("and neither did the furniture", crate.current_hp, 100.0)
	_check_int("one victim", event.victims.size(), 1)
	_check("and the total says so", event.damage_dealt, 20.0)

	# The same blast with the filter opened up, which is the ONE field that
	# answers "does a Popper hurt other bugs" - no second code path.
	var friendly_fire := _make_blast(20.0)
	friendly_fire.reach = BlastData.Reach.EVERYTHING
	bug.detonate(friendly_fire, bug.world_position)
	_check("friendly fire is a field", swarm_mate.current_hp, 80.0)
	_check("and it does not spare the crate either", crate.current_hp, 80.0)
	_check_int("the census is still the one built here", census.count_alive(), 4)

func _test_blast_damage_tapers_towards_the_rim() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var hugging := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var halfway := _sided(Vector2(50.0, 0.0), WorldTypes.Faction.PLAYERS)
	var at_the_rim := _sided(Vector2(100.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, hugging, halfway, at_the_rim])

	var blast := _make_blast(40.0)
	blast.edge_damage_share = 0.5
	bug.detonate(blast, Vector2.ZERO)

	# Standing at the edge has to be worth something, or the only decision an
	# explosion poses is whether you are inside it.
	_check("full damage at the centre", hugging.current_hp, 60.0)
	_check("three quarters halfway out", halfway.current_hp, 70.0)
	_check("half of it at the rim", at_the_rim.current_hp, 80.0)
	_check_int("all three were caught", census.count_alive(), 4)

func _test_a_capped_blast_takes_the_nearest() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var far := _sided(Vector2(90.0, 0.0), WorldTypes.Faction.PLAYERS)
	var near := _sided(Vector2(10.0, 0.0), WorldTypes.Faction.PLAYERS)
	var middle := _sided(Vector2(50.0, 0.0), WorldTypes.Faction.PLAYERS)
	# Registered furthest first on purpose: an uncapped blast hits the same set
	# whatever order it walks, so only a cap can expose an unsorted one.
	var census := _census_of([bug, far, near, middle])

	var blast := _make_blast(30.0)
	blast.max_targets = 2
	var event := bug.detonate(blast, Vector2.ZERO)

	_check_int("exactly two", event.victims.size(), 2)
	_check("the nearest was caught", near.current_hp, 70.0)
	_check("and the second nearest", middle.current_hp, 70.0)
	_check("the far one was not", far.current_hp, 100.0)
	_check_int("nothing was freed", census.count_alive(), 4)

func _test_area_size_scales_the_radius() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var outside := _sided(Vector2(120.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, outside])

	var blast := _make_blast(10.0)
	var missed := bug.detonate(blast, Vector2.ZERO)
	_check("out of reach", outside.current_hp, 100.0)
	_check("the authored radius", missed.radius, 100.0)

	# An ordinary PERCENT modifier on an ordinary stat. BlastData never learns
	# that "+50% explosion size" exists, which is the whole reason it is a stat.
	bug.stats.add_modifier(
		StatTypes.Stat.AREA_SIZE, StatTypes.Modifier.PERCENT, 0.5, &"bigger_bang"
	)
	var caught := bug.detonate(blast, Vector2.ZERO)
	_check("half again as wide", caught.radius, 150.0)
	_check("and it reaches now", outside.current_hp, 90.0)
	_check_int("both still alive", census.count_alive(), 2)

func _test_a_blast_rolls_one_crit_for_everything_it_catches() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var first := _sided(Vector2(10.0, 0.0), WorldTypes.Faction.PLAYERS)
	var second := _sided(Vector2(20.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, first, second])

	var spy := SpyEffect.new()
	spy.watched = Hooks.Hook.ON_CRIT
	bug.effects.register(EffectInstance.new(spy, &"test"))

	bug.stats.add_modifier(
		StatTypes.Stat.CRIT_CHANCE, StatTypes.Modifier.BASE, 1.0, &"certain"
	)
	# Nothing authored about the MULTIPLIER on purpose: an entity's own reads the
	# neutral 1.0, so a blast that took it literally would "crit" for nothing.
	# StatTypes.DEFAULT_CRIT_MULTIPLIER is what a weapon already carried.
	var event := bug.detonate(_make_blast(15.0), Vector2.ZERO)

	# One explosion is ONE attack, exactly as a shotgun blast is: everybody
	# inside it crits together or nobody does.
	_check_bool("the explosion crit", event.is_crit, true)
	_check("the first took double", first.current_hp, 70.0)
	_check("and so did the second", second.current_hp, 70.0)
	_check_int("one roll, not one per victim", spy.calls, 1)
	_check_int("nothing died", census.count_alive(), 3)

func _test_an_explosion_inherits_the_crit_of_the_shot_that_set_it_off() -> void:
	var shooter := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var target := _sided(Vector2(10.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([shooter, target])

	var spy := SpyEffect.new()
	spy.watched = Hooks.Hook.ON_CRIT
	shooter.effects.register(EffectInstance.new(spy, &"test"))

	# The bullet already crit and already paid for it. Its explosion is part of
	# the same attack, so it crits without rolling and without crediting twice.
	var bullet := ShotSnapshot.new()
	bullet.is_crit = true

	var blast := _make_blast(20.0)
	var event := shooter.detonate(blast, Vector2.ZERO, null, bullet)

	_check_bool("the explosion crit with the bullet", event.is_crit, true)
	_check("double damage, with crit chance at zero", target.current_hp, 60.0)
	_check_int("and the crit was not tallied twice", spy.calls, 0)
	_check_int("both still standing", census.count_alive(), 2)

func _test_a_blast_announces_itself_to_whoever_is_listening() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var player := _sided(Vector2(30.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, player])

	# An Array rather than a plain local: a lambda captures by VALUE, so assigning
	# to an outer local inside one is silently lost.
	#
	# What goes into it is COPIED OUT of the event and never the event itself.
	# Keeping one closes the cycle model -> signal -> lambda -> event -> model,
	# which RefCounted cannot collect - measured here at 48 leaked objects before
	# this line looked like it does now. BlastFlash.setup copies out for the same
	# reason, and it is the same rule that stops an effect caching a payload.
	var seen: Array[Dictionary] = []
	bug.blast_resolved.connect(
		func(event: BlastEvent) -> void:
			seen.append({
				&"centre": event.centre,
				&"radius": event.radius,
				&"victims": event.victims.size(),
			})
	)

	bug.detonate(_make_blast(5.0, 70.0), Vector2(12.0, 0.0))

	# This signal IS the view's only hook. Everything drawn for an explosion in
	# the running game comes off it, so a blast that resolves silently is an
	# explosion nobody can see.
	var centre: Vector2 = seen[0][&"centre"] if not seen.is_empty() else Vector2.ZERO
	var reported_radius: float = seen[0][&"radius"] if not seen.is_empty() else 0.0
	var caught: int = seen[0][&"victims"] if not seen.is_empty() else -1

	_check_int("the view was told once", seen.size(), 1)
	_check("where it went off", centre.x, 12.0)
	_check("how big it turned out", reported_radius, 70.0)
	_check_int("and who it caught", caught, 1)
	_check_int("census untouched", census.count_alive(), 2)

func _test_a_blast_with_nowhere_to_look_hurts_nobody() -> void:
	# No census: a model built for a test, or one whose run has gone away. It has
	# to be a quiet no-op rather than a crash, because the caller is content and
	# content cannot check.
	var stray := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var event := stray.detonate(_make_blast(50.0), Vector2.ZERO)
	_check_int("nobody was hurt", event.victims.size(), 0)
	_check("and the flash still has a size to draw", event.radius, 100.0)

func _test_a_bug_that_bursts_hurts_the_players_and_not_the_swarm() -> void:
	print("\n-- exploding on death, on a kill and on impact --")
	var popper := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES, 10.0)
	var player := _sided(Vector2(30.0, 0.0), WorldTypes.Faction.PLAYERS)
	var swarm_mate := _sided(Vector2(30.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([popper, player, swarm_mate])

	var effect := EffectBlast.new()
	effect.trigger = EffectBlast.Trigger.ON_DEATH
	effect.blast = _make_blast(25.0)
	popper.effects.register(EffectInstance.new(effect, &"popper"))

	_hit(popper, 50.0)

	_check_bool("the bug died", popper.is_alive, false)
	_check("and took the player with part of it", player.current_hp, 75.0)
	_check("the swarm is untouched", swarm_mate.current_hp, 100.0)
	_check_int("one of the three is gone", census.count_alive(), 2)

func _test_an_exploding_kill_goes_off_where_the_victim_was() -> void:
	var killer := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var victim := _sided(Vector2(400.0, 0.0), WorldTypes.Faction.ENEMIES, 10.0)
	var bystander := _sided(Vector2(430.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([killer, victim, bystander])

	var effect := EffectBlast.new()
	effect.trigger = EffectBlast.Trigger.ON_KILL
	effect.blast = _make_blast(20.0)
	killer.effects.register(EffectInstance.new(effect, &"detonator"))

	_hit(victim, 50.0, killer)

	# The centre is WHERE THE EVENT HAPPENED, which for a kill is the corpse and
	# not the killer standing four hundred units away.
	_check("the neighbour caught it", bystander.current_hp, 80.0)
	_check_int("and the killer is unharmed", roundi(killer.current_hp), 100)
	_check_int("the victim is gone", census.count_alive(), 2)

func _test_a_second_copy_of_an_exploding_item_hits_harder() -> void:
	var killer := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var victim := _sided(Vector2(50.0, 0.0), WorldTypes.Faction.ENEMIES, 10.0)
	var bystander := _sided(Vector2(60.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([killer, victim, bystander])

	var effect := EffectBlast.new()
	effect.trigger = EffectBlast.Trigger.ON_KILL
	effect.blast = _make_blast(20.0)
	# Two copies of the same item. Without the stack count reaching the blast, a
	# second one would be worth exactly nothing and the shop would still sell it.
	killer.effects.register(EffectInstance.new(effect, &"detonator", 2))

	_hit(victim, 50.0, killer)

	_check("twice the bang", bystander.current_hp, 60.0)
	_check_int("the victim is gone", census.count_alive(), 2)

func _test_elemental_damage_finally_feeds_something() -> void:
	var thrower := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var target := _sided(Vector2(20.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([thrower, target])

	thrower.stats.add_modifier(
		StatTypes.Stat.ELEMENTAL_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"hot"
	)

	# An empty scaling table means "all of my own damage type", the same rule
	# WeaponData.damage_scaling follows - and for the default ELEMENTAL that is
	# the first thing in the game to read the stat at all.
	thrower.detonate(_make_blast(8.0), Vector2.ZERO)
	_check("authored damage plus the stat", target.current_hp, 80.0)

	# An authored table replaces the default rather than adding to it, so a blast
	# that wants both says both.
	var mixed := _make_blast(8.0)
	var share := StatScaling.new()
	share.stat = StatTypes.Stat.ELEMENTAL_DAMAGE
	share.coefficient = 0.5
	mixed.damage_scaling = [share] as Array[StatScaling]
	thrower.detonate(mixed, Vector2.ZERO)
	_check("half a share of it", target.current_hp, 66.0)
	_check_int("nobody died", census.count_alive(), 2)

func _test_a_blast_goes_through_the_targets_own_defences() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var armoured := _sided(Vector2(10.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, armoured])

	armoured.stats.add_modifier(
		StatTypes.Stat.ARMOR, StatTypes.Modifier.BASE, 15.0, &"plating"
	)

	# Straight through apply_damage, so armor, dodge, resistances, lifesteal and
	# kill credit all apply to an explosion with nothing written for any of them.
	var event := bug.detonate(_make_blast(40.0), Vector2.ZERO)
	_check("armor halves it at the half point", armoured.current_hp, 80.0)
	_check("and the event reports what LANDED", event.damage_dealt, 20.0)
	_check_int("both alive", census.count_alive(), 2)

func _test_a_chain_does_not_spend_its_targets_on_corpses() -> void:
	var bug := _sided(Vector2.ZERO, WorldTypes.Faction.ENEMIES)
	var already_dead := _sided(Vector2(10.0, 0.0), WorldTypes.Faction.PLAYERS)
	var still_standing := _sided(Vector2(30.0, 0.0), WorldTypes.Faction.PLAYERS)
	var census := _census_of([bug, already_dead, still_standing])

	# The cache is built HERE, while all three are alive - and then one dies
	# without it being invalidated, which is exactly the state a chain reaction is
	# in. The census holds its answer for the whole frame, so every explosion
	# after the first one in that frame is asking a stale question. Measured in a
	# capture run as nine explosions reporting fifty victims between them.
	_check_int("all three counted while alive", census.count_alive(), 3)
	_hit(already_dead, 500.0)
	_check_int("and the cache still says so", census.count_alive(), 3)

	var blast := _make_blast(20.0)
	blast.max_targets = 1
	var event := bug.detonate(blast, Vector2.ZERO)

	_check_int("the one target was not wasted on the corpse", event.victims.size(), 1)
	_check("it went to the one still standing", still_standing.current_hp, 80.0)

	census.invalidate()
	_check_int("the census catches up on the next frame", census.count_alive(), 2)

func _test_the_authored_popper_bursts_on_death() -> void:
	print("\n-- the authored content --")
	var data := load("res://content/enemies/popper.tres") as EnemyData
	_check_bool("the popper loads", data != null, true)

	var popper := EntityModel.new(data)
	popper.faction = WorldTypes.Faction.ENEMIES
	popper.world_position = Vector2.ZERO

	var close := _sided(Vector2(20.0, 0.0), WorldTypes.Faction.PLAYERS)
	var far := _sided(Vector2(200.0, 0.0), WorldTypes.Faction.PLAYERS)
	var swarm_mate := _sided(Vector2(20.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([popper, close, far, swarm_mate])

	_hit(popper, 500.0)

	# Asserted against the AUTHORED file rather than against numbers invented
	# here: 12 damage at the centre, tapering to 45% at the authored 85 radius,
	# so 12 * (1 - 0.55 * 20/85) twenty units out.
	_check("the player next to it was hurt", close.current_hp, 100.0 - 10.4470588)
	_check("the one across the arena was not", far.current_hp, 100.0)
	_check("and the swarm is spared, as authored", swarm_mate.current_hp, 100.0)
	_check_int("the popper is gone", census.count_alive(), 3)

func _test_the_authored_mortar_explodes_where_it_lands() -> void:
	var mortar := load("res://content/weapons/slag_mortar_1.tres") as WeaponData
	var charge := load("res://content/projectiles/slag_charge.tres") as ProjectileData
	_check_bool("the mortar and its charge load", mortar != null and charge != null, true)
	_check_int("the charge carries exactly one effect", charge.innate_effects.size(), 1)

	var gunner := _sided(Vector2.ZERO, WorldTypes.Faction.PLAYERS)
	var bug := _sided(Vector2(300.0, 0.0), WorldTypes.Faction.ENEMIES)
	var census := _census_of([gunner, bug])

	var weapon := WeaponModel.new(mortar)
	weapon.set_wielder(gunner)
	weapon.rng = gunner.rng

	# The mortar carries 5% crit of its own, and a crit doubles the explosion
	# along with the shot - which is correct and would make this assertion flake
	# one run in twenty. Crit has its own tests; this one is about the radius.
	weapon.stats.add_modifier(
		StatTypes.Stat.CRIT_CHANCE, StatTypes.Modifier.PERCENT, -1.0, &"test_no_crit"
	)

	# Exactly what Projectile._run_projectile_effects does on a hit: the effect
	# is executed on the SHOOTER with the impact it was handed.
	var impact := ImpactEvent.new()
	impact.shooter = gunner
	impact.position = bug.world_position
	impact.snapshot = weapon.build_shot(mortar)

	var effect := charge.innate_effects[0]
	effect.execute(gunner, EffectInstance.new(effect, charge), impact)

	# 60% of the weapon's 14 ranged damage, at the centre of an 80 radius. The
	# tier scaling comes free: the share reads the WEAPON's damage, so tier IV
	# explodes for its own 52 with not one number authored twice.
	_check("the explosion landed on the bug", bug.current_hp, 100.0 - 8.4)
	_check_int("nothing died", census.count_alive(), 2)

func _test_a_behaviour_can_ask_for_less_than_full_speed() -> void:
	print("
-- backing off --")
	var orbit := OrbitBehavior.new()
	orbit.preferred_distance = 200.0
	orbit.tolerance = 20.0
	orbit.strafe_weight = 1.0
	orbit.retreat_speed_share = 0.5

	var target := Vector2.ZERO
	var closing := orbit.get_direction(null, Vector2(400.0, 0.0), target, 0.1, null)
	var circling := orbit.get_direction(null, Vector2(200.0, 0.0), target, 0.1, null)
	var backing := orbit.get_direction(null, Vector2(60.0, 0.0), target, 0.1, null)

	# The LENGTH is the speed share - see MovementBehavior. Full speed to close,
	# full speed to circle, and only the retreat gives ground.
	_check("closes at full speed", closing.length(), 1.0)
	_check("circles at full speed", circling.length(), 1.0)
	_check("and backs off at half", backing.length(), 0.5)

	# Direction is unchanged by the share: it still goes AWAY, it simply gives
	# ground more slowly. The enemy stands at +60 and the target at the origin,
	# so retreating is FURTHER along +x.
	_check_bool("still retreating", backing.x > 0.0, true)

	# 1.0 is what it did before this was expressible, so the old behaviour is
	# still authorable rather than merely remembered.
	orbit.retreat_speed_share = 1.0
	_check(
		"the old behaviour is one authored number",
		orbit.get_direction(null, Vector2(60.0, 0.0), target, 0.1, null).length(),
		1.0
	)

# --- spawn requests ---------------------------------------------------------
#
# core/ cannot build anything, so what is asserted here is the REQUEST: what
# would be created, how many, and where. The building is a scene concern and is
# measured by a capture run instead.

## Records every request an entity makes. A plain Array of the requests
## themselves is safe where a BlastEvent was not: a SpawnRequest holds its
## requester WEAKLY, precisely so keeping one cannot keep a corpse alive.
func _collect_requests(entity: EntityModel) -> Array[SpawnRequest]:
	var seen: Array[SpawnRequest] = []
	entity.spawn_requested.connect(func(request: SpawnRequest) -> void: seen.append(request))
	return seen

func _make_spawn_effect(what: EntityData, how_many: int, every: float = 0.0) -> EffectSpawn:
	var effect := EffectSpawn.new()
	effect.data = what
	effect.count = how_many
	effect.interval = every
	effect.trigger = (
		EffectSpawn.Trigger.ON_INTERVAL if every > 0.0 else EffectSpawn.Trigger.ON_DEATH
	)
	return effect

func _tick(entity: EntityModel, delta: float) -> void:
	var event := TickEvent.new()
	event.delta = delta
	entity.notify(Hooks.Hook.ON_TICK, event)

func _test_a_dying_thing_can_ask_for_more_of_them() -> void:
	print("
-- spawn requests --")
	var child := EnemyData.new()
	child.display_key = "TEST_CHILD"

	var parent := _at(Vector2(120.0, -40.0), 10.0)
	var seen := _collect_requests(parent)
	parent.effects.register(EffectInstance.new(_make_spawn_effect(child, 2), &"splitter"))

	_check_int("nothing asked for while it lives", seen.size(), 0)
	_hit(parent, 50.0)

	_check_int("one request on death", seen.size(), 1)
	_check_int("for two of them", seen[0].count, 2)
	_check_bool("of the authored kind", seen[0].data == child, true)
	# Read off the model rather than passed in, so it is the position the view
	# published - which is still correct on a corpse.
	_check("where it died, x", seen[0].origin.x, 120.0)
	_check("where it died, y", seen[0].origin.y, -40.0)

func _test_a_timer_asks_once_per_interval_and_keeps_the_remainder() -> void:
	var brood := EnemyData.new()
	brood.display_key = "TEST_BROOD"

	var hive := _at(Vector2.ZERO)
	var seen := _collect_requests(hive)
	hive.effects.register(EffectInstance.new(_make_spawn_effect(brood, 3, 2.0), &"hive"))

	_tick(hive, 1.9)
	_check_int("not yet", seen.size(), 0)
	_tick(hive, 0.2)
	_check_int("once the interval is crossed", seen.size(), 1)
	_check_int("three of them", seen[0].count, 3)

	# ONE brood per crossing, never a loop draining the debt: a frame that ran
	# long would otherwise put several intervals of them down at once.
	_tick(hive, 10.0)
	_check_int("a long frame still asks once", seen.size(), 2)

	# The remainder carries, so the clock does not drift later every time.
	_tick(hive, 1.9)
	_check_int("and the leftover 0.1 counted", seen.size(), 3)

func _test_two_holders_of_one_spawn_effect_keep_separate_clocks() -> void:
	var brood := EnemyData.new()
	brood.display_key = "TEST_BROOD"

	# ONE resource, two holders - which is the trap EffectInstance exists for.
	# A timer kept on the .tres would have every hive in the wave counting the
	# same seconds and releasing together.
	var shared := _make_spawn_effect(brood, 1, 2.0)

	var first := _at(Vector2.ZERO)
	var second := _at(Vector2(500.0, 0.0))
	var first_seen := _collect_requests(first)
	var second_seen := _collect_requests(second)
	first.effects.register(EffectInstance.new(shared, &"hive"))
	second.effects.register(EffectInstance.new(shared, &"hive"))

	_tick(first, 1.5)
	_tick(second, 0.2)
	_tick(first, 0.6)

	_check_int("the one that has waited releases", first_seen.size(), 1)
	_check_int("the other has not", second_seen.size(), 0)

func _test_a_request_places_itself_around_whoever_asked() -> void:
	var context := SpawnContext.new()
	context.anchor = Vector2(300.0, 200.0)

	var scatter := SpawnScatter.new()
	scatter.radius = 40.0
	var points := scatter.positions(context, 3, RunRandom.new(7))

	_check_int("one point per member", points.size(), 3)
	# The first member sits exactly on the anchor, so a request for one lands
	# precisely where it was asked for rather than jittered off it.
	_check("the first is the anchor, x", points[0].x, 300.0)
	_check("the first is the anchor, y", points[0].y, 200.0)

	var furthest := 0.0
	for point in points:
		furthest = maxf(furthest, point.distance_to(context.anchor))
	_check_bool("and the rest are inside the radius", furthest <= 40.0001, true)

func _test_the_authored_splitter_and_hive_ask_for_swarmlings() -> void:
	var splitter_data := load("res://content/enemies/splitter.tres") as EnemyData
	var hive_data := load("res://content/enemies/hive.tres") as EnemyData
	var swarmling := load("res://content/enemies/swarmling.tres") as EnemyData
	_check_bool("all three load", splitter_data != null and hive_data != null, true)

	var splitter := EntityModel.new(splitter_data)
	splitter.world_position = Vector2(10.0, 10.0)
	var split_seen := _collect_requests(splitter)
	_hit(splitter, 500.0)

	# TWO requests from one corpse, and they are different KINDS: the children it
	# breaks into, and the scrap every enemy leaves. That is the whole argument
	# for the channel carrying EntityData rather than enemies - one death, one
	# mechanism, two payloads, and nothing in core/ knows the difference.
	_check_int("the splitter asks twice", split_seen.size(), 2)

	var children: SpawnRequest = null
	var scrap: SpawnRequest = null
	for request in split_seen:
		if request.data is PickupData:
			scrap = request
		else:
			children = request

	_check_bool("one of them is swarmlings", children != null and children.data == swarmling, true)
	_check_int("two of them, as authored", children.count if children != null else 0, 2)
	_check_bool("the other is scrap", scrap != null, true)
	_check_int("three pieces of it", scrap.count if scrap != null else 0, 3)
	# Both come out of the same place, because both are things the corpse left.
	_check("and both where it died", scrap.origin.x if scrap != null else 0.0, 10.0)

	var hive := EntityModel.new(hive_data)
	var hive_seen := _collect_requests(hive)
	# The hive is authored at one brood every 5 seconds; nothing releases early.
	_tick(hive, 4.9)
	_check_int("nothing yet", hive_seen.size(), 0)
	_tick(hive, 0.2)
	_check_int("then a brood", hive_seen.size(), 1)
	_check_bool("of swarmlings", hive_seen[0].data == swarmling, true)

	# It never moves, and says so by carrying no movement behaviour at all
	# rather than by a speed of zero - one statement of a fact, not two.
	_check_bool("the hive has no movement resource", hive_data.movement == null, true)

# --- charging ---------------------------------------------------------------

func _make_charger() -> ChargeBehavior:
	var charge := ChargeBehavior.new()
	charge.trigger_distance = 200.0
	charge.approach_speed_share = 0.4
	charge.windup_time = 0.5
	charge.dash_time = 0.4
	charge.recover_time = 0.6
	charge.dash_speed_share = 1.0
	return charge

func _test_a_charge_stops_before_it_commits() -> void:
	print("
-- charging --")
	var charge := _make_charger()
	var state := MovementState.new()
	var target := Vector2.ZERO

	# Out of range: walks in, at a fraction of its speed, because MOVEMENT_SPEED
	# is the DASH speed and the approach is the slow part.
	var far := charge.get_direction(null, Vector2(400.0, 0.0), target, 0.1, state)
	_check("ambles in", far.length(), 0.4)
	_check("towards the target", far.x, -0.4)
	_check("and telegraphs nothing", state.windup, 0.0)

	# In range: stops DEAD. This is the mechanic, not the decoration - a thing
	# that was moving and suddenly is not is readable with no art at all.
	var near := Vector2(150.0, 0.0)
	var committing := charge.get_direction(null, near, target, 0.1, state)
	_check("stops the moment it commits", committing.length(), 0.0)

	charge.get_direction(null, near, target, 0.25, state)
	_check("and says how far through it is", state.windup, 0.5)

	# The wind-up ends and it launches at full speed.
	var launched := charge.get_direction(null, near, target, 0.3, state)
	_check("then goes, flat out", launched.length(), 1.0)
	_check("the telegraph is cleared with the phase", state.windup, 0.0)

func _test_a_dash_does_not_follow_you() -> void:
	var charge := _make_charger()
	var state := MovementState.new()

	# Wind-up, aimed at the origin.
	charge.get_direction(null, Vector2(150.0, 0.0), Vector2.ZERO, 0.1, state)
	var launched := charge.get_direction(null, Vector2(150.0, 0.0), Vector2.ZERO, 0.5, state)
	_check("committed straight along -x", launched.x, -1.0)

	# The player steps aside DURING the dash. It must not turn: a dash that
	# tracks is a fast chase, and stepping aside would do nothing at all - which
	# is the whole answer this enemy exists to ask for.
	var mid := charge.get_direction(null, Vector2(100.0, 0.0), Vector2(0.0, 400.0), 0.1, state)
	_check("still going the way it was pointed, x", mid.x, -1.0)
	_check("and not turning towards them", mid.y, 0.0)

	# Then it stands there, which is the punish window.
	var recovering := charge.get_direction(null, Vector2(50.0, 0.0), Vector2(0.0, 400.0), 0.5, state)
	_check("and stops afterwards", recovering.length(), 0.0)

func _test_two_chargers_keep_separate_clocks() -> void:
	# ONE resource, two holders, which is the trap MovementState exists for: a
	# phase kept on the .tres would have every charger in the wave winding up
	# together and dashing on the same frame.
	var shared := _make_charger()
	var first := MovementState.new()
	var second := MovementState.new()
	var target := Vector2.ZERO
	var near := Vector2(150.0, 0.0)

	shared.get_direction(null, near, target, 0.1, first)
	shared.get_direction(null, near, target, 0.4, first)

	shared.get_direction(null, near, target, 0.1, second)

	_check("one is nearly committed", first.windup, 0.8)
	_check("the other has only just started", second.windup, 0.0)

	# And a behaviour handed no state at all still walks in rather than freezing,
	# because an enemy standing still for ever reads as broken.
	var stateless := shared.get_direction(null, Vector2(400.0, 0.0), target, 0.1, null)
	_check("no state means it just walks", stateless.length(), 0.4)

# --- plating ----------------------------------------------------------------

func _test_flat_armor_costs_a_weak_hit_more_than_a_heavy_one() -> void:
	print("
-- plating --")
	var plated := _living(1000.0)
	var plating := EffectFlatArmor.new()
	plating.absorb = 3.0
	plated.effects.register(EffectInstance.new(plating, &"plating"))

	# THE WHOLE POINT, and the thing percentage ARMOR cannot do: a share takes
	# the same fraction off every hit and cares nothing for what is shooting.
	_check("a weak hit loses most of itself", _hit(plated, 5.0), 2.0)
	_check("a heavy one barely notices", _hit(plated, 40.0), 37.0)

	# And it can take a hit to nothing at all, which is what "a wall a fast weak
	# weapon cannot chew" means - and the danger the export documents.
	_check("under the absorb it does nothing", _hit(plated, 2.0), 0.0)

	# Stacks, so the same class is an item that says "you take 2 less per hit".
	var doubled := _living(1000.0)
	doubled.effects.register(EffectInstance.new(plating, &"plating", 2))
	_check("two copies absorb twice", _hit(doubled, 20.0), 14.0)

func _test_the_authored_warden_is_a_wall_a_fast_weapon_cannot_chew() -> void:
	var data := load("res://content/enemies/warden.tres") as EnemyData
	_check_bool("the warden loads", data != null, true)

	var warden := EntityModel.new(data)
	var opening := warden.current_hp

	# Authored: 3 absorbed flat, then 6 ARMOR takes 6/21 of what is left. The
	# order is the one apply_damage documents - armor never charges twice for
	# damage an effect already removed.
	var fast := _hit(warden, 5.0)
	var slow := _hit(warden, 40.0)
	_check("a 5-damage hit lands 1.4", fast, 2.0 * (1.0 - 6.0 / 21.0))
	_check("a 40-damage hit lands 26.4", slow, 37.0 * (1.0 - 6.0 / 21.0))

	# Same TOTAL damage delivered in eight small hits against one big one. The
	# design claim is that the small ones are worth much less, and this is it in
	# one number rather than in prose.
	var chewed := warden.current_hp
	for i in 7:
		_hit(warden, 5.0)
	var eight_small := opening - warden.current_hp - slow
	_check_bool(
		"eight small hits do less than one heavy one of the same total",
		eight_small < slow, true
	)
	_check_bool("and the warden is still standing", warden.is_alive, true)
	_check_bool("having lost less than half", warden.current_hp > chewed * 0.5, true)

func _test_neutral_is_nobody_s_ally_and_nobody_s_enemy() -> void:
	var players := WorldTypes.Faction.PLAYERS
	var enemies := WorldTypes.Faction.ENEMIES
	var neutral := WorldTypes.Faction.NEUTRAL

	_check_bool("the two sides are hostile", WorldTypes.are_hostile(players, enemies), true)
	_check_bool("a side is not hostile to itself", WorldTypes.are_hostile(players, players), false)
	_check_bool("a side is allied to itself", WorldTypes.are_allied(enemies, enemies), true)

	# Deliberately not the negation of each other: two neutrals are not comrades,
	# they are simply not in the fight.
	_check_bool("neutral is nobody's enemy", WorldTypes.are_hostile(neutral, players), false)
	_check_bool("neutral is nobody's ally", WorldTypes.are_allied(neutral, neutral), false)

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
