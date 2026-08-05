class_name FiringWindup
extends FiringPattern

## Spins up before reaching full rate, and spins back down when released.
## The minigun envelope.
##
## Pairs naturally with heat: give a weapon a tiny base_interval, no meaningful
## attack speed and a high heat_per_shot, and it becomes a weapon that fires
## continuously until it overheats, with heat - not fire rate - as the limiter.

@export var spin_up_time: float = 1.2
@export var spin_down_time: float = 0.9

## Below this the weapon is still spinning and does not fire at all.
@export var min_spin_to_fire: float = 0.3

## Fire rate multiplier at full spin, relative to the base interval.
@export var rate_at_full_spin: float = 3.0

func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int:
	# Spin decays whenever the weapon is not firing, including while overheated,
	# so an overheat costs you the spin-up as well as the downtime.
	var firing := wants_to_fire and weapon.can_fire()
	if firing:
		weapon.spin = minf(1.0, weapon.spin + delta / maxf(0.01, spin_up_time))
	else:
		weapon.spin = maxf(0.0, weapon.spin - delta / maxf(0.01, spin_down_time))

	tick_cooldown(weapon, delta, firing and weapon.spin >= min_spin_to_fire)
	if not firing or weapon.spin < min_spin_to_fire:
		return 0
	if weapon.cooldown > 0.0:
		return 0

	var rate := lerpf(1.0, rate_at_full_spin, weapon.spin)
	weapon.cooldown = maxf(0.0, weapon.cooldown) + interval_for(weapon) / maxf(0.01, rate)
	return 1
