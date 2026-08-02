class_name ItemsManager
extends RefCounted

var acquired_items: Dictionary = {} 
var _player_model: PlayerModel

func _init(player_model: PlayerModel) -> void:
	_player_model = player_model
	EventBus.wave_ended.connect(_on_wave_ended)

func add_item(item_data: ItemData, quantity: int = 1) -> void:
	if acquired_items.has(item_data):
		acquired_items[item_data] += quantity
	else:
		acquired_items[item_data] = quantity
	
	for i in range(quantity):
		for modifier in item_data.static_stats:
			_player_model.stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value)

func remove_item(item_data: ItemData, quantity: int = 1) -> void:
	if not acquired_items.has(item_data):
		return
		
	var actual_quantity = min(acquired_items[item_data], quantity)
	acquired_items[item_data] -= actual_quantity
	
	if acquired_items[item_data] <= 0:
		acquired_items.erase(item_data)
		
	for i in range(actual_quantity):
		for modifier in item_data.static_stats:
			_player_model.stats.remove_modifier(modifier.stat, modifier.modifier_type, modifier.value)

func _on_wave_ended() -> void:
	for item in acquired_items:
		var amount = acquired_items[item]
		for effect in item.dynamic_effects:
			if effect.has_method("on_wave_end"):
				effect.on_wave_end(_player_model, amount)
