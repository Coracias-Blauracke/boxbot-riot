class_name WaveTable
extends Resource

## The whole escalation curve for a run, as one authored file.
##
## Budget rather than a flat enemy count: it lets a wave trade one heavy enemy
## against a swarm of light ones, and lets new enemy types be added without
## retuning every wave by hand.

@export var entries: Array[WaveEntry] = []

@export_group("Duration")
@export var base_duration: float = 20.0
@export var duration_per_wave: float = 1.5
@export var max_duration: float = 60.0

@export_group("Budget")
@export var base_budget: float = 6.0
@export var budget_per_wave: float = 2.5
## Compounding on top of the linear growth, so late waves escalate rather than
## crawling. 1.0 disables it.
@export var budget_growth: float = 1.06

@export_group("Pacing")
## Spawn events per wave. Fewer, larger batches feel like assaults; more,
## smaller ones feel like a steady grind.
@export var spawn_events: int = 12

@export_group("Co-op scaling")
## Extra share of the budget per player beyond the first. 1.0 means two players
## face twice the wave and four players face four times it.
@export var budget_per_extra_player: float = 1.0

## Extra spawn EVENTS per player beyond the first.
##
## Scaled alongside the budget deliberately. Budget alone would keep the same
## twelve arrivals and simply make each one twice the size, which reads as
## lumpy - long quiet stretches punctuated by a wall. Scaling both keeps the
## rhythm and halves the gap between arrivals, which is what more players should
## feel like.
@export var events_per_extra_player: float = 1.0

@export_group("Modifiers")
## Named twists on particular waves - hordes, elite waves. See WaveModifier.
@export var modifiers: Array[WaveModifier] = []

@export_group("Placement")
## Used by any entry that does not name its own pattern.
@export var default_pattern: SpawnPattern

func duration_for(wave_number: int) -> float:
	return minf(max_duration, base_duration + duration_per_wave * float(wave_number - 1))

func budget_for(wave_number: int, player_count: int = 1) -> float:
	var linear := base_budget + budget_per_wave * float(wave_number - 1)
	var value := linear * pow(budget_growth, float(wave_number - 1))
	value *= _player_scale(budget_per_extra_player, player_count)
	for modifier in modifiers_for(wave_number):
		value *= modifier.budget_multiplier
	return value

func events_for(wave_number: int, player_count: int = 1) -> int:
	var value := float(spawn_events) * _player_scale(events_per_extra_player, player_count)
	for modifier in modifiers_for(wave_number):
		value *= modifier.events_multiplier
	return maxi(1, roundi(value))

## Linear rather than compounding: four players should be four times the wave,
## not eight. Compounding here turns a full couch into an unplayable wall by
## wave ten, and the budget curve already compounds on its own.
func _player_scale(per_extra: float, player_count: int) -> float:
	return 1.0 + per_extra * float(maxi(1, player_count) - 1)

func modifiers_for(wave_number: int) -> Array[WaveModifier]:
	var result: Array[WaveModifier] = []
	for modifier in modifiers:
		if modifier != null and modifier.applies_to(wave_number):
			result.append(modifier)
	return result

## Tightest cap among the active modifiers; 0.0 means uncapped.
func max_entry_cost_for(wave_number: int) -> float:
	var cap := 0.0
	for modifier in modifiers_for(wave_number):
		if modifier.max_entry_cost <= 0.0:
			continue
		cap = modifier.max_entry_cost if cap <= 0.0 else minf(cap, modifier.max_entry_cost)
	return cap

func available_entries(wave_number: int, max_cost: float = 0.0) -> Array[WaveEntry]:
	var result: Array[WaveEntry] = []
	var eligible: Array[WaveEntry] = []

	for entry in entries:
		if entry == null or entry.enemy == null or not entry.is_available(wave_number):
			continue
		eligible.append(entry)
		if max_cost > 0.0 and entry.cost > max_cost:
			continue
		result.append(entry)

	# A cost cap that excludes everything would produce a silent empty wave -
	# the worst possible failure, because nothing errors and the wave just does
	# not happen. Authoring a horde capped below the cheapest enemy is a
	# mistake, so fall back to the uncapped set rather than to nothing.
	return result if not result.is_empty() else eligible
