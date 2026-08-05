class_name PlayerPalette

## One accent colour per player, shared by the character on the arena floor and
## by that player's HUD panel.
##
## It has to be ONE table, not two: a panel whose colour does not match the blob
## it describes is worse than no colour at all, and on a shared screen "which
## one am I" is the question the HUD exists to answer first.
##
## Indexed by player index, so it only ever grows if the player cap does.
const COLORS: Array[Color] = [
	Color(0.35, 0.78, 1.00),  ## P1 - blue
	Color(1.00, 0.68, 0.26),  ## P2 - amber
	Color(0.52, 0.90, 0.45),  ## P3 - green
	Color(0.85, 0.55, 1.00),  ## P4 - violet
]

static func color_for(player_index: int) -> Color:
	return COLORS[player_index % COLORS.size()]
