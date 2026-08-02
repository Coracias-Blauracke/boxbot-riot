class_name EntityModel
extends RefCounted

signal damage_taken(amount: float, attacker: EntityModel)
signal died(killer: EntityModel)
signal damage_dealt(amount: float, target: EntityModel)

var stats: StatsManager
var current_hp: float = 0.0

func _init() -> void:
	stats = StatsManager.new()

# Funkcja wczytująca wyklikane zasoby z .tres do kalkulatora
func setup_from_data(character_data: CharacterData) -> void:
	for modifier in character_data.base_stats:
		stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value)
		
	# Po wczytaniu statystyk, ustawiamy zdrowie na maksymalne
	current_hp = stats.get_stat(StatTypes.Stat.MAX_HP)
