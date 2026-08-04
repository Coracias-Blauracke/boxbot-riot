class_name WeaponMount
extends Node2D

## Holds the wielder's weapons and spaces them evenly around it.
##
## Capacity comes from the WEAPON_SLOTS stat rather than a constant, so
## "you may carry 12 weapons instead of 6" is an ordinary modifier - which is
## exactly why weapon_slots on CharacterData is applied as a stat.

@export var radius: float = 18.0

var _weapons: Array[Weapon] = []

func slot_count(owner_model: EntityModel) -> int:
	return maxi(1, roundi(owner_model.stats.get_stat(StatTypes.Stat.WEAPON_SLOTS)))

func equip(weapon_data: WeaponData, wielder: Actor) -> Weapon:
	if _weapons.size() >= slot_count(wielder.model):
		push_warning("WeaponMount: no free slot")
		return null

	var weapon := Weapon.new()
	weapon.bind(weapon_data, wielder)
	add_child(weapon)
	_weapons.append(weapon)
	_reposition()
	return weapon

func get_weapons() -> Array[Weapon]:
	return _weapons.duplicate()

func _reposition() -> void:
	var total := _weapons.size()
	for i in total:
		var angle := TAU * float(i) / float(total)
		_weapons[i].position = Vector2.RIGHT.rotated(angle) * radius
