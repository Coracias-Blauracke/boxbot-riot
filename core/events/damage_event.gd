class_name DamageEvent
extends EventPayload

## Damage resolves in TWO phases, owned by two different entities:
##
##  PHASE 1 - CALCULATE_DAMAGE at the SOURCE, once per shot.
##            Weapon stats plus wielder stats, the crit roll, multipliers.
##            The result is frozen into a ShotSnapshot.
##
##  PHASE 2 - TAKE_DAMAGE at the TARGET, once per impact.
##            Armor, resistances, shields, "takes +20% from bleed".
##
## This class is the phase 2 payload. Note what is NOT here: pierce and bounce
## counters live on the projectile, because they are projectile state rather
## than damage state, and one snapshot may feed many projectiles.

var source: EntityModel = null
var target: EntityModel = null
var weapon: EntityModel = null

var amount: float = 0.0
var damage_type: StatTypes.DamageType = StatTypes.DamageType.MELEE
var is_crit: bool = false

## Reduction computed in phase 2, kept separate so the UI can show
## "blocked X" rather than just the final number.
var absorbed: float = 0.0

func final_amount() -> float:
	return maxf(0.0, amount - absorbed)
