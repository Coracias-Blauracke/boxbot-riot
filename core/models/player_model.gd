class_name PlayerModel
extends EntityModel # <--- KLUCZOWA ZMIANA: Dziedziczymy po Entity!

var items: ItemsManager 
var gold: int = 0

# Opcjonalnie możemy tu przekazywać np. zasób "Wojownik.tres"
func _init(player_data: CharacterData = null) -> void:
	super() # Wywołuje _init z EntityModel (czyli tworzy stats)
	
	items = ItemsManager.new(self)
	
	if player_data != null:
		setup_from_data(player_data)
