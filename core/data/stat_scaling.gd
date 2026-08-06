class_name StatScaling
extends Resource

## "This much of that stat."
##
## Two different questions on a weapon use the same pair, which is why this is
## one class rather than two:
##
##   damage_scaling    - how much of the wielder's stat is ADDED TO DAMAGE.
##                       (RANGED_DAMAGE, 0.5) is Brotato's half-scaling pistol;
##                       (MAX_HP, 0.1) is a weapon that grows with your health;
##                       (MOVEMENT_SPEED, -0.03) is one that punishes running.
##   stat_inheritance  - how much of the wielder's stat REACHES THE WEAPON at
##                       all. (ATTACK_SPEED, 0.5) is a minigun that only half
##                       cares how fast its owner is.
##
## Deliberately NOT a StatModifier. A modifier says "change this stat by this
## much" and is applied to a holder; this says "read that stat and use this
## share of it", and is never applied to anything.
##
## Named after StatusScaling, which does the same job for statuses - it names
## which stat feeds which axis. Same shape, same reason: the alternative is a
## field per stat, which stops working the moment somebody wants the third one.

@export var stat: StatTypes.Stat = StatTypes.Stat.RANGED_DAMAGE

## How much of it. 1.0 is all of it, 0.5 is half, 0 is none, and negative is a
## weapon that gets worse as its wielder gets better - which is a real design
## and falls out of the arithmetic rather than needing a case.
@export var coefficient: float = 1.0
