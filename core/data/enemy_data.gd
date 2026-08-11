class_name EnemyData
extends EntityData

## An enemy definition. Bosses use this too - they are the same scene with a
## bigger collider, higher stats and a richer effect list, not a separate type.

@export var movement: MovementBehavior

@export_group("Separation")
## Whether this one's BODY is solid to other enemies.
##
## Separation below is steering and keeps a swarm spread out at a distance; this
## is the hard floor underneath it that stops two things occupying one spot when
## steering is not enough - which is what makes a crowd read as a crowd rather
## than as one dark blob.
##
## FALSE takes it out of enemy-to-enemy collision in BOTH directions: it neither
## blocks nor is blocked. That is for the big ones. A boss that can be stopped by
## the swarmlings it arrived with spends the fight shouldering through its own
## horde and does a fraction of what it was authored to do - and asymmetric
## collision, where it passes through them but they pile against it, is the
## version that produces "why is this thing stuck" bugs nobody can reproduce.
##
## It never affects the player: a player's body collides with nothing - see
## Actor, where that is now a decision rather than an oversight.
@export var collides_with_enemies: bool = true

## Keeps a swarm from collapsing into a single point. Deliberately a property of
## the enemy rather than of its MovementBehavior - otherwise every new behaviour
## would have to reimplement crowd handling.
##
## Radius is a multiple of collider_radius; weight is relative to the pull of
## the behaviour itself, so values below 1.0 still let the enemy close in.
@export var separation_radius_scale: float = 2.6
@export var separation_weight: float = 0.9

@export_group("Contact")
## Damage dealt by simply touching the target, and how often it repeats while
## the two stay in contact.
@export var contact_damage_interval: float = 0.6

@export_group("Armament")
## What this bug attacks WITH, beyond simply touching you.
##
## The same WeaponData a player carries, on the same WeaponModel, aimed by the
## same TargetSelector - the whole weapon stack was already side-agnostic, and
## the one thing that was not is now Actor.hostile_group. A spitter is therefore
## an ordinary enemy with a weapon in the list, not a second attack system.
##
## Named `weapons` rather than `starting_weapons`: a bug never buys, sells or
## merges one, so there is no "starting" to distinguish from "later".
@export var weapons: Array[WeaponData] = []

## Whether the armament is DRAWN, and where the shot leaves from.
##
## False by default, because the default enemy is a BUG: a biter spits a glob
## out of itself, and a beetle holding a pistol is a different game. Off, the
## mount is invisible and sits at the body's centre, so the projectile leaves
## the creature rather than a rifle floating beside it.
##
## Kept as a flag rather than as two kinds of enemy, because a turret, a mech
## and a boss with a visible cannon are all things this roster will want, and
## they differ from a spitter in exactly this one respect. Whether an armament
## SHOWS is a property of the creature, not of the weapon.
@export var weapons_visible: bool = false

# --- rewards ---------------------------------------------------------------
#
# NOTHING HERE ANY MORE, and that is the point.
#
# An enemy used to pay its killer directly the instant it died. It now DROPS,
# through an ordinary EffectSpawn in innate_effects pointing at a PickupData -
# so what a corpse is worth, how many pieces it comes in and how far they
# scatter are all authored on the same axis as everything else, and an item that
# makes things drop more is content rather than a special case in the payout.
#
# The reward is on the PICKUP because that is what the player picks up. Keeping
# a number here as well would be two answers to one question.
