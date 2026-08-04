class_name WaveDirector
extends RefCounted

## Decides WHAT spawns and WHEN during a wave. Pure logic - it returns a list of
## EnemyData to place, and the scene layer decides where.
##
## Waves end on a TIMER, not on clearing the arena. That is the pacing the genre
## wants: pressure that builds and then releases, rather than a hunt for the one
## enemy hiding in a corner.

signal wave_finished

var table: WaveTable

var wave_number: int = 0
var elapsed: float = 0.0
var duration: float = 0.0

var _budget: float = 0.0
var _spent: float = 0.0
var _events_left: int = 0
var _planned_events: int = 0
var _next_event_at: float = 0.0
var _finished: bool = false

func begin(p_wave_number: int) -> void:
	wave_number = p_wave_number
	elapsed = 0.0
	_finished = false

	if table == null:
		duration = 0.0
		_events_left = 0
		return

	duration = table.duration_for(wave_number)
	_budget = table.budget_for(wave_number)
	_spent = 0.0
	_next_event_at = 0.0

	# Only schedule as many events as the budget can actually pay for, then
	# spread THOSE across the wave. With a fixed event count, a wave whose
	# budget covers three batches spends everything in the first seconds and
	# leaves the rest of the wave empty.
	_events_left = clampi(roundi(_budget / _average_batch_cost()), 1, maxi(1, table.spawn_events))
	_planned_events = _events_left

## Advances the wave and returns whatever should spawn this frame.
func advance(delta: float, rng: RunRandom) -> Array[EnemyData]:
	var spawns: Array[EnemyData] = []
	if _finished or table == null:
		return spawns

	elapsed += delta

	# Spawning is spread across the whole wave rather than dumped at the start,
	# so pressure builds instead of arriving all at once.
	while _events_left > 0 and elapsed >= _next_event_at:
		spawns.append_array(_run_spawn_event(rng))
		_events_left -= 1
		_next_event_at = _event_time(_planned_events - _events_left)

	if elapsed >= duration:
		_finished = true
		wave_finished.emit()

	return spawns

func is_finished() -> bool:
	return _finished

func time_remaining() -> float:
	return maxf(0.0, duration - elapsed)

func budget_spent_ratio() -> float:
	return _spent / _budget if _budget > 0.0 else 1.0

# --- internals -------------------------------------------------------------

## Event `index` out of the PLANNED count, spread over the wave. The last events
## land before the very end, leaving a stretch to clear what is left.
func _event_time(index: int) -> float:
	var window := duration * 0.85
	return window * float(index) / float(maxi(1, _planned_events))

## Cost of a typical batch, weighted the same way the picker weights entries -
## so the plan matches what actually gets drawn.
func _average_batch_cost() -> float:
	var available := table.available_entries(wave_number)
	if available.is_empty():
		return 1.0

	var total_weight := 0.0
	var weighted_cost := 0.0
	for entry in available:
		var batch := entry.cost * float(maxi(1, entry.group_size))
		weighted_cost += batch * entry.weight
		total_weight += entry.weight

	return weighted_cost / total_weight if total_weight > 0.0 else 1.0

func _run_spawn_event(rng: RunRandom) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	var available := table.available_entries(wave_number)
	if available.is_empty():
		return result

	# Each event gets an equal share of what is left, so a wave cannot blow its
	# whole budget on the first batch.
	var share := (_budget - _spent) / float(maxi(1, _events_left))

	var options: Array = []
	var weights := PackedFloat32Array()
	for entry in available:
		options.append(entry)
		weights.append(entry.weight)

	var guard := 0
	while _spent < _budget and guard < 32:
		guard += 1
		var entry := rng.weighted_pick(RunRandom.Stream.SPAWNS, options, weights) as WaveEntry
		if entry == null:
			break

		var batch_cost := entry.cost * float(maxi(1, entry.group_size))
		if batch_cost > share and not result.is_empty():
			break
		if _spent + batch_cost > _budget and not result.is_empty():
			break

		for i in maxi(1, entry.group_size):
			result.append(entry.enemy)
		_spent += batch_cost

		if _spent >= _budget:
			break
		share -= batch_cost
		if share <= 0.0:
			break

	return result
