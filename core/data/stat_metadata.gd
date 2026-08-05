class_name StatMetadata
extends Resource

## Describes ONE stat for UI purposes.
##
## The dense stat dictionary (every entity carries the full set) makes this
## necessary, so that the player-facing list does not show MAP_SIZE next to
## damage.
##
## Side benefit that falls out for free: a shop charging a stat instead of currency
## takes its `icon` and `format` from here - no special case anywhere.

enum Format {
	FLAT,      ## 25
	PERCENT,   ## 25%
	INTEGER,   ## 25 (no fractional part, e.g. weapon slots)
}

@export var stat: StatTypes.Stat
@export var display_key: String = ""

## Shown when the player rests on this row in the stat sheet. A translation key
## like display_key, not prose - `tr()` returns the key unchanged while no
## translation is loaded, so the sheet is readable today and localises later
## without touching a single content file.
@export var description_key: String = ""

@export var icon: Texture2D
@export var format: Format = Format.FLAT

@export_group("UI behaviour")
@export var visible_in_ui: bool = true
@export var higher_is_better: bool = true
@export var sort_order: int = 0

func format_value(value: float) -> String:
	match format:
		Format.PERCENT:
			return "%d%%" % roundi(value * 100.0)
		Format.INTEGER:
			return str(roundi(value))
		_:
			# One decimal, but never a bare ".0" - "100" reads better than
			# "100.0" in a list of thirty stats, while a regen of 1.5 still
			# needs its decimal.
			return ("%.1f" % value).trim_suffix(".0")

## Renders a MODIFIER, which is not the same thing as rendering a value.
##
## A PERCENT modifier of 0.5 is "+50%" whatever the stat's own format says,
## because the modifier is a proportion rather than a quantity of the stat. BASE
## and FLAT are in the stat's own unit and go through format_value(), so +0.08
## to a percent-formatted stat like CRIT_CHANCE correctly reads "+8%". MULT
## composes as a separate factor and reads as one.
func format_modifier(modifier_type: StatTypes.Modifier, value: float) -> String:
	match modifier_type:
		StatTypes.Modifier.PERCENT:
			return "%+d%%" % roundi(value * 100.0)
		StatTypes.Modifier.MULT:
			return "x%.2f" % value
		_:
			return ("+" if value >= 0.0 else "-") + format_value(absf(value))

## Whether this modifier helps the holder. Deliberately not "is it positive":
## less spread and less recoil are improvements, which is the entire reason
## higher_is_better exists.
func is_improvement(value: float) -> bool:
	if is_zero_approx(value):
		return true
	return (value > 0.0) == higher_is_better
