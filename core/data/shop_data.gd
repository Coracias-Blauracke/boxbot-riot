class_name ShopData
extends Resource

## The whole shop as one authored file: what it may offer, how much it charges,
## and how the odds shift as the run goes on.
##
## One resource rather than a pool plus a config, because every one of these
## numbers is meaningless without the others - a reroll cost only means anything
## against the prices it competes with.

## Everything that may ever be offered. Tier decides how often, not whether.
@export var pool: Array[ItemData] = []

@export_group("Offers")
@export var offer_count: int = 4

## Whether one roll may show the same item twice.
##
## Off by default. Items stack, so a repeat is not meaningless - but with a
## small pool it fills three of four slots with the same thing and reads as a
## bug rather than as luck. When the pool cannot supply enough distinct items,
## repeats come back rather than leaving slots empty.
@export var allow_duplicate_offers: bool = false

## Fraction added to every price per wave beyond the first. Keeps late-run
## currency from trivialising the shop.
@export var price_per_wave: float = 0.12

@export_group("Reroll")
@export var reroll_base_cost: int = 5
## Compounds WITHIN one visit and resets when the shop reopens, so rerolling is
## a decision rather than a free scan of the whole pool.
@export var reroll_cost_growth: float = 1.6

@export_group("Selling")
## Fraction of the item's AUTHORED price, deliberately not of what it would cost
## today. Buy prices rise with the wave; a refund that tracked them would make
## buying early and selling late print money.
@export var sell_ratio: float = 0.5

@export_group("Tier odds")
## Weight of tiers 1-4 on wave one. Index 0 is tier 1.
@export var base_tier_weights: PackedFloat32Array = PackedFloat32Array([100.0, 24.0, 4.0, 0.0])
## How much each tier's weight moves per wave. Negative for tier 1, positive for
## the rest, so the shop drifts from junk towards the good stuff on its own
## instead of needing a table per wave.
@export var tier_weight_per_wave: PackedFloat32Array = PackedFloat32Array([-3.0, 1.0, 1.2, 0.9])

## Weights for this wave, floored at zero so a declining tier drops out rather
## than going negative and inverting the pick.
func tier_weights_for(wave_number: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var waves_in := float(maxi(1, wave_number) - 1)

	for index in 4:
		var base := base_tier_weights[index] if index < base_tier_weights.size() else 0.0
		var slope := tier_weight_per_wave[index] if index < tier_weight_per_wave.size() else 0.0
		result.append(maxf(0.0, base + slope * waves_in))

	return result

func price_for(item: ItemData, wave_number: int) -> int:
	if item == null:
		return 0
	var scale := 1.0 + price_per_wave * float(maxi(1, wave_number) - 1)
	return maxi(0, roundi(float(item.base_price) * scale))

func sell_price_for(item: ItemData) -> int:
	return maxi(0, floori(float(item.base_price) * sell_ratio)) if item != null else 0
