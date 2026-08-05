class_name StatusStatModifier
extends StatusEffect

## Covers slow, and every timed buff or debuff that just moves a stat.
## Slow = MOVEMENT_SPEED / PERCENT / -0.3. A rage buff = MELEE_DAMAGE /
## PERCENT / +0.25. Same class, different .tres.

@export var stat: StatTypes.Stat = StatTypes.Stat.MOVEMENT_SPEED
@export var modifier_type: StatTypes.Modifier = StatTypes.Modifier.PERCENT
@export var value_per_stack: float = -0.3

## Reruns on every stack change, so it must be idempotent: strip our own
## contribution, then reapply it at the current stack count. The ActiveStatus
## itself is the source, which is what makes expiry surgical.
func on_applied(host: Variant, status: EffectInstance) -> void:
	var active := status as ActiveStatus
	var power := bonus_for(StatusScaling.Axis.POWER, active.get_applier()) if active != null else 0.0

	host.stats.remove_all_from_source(status)
	host.stats.add_modifier(stat, modifier_type, _scaled(status.stacks) * (1.0 + power), status)

func describe(inst: EffectInstance) -> String:
	return "%s %s while active" % [str(_scaled(inst.stacks)), StatTypes.Stat.keys()[stat]]

## POWER scales the authored magnitude rather than being added to it, which is
## what keeps one axis working for a debuff and a buff at once - see
## StatusScaling.Axis.POWER.

## MULT composes multiplicatively, so stacking it means raising to a power,
## not multiplying the value.
func _scaled(stacks: int) -> float:
	if modifier_type == StatTypes.Modifier.MULT:
		return pow(value_per_stack, stacks)
	return value_per_stack * stacks
