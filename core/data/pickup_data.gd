class_name PickupData
extends EntityData

## Something lying on the floor waiting to be walked over.
##
## An EntityData like everything else, which is what lets it ride the spawn
## channel with no change to it at all: SpawnRequest carries EntityData, and the
## view dispatches on the type. A corpse asking for scrap and a splitter asking
## for two swarmlings are the same request with a different payload.
##
## It inherits base_stats and innate_effects it does not use - the same trade an
## enemy makes carrying a `tier` and a `base_price`, and made for the same
## reason: one shape every consumer can read beats a narrower one half of them
## have to special-case.
##
## collider_radius from the base is how big it is AND how close you have to get,
## because for a thing on the floor those are the same question.

## What it is worth. Paid through EntityModel.add_currency, so CURRENCY_GAIN
## applies to whoever ends up collecting it - see RunModel.credit_pickup.
@export var value: int = 1

@export_group("Collection")
## How far it pulls itself towards a player BEFORE the player's PICKUP_RANGE is
## added, so ordinary movement sweeps up what you walk past.
##
## Without it the stat is not an upgrade but a requirement: at PICKUP_RANGE 0 a
## player has to pass within their own collider of every piece, and a kiting run
## leaves nearly all of it on the floor - measured at 8 collected out of 49
## dropped. On the PICKUP rather than on eight character files because it also
## says something per tier: a salvage core is worth noticing from further away
## than a chip of scrap.
@export var base_magnet: float = 0.0

## How fast it flies at a player once it is inside their PICKUP_RANGE.
##
## Comfortably faster than anything walks, or the magnet would read as the scrap
## politely following you rather than being yanked in.
@export var magnet_speed: float = 520.0

@export_group("Presentation")
## Placeholder colour, until there is art. Authored per tier so the three sizes
## are told apart by something other than a radius the player has to measure.
@export var color: Color = Color(1.0, 0.85, 0.35)
