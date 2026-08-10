class_name EffectPriceModifier
extends DynamicEffect

## GENERIC: "everything costs 20% less", "weapons cost double", "you pay for
## items in max HP instead of currency".
##
## The whole CALCULATE_PRICE family in one class. The pipeline, the stat payment
## and ShopManager's honouring of both existed before this and were driven by
## NOTHING - only two test doubles inside core_test.gd - so a finished mechanism
## had no way to reach a content file. That is the same failure the select
## screen was built to end, one layer down.
##
## It knows nothing about characters. It is an ordinary DynamicEffect, so the
## same file works in a character's innate_effects, in an item's
## dynamic_effects, on a weapon, or on a weapon class threshold, and none of
## those sites needs a line of code. It reads the event and nothing else: no
## RunModel, no shop, no node.

## What the price is MULTIPLIED by. 0.8 is "20% off", 2.0 is "twice as dear",
## 1.0 leaves it alone so an effect can switch the payment without touching the
## number.
##
## A share rather than a flat change, because a flat one cannot be authored
## once: -10 is a rounding error on a tier IV weapon and free on a tier I item.
@export var price_share: float = 1.0

## Which entries this applies to. A kind filter rather than a second class,
## since "weapons cost more" and "items cost less" are the same sentence with a
## different subject.
enum Applies {
	ANY,
	ITEMS,
	WEAPONS,
}

@export var applies_to: Applies = Applies.ANY

@export_group("Payment")
## Switches this buyer onto paying with a STAT instead of currency. The shop
## then spends whatever is named here and takes its icon and format from that
## stat's StatMetadata.
@export var uses_stat_payment: bool = false

@export var payment_stat: StatTypes.Stat = StatTypes.Stat.MAX_HP

## The EXCHANGE RATE, and it lives here rather than in the shop for the reason
## CLAUDE.md gives: a character paying in blood and one paying in max HP want
## completely different numbers, and only the effect that switched the payment
## on knows which it meant. Applied on top of price_share.
##
## 0.35 means a 40-price item costs 14 points of the stat.
@export var payment_rate: float = 1.0

func get_hooks() -> Array:
	return [Hooks.Hook.CALCULATE_PRICE]

func execute(_host: Variant, inst: EffectInstance, event: EventPayload) -> void:
	var price := event as PriceEvent
	if price == null or not _matches(price):
		return

	# Stacks multiply, so two copies of a 0.8 discount give 0.64 rather than 0.6.
	# A discount that composed additively would reach free at five copies and
	# then start paying the buyer, which the shop's own clamp would hide.
	price.price = roundi(float(price.price) * pow(price_share, float(inst.stacks)))

	if not uses_stat_payment:
		return

	price.uses_stat_payment = true
	price.pay_with_stat = payment_stat
	# Converted ONCE, whatever the stack count. Two copies of "pay in HP" is
	# still one payment, and compounding the rate would make a second copy a
	# discount on the thing it is supposed to be a cost for.
	price.price = maxi(1, roundi(float(price.price) * payment_rate))

## A REROLL has no entry, so only ANY covers it - and ANY must, or "you pay for
## everything in blood" would leave the one price on the screen that is still
## money. A kind filter is a statement about what is being BOUGHT, and a reroll
## is not one of the kinds.
func _matches(event: PriceEvent) -> bool:
	if event.is_reroll:
		return applies_to == Applies.ANY
	if event.entry == null:
		return false

	match applies_to:
		Applies.ITEMS:
			return not (event.entry is WeaponData)
		Applies.WEAPONS:
			return event.entry is WeaponData
		_:
			return true

func describe(inst: EffectInstance) -> String:
	var subject := "everything"
	match applies_to:
		Applies.ITEMS:
			subject = "items"
		Applies.WEAPONS:
			subject = "weapons"

	var lines: Array[String] = []
	var share := pow(price_share, float(inst.stacks))
	if not is_equal_approx(share, 1.0):
		lines.append("%s costs %d%% %s" % [
			subject, roundi(absf(1.0 - share) * 100.0), "less" if share < 1.0 else "more"
		])
	if uses_stat_payment:
		# The same key the stat sheet shows, translated here for the same reason
		# WeaponData.detail_notes() translates its own: a caller handed a whole
		# sentence can only translate all of it or none of it.
		lines.append("%s is paid for with %s" % [
			subject, tr("STAT_%s" % StatTypes.Stat.keys()[payment_stat])
		])

	return ", ".join(lines)
