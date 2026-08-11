class_name EffectSpawn
extends DynamicEffect

## GENERIC: "this puts more of those into the world".
##
## The WHEN is authored and the WHAT is a plain EntityData, so one class covers
## the two families the enemy list asks for and the ones it does not yet:
##
##   ON_DEATH     a splitter that bursts into two smaller ones
##   ON_INTERVAL  a hive that drops brood on a clock
##
## Deliberately the same shape as EffectBlast, which is what made this cheap: an
## occasion, a payload, and one door on EntityModel. Neither knows the other
## exists, and neither knows what a scene is.

enum Trigger {
	ON_DEATH,
	ON_INTERVAL,
}

## What to put into the world. EntityData rather than EnemyData so this class
## never learns which side it is making things for - the view dispatches on the
## type, and a pickup or a turret would come through here unchanged.
@export var data: EntityData

@export var count: int = 2

@export var trigger: Trigger = Trigger.ON_DEATH

## Seconds between arrivals, for ON_INTERVAL. Ignored by ON_DEATH.
@export var interval: float = 4.0

## Where they arrive. Null lets the view use its default scatter, exactly as a
## WaveEntry with no pattern falls back to the wave spawner's.
@export var pattern: SpawnPattern

## Nothing beyond `count` is capped here on purpose. A hive that outruns the
## player's clearing speed is a pacing problem for the WAVE TABLE to answer - by
## how many hives it buys and how long the wave runs - not something this class
## should decide on everybody's behalf.
const TIMER_STATE := &"spawn_elapsed"

func get_hooks() -> Array:
	var hook: Hooks.Hook = (
		Hooks.Hook.ON_TICK if trigger == Trigger.ON_INTERVAL else Hooks.Hook.ON_DEATH
	)
	return [hook]

func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var owner_model := host as EntityModel
	if owner_model == null or data == null or count <= 0:
		return

	if trigger == Trigger.ON_DEATH:
		# Its own position, which is still correct on a corpse: the view keeps
		# publishing it and stops only when the node is freed, which happens
		# after the death has been dispatched.
		owner_model.request_spawn(data, count * inst.stacks, pattern)
		return

	var tick := event as TickEvent
	if tick == null or interval <= 0.0:
		return

	# The clock lives in the INSTANCE, never on this resource: a .tres is shared
	# by every holder of it, so a timer kept here would have every hive in the
	# wave counting the same seconds and firing together.
	var elapsed: float = float(inst.get_state(TIMER_STATE, 0.0)) + tick.delta
	if elapsed < interval:
		inst.set_state(TIMER_STATE, elapsed)
		return

	# One brood per crossing rather than draining the whole debt in a loop. A
	# frame that ran long - a chain of explosions, a scene load - would otherwise
	# empty several intervals at once and put a wall of them down in one frame.
	inst.set_state(TIMER_STATE, elapsed - interval)
	owner_model.request_spawn(data, count * inst.stacks, pattern)

func describe(inst: EffectInstance) -> String:
	if data == null:
		return ""
	var total := count * inst.stacks
	if trigger == Trigger.ON_INTERVAL:
		return "releases %d every %.0fs" % [total, interval]
	return "breaks into %d when killed" % total
