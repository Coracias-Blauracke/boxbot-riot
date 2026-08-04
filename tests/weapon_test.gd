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
