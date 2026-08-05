class_name EffectBossChancePerWave
extends DynamicEffect

## "Each wave has a 10% chance to spawn a boss."
##
## A CALCULATE_WAVE pipeline effect. Note what this is NOT: a world override.
## Two players both carrying it roll independently as the pipeline visits each
## of them, giving a combined ~19% rather than a conflict to resolve. Only
## discrete choices - the arena shape - can actually clash.

@export var chance_per_stack: float = 0.1

func get_hooks() -> Array:
	return [Hooks.Hook.CALCULATE_WAVE]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var wave := event as WaveEvent
	if wave == null or wave.spawn_boss:
		return
	if host.rng.chance(RunRandom.Stream.SPAWNS, chance_per_stack * inst.stacks):
		wave.spawn_boss = true

func describe(inst: EffectInstance) -> String:
	return "%d%% chance of a boss each wave" % roundi(chance_per_stack * inst.stacks * 100.0)
