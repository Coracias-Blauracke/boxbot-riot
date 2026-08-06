class_name ItemData
extends ShopEntryData

## A passive item bought in the shop between waves.
##
## display_key, icon, tier and base_price all come from ShopEntryData now: they
## were never item-specific, and a weapon needs every one of them to be sold.

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

func modifiers() -> Array[StatModifier]:
	return static_stats

func effects() -> Array[DynamicEffect]:
	return dynamic_effects

# --- acquisition -----------------------------------------------------------

## Items stack without limit, so there is nothing to refuse. A weapon answers
## this differently, and that difference is the whole reason the question is
## asked of the entry rather than decided by the shop.
func can_be_acquired_by(_host: Variant) -> bool:
	return true

func can_be_sold() -> bool:
	return true

func owned_quantity(host: Variant) -> int:
	return (host as EntityModel).items.get_quantity(self)

func acquire(host: Variant) -> void:
	(host as EntityModel).add_item(self)

func release(host: Variant) -> void:
	(host as EntityModel).remove_item(self)
