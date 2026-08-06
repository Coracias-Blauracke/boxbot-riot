class_name WeaponClassTier
extends Resource

## One threshold in a weapon class: "hold this many, get this".

## How many weapons carrying the tag are needed. Counted per WEAPON, so two
## copies of the same blade count as two - you are holding two blades.
@export var required: int = 2

## What crossing it grants. Ordinary StatModifiers, so a class bonus, an item
## and a character bonus are all the same kind of thing and compose the same
## way.
@export var modifiers: Array[StatModifier] = []
