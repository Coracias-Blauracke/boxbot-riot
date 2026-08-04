class_name ItemData
extends Resource

## A passive item bought in the shop between waves.

@export var display_key: String = ""
@export var icon: Texture2D

## Tier - drives shop rolls and effects such as
## "gain +X for every tier 4 item you own".
@export_range(1, 4) var tier: int = 1

@export_group("Effects")
## Plain numbers - pushed into StatsManager immediately on acquisition.
@export var static_stats: Array[StatModifier] = []

## Behaviour that depends on game state - registered with the EffectDispatcher.
@export var dynamic_effects: Array[DynamicEffect] = []

@export_group("Character appearance")
## Brotato-style layering: the most recently bought item for a given slot
## overrides the look. The view REBUILDS itself from the model rather than
## appending layers incrementally - otherwise selling an item or loading a save
## drifts out of sync.
@export var body_slot: StringName = &""
@export var sprite_layer: Texture2D
