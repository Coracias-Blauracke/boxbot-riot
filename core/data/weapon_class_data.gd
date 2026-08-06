class_name WeaponClassData
extends Resource

## ONE weapon class - blades, guns, whatever the list ends up naming - and what
## holding several of them is worth.
##
## Set bonuses are the main build engine in this genre: they are the reason a
## player passes over a stronger weapon to keep a matching one, which is the
## most interesting decision the shop ever offers. Making them authored data
## rather than code means a new class is a .tres and nothing else.
##
## A weapon carries TAGS, plural, and counts toward every class it names. A
## bayonet is a blade and a gun, and both counts go up.

## What a weapon has to list in its `tags` to count here.
@export var tag: StringName = &""

## Translation key, for the shop and the stat sheet.
@export var display_key: String = ""

## Thresholds, in any order. See applies_at() for why they are cumulative.
@export var tiers: Array[WeaponClassTier] = []

## Every tier whose requirement is met, not just the highest.
##
## CUMULATIVE is strictly the more expressible of the two rules: a class that
## wants one big bonus at four authors a single tier, while one that wants each
## weapon to feel like progress authors several. "Highest only" cannot express
## the second without repeating the earlier numbers in every later tier, which
## is the kind of duplication that drifts the moment somebody retunes one.
func modifiers_for(count: int) -> Array[StatModifier]:
	var granted: Array[StatModifier] = []
	for tier in tiers:
		if tier != null and count >= tier.required:
			for modifier in tier.modifiers:
				if modifier != null:
					granted.append(modifier)
	return granted

## Same rule for behaviours: every tier whose requirement is met contributes.
##
## Thresholds are AUTHORED INDIVIDUALLY and need not be contiguous. A class may
## grant something at every count from one to six, or nothing until six and then
## one large thing - both are just which tiers exist in this array.
func effects_for(count: int) -> Array[DynamicEffect]:
	var granted: Array[DynamicEffect] = []
	for tier in tiers:
		if tier != null and count >= tier.required:
			for effect in tier.effects:
				if effect != null:
					granted.append(effect)
	return granted

## The smallest requirement still ahead, or 0 when everything is unlocked. The
## shop shows it, because "2 of 4 BLADE" is what makes somebody buy the fourth.
func next_threshold(count: int) -> int:
	var next := 0
	for tier in tiers:
		if tier == null or count >= tier.required:
			continue
		if next == 0 or tier.required < next:
			next = tier.required
	return next
