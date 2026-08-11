class_name GridCursor

## Where a cursor lands when it is nudged across a flat list laid out in rows.
##
## Pure arithmetic, no state, no nodes - which is the whole point. The rack in
## the lobby is a GRID on screen and a flat array in PlayerRoster, and the rule
## that turns "right" into an index is a real rule with real edge cases: a
## ragged last row, a column that some rows do not reach, and wrapping that has
## to stay inside the row rather than spilling into the next one. Rules like
## that belong where they can be asserted without a screen.
##
## WRAPPING IS PER ROW AND PER COLUMN, never across the whole list. Right from
## the end of a row returns to the start of THAT row, and up from the top of a
## column drops to the bottom of THAT column. A flat wrap reads as the cursor
## teleporting: you press right expecting the row you are reading and land one
## row down, which is how a player loses track of where they are in a rack of
## eighty.

## Rows a list of `total` fills at `columns` wide, the last one possibly ragged.
static func row_count(total: int, columns: int) -> int:
	if total <= 0:
		return 0
	var width := maxi(1, columns)
	# Ceiling division, spelled the integral way: fifty entries eight wide is
	# seven rows, and the seventh is ragged. A float here would round the wrong
	# way at exactly one full row.
	@warning_ignore("integer_division")
	return (total + width - 1) / width

static func row_of(index: int, columns: int) -> int:
	# A row number is whole by definition.
	@warning_ignore("integer_division")
	return index / maxi(1, columns)

static func column_of(index: int, columns: int) -> int:
	return index % maxi(1, columns)

## How many entries the row containing `index` actually holds. The last row of
## fifty entries at eight wide holds two, and right from either of them has to
## wrap between those two rather than jumping to a row that looks full.
static func row_length(index: int, total: int, columns: int) -> int:
	var width := maxi(1, columns)
	var start := row_of(index, width) * width
	return clampi(total - start, 0, width)

## How many rows reach `column`. Two entries in the last row means columns 0 and
## 1 have one more row than every column after them, and up from the top of
## column 5 must land on the last row that HAS a column 5.
static func column_length(column: int, total: int, columns: int) -> int:
	var width := maxi(1, columns)
	if column < 0 or column >= width or column >= total:
		return 0
	# Ceiling division again, for how many rows reach this column.
	@warning_ignore("integer_division")
	return (total - column + width - 1) / width

static func step_horizontal(index: int, total: int, columns: int, delta: int) -> int:
	if total <= 0:
		return 0

	var width := maxi(1, columns)
	var start := row_of(index, width) * width
	var length := row_length(index, total, width)
	if length <= 0:
		return index

	return start + posmod(index - start + delta, length)

static func step_vertical(index: int, total: int, columns: int, delta: int) -> int:
	if total <= 0:
		return 0

	var width := maxi(1, columns)
	var column := column_of(index, width)
	var length := column_length(column, total, width)
	if length <= 0:
		return index

	return posmod(row_of(index, width) + delta, length) * width + column

## The first visible row that keeps `index` on screen, given where the view is
## scrolled now. Returns `top` unchanged when the cursor is already visible,
## which is what stops a shared grid from lurching every time anybody moves.
static func scroll_to_show(index: int, columns: int, top: int, visible_rows: int) -> int:
	if visible_rows <= 0:
		return top

	var row := row_of(index, columns)
	if row < top:
		return row
	if row >= top + visible_rows:
		return row - visible_rows + 1
	return top

## Clamps a scroll position to the rows that exist. Called after the catalogue
## or the layout changes, since either can leave the view parked past the end.
static func clamp_scroll(top: int, total: int, columns: int, visible_rows: int) -> int:
	return clampi(top, 0, maxi(0, row_count(total, columns) - visible_rows))
