class_name WaveEntry
extends Resource

## One kind of enemy the spawner may draw, and the window in which it appears.
##
## Escalation is expressed as data rather than code: an enemy shows up from
## `min_wave`, optionally stops at `max_wave`, and competes for the wave's
## budget against everything else eligible.

@export var enemy: EnemyData

@export_group("Availability")
@export var min_wave: int = 1
## 0 means it never stops appearing.
@export var max_wave: int = 0
@export var weight: float = 1.0

@export_group("Cost")
## Budget consumed per enemy. A tough enemy costs more, so a wave that can
## afford one of them cannot also afford a swarm.
@export var cost: float = 1.0
## Spawned together as a cluster, which reads very differently from the same
## number trickling in one at a time.
@export var group_size: int = 1

func is_available(wave_number: int) -> bool:
	if wave_number < min_wave:
		return false
	return max_wave <= 0 or wave_number <= max_wave
