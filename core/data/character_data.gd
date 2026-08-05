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

@export_group("Run start")
@export var starting_weapons: Array[Resource] = []

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
