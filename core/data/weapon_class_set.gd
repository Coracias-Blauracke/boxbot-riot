class_name WeaponClassSet
extends Resource

## Every weapon class a run knows about, as one authored file.
##
## One resource rather than a folder scanned at load: the same reason ShopData
## holds its pools instead of the shop reading content/items. What exists is an
## authoring decision, and a run that silently gained a class because somebody
## added a file is a run nobody can balance.

@export var classes: Array[WeaponClassData] = []

## Every class a weapon's tags name. A weapon with two tags appears twice, which
## is the point: it counts toward both.
func classes_for_tags(tags: Array[StringName]) -> Array[WeaponClassData]:
	var found: Array[WeaponClassData] = []
	for entry in classes:
		if entry != null and tags.has(entry.tag):
			found.append(entry)
	return found

func class_for_tag(tag: StringName) -> WeaponClassData:
	for entry in classes:
		if entry != null and entry.tag == tag:
			return entry
	return null
