class_name ShopRollEvent
extends EventPayload

## PIPELINE payload for ROLL_SHOP_ITEMS - "the shop is about to be filled,
## change how".
##
## Everything here is meant to be rewritten by effects. "+1 shop slot" moves
## `offer_count`; "tier 4 items appear twice as often" scales `tier_weights`;
## "never offer melee items" filters `candidates`. None of those need the shop
## to know they exist, which is the point of doing it as a pipeline rather than
## as flags on ShopData.

var wave_number: int = 0
var offer_count: int = 0

## Index 0 is tier 1. Same shape as ShopData.tier_weights_for().
var tier_weights: PackedFloat32Array = PackedFloat32Array()

## The pool this roll may draw from. A COPY, so an effect that removes entries
## cannot damage the authored ShopData - Godot caches .tres globally and the
## edit would leak into every other player's shop and every later run.
var candidates: Array[ItemData] = []

## Tiers are 1-based; the array is not.
func weight_for_tier(tier: int) -> float:
	var index := tier - 1
	return tier_weights[index] if index >= 0 and index < tier_weights.size() else 0.0
