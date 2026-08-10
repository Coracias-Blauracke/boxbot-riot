class_name PriceEvent
extends EventPayload

## A price is not a property of the item - it is the result of the
## CALCULATE_PRICE pipeline evaluated per buyer. That lets one co-op player pay
## with currency while another pays with max HP, with no special case in the shop.

var buyer: EntityModel = null

## What is being priced. Named `entry` rather than `item` because a weapon goes
## through this pipeline identically, and a field called `item` holding a weapon
## is the kind of small lie that later reads as a bug.
var entry: ShopEntryData = null

var base_price: int = 0
var price: int = 0

## True when what is being priced is a REROLL rather than a purchase, which is
## the one thing on the shop screen that has no `entry`. Named rather than left
## implicit in a null entry: "everything costs less" has to be able to mean the
## reroll too, and an effect deciding that from a null field is an effect
## guessing.
var is_reroll: bool = false

## What is being spent. When `uses_stat_payment` is set, the shop takes the icon
## and format from that stat's StatMetadata instead of the currency icon.
var pay_with_stat: StatTypes.Stat = StatTypes.Stat.MAX_HP
var uses_stat_payment: bool = false
