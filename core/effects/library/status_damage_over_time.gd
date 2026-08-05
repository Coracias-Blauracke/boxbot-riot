class_name StatusDamageOverTime
extends StatusEffect

## Covers bleed, poison and burn - they differ only in numbers, damage type and
## which stat scales them.

@export var damage_per_stack: float = 2.0
@export var damage_type: StatTypes.DamageType = StatTypes.DamageType.POISON

## The applier's stat that scales each tick, read ONCE at application time.
@export var scaling_stat: StatTypes.Stat = StatTypes.Stat.POISON_DAMAGE

## Snapshot the applier's scaling when the status lands, mirroring the damage
## model: a buff that expires mid-duration must not retroactively weaken poison
## already ticking on a target, and the applier may die before it wears off.
func on_applied(_host: Variant, status: EffectInstance) -> void:
	var active := status as ActiveStatus
	var applier := active.get_applier()
	var scaling := applier.stats.get_stat(scaling_stat) if applier != null else 0.0
	active.set_state(&"tick_damage", damage_per_stack + scaling)

func on_tick(host: Variant, status: EffectInstance) -> void:
	var active := status as ActiveStatus

	var event := DamageEvent.new()
	event.amount = float(active.get_state(&"tick_damage", damage_per_stack)) * active.stacks
	event.damage_type = damage_type
	event.source = active.get_applier()

	# Goes through the normal damage pipeline, so armor, resistances and
	# "takes +20% from bleed" all apply without a special case here.
	host.apply_damage(event)

func describe(inst: EffectInstance) -> String:
	return "%s damage per tick (x%d)" % [str(damage_per_stack), inst.stacks]
