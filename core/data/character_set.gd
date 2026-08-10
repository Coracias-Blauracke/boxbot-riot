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

## The chassis every other one is READ against.
##
## Characters are meant to converge on one shared frame - the same health, the
## same speed - so that what a character IS can be stated as what it trades. The
## select screen therefore shows only the stats that DIFFER from this one, which
## is the difference between a panel that lists six numbers and a panel that
## says "tougher, slower, one weapon fewer".
##
## A READING aid and nothing else. Every character still carries its own
## complete stat line and a run is built from that alone, so nothing here can
## change what anybody actually plays - only what the screen bothers to mention.
## Left empty, the FIRST character stands in, because a roster's first entry is
## the plain one in every game that has a plain one.
@export var baseline: CharacterData

func baseline_or_first() -> CharacterData:
	if baseline != null:
		return baseline
	return at(0)

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
