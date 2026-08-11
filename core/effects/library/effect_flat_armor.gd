class_name EffectFlatArmor
extends DynamicEffect

## GENERIC: "every hit is worth this much less."
##
## The other half of defence, and the half that changes WHICH weapons work.
## `ARMOR` takes a percentage, so it scales a 5-damage hit and a 40-damage hit
## identically - it makes a thing tough and cares not at all what is shooting it.
## A FLAT absorb is the opposite: it costs a fast weak weapon most of its damage
## and a slow heavy one almost none, which is the only way to author an enemy
## that a particular kind of build struggles with.
##
## NOT NEW MACHINERY. EntityModel.apply_damage already takes armor as a share of
## what REMAINS after absorption, and its comment names "an effect that already
## absorbed a flat 10" as the reason. This is the content for a door that was
## built and never opened.
##
## It works just as well on a player, because TAKE_DAMAGE does not care whose
## side the target is on - so "you take 2 less from every hit" is this class with
## a different number, and no item has to be written for it separately.

## How much comes off each hit, before percentage armor takes its share of what
## is left.
##
## THE DANGER IS REAL AND IS THE POINT: a weapon whose hit is worth less than
## this does literally nothing, because DamageEvent.final_amount() floors at
## zero. That is what "a wall a fast weak weapon cannot chew" means, and it is
## also how an enemy becomes immune to a whole class of build by accident. Author
## it against the weakest weapon that should still be able to hurt the holder.
@export var absorb: float = 3.0

## Only these kinds of damage. Empty means every kind, INCLUDING damage over
## time - which is usually wrong for plating: a bleed tick of 2 against an
## absorb of 3 makes the target immune to bleeding entirely.
@export var damage_types: Array[StatTypes.DamageType] = []

func get_hooks() -> Array:
	return [Hooks.Hook.TAKE_DAMAGE]

func execute(_host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var damage := event as DamageEvent
	if damage == null or absorb <= 0.0:
		return

	if not damage_types.is_empty() and not damage_types.has(damage.damage_type):
		return

	# Added to `absorbed` rather than subtracted from `amount`, so the UI can
	# still say how much was blocked and so percentage armor below sees the
	# reduced figure instead of charging the same hit twice.
	#
	# Capped at what is actually left: absorbing more than the hit was worth
	# would bank negative damage against the NEXT effect in the pipeline.
	var stacked := absorb * inst.stacks
	damage.absorbed += minf(stacked, damage.final_amount())

func describe(inst: EffectInstance) -> String:
	return "every hit is worth %d less" % roundi(absorb * inst.stacks)
