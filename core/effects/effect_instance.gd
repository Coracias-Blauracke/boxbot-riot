class_name EffectInstance
extends RefCounted

## Solves the shared-state trap.
##
## Godot caches .tres by path, so a DynamicEffect resource is a SINGLE instance
## for the entire game. If an effect kept a counter on itself ("every 1000
## bullets"), the player and every enemy holding the same item would share one
## counter and top it up for each other - silently and unreproducibly.
##
## Therefore the resource stays pure, shared, read-only CONFIGURATION, and all
## runtime state lives here - one instance per holder.

var effect: DynamicEffect          ## shared resource - DO NOT MUTATE
var source: Variant                ## ItemData / CharacterData / weapon - who granted it
var stacks: int = 1
var state: Dictionary = {}         ## per-holder state; this is what goes into the save

func _init(p_effect: DynamicEffect, p_source: Variant = null, p_stacks: int = 1) -> void:
	effect = p_effect
	source = p_source
	stacks = p_stacks

func get_state(key: StringName, default_value: Variant = 0) -> Variant:
	return state.get(key, default_value)

func set_state(key: StringName, value: Variant) -> void:
	state[key] = value
