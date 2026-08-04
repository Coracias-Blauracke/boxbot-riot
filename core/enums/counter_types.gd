class_name CounterTypes

## Counters are STATE, not stats. They live outside StatsManager because:
##  - they must be written to the save file (stats are rebuildable from items),
##  - no percent modifier may ever accidentally multiply them,
##  - they must never show up in the player-facing stat list.
##
## Same convention as StatTypes: only APPEND new values.

enum Counter {
	BULLETS_FIRED,
	MELEE_SWINGS,
	ENEMIES_KILLED,
	CRITS_LANDED,
	DAMAGE_DEALT,
	DAMAGE_TAKEN,
	STEPS_TAKEN,
	STATUS_APPLIED,
	ITEMS_BOUGHT,
	REROLLS_USED,
	WAVES_SURVIVED,
	DODGES,
	## Current balance - the only counter that legitimately goes DOWN.
	## Do not call crossings() on it; that helper assumes monotonic growth.
	GOLD,
	## Lifetime total earned, never decreases. This is the one to hang
	## "every 500 gold earned, gain X" effects on.
	GOLD_EARNED,
}

## When a counter resets.
## RUN    - persists for the whole run
## WAVE   - cleared at the start of every wave
## COMBAT - cleared on every entry into combat (e.g. after the shop phase)
enum Scope {
	RUN,
	WAVE,
	COMBAT,
}

const SCOPES: Dictionary = {
	Counter.BULLETS_FIRED: Scope.RUN,
	Counter.MELEE_SWINGS: Scope.RUN,
	Counter.ENEMIES_KILLED: Scope.RUN,
	Counter.CRITS_LANDED: Scope.RUN,
	Counter.DAMAGE_DEALT: Scope.RUN,
	Counter.DAMAGE_TAKEN: Scope.WAVE,
	Counter.STEPS_TAKEN: Scope.WAVE,
	Counter.STATUS_APPLIED: Scope.RUN,
	Counter.ITEMS_BOUGHT: Scope.RUN,
	Counter.REROLLS_USED: Scope.RUN,
	Counter.WAVES_SURVIVED: Scope.RUN,
	Counter.DODGES: Scope.WAVE,
	Counter.GOLD: Scope.RUN,
	Counter.GOLD_EARNED: Scope.RUN,
}
