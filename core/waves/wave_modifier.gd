class_name WaveModifier
extends Resource

## A named twist applied to specific waves - the horde wave being the obvious
## one.
##
## Data rather than a special case in the director, so "wave 11 has twice the
## enemies" is authored in a .tres and reviewable, instead of an `if wave == 11`
## that the next person has to find.

## Translation key, so the HUD can announce it. Nothing consumes this yet.
@export var display_key: String = ""

@export_group("When")
## Explicit wave numbers.
@export var waves: PackedInt32Array = PackedInt32Array()
## ...or every Nth wave. 0 disables. Both may be set; either match applies.
@export var every_n_waves: int = 0

@export_group("Scaling")
## 2.0 is "100% more enemies".
@export var budget_multiplier: float = 1.0
## Scaled alongside the budget on purpose. Doubling the budget alone buys twice
## as many enemies per arrival; doubling both doubles the ARRIVALS, which is
## what a horde actually feels like - relentless rather than lumpy.
@export var events_multiplier: float = 1.0

@export_group("Composition")
## 0 means no cap. A horde restricted to cheap entries is a swarm; without the
## cap, doubling the budget just buys twice as many brutes, which is a
## completely different wave.
##
## If the cap would leave nothing eligible, it is ignored rather than producing
## an empty wave - see WaveTable.available_entries.
@export var max_entry_cost: float = 0.0

func applies_to(wave_number: int) -> bool:
	if waves.has(wave_number):
		return true
	return every_n_waves > 0 and wave_number % every_n_waves == 0
