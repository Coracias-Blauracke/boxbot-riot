class_name CharacterSet
extends Resource

## Every character a run may be started with, as one authored file.
##
## The same shape and the same argument as WeaponClassSet and ShopData's pools:
## what exists is an AUTHORING decision, not whatever happens to be sitting in
## content/characters. A roster that silently grew because somebody dropped a
## file in a folder is a roster nobody can balance, and a half-finished
## character would be selectable the moment it parsed.
##
## It is also the thing that makes a second character reachable at all. Before
## this, main.tscn held a single `character_data` export, so every authored
## character past the first was invisible unless somebody edited the scene -
## exactly the trap weapons were in when WeaponMount owned the list.

@export var characters: Array[CharacterData] = []

func count() -> int:
	return characters.size()

func is_empty() -> bool:
	return characters.is_empty()

## Null outside the list rather than an error. The roster clamps its own picks,
## and a null here reads as "no opinion" everywhere downstream - which is what
## lets a run fall back to its authored character when no set is injected.
func at(index: int) -> CharacterData:
	if index < 0 or index >= characters.size():
		return null
	return characters[index]

func index_of(character: CharacterData) -> int:
	return characters.find(character)
