class_name EffectArmorFromMaxHp
extends DynamicEffect

## PIPELINE reference pattern: "10% of max HP is added as armor".
##
## This effect CANNOT be built on a plain notification - `damage_taken(amount)`
## reports that damage has already landed, which is too late to reduce it.
## A pipeline receives a mutable payload BEFORE application and can rewrite it.

@export var max_hp_ratio: float = 0.1

func get_hooks() -> Array:
	return [Hooks.Hook.TAKE_DAMAGE]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var damage := event as DamageEvent
	if damage == null:
		return

	var armor: float = host.get_max_hp() * max_hp_ratio * inst.stacks
	var remaining: float = damage.amount - damage.absorbed
	damage.absorbed += minf(armor, maxf(0.0, remaining))

func describe(inst: EffectInstance) -> String:
	return "%d%% of max HP as armor" % roundi(max_hp_ratio * inst.stacks * 100.0)
