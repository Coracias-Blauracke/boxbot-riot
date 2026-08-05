class_name ShopLayout

## How the screen is divided between players during the shop phase.
##
##   1 player   the whole screen
##   2 players  left and right halves
##   3 players  quadrants, bottom-right left free
##   4 players  quadrants
##
## Three and four share the SAME corner map as the HUD - P1 top-left, P2
## top-right, P3 bottom-left, P4 bottom-right - so the game teaches one spatial
## rule rather than two that contradict each other. A player learns where they
## are once.
##
## Three deliberately does not give one player a full-width strip and split the
## rest. That makes one panel a different SHAPE from the others, so the panel
## would have to work at three aspect ratios instead of two, and on a shared
## couch a visibly bigger panel for one person reads as unfair. The quadrant
## nobody claims is not wasted - it is where the shared wave line goes, which
## otherwise has nowhere to live once the panels cover the screen.

## Below this width a panel switches to its compact form. A quarter of a
## 1920-wide screen is 960, so quarters stay full; halving it again would not,
## which is the case this threshold exists for.
const COMPACT_WIDTH := 620.0

static func rect_for(index: int, count: int, viewport: Vector2) -> Rect2:
	if count <= 1:
		return Rect2(Vector2.ZERO, viewport)

	var half := viewport * 0.5

	if count == 2:
		return Rect2(Vector2(half.x * float(index), 0.0), Vector2(half.x, viewport.y))

	# index 0 -> top left, 1 -> top right, 2 -> bottom left, 3 -> bottom right.
	var column := index % 2
	var row := index / 2
	return Rect2(Vector2(half.x * float(column), half.y * float(row)), half)

## The quadrant no player claims, for the shared wave line. Empty when every
## slot is taken.
static func free_rect(count: int, viewport: Vector2) -> Rect2:
	if count != 3:
		return Rect2()
	var half := viewport * 0.5
	return Rect2(half, half)

static func is_compact(rect: Rect2) -> bool:
	return rect.size.x < COMPACT_WIDTH
