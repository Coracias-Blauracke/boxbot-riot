class_name WeaponMount
extends Node2D

## The wielder's weapons as NODES, spaced evenly around them.
##
## A VIEW OF EntityModel.weapons, never the owner of that list. It used to be
## the owner, which is exactly why a weapon could not be bought, sold or even
## authored on a character: the only caller that could add one was main.gd, and
## nothing outside the scene layer could see what was being carried.
##
## Capacity is not enforced here either, and that is not an omission. The shop
## has to ask "is there room" BEFORE it takes any money, so the answer lives on
## the model where both can ask it; two places answering separately is how they
## come to disagree.

@export var radius: float = 18.0

## DEBUG. Passed to every weapon mounted here - see Weapon.time_scale.
@export var weapon_time_scale: float = 1.0

var _weapons: Array[Weapon] = []

## Rebuilds to match the model, REUSING the node of a weapon still carried.
##
## Deliberately a diff rather than "free everything and build it again". A
## Weapon node holds live state - heat, burst progress, a swing halfway through
## its arc - and throwing all of it away because a different weapon was sold is
## a bug that can only appear mid-combat, which is the worst place to find one.
func sync(wielder: Actor) -> void:
	if wielder == null or wielder.model == null:
		return

	var spare := _weapons.duplicate()
	var rebuilt: Array[Weapon] = []

	for weapon_data in wielder.model.weapons:
		if weapon_data == null:
			continue

		# Matched by data, so selling one of two identical pistols keeps the
		# other one's node rather than rebuilding both.
		var reused: Weapon = null
		for candidate in spare:
			if candidate.data == weapon_data:
				reused = candidate
				break

		if reused != null:
			spare.erase(reused)
			rebuilt.append(reused)
		else:
			rebuilt.append(_build(weapon_data, wielder))

	# Whatever the model no longer lists has been sold or otherwise lost.
	for orphan in spare:
		orphan.queue_free()

	_weapons = rebuilt
	_reposition()

func get_weapons() -> Array[Weapon]:
	return _weapons.duplicate()

func _build(weapon_data: WeaponData, wielder: Actor) -> Weapon:
	var weapon := Weapon.new()
	weapon.bind(weapon_data, wielder)
	weapon.time_scale = weapon_time_scale
	add_child(weapon)
	return weapon

func _reposition() -> void:
	var total := _weapons.size()
	for i in total:
		var angle := TAU * float(i) / float(total)
		_weapons[i].position = Vector2.RIGHT.rotated(angle) * radius
