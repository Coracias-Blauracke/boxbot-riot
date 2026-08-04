class_name StatMetadata
extends Resource

## Describes ONE stat for UI purposes.
##
## The dense stat dictionary (every entity carries the full set) makes this
## necessary, so that the player-facing list does not show MAP_SIZE next to
## damage.
##
## Side benefit that falls out for free: a shop charging a stat instead of gold
## takes its `icon` and `format` from here - no special case anywhere.

enum Format {
	FLAT,      ## 25
	PERCENT,   ## 25%
	INTEGER,   ## 25 (no fractional part, e.g. weapon slots)
}

@export var stat: StatTypes.Stat
@export var display_key: String = ""
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
			return "%.1f" % value
