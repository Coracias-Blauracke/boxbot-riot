class_name EffectApplyStatusOnHit
extends DynamicEffect

## GENERIC: "your melee hits have a chance to cause bleeding".
##
## One class covers the whole family - bleed on melee, poison on ranged, burn on
## anything - because the status, the damage type it triggers on and the chance
## are all authored. The chance itself is the status' own CHANCE axis, so an item
## raising BLEED_CHANCE improves every source of bleed at once rather than only
## the weapon that happened to grant it.

@export var status: StatusEffect

## Only hits of this kind trigger it. Leaving damage_types empty means any hit.
@export var damage_types: Array[StatTypes.DamageType] = []

## Never applied to a status' own tick, or bleed would reapply itself forever.
@export var stacks: int = 1

## Chance BEFORE the status' own CHANCE axis is added. 0.0 means the item grants
## nothing on its own and every point comes from stats, which is what "+10%
## chance to cause bleeding" means. Leaving it at 1.0 would make the item apply
## the status on every single hit and turn the stat into a penalty.
@export var base_chance: float = 0.0

func get_hooks() -> Array:
	return [Hooks.Hook.ON_DAMAGE_DEALT]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var damage := event as DamageEvent
	if damage == null or status == null or damage.target == null:
		return
	if not damage.target.is_alive:
		return

	# A status ticking damage must not be able to reapply itself: bleed dealing
	# BLEED damage would then refresh its own timer every tick and never end.
	if damage.damage_type == StatTypes.DamageType.BLEED:
		return
	if damage.damage_type == StatTypes.DamageType.POISON:
		return
	if damage.damage_type == StatTypes.DamageType.BURN:
		return

	if not damage_types.is_empty() and not damage_types.has(damage.damage_type):
		return

	# The roll lives in StatusManager, off the status' CHANCE axis, so this only
	# has to ask. Stacks scale with copies held.
	damage.target.apply_status(
		status, host as EntityModel, stacks * inst.stacks, -1.0, base_chance
	)

func describe(inst: EffectInstance) -> String:
	var name := status.status_id if status != null else &"nothing"
	return "hits may cause %s (x%d)" % [name, inst.stacks]
