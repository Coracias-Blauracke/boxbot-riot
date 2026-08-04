@abstract
class_name DynamicEffect
extends Resource

## Base for every effect: character abilities, item effects, statuses, special
## weapon behaviour. ONE mechanism for all of them - which is what lets an
## effect written for a character work on an item and vice versa, unchanged.
##
## The resource is shared, read-only CONFIGURATION. Runtime state belongs
## exclusively in EffectInstance (`inst.state`), never in fields of this
## resource - Godot caches .tres globally and the state would leak between
## holders.

## Pipeline order; lower runs first. Order must not depend on the order in which
## items were acquired, so that results stay deterministic.
@export var priority: int = 0

## Who the effect applies to. Matters in co-op.
@export var scope: Hooks.Scope = Hooks.Scope.SELF

## Which hooks this effect responds to.
##
## Deliberately a method rather than an @export field: the set of hooks is a
## property of the effect's CODE, not of its configuration. A designer must not
## be able to wire a gold effect to ON_CRIT, because it would not work anyway.
## Generic effects that genuinely need a configurable trigger override this and
## return their own exported field.
@abstract func get_hooks() -> Array

## `host` is untyped on purpose - typing it creates a cyclic dependency
## DynamicEffect <-> EntityModel that the GDScript parser handles badly.
## In practice you always receive an EntityModel.
@abstract func execute(host: Variant, inst: EffectInstance, event: EventPayload) -> void

## Description for the UI - may take the stack count into account.
func describe(_inst: EffectInstance) -> String:
	return ""
