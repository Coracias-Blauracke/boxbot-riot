class_name ShopManager
extends RefCounted

## ONE PLAYER'S shop.
##
## Per player rather than per run, and that is not a detail bolted on for co-op.
## The whole stack was built for it: RunRandom derives an independent
## sub-stream per player index so the order in which four people hit reroll
## cannot shift what the others are offered (run_test has asserted that since
## before a shop existed), currency is a per-entity counter, prices come out of
## a pipeline evaluated per BUYER, and ItemsManager takes `host` as an argument
## precisely so two player models can never trigger each other's effects. This
## is where all of that finally becomes four shops.
##
## Keeps NO reference to its owner - `host` arrives as a call argument, like
## every other manager here. RefCounted has no cycle collector.

signal offers_changed
signal ready_changed(ready: bool)

## Source recorded for stat payments, so StatsManager can tell them apart from
## item bonuses. Shared across purchases on purpose: "refund everything you paid
## in health" is then one remove_all_from_source call.
const PAYMENT_SOURCE := &"shop_payment"

var data: ShopData = null

## Which RNG sub-stream this shop draws from. MUST be unique per player, or two
## shops offer the same items in the same order.
var player_index: int = 0

var offers: Array[ShopOffer] = []
var wave_number: int = 0
var rerolls_used: int = 0
var is_ready: bool = false

## What the NEXT reroll actually costs this buyer, and in what. Three plain
## fields rather than a stored PriceEvent, exactly as ShopOffer keeps them: the
## screen reads this every frame, and re-running the pipeline sixty times a
## second to draw one number would make every price effect a hot path.
##
## Refreshed whenever anything that feeds it can have moved - the shop opening,
## a reroll, a purchase that may have granted a discount.
var reroll_price: int = 0
var reroll_pay_with_stat: StatTypes.Stat = StatTypes.Stat.MAX_HP
var reroll_uses_stat_payment: bool = false

# --- opening and closing ---------------------------------------------------

func open(host: EntityModel, p_wave_number: int, rng: RunRandom) -> void:
	wave_number = p_wave_number
	rerolls_used = 0
	set_ready(false)
	_roll(host, rng)

func close() -> void:
	offers.clear()
	set_ready(false)
	offers_changed.emit()

func set_ready(value: bool) -> void:
	if is_ready == value:
		return
	is_ready = value
	ready_changed.emit(is_ready)

# --- pricing ---------------------------------------------------------------

## Runs CALCULATE_PRICE and hands back the whole event rather than an int,
## because the pipeline can also decide this buyer pays with a STAT and the
## caller has to know which.
func quote(host: EntityModel, entry: ShopEntryData) -> PriceEvent:
	return _quote(host, entry, data.price_for(entry, wave_number) if data != null else 0, false)

## The reroll, through the SAME pipeline a purchase goes through. It used to be
## the one price on the screen decided by arithmetic alone, which meant a buyer
## who pays for everything in blood still paid money to reroll - a hole that
## only content could reveal, and did.
func quote_reroll(host: EntityModel) -> PriceEvent:
	return _quote(host, null, reroll_cost(), true)

func _quote(
	host: EntityModel, entry: ShopEntryData, base: int, is_reroll: bool
) -> PriceEvent:
	var event := PriceEvent.new()
	event.buyer = host
	event.entry = entry
	event.is_reroll = is_reroll
	event.base_price = base
	event.price = base

	host.pipeline(Hooks.Hook.CALCULATE_PRICE, event)
	event.price = maxi(0, event.price)
	return event

## Compounds WITHIN a visit and resets when the shop reopens, so rerolling is a
## decision rather than a free scan of the entire pool.
##
## The AUTHORED cost, before any effect has had its say - what quote_reroll
## starts from. What the player actually pays is `reroll_price`.
func reroll_cost() -> int:
	if data == null:
		return 0
	return maxi(0, roundi(
		float(data.reroll_base_cost) * pow(data.reroll_cost_growth, float(rerolls_used))
	))

# --- transactions ----------------------------------------------------------

func buy(host: EntityModel, index: int) -> bool:
	if index < 0 or index >= offers.size():
		return false

	var offer := offers[index]
	if offer.sold or offer.entry == null:
		return false

	# Asked of the ENTRY rather than decided here. A weapon refuses when the rack
	# is full; an item never refuses. ShopManager stays as ignorant of
	# WEAPON_SLOTS as it already is of SHOP_SLOTS, which is what keeps "this
	# curse costs you a slot" an ordinary modifier.
	if not offer.entry.can_be_acquired_by(host):
		return false

	# Re-quoted at the moment of purchase rather than trusting the number on
	# screen. An item bought two slots ago can have changed what this one costs,
	# and a displayed price is a view, not a contract.
	var event := quote(host, offer.entry)
	if not _can_pay(host, event):
		return false

	_pay(host, event)
	offer.entry.acquire(host)
	host.counters.add(_purchase_counter(offer.entry))

	offer.sold = true
	offer.price = event.price
	offer.pay_with_stat = event.pay_with_stat
	offer.uses_stat_payment = event.uses_stat_payment

	host.notify(Hooks.Hook.ON_ITEM_BOUGHT, event)
	# A purchase can grant the very effect that prices a reroll, so the quote is
	# stale the instant one lands.
	_refresh_reroll_quote(host)
	offers_changed.emit()
	return true

## Which tally a purchase lands in.
##
## Counters are kept apart here where the HOOKS deliberately are not, and the
## difference is real. A hook hands the entry over, so an effect can look at
## what was bought and decide; a counter is a NUMBER that effects do arithmetic
## on, and "for every 5 items bought" cannot un-mix a weapon somebody folded
## into the same tally.
func _purchase_counter(entry: ShopEntryData) -> CounterTypes.Counter:
	return (
		CounterTypes.Counter.WEAPONS_BOUGHT if entry is WeaponData
		else CounterTypes.Counter.ITEMS_BOUGHT
	)

func sell(host: EntityModel, entry: ShopEntryData) -> bool:
	if entry == null or data == null or not entry.can_be_sold():
		return false
	if entry.owned_quantity(host) <= 0:
		return false

	var refund := data.sell_price_for(entry)
	entry.release(host)

	# Deliberately NOT add_currency(): that also credits CURRENCY_EARNED, and a
	# buy-then-sell loop would then farm every "for each 500 earned" effect for
	# the price of the spread. A refund is money coming back, not money earned.
	host.counters.add(CounterTypes.Counter.CURRENCY, refund)

	var event := PriceEvent.new()
	event.buyer = host
	event.entry = entry
	event.base_price = entry.base_price
	event.price = refund
	host.notify(Hooks.Hook.ON_ITEM_SOLD, event)

	# Selling can take away the very effect that prices a reroll, exactly as
	# buying can grant one. Missing this half leaves the discount on screen
	# after the item that granted it is gone.
	_refresh_reroll_quote(host)
	return true

func reroll(host: EntityModel, rng: RunRandom) -> bool:
	# Re-quoted at the moment it is paid for rather than trusting the number on
	# screen, for the same reason a purchase is: a displayed price is a view.
	var event := quote_reroll(host)
	if not _can_pay(host, event):
		return false

	_pay(host, event)
	rerolls_used += 1
	host.counters.add(CounterTypes.Counter.REROLLS_USED)
	_roll(host, rng)
	host.notify(Hooks.Hook.ON_REROLL, event)
	return true

func _refresh_reroll_quote(host: EntityModel) -> void:
	var event := quote_reroll(host)
	reroll_price = event.price
	reroll_pay_with_stat = event.pay_with_stat
	reroll_uses_stat_payment = event.uses_stat_payment

# --- payment ---------------------------------------------------------------
#
# Paying with a stat is a first-class path, not a special case. PriceEvent
# carries the choice out of the pipeline and both routes land here.
#
# What a point of a stat is WORTH is deliberately not decided here. The effect
# that switches a buyer onto stat payment also rewrites `price`, because only it
# knows the exchange rate it intends - a character who pays in blood and one who
# pays in max HP want completely different numbers.

func _can_pay(host: EntityModel, event: PriceEvent) -> bool:
	if not event.uses_stat_payment:
		return host.can_afford(event.price)

	# Must leave something behind. Paying a stat down to its floor lets a
	# purchase kill the buyer, or divides by zero further along the chain.
	var available := host.stats.get_stat(event.pay_with_stat)
	var floor_value: float = StatTypes.FLOORS.get(event.pay_with_stat, 0.0)
	return available - float(event.price) > floor_value

func _pay(host: EntityModel, event: PriceEvent) -> void:
	if not event.uses_stat_payment:
		host.add_currency(-event.price)
		return

	host.stats.add_modifier(
		event.pay_with_stat, StatTypes.Modifier.FLAT, -float(event.price), PAYMENT_SOURCE
	)

# --- rolling ---------------------------------------------------------------

func _roll(host: EntityModel, rng: RunRandom) -> void:
	offers.clear()
	if data == null:
		offers_changed.emit()
		return

	var event := ShopRollEvent.new()
	event.wave_number = wave_number
	event.offer_count = _slots_for(host)
	event.tier_weights = data.tier_weights_for(wave_number)
	# A COPY, items and weapons together. An effect that filters the pool must
	# not edit the authored ShopData - Godot caches .tres globally, so the edit
	# would leak into every other player's shop and every later run in the same
	# session.
	event.candidates = data.all_candidates()

	host.pipeline(Hooks.Hook.ROLL_SHOP_ITEMS, event)

	var taken: Array[ShopEntryData] = []
	for slot in maxi(0, event.offer_count):
		# Rolled PER SLOT, from an authored chance rather than from how many of
		# each kind exist. Authoring thirty weapons must not silently make items
		# rarer - the same reason tiers are weighted rather than items.
		var want_weapon := rng.chance(
			RunRandom.Stream.SHOP, data.weapon_offer_chance, player_index
		)
		var entry := _draw(event, rng, taken, want_weapon)
		if entry == null:
			continue
		taken.append(entry)

		var offer := ShopOffer.new()
		offer.entry = entry
		var quoted := quote(host, entry)
		offer.price = quoted.price
		offer.pay_with_stat = quoted.pay_with_stat
		offer.uses_stat_payment = quoted.uses_stat_payment
		offers.append(offer)

	# Here rather than in open(): every path that changes what a reroll costs -
	# opening the shop and rerolling - goes through this function.
	_refresh_reroll_quote(host)
	offers_changed.emit()

## How many slots this buyer sees.
##
## Read off the SHOP_SLOTS stat rather than straight off ShopData, so a
## character can start with one slot or eight and an item can grant another,
## with no branch here - the same trick WEAPON_SLOTS already uses. A buyer with
## nothing to say reports 0 and the authored default stands, which is what an
## entity built without CharacterData does.
func _slots_for(host: EntityModel) -> int:
	var from_stat := maxi(0, roundi(host.stats.get_stat(StatTypes.Stat.SHOP_SLOTS)))
	return from_stat if from_stat > 0 else data.offer_count

## Tier first, then uniformly within it.
##
## Weighting every ITEM by its tier's weight instead would make a tier holding
## twenty items twenty times as likely as a tier holding one - the odds would
## then be decided by how much content happened to be authored rather than by
## the numbers on ShopData.
## The kind asked for, or the other kind rather than an empty slot.
##
## The fallback matters more than it looks: a run with no weapons authored yet,
## a pool an effect has filtered down to items, or a weapon list exhausted by
## the no-duplicates rule would all otherwise hand back short shops with holes
## in them. A slot is filled with something or the shop is lying about its size.
func _draw(
	event: ShopRollEvent, rng: RunRandom, taken: Array[ShopEntryData], want_weapon: bool
) -> ShopEntryData:
	var picked := _draw_of_kind(event, rng, taken, want_weapon)
	return picked if picked != null else _draw_of_kind(event, rng, taken, not want_weapon)

func _draw_of_kind(
	event: ShopRollEvent, rng: RunRandom, taken: Array[ShopEntryData], want_weapon: bool
) -> ShopEntryData:
	# Two passes: distinct items first, then repeats if the pool cannot fill the
	# shop. A pool smaller than the shop is an authoring choice, not an error.
	#
	# ZERO WEIGHT IS EXCLUDED FROM BOTH. It is a stronger statement than "no
	# duplicates" - it means this tier does not exist yet at this wave. Letting
	# the dedupe pass fall through to it put a tier 4 item on wave 1 the moment
	# every other item had already been drawn, which is exactly the thing the
	# weight curve exists to prevent.
	var by_tier: Dictionary = {}
	var skip_taken := not data.allow_duplicate_offers

	for attempt in 2:
		for entry in event.candidates:
			if entry == null or (entry is WeaponData) != want_weapon:
				continue
			if event.weight_for_tier(entry.tier) <= 0.0:
				continue
			if skip_taken and taken.has(entry):
				continue
			if not by_tier.has(entry.tier):
				by_tier[entry.tier] = []
			(by_tier[entry.tier] as Array).append(entry)

		if not by_tier.is_empty() or not skip_taken:
			break
		skip_taken = false

	if by_tier.is_empty():
		return null

	var tiers: Array = []
	var weights := PackedFloat32Array()
	for tier in by_tier:
		tiers.append(tier)
		weights.append(event.weight_for_tier(tier))

	# No := here: a Dictionary lookup and weighted_pick both return Variant, and
	# inferring from one is a parse error that skips the whole suite.
	var picked = rng.weighted_pick(RunRandom.Stream.SHOP, tiers, weights, player_index)
	if picked == null:
		return null

	var options: Array = by_tier[picked]
	return rng.pick(RunRandom.Stream.SHOP, options, player_index) as ShopEntryData
