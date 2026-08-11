class_name MovementState
extends RefCounted

## Per-holder runtime state for a MovementBehavior.
##
## THE SAME SPLIT EffectInstance EXISTS FOR, and for the same reason. A
## MovementBehavior is a `.tres`, and Godot caches those globally, so a charger
## keeping its phase on the resource would have every charger in the wave sharing
## one clock and winding up together. The resource stays shared, read-only
## configuration; everything that changes lives here, one per enemy.
##
## Owned by the ENEMY rather than created by the behaviour, so a behaviour that
## needs no state costs nothing to give one to and no call site has to ask which
## kind it is.

## Free-form, exactly as EffectInstance.state is. A behaviour with two phases and
## a timer keeps them here under its own keys.
var state: Dictionary = {}

## HOW FAR THROUGH COMMITTING TO AN ATTACK, 0 to 1.
##
## A model fact rather than a presentation one, which is why it is here and not
## a flag in the view: the wind-up is what makes an attack readable and therefore
## dodgeable, so its progress is part of what the enemy IS doing. What that looks
## like - a flash, a shiver, a drawn arc - is the view's business entirely, and
## the view is free to draw nothing at all.
##
## 0 means "not winding up anything". Behaviours that never telegraph leave it
## alone and the view never sees it move.
var windup: float = 0.0

func get_state(key: StringName, default_value: Variant = 0.0) -> Variant:
	return state.get(key, default_value)

func set_state(key: StringName, value: Variant) -> void:
	state[key] = value
