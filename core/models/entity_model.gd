class_name EntityModel
extends RefCounted

## The ONE model for everything that exists in the world: the player, enemies,
## bosses, weapons, turrets, destructible obstacles, and the map and run models
## themselves.
##
## There is deliberately no PlayerModel or EnemyModel subclass. Once currency moved
## into the counters, nothing distinguished them but the way they are driven -
## input versus AI - and that is a concern of the scene layer, not of the model.
##
## Pure logic - RefCounted, zero SceneTree dependencies. That is what allows the
## whole game to be run and tested headless, without the editor.

signal died
signal revived
signal hp_changed(current: float, maximum: float)

## An area attack this entity set off, once its damage has landed.
##
## The view's ONE hook for every explosion in the game, and the mirror of
## world_position: the view writes where things are, the model says what happened
## there. Nothing in core/ listens, and core/ works identically when nothing
## does - which is what keeps a headless test and a running game the same code.
signal blast_resolved(event: BlastEvent)

var stats: StatsManager
var counters: CounterManager
var effects: EffectDispatcher
var statuses: StatusManager

var current_hp: float = 0.0
var is_alive: bool = true

## Where this entity is, written once per frame by its Actor.
##
## A Vector2 rather than a node reference, which is what keeps core/ Node-free
## while still letting it answer "what is within 120 units of here" - the same
## trick SpawnContext uses. core/ never writes this; it is a read-only fact
## handed down from the view.
var world_position: Vector2 = Vector2.ZERO

## Which side this entity is on, written by its Actor when it joins one.
##
## Read-only data handed down from the view, exactly like world_position and for
## exactly the same reason: it is what lets core/ answer "does this explosion
## hurt that one" without ever seeing a SceneTree group or a physics layer.
## core/ never writes it, and NEUTRAL is the honest default - a weapon model and
## the arena model are entities too, and neither is on anybody's side.
var faction: WorldTypes.Faction = WorldTypes.Faction.NEUTRAL

## Weak, set by WorldCensus.register. Lets an effect reaching outwards - fire
## spreading off a corpse - ask what is nearby at the moment it fires, when
## there is no payload to thread the answer through. Weak in both directions:
## the census holds weakrefs to entities and this holds one back, so neither can
## keep the other alive.
var _census_ref: WeakRef = null

func set_census(census: WorldCensus) -> void:
	_census_ref = weakref(census)

func get_census() -> WorldCensus:
	return _census_ref.get_ref() as WorldCensus if _census_ref != null else null

var _items: ItemsManager = null
var _rng: RunRandom = null
var _last_max_hp: float = 0.0

## Whoever last landed damage, for kill credit. Weak, because the killer may
## well die before its victim's death is processed.
var last_attacker: WeakRef = null

func get_last_attacker() -> EntityModel:
	return last_attacker.get_ref() as EntityModel if last_attacker != null else null

## Injected by RunModel.add_player so the whole run shares one seed. Falls back
## to a private generator when the entity is used standalone (tests, previews);
## assign explicitly when a deterministic roll matters.
var rng: RunRandom:
	get:
		if _rng == null:
			_rng = RunRandom.new()
		return _rng
	set(value):
		_rng = value

## Created on first use - a rock or a projectile never needs an inventory, and
## there may be hundreds of them on screen.
var items: ItemsManager:
	get:
		if _items == null:
			_items = ItemsManager.new()
		return _items

func _init(data: EntityData = null) -> void:
	stats = StatsManager.new()
	counters = CounterManager.new()
	effects = EffectDispatcher.new()
	statuses = StatusManager.new()
	stats.stat_changed.connect(_on_stat_changed)
	_seed_neutrals()

	if data != null:
		setup_from_data(data)

## Every multiplicative stat starts at the value that means "no effect".
##
## Without this a player's ATTACK_SPEED reads its FLOOR of 0.05, because nothing
## ever set a base for it - and the moment a weapon starts inheriting its
## wielder's attack speed, that 0.05 would slow every weapon in the game to a
## twentieth of its rate. A floor is not a default; this is the default.
##
## Seeded for EVERY entity rather than for players, because "everything carries
## the full stat set" is the decision the whole stat system rests on, and an
## enemy whose attack speed reads 0.05 is wrong in exactly the same way.
func _seed_neutrals() -> void:
	for stat in StatTypes.NEUTRALS:
		stats.add_modifier(
			stat, StatTypes.Modifier.BASE, StatTypes.NEUTRALS[stat], &"stat_neutral"
		)

func setup_from_data(data: EntityData) -> void:
	if data == null:
		return

	for modifier in data.base_stats:
		if modifier == null:
			continue
		stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, data)

	for effect in data.innate_effects:
		if effect == null:
			continue
		effects.register(EffectInstance.new(effect, data))

	# An enemy's rack is exactly what it was authored with. It never buys, sells
	# or merges, so its capacity is not a decision anybody makes at runtime -
	# but it still has to EXIST, because add_weapon asks WEAPON_SLOTS like it
	# does for everybody and would otherwise refuse a bug its own gun.
	if data is EnemyData:
		var armed := (data as EnemyData).weapons.size()
		if armed > 0:
			stats.add_modifier(
				StatTypes.Stat.WEAPON_SLOTS, StatTypes.Modifier.BASE, float(armed), data
			)

	# Asked of the DATA rather than derived here. The rule that a slot count is a
	# BASE modifier on its stat belongs beside the fields, or every screen that
	# wants to describe a chassis has to know it too - see slot_modifiers().
	if data is CharacterData:
		for modifier in (data as CharacterData).slot_modifiers():
			stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, data)

	current_hp = stats.get_stat(StatTypes.Stat.MAX_HP)
	_last_max_hp = current_hp
	hp_changed.emit(current_hp, _last_max_hp)

# --- events ----------------------------------------------------------------

## NOTIFICATION: "this happened". The payload is read-only.
func notify(hook: Hooks.Hook, event: EventPayload) -> void:
	effects.dispatch(self, hook, event)

## PIPELINE: "this is about to happen, change it". Effects mutate the payload
## one after another in `priority` order; the same object is returned carrying
## the result.
func pipeline(hook: Hooks.Hook, event: EventPayload) -> EventPayload:
	return effects.dispatch(self, hook, event)

# --- inventory -------------------------------------------------------------

func add_item(item: ItemData, quantity: int = 1) -> void:
	items.add_item(self, item, quantity)

func remove_item(item: ItemData, quantity: int = 1) -> void:
	items.remove_item(self, item, quantity)

# --- weapons ---------------------------------------------------------------
#
# WHAT IS CARRIED IS MODEL STATE; the nodes in the hands are a view of it. It
# used to be the other way round - WeaponMount owned the list and main.gd was
# the only caller - which is why a weapon could not be bought, sold, saved or
# even authored on a character: nothing outside the scene could see it.
#
# A plain array rather than a WeaponsManager. ItemsManager exists because items
# have real bookkeeping (per-copy modifier handles, effect instances, stacks);
# a weapon pushes nothing into the buyer's stats, because its base_stats belong
# to the WeaponModel the Weapon node builds. There is no state here to manage,
# and a manager holding one array would be a layer that only forwards.
#
# Duplicates are allowed on purpose: two of the same pistol is an ordinary
# loadout in this genre, and it falls out of a list rather than needing a count.

signal weapons_changed

var weapons: Array[WeaponData] = []

## The classes this entity's weapons count toward. Injected, because core/ may
## not load content - the same way rng and the census arrive.
var weapon_classes: WeaponClassSet = null:
	set(value):
		weapon_classes = value
		_refresh_class_bonuses()

## Capacity, read off the WEAPON_SLOTS stat so a character starting with eight,
## an item granting one and a curse taking one away are all ordinary modifiers.
func weapon_slots() -> int:
	return maxi(0, roundi(stats.get_stat(StatTypes.Stat.WEAPON_SLOTS)))

func has_free_weapon_slot() -> bool:
	return weapons.size() < weapon_slots()

func weapon_count(weapon: WeaponData) -> int:
	var total := 0
	for entry in weapons:
		if entry == weapon:
			total += 1
	return total

## Refuses rather than overflowing. The shop asks first through
## WeaponData.can_be_acquired_by, so a refusal here means a caller went around
## it - and silently carrying a ninth weapon in six slots is worse than nothing
## happening.
func add_weapon(weapon: WeaponData) -> bool:
	if weapon == null or not has_free_weapon_slot():
		return false
	weapons.append(weapon)
	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

# --- merging ---------------------------------------------------------------
#
# Duplicates are CARRIED, not folded together on sight. That is what makes the
# shop pose a question rather than run an algorithm: four copies of one weapon
# complete a class set, one merged copy is stronger, and six slots mean you
# cannot have both. A model that merged automatically on every duplicate would
# take the decision away and quietly make the class thresholds unreachable.

## Two copies of something that has a next tier.
func can_merge_weapon(weapon: WeaponData) -> bool:
	return weapon != null and weapon.upgrades_into != null and weapon_count(weapon) >= 2

## Two in, one out. Never blocked by capacity, because it frees a slot.
func merge_weapon(weapon: WeaponData) -> bool:
	if not can_merge_weapon(weapon):
		return false

	# Mutated directly rather than through remove_weapon twice: that would
	# recompute the class bonuses three times and emit three signals for one
	# player action, and the view would rebuild the rack mid-merge.
	weapons.erase(weapon)
	weapons.erase(weapon)
	weapons.append(weapon.upgrades_into)

	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

## Whether a purchase can land at all.
##
## A full rack normally refuses. It accepts one case: the weapon duplicates
## something already carried that HAS a next tier, so the purchase merges
## instead of overflowing and the count comes out unchanged. Without that
## exception merging becomes impossible exactly when it is most wanted - late,
## with six weak weapons and nowhere to put the seventh.
func can_take_weapon(weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	if has_free_weapon_slot():
		return true
	return weapon.upgrades_into != null and weapon_count(weapon) >= 1

## Adds, or merges when there is no room. The auto-merge is deliberately the
## ONLY automatic one - everywhere else merging is something the player asks
## for.
func take_weapon(weapon: WeaponData) -> bool:
	if not can_take_weapon(weapon):
		return false
	if has_free_weapon_slot():
		return add_weapon(weapon)

	# One carried copy is consumed and replaced by the next tier: the same
	# arithmetic as adding then merging, without ever holding seven weapons.
	weapons.erase(weapon)
	weapons.append(weapon.upgrades_into)
	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

## Removes ONE copy, not every copy. Selling one of two identical pistols must
## leave the other one in your hands.
func remove_weapon(weapon: WeaponData) -> bool:
	var index := weapons.find(weapon)
	if index < 0:
		return false
	weapons.remove_at(index)
	_refresh_class_bonuses()
	weapons_changed.emit()
	return true

## WeaponClassData -> Array[EffectInstance] currently granted by it. Held only
## so the recompute can strip what an effect of its own added.
var _class_effects: Dictionary = {}

## How many carried weapons name this tag. Two copies of one blade is two.
func weapon_tag_count(tag: StringName) -> int:
	var total := 0
	for weapon in weapons:
		if weapon != null and weapon.tags.has(tag):
			total += 1
	return total

## Strips every class bonus and reapplies from scratch.
##
## IDEMPOTENT ON PURPOSE, and for the reason EffectStatPerWorldCount is: the
## count goes DOWN as well as up. Selling the third blade has to take the third
## blade's bonus away, and an incremental version that adds on acquisition and
## subtracts on loss breaks permanently the first time an event is missed. A
## recompute cannot drift.
##
## The source is the class RESOURCE, so remove_all_from_source strips exactly
## that class's contribution and nothing else - the same trick that lets an
## expiring status remove only what it added when several overlap on one stat.
func _refresh_class_bonuses() -> void:
	if weapon_classes == null:
		return

	for entry in weapon_classes.classes:
		if entry == null:
			continue

		# Modifiers an EFFECT of this class added carry the INSTANCE as their
		# source, not the class, so they have to be stripped through the
		# instances before the instances themselves are dropped. Same order
		# ItemsManager uses when an item leaves.
		for instance in _class_effects.get(entry, []):
			stats.remove_all_from_source(instance)
		effects.unregister_source(entry)
		stats.remove_all_from_source(entry)

		var count := weapon_tag_count(entry.tag)
		for modifier in entry.modifiers_for(count):
			stats.add_modifier(modifier.stat, modifier.modifier_type, modifier.value, entry)

		var created: Array[EffectInstance] = []
		for effect in entry.effects_for(count):
			var instance := EffectInstance.new(effect, entry)
			effects.register(instance)
			created.append(instance)
		_class_effects[entry] = created

# --- currency --------------------------------------------------------------
#
# Currency is a counter, not a stat: accumulated state that must be saved and
# must never be touched by a percent modifier. CURRENCY is the spendable
# balance, CURRENCY_EARNED the lifetime tally that "every 500 earned" effects
# hang on. Nothing here names a theme, so it can be coins, crystals or scrap.

func get_currency() -> int:
	return counters.get_value(CounterTypes.Counter.CURRENCY)

## CURRENCY_GAIN is read HERE and nowhere else, because this is the one door
## currency comes through. A kill, a wave-end payout and an effect handing out
## money all arrive at this function, so none of them has to learn that the stat
## exists - and none of them can forget it either.
##
## It scales what is EARNED and never what is spent: the same call takes a
## NEGATIVE amount when the shop charges, and a "+30% currency" stat that also
## inflated prices would be a curse wearing a bonus's name. Selling never
## reaches this at all - ShopManager credits CURRENCY directly, because a refund
## is not earnings.
##
## The bonus lands in CURRENCY_EARNED too, deliberately. That tally is what
## "for every 500 earned" effects hang on, and crediting the pre-bonus figure
## there would hide the stat from precisely the effects that count earnings.
func add_currency(amount: int) -> void:
	if amount > 0:
		# Floored at -1.0 on the stat, so this can reach zero and never reverse.
		amount = roundi(float(amount) * (1.0 + stats.get_stat(StatTypes.Stat.CURRENCY_GAIN)))

	counters.add(CounterTypes.Counter.CURRENCY, amount)
	if amount > 0:
		counters.add(CounterTypes.Counter.CURRENCY_EARNED, amount)

func can_afford(amount: int) -> bool:
	return get_currency() >= amount

# --- statuses --------------------------------------------------------------

func apply_status(
	definition: StatusEffect, applier: EntityModel = null, stacks: int = 1,
	duration: float = -1.0, chance: float = -1.0
) -> ActiveStatus:
	return statuses.apply(self, definition, applier, stacks, duration, chance)

func tick_statuses(delta: float) -> void:
	statuses.tick(self, delta)

# --- area attacks ----------------------------------------------------------

## Sets off an area attack centred on `at`, and announces it.
##
## THE ONE DOOR for area damage, exactly as add_currency is the one door for
## money: a bug bursting, an item detonating a corpse and a grenade landing all
## arrive here, so none of them has to remember to tell the view and none of them
## can forget. The arithmetic belongs to the DATA - see BlastData.resolve - and
## this is only the entity's half: whose explosion it is, and saying so.
##
## Returns the event even when nothing was in range, because "it went off and
## caught nobody" is a real answer and the view still has a flash to draw.
func detonate(
	blast: BlastData,
	at: Vector2,
	weapon: WeaponModel = null,
	inherited: ShotSnapshot = null,
	power: float = 1.0
) -> BlastEvent:
	if blast == null:
		return null

	var event := blast.resolve(self, at, weapon, inherited, power)
	blast_resolved.emit(event)
	return event

# --- health and damage -----------------------------------------------------

func get_max_hp() -> float:
	return stats.get_stat(StatTypes.Stat.MAX_HP)

## The single entry point for damage. Runs the target-side pipeline, gives
## BEFORE_DEATH a chance to cancel a lethal blow, applies the result and then
## notifies both sides.
func apply_damage(event: DamageEvent) -> float:
	# A corpse takes no further hits. Every blow landing on something already
	# dead used to award another ENEMIES_KILLED and fire ON_KILL again, because
	# the credit below only checks `not is_alive`. That was unreachable while
	# everything was freed the instant it died; downed players now persist, so a
	# damage-over-time status on one would have farmed kill credit forever.
	if not is_alive:
		return 0.0

	event.target = self

	# Offence first with the target now known, then defence - the same two-phase
	# shape statuses use. The attacker gets to say "more damage to burning
	# things" before the victim gets to say "I resist fire".
	# Seeded BEFORE the pipeline so an effect can adjust either, and resolved
	# after it so the roll happens once, on the final numbers.
	event.dodge_chance = stats.get_stat(StatTypes.Stat.DODGE)
	event.armor = stats.get_stat(StatTypes.Stat.ARMOR)

	if event.source != null:
		event.source.pipeline(Hooks.Hook.ON_OUTGOING_DAMAGE, event)
	pipeline(Hooks.Hook.TAKE_DAMAGE, event)
	if event.cancelled:
		return 0.0

	if _rolls_a_dodge(event):
		event.dodged = true
		event.cancelled = true
		counters.add(CounterTypes.Counter.DODGES)
		notify(Hooks.Hook.ON_DAMAGE_TAKEN, event)
		return 0.0

	# Armor takes a share of WHAT IS LEFT, not of the original amount: an effect
	# that already absorbed a flat 10 has removed that damage, and charging
	# armor against it again would count the same hit twice.
	var remaining := event.final_amount()
	if remaining > 0.0 and event.armor > 0.0:
		event.absorbed += remaining * StatTypes.armor_reduction(event.armor)

	var final := event.final_amount()

	if final >= current_hp and is_alive:
		# Room for "survive one lethal hit per wave" style effects.
		var lethal := pipeline(Hooks.Hook.BEFORE_DEATH, event)
		if lethal.cancelled:
			return 0.0

	if final > 0.0:
		counters.add(CounterTypes.Counter.DAMAGE_TAKEN, roundi(final))
		if event.source != null:
			last_attacker = weakref(event.source)
		set_hp(current_hp - final)

	notify(Hooks.Hook.ON_DAMAGE_TAKEN, event)
	if event.source != null:
		event.source.counters.add(CounterTypes.Counter.DAMAGE_DEALT, roundi(final))
		event.source.notify(Hooks.Hook.ON_DAMAGE_DEALT, event)
		# After the notification, so an effect that adds damage on hit has
		# already had its say and the steal is taken from the real total.
		_apply_lifesteal(event, final)
		if not is_alive:
			event.source.counters.add(CounterTypes.Counter.ENEMIES_KILLED)
			event.source.notify(Hooks.Hook.ON_KILL, event)

	return final

## Seconds of regeneration owed. HP_REGEN is read as HP PER SECOND and paid out
## once a second rather than every frame: sixty heals a second would fire
## CALCULATE_HEAL and ON_HEAL sixty times for fractions of a point, so every
## "when you are healed" effect would go off constantly for nothing.
var _regen_owed: float = 0.0

## Called on the run's heartbeat. Healing goes through heal(), so regeneration
## is subject to CALCULATE_HEAL like every other heal - "healing is 50% less
## effective on you" has to reach it, and would not if this wrote current_hp.
func tick_regen(delta: float) -> void:
	if not is_alive:
		return

	var per_second := stats.get_stat(StatTypes.Stat.HP_REGEN)
	if per_second <= 0.0:
		# Not accumulated while the stat is zero, or losing a regen item would
		# pay out a second of healing it never earned.
		_regen_owed = 0.0
		return

	_regen_owed += delta
	if _regen_owed < 1.0:
		return
	_regen_owed -= 1.0
	heal(per_second, self)

## The attacker's share of what they just dealt.
##
## Read from the damage that ACTUALLY LANDED rather than what was intended, so a
## heavily armoured target heals the attacker less - which is the honest reading
## of "steal life from the damage you deal" and stops armor on the victim from
## inflating the attacker's healing.
##
## HITS only, like dodge and for the same reason: a bleed applied once would
## otherwise keep healing its applier for the rest of its duration, and every
## status would quietly become a healing item.
func _apply_lifesteal(event: DamageEvent, landed: float) -> void:
	if landed <= 0.0 or event.source == null or not event.is_hit():
		return
	var share := event.source.stats.get_stat(StatTypes.Stat.LIFESTEAL)
	if share > 0.0:
		event.source.heal(landed * share, event.source)

## DODGE is a chance to take NOTHING, so it belongs to hits alone - see
## DamageEvent.is_hit(). Rolled BEFORE armor is applied because avoiding a blow
## and softening one are different questions, and the other order would have
## armor reducing damage that was never going to land.
func _rolls_a_dodge(event: DamageEvent) -> bool:
	if event.dodge_chance <= 0.0 or not event.is_hit():
		return false
	return rng.chance(RunRandom.Stream.COMBAT, event.dodge_chance)

func set_hp(value: float) -> void:
	var maximum := get_max_hp()
	var clamped := clampf(value, 0.0, maximum)
	if is_equal_approx(clamped, current_hp):
		return
	current_hp = clamped
	hp_changed.emit(current_hp, maximum)
	if current_hp <= 0.0 and is_alive:
		is_alive = false
		notify(Hooks.Hook.ON_DEATH, EventPayload.new())
		died.emit()

## Brings a downed entity back on `fraction` of its max HP.
##
## Deliberately NOT heal(): healing a corpse must stay impossible, or lifesteal
## and regeneration would quietly undo death. Who may stand up again, and when,
## is a decision of the run - see RunTypes.DeathRule - and this is the only door
## it has.
func revive(fraction: float = 1.0) -> float:
	if is_alive:
		return 0.0

	is_alive = true
	set_hp(get_max_hp() * clampf(fraction, 0.01, 1.0))
	revived.emit()
	return current_hp

## Goes through CALCULATE_HEAL so effects can scale or block healing, then
## notifies ON_HEAL with what actually landed. Previously this called set_hp()
## directly and both hooks were unreachable.
func heal(amount: float, source: EntityModel = null) -> float:
	# Healing must never raise a corpse. set_hp() would happily push current_hp
	# back above zero while is_alive stayed false, leaving an entity that is
	# neither dead nor playable. Standing up goes through revive() only.
	if amount <= 0.0 or not is_alive:
		return 0.0

	var event := HealEvent.new()
	event.source = source
	event.target = self
	event.amount = amount

	pipeline(Hooks.Hook.CALCULATE_HEAL, event)
	if event.cancelled:
		return 0.0

	var before := current_hp
	set_hp(current_hp + event.amount)
	event.applied = current_hp - before

	if event.applied > 0.0:
		notify(Hooks.Hook.ON_HEAL, event)
		if source != null and source != self:
			source.notify(Hooks.Hook.ON_HEAL, event)

	return event.applied

## current_hp is STATE, so it does not recompute itself from the stats - a
## change of MAX_HP has to be reacted to explicitly. An increase tops up the
## same amount (a +50 max HP item heals for 50); a decrease only clamps.
func _on_stat_changed(stat: StatTypes.Stat) -> void:
	if stat != StatTypes.Stat.MAX_HP:
		return

	var new_max := get_max_hp()
	var delta := new_max - _last_max_hp
	_last_max_hp = new_max

	if delta > 0.0:
		current_hp += delta
	current_hp = clampf(current_hp, 0.0, new_max)
	hp_changed.emit(current_hp, new_max)
