class_name DamageEvent
extends EventPayload

## Damage resolves in TWO phases, owned by two different entities:
##
##  PHASE 1 - CALCULATE_DAMAGE at the SOURCE (moment of firing / swinging)
##            weapon stats + wielder stats, crit roll, multipliers.
##            The result is frozen and travels with the projectile.
##
##  PHASE 2 - TAKE_DAMAGE at the TARGET (moment of impact)
##            armor, resistances, shields, "takes +20% from bleed".
##
## Snapshotting in phase 1 is deliberate: the weapon may be sold while the
## projectile is in flight and buffs may expire, and retroactively changing an
## already-fired shot feels wrong - plus piercing would recompute it N times.

var source: EntityModel = null
var target: EntityModel = null
var weapon: EntityModel = null

var amount: float = 0.0
var damage_type: StatTypes.DamageType = StatTypes.DamageType.MELEE
var is_crit: bool = false

## Reduction computed in phase 2, kept separate so the UI can show
## "blocked X" rather than just the final number.
var absorbed: float = 0.0

var pierce_left: int = 0
var bounce_left: int = 0

func final_amount() -> float:
	return maxf(0.0, amount - absorbed)
