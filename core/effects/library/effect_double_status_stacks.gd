class_name EffectDoubleStatusStacks
extends DynamicEffect

## "5% chance to double the stacks of any status you apply."
##
## A PIPELINE on CALCULATE_STATUS, which is the only place the stack count is
## still changeable - by the time ON_STATUS_APPLIED fires it has already landed.

@export var chance: float = 0.05
@export var multiplier: int = 2

func get_hooks() -> Array:
	return [Hooks.Hook.CALCULATE_STATUS]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var status := event as StatusEvent
	if status == null or status.stacks <= 0:
		return

	# Only on the APPLIER's side of the pipeline. StatusManager runs offence then
	# defence with the same payload, so without this the effect would also fire
	# when somebody poisons its holder and double what they receive.
	if status.applier != host:
		return

	var applier := host as EntityModel
	if not applier.rng.chance(RunRandom.Stream.COMBAT, chance * float(inst.stacks)):
		return

	status.stacks *= multiplier

func describe(inst: EffectInstance) -> String:
	return "%d%% to apply %dx status stacks (x%d)" % [
		roundi(chance * 100.0), multiplier, inst.stacks
	]
