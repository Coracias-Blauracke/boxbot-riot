class_name PriceEvent
extends EventPayload

## A price is not a property of the item - it is the result of the
## CALCULATE_PRICE pipeline evaluated per buyer. That lets one co-op player pay
## with gold while another pays with max HP, with no special case in the shop.

var buyer: EntityModel = null
var item: Resource = null

var base_price: int = 0
var price: int = 0

## What is being spent. When `uses_stat_payment` is set, the shop takes the icon
## and format from that stat's StatMetadata instead of the gold icon.
var pay_with_stat: StatTypes.Stat = StatTypes.Stat.MAX_HP
var uses_stat_payment: bool = false
