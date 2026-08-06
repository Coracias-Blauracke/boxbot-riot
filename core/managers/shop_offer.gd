class_name ShopOffer
extends RefCounted

## One slot in one player's shop.
##
## Runtime state, so RefCounted rather than a Resource. Putting `sold` on the
## ItemData would be the classic version of the bug this codebase already
## documents: Godot caches .tres globally, so one player buying a thing would
## mark it sold in everybody else's shop and in every future run.

## An item or a weapon - the slot does not care which, and neither does anything
## that draws it. See ShopEntryData.
var entry: ShopEntryData = null

## What was quoted when the shop was rolled. The price is re-derived at the
## moment of purchase, because a stat bought two slots ago can have changed it -
## this is what to DISPLAY, not what to charge.
var price: int = 0

var sold: bool = false

## Set when the quote came out of the pipeline as a stat payment rather than
## currency, so the view can show a heart instead of a coin.
var pay_with_stat: StatTypes.Stat = StatTypes.Stat.MAX_HP
var uses_stat_payment: bool = false
