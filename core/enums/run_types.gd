class_name RunTypes

## Rules of a single run, as opposed to rules of the world (WorldTypes).
##
## Same convention as every other enum here: only APPEND new values. These are
## serialized as bare integers the moment a challenge is authored as a .tres.

## What happens to a player who runs out of health.
##
## This is a knob rather than a constant because a challenge mode is exactly
## this switch flipped - not a second copy of the wave loop. Everything else
## about a run stays identical.
enum DeathRule {
	## Down for the rest of the wave, back up when the shop opens at
	## `revive_hp_fraction` of max HP. The run is lost only when every player is
	## down at the same time. The forgiving default: on a shared couch, benching
	## somebody for fifteen waves is worse than the difficulty it buys.
	REVIVE_NEXT_WAVE,
	## Down for good. Survivors keep their own currency and their own shop and
	## play on; the run ends with the last of them.
	PERMANENT,
	## One death ends the run for everybody.
	SHARED_FATE,
}

## How a run finished, or that it has not.
##
## Deliberately not a bool: "did the run end" and "was it won" are two different
## questions, and the HUD needs both to say anything useful.
enum Outcome {
	UNDECIDED,
	VICTORY,
	DEFEAT,
}
