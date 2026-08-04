class_name FiringChannel
extends FiringPattern

## Sustained fire for a fixed duration, then a recovery pause. Lasers,
## flamethrowers.
##
## Each tick is a full shot, so a channelled weapon goes through exactly the
## same CALCULATE_DAMAGE path as a pistol - crit is rolled per tick, and any
## effect that reacts to firing fires per tick too.

@export var channel_duration: float = 1.5
@export var tick_interval: float = 0.1
@export var recovery: float = 0.8

func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int:
	tick_cooldown(weapon, delta, wants_to_fire or weapon.channel_remaining > 0.0)

	if weapon.channel_remaining > 0.0:
		weapon.channel_remaining -= delta
		if not weapon.can_fire() or not wants_to_fire:
			# Releasing mid-beam ends it and still costs the recovery, so
			# tapping is not a way to dodge the downtime.
			weapon.channel_remaining = 0.0
			weapon.cooldown = maxf(weapon.cooldown, recovery)
			return 0
		if weapon.cooldown > 0.0:
			return 0
		weapon.cooldown += tick_interval
		if weapon.channel_remaining <= 0.0:
			weapon.cooldown = maxf(weapon.cooldown, recovery)
		return 1

	if not wants_to_fire or not weapon.can_fire() or weapon.cooldown > 0.0:
		return 0

	weapon.channel_remaining = channel_duration
	weapon.cooldown += tick_interval
	return 1
