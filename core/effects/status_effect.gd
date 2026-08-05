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
