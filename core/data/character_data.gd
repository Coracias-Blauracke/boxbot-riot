class_name CharacterData
extends EntityData

## A character is a DATA FILE, not an inherited scene and not a class.
##
## A single `Character` scene drives every character; the identity of "Medic"
## lives in this resource: sprite, collider, base stats and the ability list
## (`innate_effects`, inherited from EntityData).
##
## Why scene inheritance was rejected: it is fragile whenever the base scene
## changes, it creates two parallel mechanisms for the same thing (abilities in
## code vs effects in .tres), and it does not scale combinatorially - "a Medic
## who also explodes on every step" would need a new class instead of one more
## entry in a list.

## A few sentences of flavour for the select screen, as a TRANSLATION KEY like
## every other player-facing string here.
##
## Deliberately on CharacterData and NOT on ShopEntryData, which would give
## every item and weapon one too. "Item text is DERIVED, never authored" is a
## rule with a reason - hand-written text drifts from the numbers it describes
## the moment somebody retunes one, silently, at a few hundred items. A chassis
## is the exception because it is an IDENTITY rather than a bundle: "pays for
## everything in blood" is a sentence no stat line can produce, and there are
## eight of these rather than hundreds.
##
## The numbers under it are still derived. This adds a paragraph, it does not
## replace the stat lines.
@export var description_key: String = ""

@export_group("Run start")
## Weapons this character begins the run holding.
##
## Typed, and actually READ, since neither was true before: it was
## Array[Resource] and nothing ever looked at it, because the loadout was an
## export on main.tscn instead. A character could therefore not define its own
## weapons, which is not a property a scene should own.
##
## Granted through the same path a purchase takes, so a starting weapon and a
## bought one are the same thing - and can be sold like one.
@export var starting_weapons: Array[WeaponData] = []

## Items this character begins the run holding. Listing one twice grants two
## copies, since items stack and every copy applies its own modifiers.
##
## An ordinary inventory rather than a special case: a starting item and a
## bought one are the same thing, which is why the shop can sell these back.
@export var starting_items: Array[ItemData] = []

## How many weapons this character can carry. Applied as a BASE modifier to
## WEAPON_SLOTS, which makes "you may carry 12 weapons instead of 6" an
## ordinary modifier rather than a special case.
@export var weapon_slots: int = 6

## How many things this character is offered in the shop. Applied as a BASE
## modifier to SHOP_SLOTS, exactly like weapon_slots above, so "you see two more
## items" is an ordinary item modifier rather than a shop feature.
##
## 0 means "no opinion" and ShopData.offer_count decides - which is what an
## entity with no CharacterData at all reports, so tests and previews keep the
## authored default.
@export var shop_slots: int = 4

## Optional escape hatch: if a character genuinely needs unique nodes (a
## particle system, some bespoke visual), they are instantiated as a child.
## An escape hatch without scene inheritance.
@export var extra_nodes: PackedScene

## The two slot fields as the MODIFIERS they become.
##
## They are stats like any other - that is the whole reason "this item grants a
## weapon slot" and "this curse takes a shop slot away" need no code anywhere.
## But the fact that `weapon_slots` IS a BASE modifier on WEAPON_SLOTS used to
## live inside EntityModel, which meant the select screen would have had to know
## it a second time to describe a chassis honestly. Two copies of a rule is one
## copy too many, so it lives here, next to the fields it is about.
##
## Built fresh rather than cached: a .tres is shared by every holder, and a
## mutable field on one is how state leaks between players.
func slot_modifiers() -> Array[StatModifier]:
	return [
		_slot_modifier(StatTypes.Stat.WEAPON_SLOTS, weapon_slots),
		_slot_modifier(StatTypes.Stat.SHOP_SLOTS, shop_slots),
	]

func _slot_modifier(stat: StatTypes.Stat, value: int) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.modifier_type = StatTypes.Modifier.BASE
	modifier.value = float(value)
	return modifier
