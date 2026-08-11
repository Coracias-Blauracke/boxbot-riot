class_name EffectStatPerCounter
extends DynamicEffect

## GENERIC effect: "for every N <somethings>, gain +X to <stat>".
## One class covers a whole family of items - "every 1000 bullets fired grants
## +1% ranged damage", "every 50 kills grants +2 armor", "every 10 dodges grants
## +5% movement speed".
##
## This is the rare case where the trigger IS configuration, so `get_hooks()`
## returns an exported field instead of a fixed list.

@export var counter: CounterTypes.Counter = CounterTypes.Counter.BULLETS_FIRED
@export var step: int = 1000

@export_group("Reward")
@export var stat: StatTypes.Stat = StatTypes.Stat.RANGED_DAMAGE
@export var modifier_type: StatTypes.Modifier = StatTypes.Modifier.PERCENT
@export var value_per_step: float = 0.01

@export_group("Trigger")
@export var trigger_hooks: Array[Hooks.Hook] = []

func get_hooks() -> Array:
	if trigger_hooks.is_empty():
		return [Hooks.Hook.ON_WEAPON_FIRED]
	return trigger_hooks

func execute(host: Variant, inst: EffectInstance, _event: EventPayload) -> void:
	var total: int = host.counters.get_value(counter)
	# Whole steps only: "for every 500 earned" pays at 500, not at 499.9.
	@warning_ignore("integer_division")
	var reached: int = int(total / step) if step > 0 else 0

	if reached == inst.get_state(&"applied", 0):
		return

	# Idempotent: strip this effect's entire contribution and reapply it.
	# Robust against a missed event and against the counter being reset after a
	# wave - the state always mirrors the current counter value rather than the
	# history of calls.
	host.stats.remove_all_from_source(inst)
	if reached > 0:
		host.stats.add_modifier(
			stat, modifier_type, value_per_step * reached * inst.stacks, inst
		)
	inst.set_state(&"applied", reached)

func describe(inst: EffectInstance) -> String:
	return "every %d: +%s (x%d)" % [step, str(value_per_step), inst.stacks]
