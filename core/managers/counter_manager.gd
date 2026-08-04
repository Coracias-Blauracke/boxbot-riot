class_name CounterManager
extends RefCounted

## State counters, deliberately kept outside StatsManager.
## Every entity owns its own full set, exactly like it owns its own stats.

signal counter_changed(counter: CounterTypes.Counter, value: int)

var _values: Dictionary = {}

func _init() -> void:
	for counter in CounterTypes.Counter.values():
		_values[counter] = 0

func add(counter: CounterTypes.Counter, amount: int = 1) -> int:
	_values[counter] += amount
	counter_changed.emit(counter, _values[counter])
	return _values[counter]

func get_value(counter: CounterTypes.Counter) -> int:
	return _values[counter]

func set_value(counter: CounterTypes.Counter, value: int) -> void:
	if _values[counter] == value:
		return
	_values[counter] = value
	counter_changed.emit(counter, value)

## Clears counters of a given scope. Called on wave start / combat entry.
func reset_scope(scope: CounterTypes.Scope) -> void:
	for counter in CounterTypes.Counter.values():
		if CounterTypes.SCOPES.get(counter, CounterTypes.Scope.RUN) == scope:
			set_value(counter, 0)

## How many multiples of `step` were crossed by the last `added` increment.
## The "every 1000 bullets fired" pattern:
##     var total := counters.add(BULLETS_FIRED, shots)
##     var times := counters.crossings(BULLETS_FIRED, 1000, shots)
## Returns >1 when a single event jumped several thresholds at once.
func crossings(counter: CounterTypes.Counter, step: int, added: int) -> int:
	if step <= 0 or added <= 0:
		return 0
	var now: int = _values[counter]
	var before: int = now - added
	return int(now / step) - int(before / step)

## For save games - counters are not rebuildable, they must be persisted.
func to_dict() -> Dictionary:
	return _values.duplicate()

func from_dict(data: Dictionary) -> void:
	for counter in CounterTypes.Counter.values():
		if data.has(counter):
			set_value(counter, int(data[counter]))
