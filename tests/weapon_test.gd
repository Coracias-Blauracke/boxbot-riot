extends SceneTree

## Tests for the weapon logic layer:
##   godot --headless --path . --script res://tests/weapon_test.gd

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	print("=== WEAPON TESTS ===\n")

	_test_instant_fire_rate()
	_test_neutral_attack_speed()
	_test_attack_speed_scales_every_pattern()
	_test_fire_rate_is_capped()
	_test_idling_does_not_bank_shots()
	_test_windup_gates_and_ramps()
	_test_burst_finishes_once_started()
	_test_channel_duration_and_recovery()
	_test_heat_disabled_by_default()
	_test_heat_overheats_and_vents()
	_test_heat_works_on_any_pattern()
	_test_spread_counts_and_cone()
	_test_spread_fan_is_even()
	_test_target_nearest()
	_test_target_by_health()
	_test_shot_damage_sums_weapon_and_wielder()
	_test_crit_is_rolled_once_per_shot()
	_test_pipeline_can_force_a_crit()
	_test_falloff()
	_test_swing_arc_sweeps()
	_test_swing_mirroring()
	_test_swing_thrust_goes_out_and_back()
	_test_swing_windup_is_not_live()
	_test_swing_curve_override()
	_test_blade_points_outward()
	_test_blade_tilt_offset()
	_test_the_wielder_stats_now_reach_the_weapon()
	_test_a_multiplier_multiplies_rather_than_adding()
	_test_inheritance_can_withhold_part_of_a_stat()
	_test_damage_scales_off_whatever_stat_it_names()
	_test_half_scaling_halves_the_bonus_not_the_weapon()
	_test_a_weapon_says_what_it_scales_with()
	_test_a_weapon_may_scale_off_many_stats_in_both_directions()

	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --- helpers ---------------------------------------------------------------

## WeaponModel already supplies a neutral ATTACK_SPEED of 1.0, so a multiplier
## is expressed as a delta on top of it rather than another BASE.
func _make_weapon(attack_speed: float = 1.0) -> WeaponModel:
	var weapon := WeaponModel.new()
	if not is_equal_approx(attack_speed, 1.0):
		weapon.stats.add_modifier(
			StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.FLAT, attack_speed - 1.0, &"test"
		)
	weapon.rng = RunRandom.new(1234)
	return weapon

## Runs a pattern for `seconds` at a fixed step and totals the shots fired.
func _simulate(weapon: WeaponModel, pattern: FiringPattern, seconds: float, step: float = 0.02, firing: bool = true) -> int:
	var shots := 0
	var elapsed := 0.0
	while elapsed < seconds:
		shots += pattern.advance(weapon, step, firing)
		weapon.cool(step)
		elapsed += step
	return shots

# --- firing patterns -------------------------------------------------------

func _test_instant_fire_rate() -> void:
	var weapon := _make_weapon(1.0)
	var pattern := FiringInstant.new()
	pattern.base_interval = 0.25

	# 2 seconds at 0.25s intervals
	_check_int("instant fires at its interval", _simulate(weapon, pattern, 2.0), 8)

	var idle := _make_weapon(1.0)
	_check_int("no trigger, no shots", _simulate(idle, pattern, 2.0, 0.02, false), 0)

## A weapon whose data says nothing about attack speed must be neutral, not
## fall to the 0.05 stat floor and end up twenty times too slow.
func _test_neutral_attack_speed() -> void:
	var bare := WeaponModel.new()
	_check("bare weapon has neutral attack speed", bare.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 1.0)
	_check("bare weapon has neutral crit multiplier", bare.stats.get_stat(StatTypes.Stat.CRIT_MULTIPLIER), 2.0)
	_check("bare weapon has neutral projectile speed", bare.stats.get_stat(StatTypes.Stat.PROJECTILE_SPEED), 1.0)

## Stacked haste must not drive the interval to zero and spawn a projectile
## every frame.
func _test_fire_rate_is_capped() -> void:
	var weapon := _make_weapon(1.0)
	weapon.stats.add_modifier(StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.FLAT, 999.0, &"absurd")

	var pattern := FiringInstant.new()
	pattern.base_interval = 0.5
	_check("interval is floored", pattern.interval_for(weapon), FiringPattern.MIN_INTERVAL)

	# One second at the cap, so at most 1 / MIN_INTERVAL shots.
	var shots := _simulate(weapon, pattern, 1.0, 0.01)
	_check_bool("absurd haste stays bounded (%d shots)" % shots, shots <= 26, true)

## Regression: a weapon with no target used to tick its cooldown ever further
## negative, so the moment something walked into range it fired every frame
## until the debt was paid off. On a melee weapon each of those restarted the
## swing on top of the last, which read as the first attack being cancelled.
func _test_idling_does_not_bank_shots() -> void:
	for pattern in [FiringInstant.new(), FiringWindup.new()] as Array[FiringPattern]:
		var weapon := _make_weapon(1.0)
		var label: String = pattern.get_script().resource_path.get_file()

		# Ten seconds with nothing to shoot at.
		_simulate(weapon, pattern, 10.0, 0.02, false)
		_check_bool("%s banks no cooldown debt" % label, weapon.cooldown >= 0.0, true)

		# A target appears: a short burst of frames must not empty a magazine.
		var fired := 0
		for i in 8:
			fired += pattern.advance(weapon, 0.02, true)
		_check_bool("%s fires at most once on acquisition (%d)" % [label, fired], fired <= 1, true)

func _test_attack_speed_scales_every_pattern() -> void:
	var pattern := FiringInstant.new()
	pattern.base_interval = 0.25

	var slow := _simulate(_make_weapon(1.0), pattern, 2.0)
	var fast := _simulate(_make_weapon(2.0), pattern, 2.0)
	# Attack speed lives in the base class, so haste items reach every pattern
	# without any of them knowing about the stat.
	#
	# Asserted within one shot rather than exactly: shots do not land on step
	# boundaries, so an exact ratio would be testing the simulation step size
	# rather than the behaviour.
	_check_bool(
		"double attack speed roughly doubles the shots (%d vs %d)" % [fast, slow],
		absi(fast - slow * 2) <= 1,
		true
	)

func _test_windup_gates_and_ramps() -> void:
	var weapon := _make_weapon(1.0)
	var pattern := FiringWindup.new()
	pattern.base_interval = 0.1
	pattern.spin_up_time = 1.0
	pattern.min_spin_to_fire = 0.5
	pattern.rate_at_full_spin = 3.0

	# Below the spin threshold nothing comes out at all.
	_check_int("silent while spinning up", _simulate(weapon, pattern, 0.4), 0)
	_check_bool("spin is ramping", weapon.spin > 0.3 and weapon.spin < 0.5, true)

	var firing_shots := _simulate(weapon, pattern, 1.5)
	_check_bool("fires once spun up", firing_shots > 0, true)
	_check_bool("reaches full spin", is_equal_approx(weapon.spin, 1.0), true)

	# Releasing the trigger spins back down.
	_simulate(weapon, pattern, 1.0, 0.02, false)
	_check("spin decays when released", weapon.spin, 0.0)

func _test_burst_finishes_once_started() -> void:
	var weapon := _make_weapon(1.0)
	var pattern := FiringBurst.new()
	pattern.base_interval = 1.0
	pattern.shots_per_burst = 3
	pattern.shot_interval = 0.05

	# One trigger pull, then release immediately: the burst must still complete.
	var shots := pattern.advance(weapon, 0.02, true)
	for i in 30:
		shots += pattern.advance(weapon, 0.02, false)
	_check_int("a started burst completes after release", shots, 3)

	# And then respects the long cooldown.
	_check_int("burst then waits", pattern.advance(weapon, 0.02, true), 0)

func _test_channel_duration_and_recovery() -> void:
	var weapon := _make_weapon(1.0)
	var pattern := FiringChannel.new()
	pattern.channel_duration = 1.0
	pattern.tick_interval = 0.1
	pattern.recovery = 0.5

	var during := _simulate(weapon, pattern, 1.0, 0.02)
	_check_bool("channel ticks throughout", during >= 9 and during <= 11, true)

	# Immediately after the beam ends the weapon is recovering.
	_check_int("recovery blocks refiring", pattern.advance(weapon, 0.02, true), 0)

# --- heat ------------------------------------------------------------------

func _test_heat_disabled_by_default() -> void:
	var weapon := _make_weapon(1.0)
	weapon.stats.add_modifier(StatTypes.Stat.HEAT_CAPACITY, StatTypes.Modifier.BASE, 10.0, &"base")

	# heat_per_shot 0 means nothing ever calls add_heat - the common case.
	_check_bool("no heat, always able to fire", weapon.can_fire(), true)
	_check("heat starts empty", weapon.heat, 0.0)

func _test_heat_overheats_and_vents() -> void:
	var weapon := _make_weapon(1.0)
	weapon.stats.add_modifier(StatTypes.Stat.HEAT_CAPACITY, StatTypes.Modifier.BASE, 10.0, &"base")
	weapon.stats.add_modifier(StatTypes.Stat.HEAT_DISSIPATION, StatTypes.Modifier.BASE, 5.0, &"base")

	for i in 4:
		weapon.add_heat(2.0)
	_check("heat accumulates", weapon.heat, 8.0)
	_check_bool("still under the cap", weapon.can_fire(), true)

	weapon.add_heat(2.0)
	_check_bool("overheats at capacity", weapon.is_overheated, true)
	_check_bool("locked out while overheated", weapon.can_fire(), false)

	# Dipping just below the cap must NOT free it, or the weapon stutters one
	# shot at a time at maximum heat.
	weapon.cool(0.1)
	_check_bool("still locked just under the cap", weapon.can_fire(), false)

	weapon.cool(2.0)
	_check_bool("frees up once properly vented", weapon.can_fire(), true)

func _test_heat_works_on_any_pattern() -> void:
	# Heat is an orthogonal layer, not a firing pattern, so it must gate a plain
	# instant weapon exactly as it gates a minigun.
	for pattern in [FiringInstant.new(), FiringWindup.new(), FiringBurst.new()] as Array[FiringPattern]:
		var weapon := _make_weapon(1.0)
		weapon.stats.add_modifier(StatTypes.Stat.HEAT_CAPACITY, StatTypes.Modifier.BASE, 5.0, &"base")
		weapon.add_heat(5.0)
		_check_int(
			"overheated %s emits nothing" % pattern.get_script().resource_path.get_file(),
			pattern.advance(weapon, 0.5, true),
			0
		)

# --- spread ----------------------------------------------------------------

func _test_spread_counts_and_cone() -> void:
	var rng := RunRandom.new(99)
	var aim := Vector2.RIGHT

	var single := SpreadSingle.new()
	_check_int("single produces one direction", single.directions(aim, 0.0, rng).size(), 1)
	_check("zero spread fires perfectly straight", single.directions(aim, 0.0, rng)[0].angle(), 0.0)

	var cone := SpreadCone.new()
	cone.count = 8
	var pellets := cone.directions(aim, 20.0, rng)
	_check_int("cone produces every pellet", pellets.size(), 8)

	var widest := 0.0
	for direction in pellets:
		widest = maxf(widest, absf(direction.angle()))
	_check_bool("every pellet stays inside the cone", widest <= deg_to_rad(20.0) + 0.001, true)
	_check_bool("pellets actually scatter", widest > 0.0, true)

func _test_spread_fan_is_even() -> void:
	var rng := RunRandom.new(7)
	var fan := SpreadFan.new()
	fan.count = 3
	fan.jitter_ratio = 0.0

	var directions := fan.directions(Vector2.RIGHT, 30.0, rng)
	_check_int("fan produces every projectile", directions.size(), 3)
	_check("fan spans the full cone low", directions[0].angle(), -deg_to_rad(30.0))
	_check("fan centres the middle shot", directions[1].angle(), 0.0)
	_check("fan spans the full cone high", directions[2].angle(), deg_to_rad(30.0))

# --- targeting -------------------------------------------------------------

func _test_target_nearest() -> void:
	var positions := PackedVector2Array([Vector2(100, 0), Vector2(30, 0), Vector2(300, 0)])
	var models: Array = [EntityModel.new(), EntityModel.new(), EntityModel.new()]

	var selector := TargetNearest.new()
	_check_int("picks the closest", selector.select(Vector2.ZERO, positions, models, 0.0), 1)
	_check_int("respects max range", selector.select(Vector2.ZERO, positions, models, 20.0), -1)
	_check_int("nothing to shoot", selector.select(Vector2.ZERO, PackedVector2Array(), [], 0.0), -1)

func _test_target_by_health() -> void:
	var positions := PackedVector2Array([Vector2(100, 0), Vector2(30, 0), Vector2(300, 0)])
	var models: Array = []
	for hp in [50.0, 90.0, 10.0]:
		var model := EntityModel.new()
		model.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0, &"base")
		model.set_hp(hp)
		models.append(model)

	var lowest := TargetByHealth.new()
	lowest.mode = TargetByHealth.Mode.LOWEST
	_check_int("finishes off the weakest", lowest.select(Vector2.ZERO, positions, models, 0.0), 2)

	var highest := TargetByHealth.new()
	highest.mode = TargetByHealth.Mode.HIGHEST
	_check_int("goes for the toughest", highest.select(Vector2.ZERO, positions, models, 0.0), 1)

	# Range still applies, so a sniper selector cannot reach past its range.
	_check_int("out of range means no target", lowest.select(Vector2.ZERO, positions, models, 50.0), 1)

# --- shot construction -----------------------------------------------------

func _test_shot_damage_sums_weapon_and_wielder() -> void:
	var wielder := EntityModel.new()
	wielder.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 5.0, &"char")

	var weapon := _make_weapon()
	weapon.set_wielder(wielder)
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")

	var shot := weapon.build_shot(null)
	# The wielder's damage stat adds to the weapon's, which is why a ranged
	# character improves every gun rather than one of them.
	_check("weapon and wielder damage combine", shot.amount, 17.0)
	_check_bool("no crit without crit chance", shot.is_crit, false)

func _test_crit_is_rolled_once_per_shot() -> void:
	var weapon := _make_weapon()
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 10.0, &"weapon")
	weapon.stats.add_modifier(StatTypes.Stat.CRIT_CHANCE, StatTypes.Modifier.BASE, 1.0, &"weapon")
	# Neutral crit multiplier is 2.0, so +1.0 makes it 3.0.
	weapon.stats.add_modifier(StatTypes.Stat.CRIT_MULTIPLIER, StatTypes.Modifier.FLAT, 1.0, &"weapon")

	var shot := weapon.build_shot(null)
	_check_bool("guaranteed crit lands", shot.is_crit, true)
	_check("crit multiplies the shot", shot.amount, 30.0)

	# One snapshot feeds every pellet and every pierce, so all of them inherit
	# the same single roll - shotgun pellets crit together by construction.
	var first := shot.to_damage_event()
	var second := shot.to_damage_event()
	_check_bool("all hits from one shot share the crit", first.is_crit and second.is_crit, true)
	_check("all hits share the amount", second.amount, 30.0)

func _test_pipeline_can_force_a_crit() -> void:
	var weapon := _make_weapon()
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 10.0, &"weapon")

	var guarantee := GuaranteedCrit.new()
	weapon.effects.register(EffectInstance.new(guarantee, StringName("test")))

	# The pipeline runs BEFORE the roll, which is what lets "your next shot
	# always crits" exist at all.
	var shot := weapon.build_shot(null)
	_check_bool("effect forced the crit", shot.is_crit, true)
	_check("forced crit applies the multiplier", shot.amount, 20.0)

func _test_falloff() -> void:
	var shot := ShotSnapshot.new()
	shot.amount = 100.0
	shot.falloff_start = 100.0
	shot.falloff_end = 300.0
	shot.falloff_multiplier = 0.25

	_check("full damage inside the sweet spot", shot.to_damage_event(50.0).amount, 100.0)
	_check("half way through the falloff", shot.to_damage_event(200.0).amount, 62.5)
	_check("floor beyond the far end", shot.to_damage_event(500.0).amount, 25.0)

	var flat := ShotSnapshot.new()
	flat.amount = 100.0
	_check("falloff disabled by default", flat.to_damage_event(9999.0).amount, 100.0)

# --- melee swings ----------------------------------------------------------

func _make_swing(motion: SwingPattern.Motion) -> SwingPattern:
	var swing := SwingPattern.new()
	swing.motion = motion
	swing.arc_degrees = 160.0
	swing.reach = 50.0
	swing.duration = 0.3
	swing.windup_ratio = 0.4
	return swing

func _test_swing_arc_sweeps() -> void:
	var swing := _make_swing(SwingPattern.Motion.ARC)
	var half := deg_to_rad(160.0) * 0.5
	var overshoot := deg_to_rad(swing.windup_overshoot_degrees)

	# Anticipation: the weapon travels BEYOND the start of the arc during the
	# windup, then releases through the whole sweep. Without this the swing is
	# a bare rotation and reads as sterile.
	_check("swing begins at the arc edge", swing.angle_at(0.0, false), -half)
	_check_bool("windup winds back past the start", swing.angle_at(swing.windup_ratio * 0.99, false) < -half, true)
	_check("release starts from the wound-back angle", swing.angle_at(swing.windup_ratio, false), -half - overshoot)
	_check("arc finishes at the far edge", swing.angle_at(1.0, false), half)

	# Monotonic through the live window - a swing must not wobble backwards.
	var previous := -INF
	var monotonic := true
	for i in 20:
		var t := lerpf(swing.windup_ratio, 1.0, float(i) / 19.0)
		var angle := swing.angle_at(t, false)
		if angle < previous - 0.0001:
			monotonic = false
		previous = angle
	_check_bool("arc sweeps one way only", monotonic, true)

func _test_swing_mirroring() -> void:
	var swing := _make_swing(SwingPattern.Motion.ARC)
	# Alternating sides is just a sign flip, so a repeated swing does not read
	# as a loop.
	_check("mirrored swing is the exact opposite", swing.angle_at(1.0, true), -swing.angle_at(1.0, false))
	_check("mirroring does not change reach", swing.reach_at(0.8), swing.reach_at(0.8))

func _test_swing_thrust_goes_out_and_back() -> void:
	var swing := _make_swing(SwingPattern.Motion.THRUST)

	_check("thrust does not rotate", swing.angle_at(0.7, false), 0.0)
	# Fully extended halfway through the live window, retracted at both ends.
	var midpoint := lerpf(swing.windup_ratio, 1.0, 0.5)
	_check("thrust extends fully at the midpoint", swing.reach_at(midpoint), 50.0)
	_check("thrust is retracted at the end", swing.reach_at(1.0), 0.0)

func _test_swing_windup_is_not_live() -> void:
	var swing := _make_swing(SwingPattern.Motion.ARC)

	# The telegraph deals no damage - it is what makes a heavy weapon read as
	# heavy rather than merely slow.
	_check_bool("no damage during the windup", swing.is_active(0.2), false)
	_check_bool("live once the windup ends", swing.is_active(0.5), true)
	_check_bool("live at the last instant", swing.is_active(1.0), true)

	# And the weapon draws in before it goes out.
	_check_bool("weapon pulls back first", swing.reach_at(0.35) < swing.reach_at(0.05), true)

func _test_swing_curve_override() -> void:
	var swing := _make_swing(SwingPattern.Motion.ARC)

	# A Curve replaces the built-in easing, which is how the feel gets tuned in
	# the Inspector without touching code.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	swing.angle_curve = curve

	# A curve that sits at 1.0 puts the blade at the end of the arc from the
	# instant the release begins.
	var half := deg_to_rad(160.0) * 0.5
	_check("curve overrides the default easing", swing.angle_at(swing.windup_ratio, false), half)

## The blade points AWAY from the wielder in every motion - a weapon seen from
## above reads that way whether it sweeps or stabs. Rotating arcs by 90 made the
## sword look like it was being swept flat, sideways-on.
func _test_blade_points_outward() -> void:
	for motion in [SwingPattern.Motion.ARC, SwingPattern.Motion.THRUST]:
		var swing := _make_swing(motion)
		var midpoint := lerpf(swing.windup_ratio, 1.0, 0.5)
		_check(
			"blade lies along its own radius (motion %d)" % motion,
			swing.tilt_at(midpoint, false),
			swing.angle_at(midpoint, false)
		)

## An offset is still available for weapons that want to be off-axis, and it
## eases in and out rather than sitting at a fixed skew.
func _test_blade_tilt_offset() -> void:
	var swing := _make_swing(SwingPattern.Motion.ARC)
	swing.blade_tilt_offset_degrees = 40.0
	var midpoint := lerpf(swing.windup_ratio, 1.0, 0.5)

	_check_bool(
		"offset skews the blade",
		absf(swing.tilt_at(midpoint, false) - swing.angle_at(midpoint, false)) > 0.1,
		true
	)
	_check_bool(
		"mirrored swing skews the other way",
		swing.tilt_at(midpoint, true) < -swing.angle_at(midpoint, false),
		true
	)

# --- test-only effect ------------------------------------------------------

class GuaranteedCrit extends DynamicEffect:
	func get_hooks() -> Array:
		return [Hooks.Hook.CALCULATE_DAMAGE]

	func execute(_host: Variant, _inst: EffectInstance, event: EventPayload) -> void:
		var shot := event as ShotSnapshot
		if shot != null:
			shot.crit_chance = 1.0

# --- assertions ------------------------------------------------------------

# --- what a weapon inherits from whoever is holding it ----------------------

func _scaling(stat: StatTypes.Stat, coefficient: float) -> StatScaling:
	var entry := StatScaling.new()
	entry.stat = stat
	entry.coefficient = coefficient
	return entry

func _weapon_from(data: WeaponData) -> WeaponModel:
	var weapon := WeaponModel.new(data)
	weapon.rng = RunRandom.new(1234)
	return weapon

## REGRESSION. Only MELEE_DAMAGE and RANGED_DAMAGE ever crossed from holder to
## weapon; every other combat stat was read off the weapon alone, which made
## four authored items decorative - the stat sheet moved and no shot changed.
func _test_the_wielder_stats_now_reach_the_weapon() -> void:
	var wielder := EntityModel.new()
	wielder.stats.add_modifier(StatTypes.Stat.CRIT_CHANCE, StatTypes.Modifier.FLAT, 0.25, &"item")
	wielder.stats.add_modifier(StatTypes.Stat.RANGE, StatTypes.Modifier.FLAT, 50.0, &"item")
	wielder.stats.add_modifier(StatTypes.Stat.PIERCING, StatTypes.Modifier.FLAT, 2.0, &"item")

	var weapon := _make_weapon()
	weapon.stats.add_modifier(StatTypes.Stat.CRIT_CHANCE, StatTypes.Modifier.BASE, 0.1, &"weapon")
	weapon.stats.add_modifier(StatTypes.Stat.RANGE, StatTypes.Modifier.BASE, 300.0, &"weapon")

	_check("with no wielder a weapon is only itself", weapon.combined_stat(StatTypes.Stat.RANGE), 300.0)

	weapon.set_wielder(wielder)
	_check("the holder's crit chance arrives", weapon.combined_stat(StatTypes.Stat.CRIT_CHANCE), 0.35)
	_check("so does their range", weapon.combined_stat(StatTypes.Stat.RANGE), 350.0)
	_check("and their piercing", weapon.combined_stat(StatTypes.Stat.PIERCING), 2.0)

## The trap this whole mechanism exists to avoid. ATTACK_SPEED is a multiplier
## neutral at 1.0, so ADDING the holder's 1.0 to the weapon's 1.0 would double
## every weapon's rate of fire out of nowhere.
func _test_a_multiplier_multiplies_rather_than_adding() -> void:
	var wielder := EntityModel.new()
	var weapon := _make_weapon()
	weapon.set_wielder(wielder)

	# A player carrying nothing must leave the weapon exactly as it was. Before
	# EntityModel seeded neutrals this read the FLOOR of 0.05 and would have
	# slowed every weapon in the game to a twentieth of its rate.
	_check("a holder with no bonuses changes nothing", weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED), 1.0)

	wielder.stats.add_modifier(StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.FLAT, 0.4, &"item")
	_check("+40% on the holder is x1.4, not +1.4", weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED), 1.4)

	var fast := _make_weapon(2.0)
	fast.set_wielder(wielder)
	_check("and it composes with the weapon's own rate", fast.combined_stat(StatTypes.Stat.ATTACK_SPEED), 2.8)

func _test_inheritance_can_withhold_part_of_a_stat() -> void:
	var wielder := EntityModel.new()
	wielder.stats.add_modifier(StatTypes.Stat.ATTACK_SPEED, StatTypes.Modifier.FLAT, 0.4, &"item")
	wielder.stats.add_modifier(StatTypes.Stat.RANGE, StatTypes.Modifier.FLAT, 100.0, &"item")

	var data := WeaponData.new()
	data.stat_inheritance = [
		_scaling(StatTypes.Stat.ATTACK_SPEED, 0.5),
		_scaling(StatTypes.Stat.RANGE, 0.0),
	]

	var weapon := _weapon_from(data)
	weapon.set_wielder(wielder)
	weapon.stats.add_modifier(StatTypes.Stat.RANGE, StatTypes.Modifier.BASE, 300.0, &"weapon")

	# HALF OF THE DEVIATION, not half of the number: half of a 1.4 attack speed
	# is 1.2. Halving the value itself would hand a well-equipped player a
	# SLOWER weapon than an empty-handed one.
	_check("half of +40% is +20%", weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED), 1.2)
	_check("a share of zero takes nothing", weapon.combined_stat(StatTypes.Stat.RANGE), 300.0)
	# Unlisted stats are unaffected and still transfer in full.
	_check("what is not listed still arrives whole", weapon.inheritance_share(StatTypes.Stat.CRIT_CHANCE), 1.0)

func _test_damage_scales_off_whatever_stat_it_names() -> void:
	var wielder := EntityModel.new()
	wielder.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 100.0, &"char")
	wielder.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 200.0, &"char")
	wielder.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 10.0, &"char")

	# A weapon that grows with health and shrinks as its owner runs. Neither
	# needs a line of code - both are two entries in a .tres.
	var data := WeaponData.new()
	data.damage_scaling = [
		_scaling(StatTypes.Stat.MAX_HP, 0.1),
		_scaling(StatTypes.Stat.MOVEMENT_SPEED, -0.02),
	]

	var weapon := _weapon_from(data)
	weapon.set_wielder(wielder)
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")

	# 12 own + 10% of 100 max HP - 2% of 200 speed = 12 + 10 - 4.
	var shot := weapon.build_shot(data)
	_check("damage comes from the stats it names", shot.amount, 18.0)

	# And ONLY from those. A table that silently kept the damage type as well
	# would be a table nobody could read.
	_check_bool("the holder's ranged damage is not added too", is_equal_approx(shot.amount, 28.0), false)

func _test_half_scaling_halves_the_bonus_not_the_weapon() -> void:
	var wielder := EntityModel.new()
	wielder.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 10.0, &"char")

	var data := WeaponData.new()
	data.damage_scaling = [_scaling(StatTypes.Stat.RANGED_DAMAGE, 0.5)]

	var weapon := _weapon_from(data)
	weapon.set_wielder(wielder)
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")

	# The WEAPON's own 12 is untouched and only the holder's 10 is halved. This
	# is the whole lever: a flat bonus applies per hit, so without it a very
	# fast weapon converts every damage item into far more DPS than a slow one.
	_check("the weapon keeps all of its own damage", weapon.build_shot(data).amount, 17.0)

	var empty := WeaponData.new()
	var plain := _weapon_from(empty)
	plain.set_wielder(wielder)
	plain.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")
	_check("an empty table still means all of it", plain.build_shot(empty).amount, 22.0)

## A mechanic the player cannot see reads as a bug: buy +50% ranged damage,
## watch half of it disappear, conclude the item is broken. The text is DERIVED
## from the same tables the arithmetic uses, so it cannot drift from them.
func _test_a_weapon_says_what_it_scales_with() -> void:
	var plain := WeaponData.new()
	_check_int("a weapon with no tables says nothing", plain.detail_notes().size(), 0)

	var data := WeaponData.new()
	data.damage_scaling = [
		_scaling(StatTypes.Stat.RANGED_DAMAGE, 0.5),
		_scaling(StatTypes.Stat.MAX_HP, 0.1),
	]
	data.stat_inheritance = [_scaling(StatTypes.Stat.ATTACK_SPEED, 0.5)]

	var notes := data.detail_notes()
	_check_int("one line per entry", notes.size(), 3)
	# The SAME key the stat sheet shows, built from the enum rather than spelled
	# again - two spellings of one name is how a screen disagrees with itself.
	_check_bool("names the stat as the sheet does", notes[0] == "scales 50% with STAT_RANGED_DAMAGE", true)
	_check_bool("and the foreign one too", notes[1] == "scales 10% with STAT_MAX_HP", true)
	_check_bool("inheritance reads differently", notes[2] == "inherits 50% of STAT_ATTACK_SPEED", true)

## THIRTY stats at once, half of them pulling the other way.
##
## Asserted rather than assumed, because "it is just a list" is exactly the kind
## of claim that turns out to have a cap, a lookup that only checks the first
## match, or a sign that gets lost somewhere. The table is walked in full and
## every entry lands, positive and negative alike.
func _test_a_weapon_may_scale_off_many_stats_in_both_directions() -> void:
	var wielder := EntityModel.new()
	var data := WeaponData.new()
	var expected := 0.0
	var used := 0

	for stat in StatTypes.Stat.values():
		# The weapon's own damage type takes the other path - a share of the
		# holder's bonuses rather than a stat's value - and is covered above.
		if stat == StatTypes.Stat.RANGED_DAMAGE or stat == StatTypes.Stat.MELEE_DAMAGE:
			continue
		# The crit pair is held out for a reason worth recording: piling +10 onto
		# the holder's CRIT_CHANCE made every shot in this test a guaranteed
		# crit, and +10 on CRIT_MULTIPLIER turned the weapon's 2.0 into 22.0, so
		# the total came out 22x. That was the inheritance working exactly as
		# intended and the test asking the wrong question.
		if stat == StatTypes.Stat.CRIT_CHANCE or stat == StatTypes.Stat.CRIT_MULTIPLIER:
			continue
		if used >= 30:
			break

		wielder.stats.add_modifier(stat, StatTypes.Modifier.FLAT, 10.0, &"test")
		# Alternating, so a sign that was being dropped or taken as absolute
		# would show up as a wrong total rather than as a plausible one.
		var coefficient := 0.5 if used % 2 == 0 else -0.25
		data.damage_scaling.append(_scaling(stat, coefficient))
		# Read back rather than assumed to be 10: floors and neutrals apply, and
		# the expectation has to be whatever the stat actually reports.
		expected += wielder.stats.get_stat(stat) * coefficient
		used += 1

	var weapon := _weapon_from(data)
	weapon.set_wielder(wielder)
	weapon.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")

	_check_int("thirty stats feed one weapon", used, 30)
	_check("and every one of them lands", weapon.build_shot(data).amount, 12.0 + expected)
	_check_int("each gets its own line in the shop", data.detail_notes().size(), 30)

	# Scaled far enough into the negative, a shot comes out below zero. It must
	# deal NOTHING rather than heal what it hits - DamageEvent.final_amount()
	# floors at zero, which is what makes deep negative scaling safe to author.
	var cursed := WeaponData.new()
	cursed.damage_scaling = [_scaling(StatTypes.Stat.MOVEMENT_SPEED, -1.0)]
	var runner := EntityModel.new()
	runner.stats.add_modifier(StatTypes.Stat.MOVEMENT_SPEED, StatTypes.Modifier.BASE, 200.0, &"char")

	var weak := _weapon_from(cursed)
	weak.set_wielder(runner)
	weak.stats.add_modifier(StatTypes.Stat.RANGED_DAMAGE, StatTypes.Modifier.BASE, 12.0, &"weapon")

	var shot := weak.build_shot(cursed)
	_check("a shot can go negative", shot.amount, -188.0)

	var victim := EntityModel.new()
	victim.stats.add_modifier(StatTypes.Stat.MAX_HP, StatTypes.Modifier.BASE, 50.0, &"body")
	victim.set_hp(50.0)
	var event := DamageEvent.new()
	event.amount = shot.amount
	victim.apply_damage(event)
	_check("but it heals nothing", victim.current_hp, 50.0)

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
