class_name StatModifier
extends Resource

## A single "+X to stat Y of kind Z" entry, authored in the Inspector.
##
## Note that `stat` and `modifier_type` serialize as plain integers, which is
## why both enums in StatTypes are append-only. See the comment there.

@export var stat: StatTypes.Stat
@export var modifier_type: StatTypes.Modifier
@export var value: float
