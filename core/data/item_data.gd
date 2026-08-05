class_name ItemData
extends Resource

## A passive item bought in the shop between waves.

@export var display_key: String = ""
@export var icon: Texture2D

## Tier - drives shop rolls and effects such as
## "gain +X for every tier 4 item you own".
@export_range(1, 4) var tier: int = 1

## What the shop asks on wave one, before scaling and before any effect.
##
## Authored rather than derived from the tier: a tier 3 item that only suits one
## build should be cheap, and a tier 1 item everybody wants should not be. Tier
## decides how OFTEN it is offered; this decides what it costs.
##
## Never the final figure - that comes out of the CALCULATE_PRICE pipeline, per
## buyer, which is what lets one co-op player pay currency while another pays a
## stat.
@export var base_price: int = 10

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
