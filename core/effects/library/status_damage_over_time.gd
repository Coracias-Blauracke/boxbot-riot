class_name StatusDamageOverTime
extends StatusEffect

## Covers bleed, poison and burn - they differ only in numbers, damage type and
## which stat scales them.

@export var damage_per_stack: float = 1.0
@export var damage_type: StatTypes.DamageType = StatTypes.DamageType.POISON

## Which stat the applier tallies this status' damage into, so "every 1000 fire
## damage dealt" can only be fed by fire. NONE-equivalent is simply leaving the
## counter unauthored on a status nobody counts.
@export var damage_counter: CounterTypes.Counter = CounterTypes.Counter.DAMAGE_DEALT

## Snapshots the applier's DAMAGE scaling alongside the parameters the base
## class resolves. The stat that feeds it is named in `scaling`, so bleed and
## burn differ by authoring rather than by a field here.
func on_applied(_host: Variant, status: EffectInstance) -> void:
	var active := status as ActiveStatus
	active.tick_damage = damage_per_stack + bonus_for(
		StatusScaling.Axis.DAMAGE, active.get_applier()
	)

func on_tick(host: Variant, status: EffectInstance) -> void:
	var active := status as ActiveStatus

	var event := DamageEvent.new()
	event.amount = active.tick_damage * active.stacks
	event.damage_type = damage_type
	event.source = active.get_applier()

	# Goes through the normal damage pipeline, so armor, resistances and
	# "takes +20% from bleed" all apply without a special case here.
	# Typed explicitly: `host` is Variant, so `:=` cannot infer from it and the
	# whole script fails to compile - taking every test in the file with it.
	var landed: float = host.apply_damage(event)

	# Tallied per status, not into DAMAGE_DEALT alone: an item rewarding fire
	# specifically must not be fed by a sword.
	var applier := active.get_applier()
	if applier != null and landed > 0.0:
		applier.counters.add(damage_counter, roundi(landed))

func describe(inst: EffectInstance) -> String:
	return "%s damage per tick (x%d)" % [str(damage_per_stack), inst.stacks]
