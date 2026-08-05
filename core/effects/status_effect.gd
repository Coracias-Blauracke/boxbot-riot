class_name StatusEffect
extends DynamicEffect

## A status is an effect with a duration and a stack count.
##
## Bleeding, poison, burning, stun, slow, and every timed buff all live here.
## Because it derives from DynamicEffect it may ALSO subscribe to hooks - a
## status that changes how its bearer takes damage just overrides get_hooks().
##
## Instantiable as-is: a marker status such as stun needs no behaviour at all,
## only its presence queried via StatusManager.has().

enum RefreshMode {
	REFRESH,  ## reapplying resets the timer to full duration
	EXTEND,   ## reapplying adds to the remaining time
	KEEP,     ## reapplying only adds stacks, the timer is untouched
}

@export var status_id: StringName = &""
@export var base_duration: float = 5.0
@export var max_stacks: int = 99

## 0 disables ticking entirely (a pure modifier status such as slow).
@export var tick_interval: float = 0.0

@export var refresh_mode: RefreshMode = RefreshMode.REFRESH

## Which of the applier's stats modify which axis of this status.
##
## Empty means the status is exactly what is authored above and nothing can
## change it, which is a legitimate choice for a scripted debuff.
@export var scaling: Array[StatusScaling] = []

## Incremented on the APPLIER each time this status lands on a fresh target, for
## "for every 100 enemies poisoned". Left at STATUS_APPLIED it simply shares the
## generic tally.
@export var apply_counter: CounterTypes.Counter = CounterTypes.Counter.STATUS_APPLIED

## Sums every scaling entry for one axis off the APPLIER's stats.
##
## Generic and specific stats on the same axis simply add, which is the whole
## reason this is a list rather than four optional fields: a status can read
## both STATUS_CHANCE and BLEED_CHANCE, and an item raising either one works
## without a branch anywhere.
func bonus_for(axis: StatusScaling.Axis, applier: EntityModel) -> float:
	if applier == null:
		return 0.0

	var total := 0.0
	for entry in scaling:
		if entry != null and entry.axis == axis:
			total += applier.stats.get_stat(entry.stat)
	return total

## Freezes the applier's contribution onto the status as it lands.
##
## A SNAPSHOT, never a live read, for the same reason crit is rolled once per
## shot: the .tres is globally cached so a per-player value cannot live on it,
## the applier may die long before the poison wears off, and a buff that expires
## mid-duration must not retroactively weaken something already ticking.
##
## Typed as EffectInstance rather than ActiveStatus to keep the dependency graph
## acyclic - see the note below. Cast when the timing fields are needed.
func resolve_onto(status: EffectInstance, applier: EntityModel) -> void:
	var active := status as ActiveStatus
	if active == null:
		return

	active.max_stacks = maxi(
		1, max_stacks + roundi(bonus_for(StatusScaling.Axis.MAX_STACKS, applier))
	)

	# RATE is additive "how much faster", so 0.1 divides the interval by 1.1.
	# Additive because a stat starts at 0 and a multiplier neutral at 1.0 cannot
	# be expressed by an empty pool.
	var rate := bonus_for(StatusScaling.Axis.RATE, applier)
	active.tick_interval = tick_interval / maxf(0.05, 1.0 + rate)

## By default a status takes part in no hooks - it is driven by StatusManager.
func get_hooks() -> Array:
	return []

func execute(_host: Variant, _inst: EffectInstance, _event: EventPayload) -> void:
	pass

# --- lifecycle, driven by StatusManager ------------------------------------
#
# `status` is always an ActiveStatus; it is typed as EffectInstance to keep the
# dependency graph acyclic (StatusEffect -> ActiveStatus -> EffectInstance ->
# DynamicEffect would close a loop the GDScript parser handles badly).
# Cast with `status as ActiveStatus` when you need the timing fields.

## Called on first application AND after any stack change, so implementations
## must be idempotent.
func on_applied(_host: Variant, _status: EffectInstance) -> void:
	pass

func on_tick(_host: Variant, _status: EffectInstance) -> void:
	pass

func on_expired(_host: Variant, _status: EffectInstance) -> void:
	pass
