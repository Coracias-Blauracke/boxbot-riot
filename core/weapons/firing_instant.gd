class_name FiringInstant
extends FiringPattern

## Plain repeating fire. Pistols, bows, most melee.

func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int:
	weapon.cooldown -= delta
	if not wants_to_fire or not weapon.can_fire():
		return 0
	if weapon.cooldown > 0.0:
		return 0

	weapon.cooldown += interval_for(weapon)
	return 1
