class_name ShopEntryData
extends Resource

## Anything a shop slot can hold.
##
## A weapon and an item are the SAME transaction from every side that matters:
## both are rolled by tier, priced through CALCULATE_PRICE per buyer, paid for
## with currency or with a stat, listed in the owned strip and sold back. The
## only thing that genuinely differs is what happens at the instant of
## acquisition - an item pushes modifiers into StatsManager, a weapon takes a
## slot and appears in the wielder's hands. That one difference is therefore the
## only thing subclasses override.
##
## The alternative was a `kind` enum and a branch at every one of those sites.
## The cost of that is a branch per KIND per SITE, for ever, and it is the sites
## that get expensive at a hundred weapons rather than the content.
##
## `modifiers()` and `effects()` exist because the two shapes were ALREADY
## identical under different names - ItemData calls them static_stats and
## dynamic_effects, EntityData calls them base_stats and innate_effects - and
## ShopPanel was already flattening that by hand to put the character into the
## owned strip. Naming it here means the detail block, the owned strip and the
## offer row stop knowing which kind of thing they are drawing at all.

## Translation key, not display text.
@export var display_key: String = ""
@export var icon: Texture2D

## Drives shop rolls and effects such as "gain +X for every tier 4 item you
## own". Tier decides how OFTEN a thing is offered, never whether it is good.
@export_range(1, 4) var tier: int = 1

## What the shop asks on wave one, before scaling and before any effect.
##
## Authored rather than derived from the tier: a tier 3 thing that suits one
## build should be cheap, and a tier 1 thing everybody wants should not be.
##
## Never the final figure - that comes out of the CALCULATE_PRICE pipeline, per
## buyer, which is what lets one co-op player pay currency and another a stat.
@export var base_price: int = 10

## The stat lines this thing contributes, whatever the subclass calls them.
func modifiers() -> Array[StatModifier]:
	var none: Array[StatModifier] = []
	return none

## The behaviours this thing contributes, whatever the subclass calls them.
func effects() -> Array[DynamicEffect]:
	var none: Array[DynamicEffect] = []
	return none

## Derived lines the detail block shows that are neither a modifier nor an
## effect. A weapon's scaling is the first: it is not a stat line, it changes
## how every stat line the buyer already owns is worth, and a mechanic the
## player cannot see reads as a bug - buy +50% ranged, watch nothing happen.
##
## Strings rather than structured data, and they carry translation KEYS, because
## `tr()` returns the key unchanged until a translation is loaded, which is
## exactly what the stat sheet already shows on screen today.
func detail_notes() -> PackedStringArray:
	return PackedStringArray()

# --- acquisition -----------------------------------------------------------
#
# `host` is untyped for the same reason DynamicEffect.execute takes a Variant:
# typing it as EntityModel closes a cyclic dependency between core/data and
# core/models that the GDScript parser handles badly. In practice it is always
# an EntityModel.

## Whether this buyer may take one more.
##
## Defaults to NO. A resource that has never said how it is granted must not be
## silently purchasable - the money would leave and nothing would arrive, and
## the shop is the last place that should fail quietly.
func can_be_acquired_by(_host: Variant) -> bool:
	return false

## Whether it can go back. False for a character: the owned strip carries one,
## and "you cannot sell yourself" falls out of this rather than out of a branch
## in the renderer.
func can_be_sold() -> bool:
	return false

func owned_quantity(_host: Variant) -> int:
	return 0

func acquire(_host: Variant) -> void:
	push_error("ShopEntryData.acquire is not implemented for '%s'" % display_key)

func release(_host: Variant) -> void:
	push_error("ShopEntryData.release is not implemented for '%s'" % display_key)
