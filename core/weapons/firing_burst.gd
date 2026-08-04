class_name FiringBurst
extends FiringPattern

## N shots in quick succession, then a longer pause. Once a burst starts it
## finishes, even if the trigger is released - that is what makes a burst read
## as one action rather than a stutter.

@export var shots_per_burst: int = 3
@export var shot_interval: float = 0.07

func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int:
	weapon.cooldown -= delta

	if weapon.burst_remaining > 0:
		if not weapon.can_fire():
			weapon.burst_remaining = 0
			return 0
		if weapon.cooldown > 0.0:
			return 0
		weapon.burst_remaining -= 1
		weapon.cooldown += shot_interval if weapon.burst_remaining > 0 else interval_for(weapon)
		return 1

	if not wants_to_fire or not weapon.can_fire() or weapon.cooldown > 0.0:
		return 0

	weapon.burst_remaining = maxi(0, shots_per_burst - 1)
	weapon.cooldown += shot_interval if weapon.burst_remaining > 0 else interval_for(weapon)
	return 1
