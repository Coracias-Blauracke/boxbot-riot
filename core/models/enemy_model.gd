class_name EnemyModel
extends EntityModel

func _init(enemy_data: CharacterData) -> void:
	super() # Tworzy kalkulator stats
	setup_from_data(enemy_data) # Wczytuje np. goblin.tres
