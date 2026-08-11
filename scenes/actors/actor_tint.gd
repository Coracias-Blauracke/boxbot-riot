class_name ActorTint
extends RefCounted

## "Something is happening to this body, and you should be able to see it."
##
## The view-side half of every readable state an actor can be in: a charger
## winding up, and whatever else turns out to want saying. Owned by Actor, so
## anything that walks around has one and nothing has to reimplement a pulse.
##
## WHAT DRIVES IT IS NOT ITS BUSINESS. A driver sets `sustain` every frame from
## whatever fact it has - a behaviour's wind-up, a boss phase, a status - and
## this only decides what that looks like. That split is the whole point: the
## fact belongs to the model or the behaviour, where it can be tested without a
## screen, and the picture belongs here, where it can be changed without touching
## either.
##
## It survives the art pass. With placeholders it lerps a drawn colour; with
## sprites the same number becomes a `modulate`, and every caller stays as it is.

## The colour being mixed in. Set by whoever drives it, so two enemies can use
## the same mechanism to say different things.
##
## NEAR-WHITE by default, and that is a finding rather than a taste. The obvious
## choice for "this is about to hurt you" is red, and red is invisible here: the
## enemy placeholder is ALREADY red, so a red telegraph tints red with red. It
## was measured as working - windup=2 in the state line - and photographed as
## nothing at all, which is exactly why a picture gets read as well as a number.
##
## Whatever replaces it has the same job: contrast with what the BODY is, not
## with the background.
var accent: Color = Color(1.0, 0.97, 0.9)

## HOW STRONGLY, 0 to 1, and the only thing a driver has to write each frame.
##
## 0 leaves the body alone entirely, which is what every actor that never sets it
## reads for ever.
var sustain: float = 0.0

## Flashes per unit of sustain. The pulse also gets stronger as `sustain` climbs,
## so a wind-up reads as "louder and faster the closer it gets" rather than as a
## steady glow that happens to end.
var pulse_rate: float = 4.0

## Floor under the mix while anything is sustained at all, so the first instant
## of a telegraph is already visible rather than fading in from nothing.
var floor_share: float = 0.3

## What the body should be drawn as, given what it normally is.
##
## NO STATE OF ITS OWN and no clock: the pulse is a function of `sustain`, which
## the driver is already advancing. A timer here would be a second clock to keep
## in step with the first, and the two would disagree the moment anything paused.
func apply(base: Color) -> Color:
	if sustain <= 0.0:
		return base

	var strength := clampf(sustain, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(strength * TAU * pulse_rate)
	return base.lerp(accent, clampf(floor_share + (1.0 - floor_share) * pulse * strength, 0.0, 1.0))

# NO ONE-SHOT FLASH HERE YET, deliberately.
#
# "Flash white when hit" is the obvious next member and would need a clock and a
# decay, which is a different shape from the sustained mix above - and it has no
# caller today. This repo has been bitten by machinery invented ahead of the
# content that needs it; when hit feedback is actually wanted, it arrives as a
# second method beside this one and nothing here changes.
