@abstract
class_name FiringPattern
extends Resource

## WHEN a shot happens. One of the four independent axes a weapon is built from:
## firing (when) x delivery (what) x spread (how many, arranged how) x targeting
## (at whom). A minigun differs from a pistol on this axis alone.
##
## Heat is deliberately NOT a pattern. It is an orthogonal layer on WeaponModel
## available to every weapon, because any weapon should be able to overheat.

## Hard ceiling on rate of fire, whatever the stats say.
##
## Without it, stacked attack speed drives the interval towards zero and a
## weapon fires once per frame - 60/s per weapon, times six weapons, times eight
## pellets. This is a correctness bound, not a performance tweak: the stat is
## unbounded above by design.
const MIN_INTERVAL := 0.04

## Seconds between shots at ATTACK_SPEED 1.0. This is the weapon's OWN rate;
## ATTACK_SPEED is the multiplier items and characters apply on top.
@export var base_interval: float = 0.5

## How many shots to emit this frame. Zero most frames; more than one only if a
## frame was long enough to cover several intervals.
@abstract func advance(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> int

func interval_for(weapon: WeaponModel) -> float:
	var scaled := base_interval / maxf(0.05, weapon.combined_stat(StatTypes.Stat.ATTACK_SPEED))
	return maxf(MIN_INTERVAL, scaled)

## Ticks the cooldown down, but never below zero.
##
## Letting it run negative banks up "debt": a weapon idle for ten seconds
## reaches -10, and the moment a target appears every `cooldown += interval`
## still leaves it negative, so it fires every frame for dozens of frames. On a
## melee weapon each of those restarted the swing on top of the last one, which
## looked like the first attack being cancelled mid-windup.
func tick_cooldown(weapon: WeaponModel, delta: float, wants_to_fire: bool) -> void:
	weapon.cooldown -= delta
	if not wants_to_fire:
		weapon.cooldown = maxf(weapon.cooldown, 0.0)
