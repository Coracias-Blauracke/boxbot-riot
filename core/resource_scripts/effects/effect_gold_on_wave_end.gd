extends DynamicEffect
class_name EffectGoldOnWaveEnd

@export var gold_per_item: int = 15

# Nadpisujemy funkcję z klasy bazowej
func on_wave_end(model, amount: int) -> void:
	var total_gold = gold_per_item * amount
	
	# Model musi mieć zmienną 'gold' (dodawaliśmy ją w pierwotnym PlayerModel!)
	model.gold += total_gold 
	print("-> EFEKT DYNAMICZNY: Dodano ", total_gold, " złota! Aktualne złoto: ", model.gold)
