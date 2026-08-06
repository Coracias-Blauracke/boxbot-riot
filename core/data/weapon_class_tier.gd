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

## Behaviour, for a threshold that grants something a number cannot say.
##
## Added when the design asked for a class that gives NOTHING from one to five
## and something powerful at six - which a stat line cannot express. Same type
## as item and character effects, so a class bonus, an item and an innate
## ability are one kind of thing throughout.
##
## Registered and unregistered by the same recompute that handles the
## modifiers, so a class dropping below its threshold takes the behaviour back
## as well as the numbers.
@export var effects: Array[DynamicEffect] = []
