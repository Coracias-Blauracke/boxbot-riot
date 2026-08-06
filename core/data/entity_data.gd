class_name EntityData
extends ShopEntryData

## Shared data base for EVERYTHING that exists in the world: characters,
## enemies, bosses, weapons, turrets, destructible obstacles, and the map model.
##
## This follows directly from the "every object carries the full stat set"
## decision: if a pistol has MELEE_DAMAGE and a rock has MOVEMENT_SPEED, then
## they are entities of the same kind and can share the same machinery.
##
## Extending ShopEntryData means an enemy carries a `tier` and a `base_price` it
## never uses, which is the SAME trade as an arena carrying MELEE_DAMAGE and is
## made for the same reason: one shape that every consumer can read beats a
## narrower one that half of them have to special-case. It is also what lets a
## weapon be sold in a shop and a character be described in the owned strip
## through exactly the same code path.
##
## display_key and icon come from the base. They used to be declared here AND on
## ItemData, which is the duplication that made the owned strip flatten the two
## by hand.

@export_group("Presentation")
@export var sprite: Texture2D
@export var collider_radius: float = 8.0

@export_group("Logic")
@export var base_stats: Array[StatModifier] = []

## Innate abilities. Same type as item effects - a character ability and an item
## effect are exactly the same thing, differing only in their source.
@export var innate_effects: Array[DynamicEffect] = []

func modifiers() -> Array[StatModifier]:
	return base_stats

func effects() -> Array[DynamicEffect]:
	return innate_effects
