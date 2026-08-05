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

func duration_for(wave_number: int) -> float:
	return minf(max_duration, base_duration + duration_per_wave * float(wave_number - 1))

func budget_for(wave_number: int) -> float:
	var linear := base_budget + budget_per_wave * float(wave_number - 1)
	return linear * pow(budget_growth, float(wave_number - 1))

func available_entries(wave_number: int) -> Array[WaveEntry]:
	var result: Array[WaveEntry] = []
	for entry in entries:
		if entry != null and entry.enemy != null and entry.is_available(wave_number):
			result.append(entry)
	return result
