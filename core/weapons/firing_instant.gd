class_name FiringInstant
extends FiringPattern

## Plain repeating fire. Pistols, bows, most melee.

func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int:
	tick_cooldown(weapon, delta, wants_to_fire and weapon.can_fire())
	if not wants_to_fire or not weapon.can_fire():
		return 0
	if weapon.cooldown > 0.0:
		return 0

	weapon.cooldown = maxf(0.0, weapon.cooldown) + interval_for(weapon)
	return 1
