class_name EntityData
extends Resource

## Shared data base for EVERYTHING that exists in the world: characters,
## enemies, bosses, weapons, turrets, destructible obstacles, and the map model.
##
## This follows directly from the "every object carries the full stat set"
## decision: if a pistol has MELEE_DAMAGE and a rock has MOVEMENT_SPEED, then
## they are entities of the same kind and can share the same machinery.

## Translation key, not display text. With hundreds of content files and a Steam
## release, retrofitting this later is a week of tedium.
@export var display_key: String = ""
@export var icon: Texture2D

@export_group("Presentation")
@export var sprite: Texture2D
@export var collider_radius: float = 8.0

@export_group("Logic")
@export var base_stats: Array[StatModifier] = []

## Innate abilities. Same type as item effects - a character ability and an item
## effect are exactly the same thing, differing only in their source.
@export var innate_effects: Array[DynamicEffect] = []
