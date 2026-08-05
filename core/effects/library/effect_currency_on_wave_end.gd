class_name EffectCurrencyOnWaveEnd
extends DynamicEffect

## NOTIFICATION reference pattern: reacts to a fact that already happened.
## Read-only payload, call order irrelevant.

@export var currency_per_stack: int = 15

func get_hooks() -> Array:
	return [Hooks.Hook.ON_WAVE_ENDED]

func execute(host: Variant, inst: EffectInstance, _event: EventPayload) -> void:
	# Currency is a counter on EntityModel, so this works on any entity - no
	# type check and no cyclic dependency on a player-specific class.
	host.add_currency(currency_per_stack * inst.stacks)

func describe(inst: EffectInstance) -> String:
	return "+%d currency at end of wave" % (currency_per_stack * inst.stacks)
