class_name StatsManager
extends RefCounted

var _stats: Dictionary = {}

func _init() -> void:
	# Automatyczne budowanie szufladek dla każdej statystyki z Enuma
	for stat in StatTypes.Stat.values():
		_stats[stat] = {
			StatTypes.Modifier.BASE: 0.0,
			StatTypes.Modifier.FLAT: 0.0,
			StatTypes.Modifier.PERCENT: 0.0
		}

func add_modifier(stat: StatTypes.Stat, mod_type: StatTypes.Modifier, value: float) -> void:
	_stats[stat][mod_type] += value

func remove_modifier(stat: StatTypes.Stat, mod_type: StatTypes.Modifier, value: float) -> void:
	_stats[stat][mod_type] -= value

func get_stat(stat: StatTypes.Stat) -> float:
	var mods = _stats[stat]
	
	var base = mods[StatTypes.Modifier.BASE]
	var flat = mods[StatTypes.Modifier.FLAT]
	var percent = mods[StatTypes.Modifier.PERCENT]
	
	return (base + flat) * (1.0 + percent)
