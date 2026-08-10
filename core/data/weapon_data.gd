class_name WeaponData
extends EntityData

## ONE weapon definition covering guns, melee, beams and summons. The four
## resources below are independent axes; a weapon is a point in that space
## rather than a class:
##
##   pistol   = Instant + Projectile + Single
##   shotgun  = Instant + Projectile + Cone(8)
##   minigun  = Windup  + Projectile + Cone(1)
##   laser    = Channel + Beam       + Single
##   sword    = Instant + MeleeSweep + -
##
## Combinations nobody planned for - a channelled shotgun, a spinning-up melee
## flurry - fall out for free, because the axes do not know about each other.

enum DeliveryKind {
	PROJECTILE,
	MELEE_SWEEP,
	BEAM,
	SUMMON,
}

@export_group("Axes")
@export var firing: FiringPattern
@export var spread: SpreadPattern
@export var targeting: TargetSelector
@export var delivery: DeliveryKind = DeliveryKind.PROJECTILE

@export_group("Delivery payload")
## Used when delivery is PROJECTILE.
@export var projectile: ProjectileData
@export var projectile_scene: PackedScene

## Used when delivery is MELEE_SWEEP. More than one entry makes a combo: each
## attack advances through the list, so "slash, slash, heavy thrust" is authored
## rather than coded. One entry simply repeats.
@export var melee_combo: Array[SwingPattern] = []

## Alternate left and right between attacks. Cheap, and it stops a repeated
## swing looking like a loop.
@export var alternate_swing_sides: bool = true

@export_group("Heat")
## 0 disables heat entirely, which is how most weapons will be configured.
## Capacity and dissipation are stats, so items can widen or vent them.
@export var heat_per_shot: float = 0.0

@export_group("Family")
## The next tier up, or null on the top tier.
##
## A CHAIN rather than a shared family id plus a tier number: the chain cannot
## disagree with itself. An id-and-tier scheme has to answer what happens when
## two weapons claim the same family at the same tier, or when a tier is missing
## from the middle, and both are states a validator has to invent rules for.
## Following a pointer has neither problem.
##
## Two carried copies of a weapon with an upgrade can be merged into one of the
## next tier, which frees a slot. Null here means "top of the chain": the weapon
## is still perfectly good, it simply cannot be merged any further.
@export var upgrades_into: WeaponData

@export_group("Classes")
## Which weapon classes this counts toward. PLURAL on purpose: a bayonet is a
## blade and a gun, and it should raise both counts rather than forcing a choice
## the fiction does not have.
##
## Tags are StringNames matched against WeaponClassData.tag. A tag naming no
## authored class is inert rather than an error, so a weapon can be tagged
## before its class exists - the validator warns about it.
@export var tags: Array[StringName] = []

@export_group("Scaling")
## Which of the WIELDER's stats feed this weapon's damage, and how much of each.
##
## EMPTY MEANS "all of my own damage type", which is what every weapon authored
## before this did implicitly. Listing anything replaces that default outright
## rather than adding to it: a weapon that wants full ranged damage AND a share
## of max HP lists both, because a list that silently keeps something you did
## not write is a list nobody can read.
##
## This is the balance lever for fast weapons. A flat damage bonus applies PER
## HIT, so its value scales with rate of fire; without a coefficient the fastest
## weapon in the game wins by more the longer a run goes on. It is also what
## makes a weapon that scales off MAX_HP or MOVEMENT_SPEED expressible with no
## code at all.
##
## Only STATS can appear here. "The lower your health, the harder you hit" reads
## current_hp, which is state rather than a stat, and belongs in a
## CALCULATE_DAMAGE effect where it can change between shots.
@export var damage_scaling: Array[StatScaling] = []

## How much of the wielder's OTHER combat stats reaches this weapon.
##
## Unlisted stats transfer in FULL. Before this existed they did not transfer at
## all - only damage did - which quietly made four authored items decorative.
##
## Note this is a different question from damage_scaling above: that one adds a
## number to one shot, this one changes a stat that firing intervals, spread,
## range and projectile speed are all read from.
@export var stat_inheritance: Array[StatScaling] = []

@export_group("Damage falloff")
## Distance in world units at which damage starts dropping, and where it bottoms
## out. A strong balance lever: it stops shotguns being good at every range.
@export var falloff_start: float = 0.0
@export var falloff_end: float = 0.0
@export_range(0.0, 1.0) var falloff_multiplier: float = 1.0

@export_group("Feel")
## Push applied to the wielder on firing. Almost always 0; a shotgun that shoves
## you backwards turns recoil into a movement option.
@export var recoil: float = 0.0

# --- acquisition -----------------------------------------------------------
#
# The one purchasable with a CAPACITY. That capacity is the WEAPON_SLOTS stat,
# so "this character carries eight" and "this item grants a slot" stay ordinary
# modifiers and neither ShopManager nor this file ever learns they exist - the
# same arrangement SHOP_SLOTS already has.
#
# A weapon's own base_stats belong to the WEAPON, not to the wielder: Weapon
# builds a WeaponModel from this resource. So acquiring one deliberately pushes
# nothing into the buyer's StatsManager, which is exactly where it differs from
# an item.

## What this weapon does with its holder's stats, in words.
##
## Derived, never authored: the numbers below ARE the tables, so the text cannot
## drift from them. Without it the scaling is invisible and reads as a bug the
## first time somebody buys a damage item and watches nothing happen.
func detail_notes() -> PackedStringArray:
	var notes := PackedStringArray()

	# Classes first: which set a weapon belongs to is the reason to buy it over
	# a stronger one, so it should not be the last line the eye reaches.
	# tr() is called HERE because the note is a SENTENCE with a name inside it,
	# and a caller can only translate the whole string or none of it. Building
	# the class key from the tag is the same trick _stat_key uses on the enum:
	# core/ cannot reach the authored WeaponClassSet, and two spellings of one
	# name is how a screen ends up disagreeing with itself.
	#
	# Note this does not break the layer rule - tr() is an Object method reading
	# the engine's translation server, not a Node and not a project autoload.
	for tag in tags:
		notes.append("class %s" % tr("CLASS_%s" % String(tag).to_upper()))

	for scaling in damage_scaling:
		if scaling != null:
			notes.append("scales %d%% with %s" % [
				roundi(scaling.coefficient * 100.0), tr(_stat_key(scaling.stat))
			])

	for scaling in stat_inheritance:
		if scaling != null:
			notes.append("inherits %d%% of %s" % [
				roundi(scaling.coefficient * 100.0), tr(_stat_key(scaling.stat))
			])

	return notes

## The same key StatMetadata authors and the stat sheet already shows, built
## from the enum rather than looked up - core/ has no access to the sheet, and
## two spellings of one name is how a screen ends up disagreeing with itself.
static func _stat_key(stat: StatTypes.Stat) -> String:
	return "STAT_%s" % StatTypes.Stat.keys()[stat]

## A free slot, or a full rack this purchase would merge into. See
## EntityModel.can_take_weapon for why the second case has to exist.
func can_be_acquired_by(host: Variant) -> bool:
	return (host as EntityModel).can_take_weapon(self)

func can_be_sold() -> bool:
	return true

func owned_quantity(host: Variant) -> int:
	return (host as EntityModel).weapon_count(self)

func acquire(host: Variant) -> void:
	(host as EntityModel).take_weapon(self)

func release(host: Variant) -> void:
	(host as EntityModel).remove_weapon(self)
