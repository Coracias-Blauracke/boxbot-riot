class_name EffectHealWhenHittingStatus
extends DynamicEffect

## "5% chance to heal 1 HP when attacking a poisoned enemy."
##
## A notification rather than a pipeline: the healing happens AFTER the blow has
## landed and changes nothing about it, so there is nothing to intercept.

@export var status_id: StringName = &"poison"
@export var chance: float = 0.05
@export var heal_amount: float = 1.0

func get_hooks() -> Array:
	return [Hooks.Hook.ON_DAMAGE_DEALT]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var damage := event as DamageEvent
	if damage == null or damage.target == null:
		return
	if not damage.target.statuses.has(status_id):
		return

	var attacker := host as EntityModel
	# Rolled on the run generator, not randf(), so a run replays identically
	# from its seed and this is testable.
	if not attacker.rng.chance(RunRandom.Stream.COMBAT, chance * float(inst.stacks)):
		return

	# Through heal() so CALCULATE_HEAL applies, and so it cannot raise a corpse.
	attacker.heal(heal_amount, attacker)

func describe(inst: EffectInstance) -> String:
	return "%d%% to heal %s hitting %s (x%d)" % [
		roundi(chance * 100.0), str(heal_amount), status_id, inst.stacks
	]
