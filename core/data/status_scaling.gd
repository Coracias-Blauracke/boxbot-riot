class_name StatusScaling
extends Resource

## "This axis of this status is modified by this stat."
##
## One entry per (axis, stat) pair, authored on the StatusEffect. A status
## declares only the axes it actually uses, which is why there is no sentinel
## for "no stat here" - the entry simply is not in the list.
##
## Why a list rather than four optional fields: a generic stat and a specific
## one COMPOSE. Bleed can name both STATUS_CHANCE and BLEED_CHANCE on the CHANCE
## axis, and an item that raises either one works, with no branch anywhere. Four
## fields would force a choice between the two.
##
## Adding a new axis is one enum value plus its handling. Adding a new status is
## a .tres and nothing else.

## Same append-only rule as every other serialized enum.
enum Axis {
	## Probability the status lands at all, added to the base chance.
	CHANCE,
	## Damage per tick per stack.
	DAMAGE,
	## How much FASTER it ticks. 0.1 is "+10% faster", so the interval is
	## divided by 1.1. Additive because stats default to 0, and a multiplier
	## neutral at 1.0 cannot be expressed by a stat that starts empty.
	RATE,
	## Extra stacks allowed on one target, added to the authored maximum.
	MAX_STACKS,
	## Seconds added to the authored duration. Only meaningful for a status that
	## does NOT tick - a ticking one lives by its tick count instead.
	DURATION,
	## Extra ticks before a ticking status expires.
	TICKS,
	## Fraction added to a spreading status' reach. 0.25 is "+25% radius".
	SPREAD_RADIUS,
	## How strong a stat-modifier status is, as a fraction of its authored
	## magnitude. A MULTIPLIER rather than an addend, so it is sign-agnostic:
	## +0.2 makes a -30% slow into -36% and a +25% rage buff into +30%. Adding
	## instead would strengthen buffs and WEAKEN debuffs with the same number.
	POWER,
}

@export var axis: Axis = Axis.DAMAGE
@export var stat: StatTypes.Stat = StatTypes.Stat.STATUS_CHANCE
